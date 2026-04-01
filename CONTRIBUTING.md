# Contributing to adamant-Lib

Shared utility library for adamant modpack modules. Provides the module contract, UI primitives, managed UI-state handling, and the field type system.

See also:

- `FIELD_TYPES.md` for the dedicated field type contract
- `../adamant-ModpackFramework/HASH_PROFILE_ABI.md` for the shared hash/profile ABI policy
- `../Support/mutation_plan_migration.md` for mutation-plan migration examples

## Architecture

Lib is split internally across `src/main.lua`, `src/core.lua`, `src/fields.lua`, and `src/special.lua`,
but modules still load it as one mod package:

```lua
local lib = rom.mods["adamant-ModpackLib"]
```

## Public API

| Function | Purpose |
|---|---|
| `lib.isEnabled(store, packId)` | True if module plus coordinator master toggle are both on |
| `lib.warn(packId, enabled, fmt, ...)` | Framework diagnostic print, printf-style. For framework-detected problems. Do not use for normal module tracing. |
| `lib.log(name, enabled, fmt, ...)` | Module trace print, printf-style, gated by the caller-supplied boolean |
| `lib.createBackupSystem()` | Returns `backup, revert` for isolated state save/restore |
| `lib.createMutationPlan()` | Returns a reversible declarative mutation plan for patch-style data edits |
| `lib.MutationMode` | Optional enum-like constants for `definition.mutationMode` |
| `lib.standaloneUI(def, store)` | Returns menu-bar callback for standalone regular modules |
| `lib.readPath(tbl, key)` | Read from table using string or path key |
| `lib.writePath(tbl, key, value)` | Write to table using string or path key |
| `lib.drawField(imgui, field, value, width)` | Render a regular-module option widget, returns `(newValue, changed)` |
| `lib.validateSchema(schema, label)` | Validate field descriptors at declaration time |
| `lib.createStore(config, definitionOrSchema?)` | Returns the module store; modules with managed fields get `store.uiState` |
| `lib.isFieldVisible(field, values)` | Returns true if `field.visibleIf` is absent or `values[field.visibleIf] == true` |
| `lib.FieldTypes` | The field type registry table |

`lib.createStore(...)` is the only supported store constructor. Do not build hand-rolled store tables.
Raw config/backend handles are intentionally hidden; `store.read(...)`, `store.write(...)`, and
`store.uiState` are the supported store surface.

### `createStore(config, definitionOrSchema)` contract

`lib.createStore(...)` accepts either:

- a full module definition table
- or a raw schema/options array

Detection is shape-based:

- if the table has module-definition markers such as `stateSchema`, `options`, `special`, or `id`,
  Lib treats it as a definition
- otherwise Lib treats the table itself as the managed field list

Resolution rules:

- `definition.stateSchema` wins for special modules
- otherwise `definition.options` is used for regular modules
- otherwise no `uiState` is created

Supported patterns:

```lua
public.store = lib.createStore(config, public.definition)
public.store = lib.createStore(config, public.definition.stateSchema)
public.store = lib.createStore(config, public.definition.options)
```

Preferred pattern for new code:

```lua
public.store = lib.createStore(config, public.definition)
```

Do not pass arbitrary mixed tables that are neither a real definition table nor a real schema list.

## Module contract

Every module must expose `public.definition`:

```lua
public.definition = {
    id           = "MyMod",
    name         = "My Mod",
    category     = "Bug Fixes",
    group        = "General",
    tooltip      = "...",
    default      = true,
    dataMutation = true,
}

public.definition.apply  = apply   -- optional in patch-only modules
public.definition.revert = revert  -- optional in patch-only modules
```

- mutation lifecycle is inferred from exports
- Framework and standalone helpers both call Lib-owned orchestration, not raw `apply/revert` directly
- failing mutation lifecycle work is warned, not allowed to crash the pack UI

### Mutation authoring contract

For modules that mutate game data, Lib now supports three authoring shapes:

- patch-only
- manual-only
- hybrid

Current v1 rule:

- shape is inferred from exports
- `definition.mutationMode = lib.MutationMode.*` is optional
- if the enum is present and does not match the inferred shape, Framework warns

### Patch-only modules

Patch-only modules expose:

```lua
public.definition.dataMutation = true
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "SomeKey", 123)
end
```

Patch plans use `lib.createMutationPlan()` internally and are the preferred path for common
reversible table edits.

Supported v1 primitives:

- `plan:set(tbl, key, value)`
- `plan:setMany(tbl, kv)`
- `plan:transform(tbl, key, fn)`
- `plan:append(tbl, key, value)`
- `plan:appendUnique(tbl, key, value, equivalentFn?)`

Important:

- plans are built fresh on every apply
- `appendUnique(...)` uses Lib-owned deep-equivalence by default
- `transform(...)` returns the full replacement value for the targeted key

### Manual-only modules

Manual modules expose:

```lua
public.definition.dataMutation = true
public.definition.apply = apply
public.definition.revert = revert
```

Use this when the mutation logic is too procedural or engine-specific for a patch plan.

Current standard manual primitive:

- `lib.createBackupSystem()`

Current guidance:

- call `backup(...)` before every write performed by `apply()`
- use the returned `restore()` as `revert()` unless the module has a clear reason to wrap it
- do not hand-roll ad hoc saved-value registries when `createBackupSystem()` is sufficient

### Hybrid modules

Hybrid modules expose both:

```lua
public.definition.patchPlan = function(plan, store) ... end
public.definition.apply = apply
public.definition.revert = revert
```

Use this when the module has:

- deterministic table edits that fit patch mode
- plus procedural leftovers that still need manual mode

Lib orchestration order is stable:

- apply: patch first, then manual
- revert: manual first, then patch

Practical rule:

- keep patch-owned keys and manual-owned keys conceptually separate where possible
- do not intentionally make patch and manual logic fight over the same `(table, key)` unless the
  module author owns that interaction deliberately

### Optional mutation enum

Modules may declare:

```lua
public.definition.mutationMode = lib.MutationMode.Patch
public.definition.mutationMode = lib.MutationMode.Manual
public.definition.mutationMode = lib.MutationMode.Hybrid
```

This is optional in v1.

Current behavior:

- absent enum: shape is inferred silently
- present matching enum: accepted
- present mismatched enum: warning only

### When to choose which

Prefer patch mode when the change is fundamentally:

- set/replace one or more keys
- append to a list
- append-if-missing
- clone/modify/replace one keyed value

Prefer manual mode when the change is fundamentally:

- procedural
- hook-like
- engine-side
- difficult to express as a bounded table mutation

Prefer hybrid when a module is mostly patch-shaped but still has a small procedural remainder.

### Current enforcement

Framework warns when:

- `dataMutation = true` but the module exposes neither patch plan nor manual `apply/revert`
- `definition.mutationMode` is present but does not match the inferred shape

Patch mode and hybrid mode are now the preferred tightening path for reversible data edits.

### Inline options (regular modules)

Boolean modules can declare options rendered below their checkbox:

```lua
public.definition.options = {
    { type = "checkbox", configKey = "Strict", label = "Strict Mode", default = false },
    { type = "dropdown", configKey = "Mode", label = "Mode",
      values = { "Vanilla", "Always", "Never" }, default = "Vanilla" },
}
```

`configKey` must be a flat string. Table-path keys are only valid in `definition.stateSchema` for special modules.

Regular modules with inline options also get `public.store.uiState`. Hosted Framework UI and
standalone regular-module UI both edit options through that managed state and flush to persisted
config at the end of the draw pass.

### Special modules

Special modules get their own sidebar tab and custom state:

```lua
public.definition.special     = true
public.definition.tabLabel    = "Hammers"
public.definition.stateSchema = { ... }
public.store                  = lib.createStore(config, public.definition)

function public.DrawTab(imgui, uiState, theme) ... end
function public.DrawQuickContent(imgui, uiState, theme) ... end
```

`public.store.uiState` is the managed state object for schema-backed UI state.

It exposes:
- `uiState.view` - read-only render view
- `uiState.get(path)`
- `uiState.set(path, value)`
- `uiState.update(path, fn)`
- `uiState.toggle(path)`
- `uiState.reloadFromConfig()`
- `uiState.flushToConfig()`
- `uiState.isDirty()`

### Schema caching

`lib.validateSchema` writes two cached values onto each field descriptor at declaration time:

| Field | Value | Purpose |
|---|---|---|
| `field._schemaKey` | `table.concat(configKey, ".")` for path keys, `tostring(configKey)` for strings | Stable hash key used by hash encode/decode and managed `uiState` bookkeeping |
| `field._imguiId` | `"##" .. tostring(configKey)` | Stable ImGui widget ID reused by `drawField` every frame |

These are written once and never recomputed. Do not overwrite them.

Lib and Framework also mutate descriptor tables in place with additional cached runtime fields such
as `_readValue`, `_writeValue`, `_pushId`, `_hashKey`, and stepper display caches. Treat schema and
field tables as per-module declarations, not immutable shared constants:

- declare schemas freshly in the module loader/setup path
- do not share field descriptor tables across modules or schemas
- do not mutate descriptor objects after validation/discovery

### Managed UI-state rules

For managed fields:
- read from `uiState.view`
- mutate only through `uiState.set/update/toggle`
- do not bypass `store`/`uiState` from feature files

Framework-owned hosted flow:
- Framework calls `DrawTab` / `DrawQuickContent`
- if `uiState.isDirty()` is true after draw, Framework calls `uiState.flushToConfig()`
- Framework then invalidates the cached hash and updates the HUD fingerprint

Standalone special-module flow:
- the module renders its own window
- after `DrawTab` / `DrawQuickContent`, the module should call `uiState.flushToConfig()` if dirty

Standalone regular-module flow:
- Lib renders the regular controls
- reads from `store.uiState.view`
- writes through `store.uiState`
- flushes once after the draw pass if dirty

## Field type system

This section is a summary. See `FIELD_TYPES.md` for the full contract.

All field types live in the `FieldTypes` registry in `src/main.lua`. Each type implements:

| Method | Purpose |
|---|---|
| `validate(field, prefix)` | Declaration-time checks |
| `toHash(field, value)` | Serialize value to canonical hash string |
| `fromHash(field, str)` | Deserialize value from canonical hash string |
| `toStaging(val)` | Transform config value for managed `uiState` staging |
| `draw(imgui, field, value, width)` | Render the ImGui widget for regular-module options |

### Built-in field types

| Type | Widget | Notes |
|---|---|---|
| `checkbox` | `imgui.Checkbox` | `default` must be boolean |
| `dropdown` | `imgui.BeginCombo` | `values` must be a non-empty list of strings |
| `radio` | `imgui.RadioButton` | `values` must be a non-empty list of strings |
| `int32` | display only (no widget) | `default`, `min`, `max` must be numbers; value is clamped and floored |
| `stepper` | `-` / `+` buttons + text | `default`, `min`, `max` must be numbers; `step` optional positive number |
| `separator` | `imgui.Separator` | `label` optional; no `configKey`, not encoded in hash |

All string-valued types (`dropdown`, `radio`) reject values containing `|` since that character is used as the hash delimiter.

For `stepper`, the resolved step value is cached on `field._step` at `validateSchema` time to avoid recomputation every frame.

Note: special modules use field types as typed state descriptors for hashing and state management, but Framework does not render `stateSchema` fields automatically.

### Adding a new field type

Add one entry to the registry and all consumers pick it up automatically:

```lua
FieldTypes.mytype = {
    validate  = function(field, prefix) end,
    toHash    = function(field, value) return tostring(value) end,
    fromHash  = function(field, str) return str end,
    toStaging = function(val) return val end,
    draw      = function(imgui, field, value, width) ... end,
}
```

## Templates

The canonical templates live in the `h2-modpack-template` repo:
- `src/main.lua` - regular module starting point
- `src/main_special.lua` - special module starting point

## Standalone mode

Every module works without Core installed.
- Regular modules get a menu-bar toggle via `lib.standaloneUI()`
- Special modules render their own window and use `public.store.uiState` there too

When Core is installed, standalone UI is automatically suppressed.

Standalone helpers now follow the same inferred mutation lifecycle as Framework:

- patch-only modules are supported
- manual-only modules are supported
- hybrid modules are supported

The mutation lifecycle is driven by the module definition shape (inferred from `patchPlan`, `apply`, `revert` exports), not by separate callback parameters.

## Debug system

Two distinct functions, two distinct purposes:

| Function | Purpose | Gated by |
|---|---|---|
| `lib.warn(packId, enabled, fmt, ...)` | Framework-detected problems such as schema errors, discovery errors, skipped modules | Caller-supplied coordinator debug flag |
| `lib.log(name, enabled, fmt, ...)` | Module author traces and debug warnings | Caller-supplied boolean, usually `config.DebugMode` |

Both functions accept printf-style arguments — string building is deferred past the gate, so no allocation occurs when disabled:

```lua
lib.warn(packId, config.DebugMode, "Skipping %s: missing id", modName)
lib.log("MyMod", config.DebugMode, "hook fired: value=%s", value)
```

Console output is visually distinct:

```text
[run-director] adamant-foo: special module is missing public.store.uiState (managed UI state)
[MyMod] hook fired: value=Always
```

Module authors should use `lib.log(...)` for all intentional diagnostics. `lib.warn(...)` is for framework-level problems.
