# adamant-ModpackLib API

This is the public Lib surface.

Preferred usage uses top-level module authoring helpers plus namespaces for specialized APIs:
- `lib.createModule(...)`
- `lib.tryCreateModule(...)`
- `lib.prepareDefinition(...)`
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.activateModuleHost(...)`
- `lib.tryActivateModule(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`
- `lib.hashing.*`
- `lib.hooks.*`
- `lib.overlays.*`
- `lib.integrations.*`
- `lib.gameObject.*`
- `lib.mutation.*`
- `lib.lifecycle.*`
- `lib.logging.*`
- `lib.widgets.*`
- `lib.nav.*`
- `lib.imguiHelpers.*`

The top-level `lib.config` export also exposes Lib's Chalk config.

## Core Model

Modules declare:
- required `definition.id`
- required `definition.name`
- optional `definition.modpack`
- optional `definition.storage`

Modules normally create and publish their behavior host through:
- `lib.createModule(...)`
- `host.activate()`

Module/host creation requires:
- `drawTab`

Optional module capabilities are passed to module/host creation:
- `registerPatchMutation`
- `registerManualMutation`
- `onSettingsCommitted`
- `registerHooks`
- `registerIntegrations`
- `drawQuickContent`

That host owns:
- `drawTab`
- optional `drawQuickContent`
- built-in lifecycle/state helpers for Framework and standalone hosting

Module behavior is hosted through Lib's live host registry.

## `lib.config`

Live Lib config loaded from Chalk.

Meaningful field:
- `lib.config.DebugMode`

## `lib.integrations`

Small registry for optional cross-module cooperation. Modules can publish a
domain-named integration API, and consumers can use it when present while
remaining fully functional when absent.

Typical provider inside `registerIntegrations(host, store)`:

```lua
lib.integrations.register("run-director.god-availability", MODULE_ID, {
    isActive = function()
        return host.isEnabled()
    end,
    isAvailable = function(godKey)
        return true
    end,
})
```

Typical consumer:

```lua
local active = lib.integrations.invoke("run-director.god-availability", "isActive", false)
if active then
    return lib.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey) ~= false
end
return true
```

Surface:
- `lib.integrations.register(id, providerId, api)`
- `lib.integrations.unregister(id, providerId)`
- `lib.integrations.unregisterProvider(providerId)`
- `lib.integrations.invoke(id, methodName, fallback, ...)`
- `lib.integrations.get(id)`
- `lib.integrations.list(id)`

Rules:
- integration ids should describe domain behavior, not consumer names
- absence means the optional enhancement is inactive
- provider APIs should be safe to call when their module is disabled
- consumers should prefer `invoke(...)` so Lib resolves active provider behavior at call time
- when multiple providers exist, `get(id)` returns the most recently registered provider

## `lib.gameObject`

Namespaced state buckets attached to live game object tables such as `CurrentRun`, room data, or loot data.

Use this for object-owned runtime state whose lifetime should follow that game table. It is not persisted, staged, hashed, profiled, or reset by Lib.

The normal author path is `lib.createModule(...)`, which prepares the definition,
creates the store/session pair, and returns the author-facing host plus the state
handles to keep. `host.activate()` publishes the live host and runs side effects.

Advanced use:

```lua
local state = lib.gameObject.get(CurrentRun, PACK_ID, MODULE_ID, "run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

Surface:
- `lib.gameObject.get(object, packId, moduleId, key, factory?)`
- `lib.gameObject.peek(object, packId, moduleId, key)`
- `lib.gameObject.clear(object, packId, moduleId, key)`

Rules:
- `object` must be a table
- `packId`, `moduleId`, and `key` must be non-empty strings
- `factory` runs only when the bucket is missing
- `factory` must return a table when provided
- state is namespaced under one Lib-owned root on the object

## Store And Session

### `lib.prepareDefinition(owner, definition, opts)`

Creates the canonical definition object for a module from a raw authored definition table.

What it does:
- clones the authored definition into a Lib-owned table
- requires `definition.id` as the stable module identity
- requires `definition.name` as the stable display name
- validates top-level definition keys and types
- prepares `definition.storage` metadata for later `createStore(...)` use
- injects Lib-owned built-in storage aliases:
  - `Enabled`
  - `DebugMode`
- requires persisted storage roots to have explicit effective defaults in the storage declaration
- preserves optional `definition.hashGroupPlan` hash-compaction hints as structural contract data
- records a structural fingerprint on the persistent `owner` table when provided
- warns and marks `owner.requiresFullReload = true` when a later hot reload changes structural definition shape

Structural reload checks cover:
- `modpack`
- `id`
- `name`
- `shortName`
- `tooltip`
- `storage`
- `hashGroupPlan`
- `opts.hasQuickContent`

Behavior callbacks are not valid definition fields and do not participate in structural fingerprinting.
When using the lower-level `prepareDefinition(...)` -> `createStore(...)` ->
`createModuleHost(...)` pipeline directly, pass
`{ hasQuickContent = type(drawQuickContent) == "function" }` so quick-content
add/remove changes are tracked as structural UI changes. `createModule(...)`
does this automatically.

Typical use:

```lua
local definition = lib.prepareDefinition(internal, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = internal.BuildStorage(),
    hashGroupPlan = internal.BuildHashGroupPlan(),
})
```

Treat the returned definition as the authoritative module contract and pass it to
`createStore(...)` and `createModuleHost(...)` when using the lower-level
pipeline directly.

`hashGroupPlan` is the preferred author-facing input for complex hash layouts:

```lua
hashGroupPlan = {
    {
        keyPrefix = "global",
        items = {
            { "EnabledFlag", "Tier" },
            "DebugFlag",
        },
    },
}
```

Rules:
- `keyPrefix` names a hash-group family
- `items` is an ordered list of logical bundles
- each item may be a single alias string or a list of aliases that must stay together
- Framework may use these hints to pack multiple persisted roots into shorter canonical hash tokens

### `lib.createModule(opts)`

Canonical module-construction helper.
`owner` is used for structural hot-reload tracking and hook refresh ownership.
When a module declares runtime hooks, use a persistent owner table so Lib can
remove omitted hook declarations on later reloads.

```lua
local host, store = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
        storage = internal.BuildStorage(),
    },
    registerPatchMutation = internal.BuildPatchPlan,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
host.activate()
```

Returns:
- `host`
  Author-facing host with `activate()`, `isEnabled()`, metadata getters, and module-scoped logging helpers.
- `store`
  Runtime read surface for gameplay/hooks.

`createModule(...)` intentionally does not return the prepared definition or
raw session. Draw callbacks receive the restricted author session, and custom
construction can use `prepareDefinition(...)`, `createStore(...)`,
`createModuleHost(...)`, and `activateModuleHost(...)` directly.

If `registerHooks` is provided, Lib calls it as:

```lua
registerHooks(host, store)
```

Runtime helper files should receive the needed `store` or narrowed read/access
closures from `registerHooks(...)`; draw/UI paths should continue using the
session passed to draw callbacks.

### `lib.tryCreateModule(opts)`

Safe wrapper around `lib.createModule(...)`.

Returns:
- `host, store, nil` when construction succeeds
- `nil, nil, err` when construction fails

The failure path logs `host.create_failed` and does not activate or publish a
host. Use this at pack orchestration boundaries when one invalid module should
be skipped without stopping sibling modules.

```lua
local host, store, err = lib.tryCreateModule(opts)
if host then
    local ok, activateErr = host.tryActivate()
end
```

`tryCreateModule(...)` only wraps construction. Activation remains explicit.

### `lib.createStore(config, definition)`

Creates the managed store facade around persisted module config from a prepared
definition.
What it does:
- requires a definition returned by `lib.prepareDefinition(...)`
- consumes the prepared `definition.storage` metadata
- returns a separate `session` for staged UI state
- exposes persisted read helpers

Typical use:

```lua
local store, session = lib.createStore(config, definition)
```

Ownership rule: `store` and `session` are a matched pair created for one prepared
`definition` and one backing config table. Pass them together to
`lib.createModuleHost(...)`, and do not mix a store from one `createStore(...)`
call with a session from another. Recreate the pair together on module reload.

Returned surface:
- `store.read(alias)`
- `store.table(alias)`
- `store.writeUnstaged(alias, value)` returns whether the write was accepted

Persisted writes happen through semantic helpers or session flushes:

```lua
lib.lifecycle.setEnabled(def, mutationBundle, host, store, enabled)
lib.lifecycle.setDebugMode(store, enabled)
```

Use `setEnabled` from lower-level host/custom construction code when you also
own the mutation bundle. Normal modules should let `createModule(...)` and the
host own enabled/debug transitions. Module/host plumbing can use
`session.write(...)` plus `session._flushToConfig()` for immediate persisted
writes such as profile/hash import. Ordinary draw-code edits stay staged and
commit through the host/framework flow.

`Enabled` and `DebugMode` are ordinary prepared storage aliases injected by Lib.
Do not declare them in module storage or module `config.lua`.
`Enabled` is the module behavior toggle. Framework serializes it through the
module-level hash key. `DebugMode` is diagnostic-only and has `hash = false`.

Rules:
- keep each `store, session` pair together for its lifetime
- widgets and draw code should usually read staged values from `session.view`
- runtime/gameplay code should read persisted values through `store.read(...)`
- module-owned runtime markers declared with `stage = false, hash = false` should write through `store.writeUnstaged(...)`
- enabled toggles should write through the host or `lib.lifecycle.setEnabled(def, mutationBundle, host, store, enabled)`
- debug toggles should write through `lib.lifecycle.setDebugMode(store, enabled)`
- profile/hash plumbing should stage values through `session.write(...)` and flush them through `session._flushToConfig()`
- transient aliases are read from `session`
- transient aliases declare `persist = false, hash = false` and stay out of persisted config
- runtime-cache aliases declare `stage = false, hash = false` and are excluded from session, hash, profile, and reset-to-defaults surfaces

Persistent runtime cache storage is declared on ordinary storage nodes:

```lua
{
    type = "bool",
    alias = "BatchRecordingArmed",
    default = false,
    stage = false,
    hash = false,
}
```

Use it for module-owned runtime intent or small reload/restart markers that should not affect UI staging, profiles, or config hashes:

```lua
store.writeUnstaged("BatchRecordingArmed", true)
local armed = store.read("BatchRecordingArmed") == true
```

`store.writeUnstaged(alias, value)` only accepts aliases declared with `stage = false`.
It returns `false` without mutating state if violation policy is downgraded from
error and the alias is rejected.

Composite table storage is declared as one table root with a uniform row schema:

```lua
{
    type = "table",
    alias = "Tiers",
    minRows = 0,
    maxRows = 10,
    defaultRows = 1,
    row = {
        { type = "bool", alias = "Enabled", default = true },
        { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
        {
            type = "packedInt",
            alias = "PackedChoices",
            bits = {
                { alias = "ChoiceA", offset = 0, width = 1, type = "bool", default = false },
                { alias = "ChoiceMode", offset = 1, width = 2, type = "int", default = 0 },
            },
        },
    },
}
```

The table root owns `persist`, `stage`, and `hash`. Row fields are row-scoped
storage aliases and do not declare storage axes. Table rows are compact ordered
arrays with no row ids or holes.

Read table state through:

```lua
local tiers = session.table("Tiers")
tiers:append({ Enabled = true, ChoiceA = true })
tiers:write(1, "ChoiceMode", 2)
local enabled = tiers:read(1, "Enabled")

local row = tiers:rowHandle(1)
row.write("ChoiceMode", 2)
local selected = row.read("ChoiceMode")
```

Table handles:
- `store.table(alias)` returns a read-only table handle
- `session.table(alias)` returns a staged writable table handle
- table handles are object methods; call them with colon syntax such as `tiers:read(rowIndex, alias)`
- row aliases can address scalar row roots, packed row roots, or packed child aliases
- `rowHandle(rowIndex)` returns a positional row cursor with `read(alias)` and `getAliasSchema(alias)`
- writable session row handles also expose `write(alias, value)` and `reset(alias)`
- read-only store row handles do not expose write methods
- table storage participates in hash/profile serialization when `hash` is true

Aliases are direct flat storage identifiers. Managed storage reads and writes the
declared alias key directly; future composite storage should own any generated
backing keys internally.

Storage axis defaults:

| Declaration | Persisted config | Session/staged UI | Hash/profile |
| --- | --- | --- | --- |
| omitted flags | yes | yes | yes |
| `persist = false, hash = false` | no | yes | no |
| `stage = false, hash = false` | yes | no | no |
| `hash = false` | yes | yes | no |

Invalid storage combinations fail during storage validation:
- `hash = true` requires `persist = true`
- `hash = true` requires `stage = true`

Reserved aliases:
- `Enabled`
- `DebugMode`

### `session`

Managed staged UI state for the module.

Useful surface:
- `session.view`
- `session.read(alias)`
- `session.table(alias)`
- `session.getAliasSchema(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`
- `session.isDirty()`
- `session.auditMismatches()`

Host/framework plumbing methods:
- `session._flushToConfig()`
- `session._reloadFromConfig()`
- `session._captureDirtyConfigSnapshot()`
- `session._restoreConfigSnapshot(snapshot)`

When a module is rendered through a Lib host, draw callbacks receive a restricted author-facing session view with:
- `view`
- `read(alias)`
- `table(alias)`
- `write(alias, value)`
- `reset(alias)`
- `getAliasSchema(alias)`
- `resetToDefaults(opts?)`

`session.getAliasSchema(alias)` exposes prepared storage schema metadata for UI
and widget plumbing. Treat the returned nodes as read-only metadata owned by Lib
storage preparation. Widgets use this metadata for composite storage such as
packed roots.

Behavior:
- persisted aliases stage in `session` and only hit config on flush/commit
- transient aliases live only in `session`
- packed child aliases re-encode their owning packed root automatically

`session.read(alias)` returns:
- staged value

## Reset Helpers

### `lib.resetStorageToDefaults(storage, session, opts?)`

Resets changed persistent storage roots back to their defaults in the staged `session`.

Returns:
- `changed`
- `count`

Options:
- `exclude = { Alias = true }` skips specific root aliases.

## `lib.hooks`

Reload-stable wrappers around ModUtil path hooks.

Hosted modules normally call ownerless hook APIs inside `registerHooks(...)`.
Lib scopes those calls to the persistent owner passed to `createModule(...)`.

### `lib.hooks.Wrap(path, handler)`

Registers or updates a stable `modutil.mod.Path.Wrap(...)` dispatcher.

Also supports:
- `lib.hooks.Wrap(path, key, handler)`

Use the keyed form when one module registers more than one wrap against the same path.

### `lib.hooks.Override(path, replacement)`

Registers or updates a stable `modutil.mod.Path.Override(...)`.

Also supports:
- `lib.hooks.Override(path, key, replacement)`

Function replacements are dispatched through a stable wrapper so reloading updates behavior without stacking another override.

### `lib.hooks.Context.Wrap(path, context)`

Registers or updates a stable `modutil.mod.Path.Context.Wrap(...)` dispatcher.

Also supports:
- `lib.hooks.Context.Wrap(path, key, context)`

Infrastructure and non-hosted code can use explicit-owner variants. Module
authors should prefer the ownerless APIs inside `registerHooks(...)`.
- `lib.hooks.WrapOwned(owner, path, handler)`
- `lib.hooks.OverrideOwned(owner, path, replacement)`
- `lib.hooks.Context.WrapOwned(owner, path, context)`

### Typical module pattern

```lua
function internal.RegisterHooks(host, store)
    lib.hooks.Wrap("GetEligibleLootNames", function(base, ...)
        local result = base(...)
        if host.isEnabled() and store.read("FeatureEnabled") then
            -- inspect or transform the wrapped call here
        end
        return result
    end)
end

local PLUGIN_GUID = _PLUGIN.guid

local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "Example Module",
        storage = internal.BuildStorage(),
    },
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
})
host.activate()
```

When `host.activate()` runs with `owner` and `registerHooks`, activation runs the registration pass and deactivates hooks omitted by a later pass for the same owner.

## `lib.overlays`

Retained HUD text helpers for shared overlay placement.

Overlay visibility has two layers:
- Lib applies a global game-HUD gate, currently based on `ShowingCombatUI`.
- Each overlay can also provide its own `visible` boolean or callback.
- Lib-hosted ImGui configuration windows acquire a UI suppression token while
  open. Any active token hides the entire overlay layer until released.

When the global gate is closed, lib hides all retained overlay components even if their own `visible` callback returns true. Text callbacks may still be refreshed so the display is fresh when the game HUD returns.

Framework and standalone module UIs use this gate so configuration UI and
gameplay overlays are mutually exclusive on screen.

Managed region:
- `middleRightStack`: a right-anchored vertical stack used for framework markers and module status text.

Order bands:
- `lib.overlays.order.framework`
- `lib.overlays.order.module`
- `lib.overlays.order.debug`

### `lib.overlays.registerStackedText(opts)`

Registers one text box in a managed stack region.

Useful for single-line overlays where the whole line can share one font and alignment.

### `lib.overlays.registerStackedRow(opts)`

Registers one multi-column row in a managed stack region.

Columns are declared left-to-right:

```lua
lib.overlays.registerStackedRow({
    id = "example.timer",
    region = "middleRightStack",
    order = lib.overlays.order.module,
    columnGap = 6,
    columns = {
        {
            key = "label",
            minWidth = 42,
            justify = "Right",
            text = "IGT:",
            textArgs = { Font = "P22UndergroundSCMedium" },
        },
        {
            key = "time",
            minWidth = 96,
            justify = "Right",
            text = function() return "00:00.00" end,
            textArgs = { Font = "MonospaceTypewriterBold" },
        },
    },
})
```

`minWidth` reserves layout space so columns line up across rows. It does not clip text.

Stacked handles expose two refresh paths:
- `refresh()` recomputes region layout, visibility, and text.
- `refreshText()` updates retained text only and is intended for hot paths where row visibility/order is known to be stable.

### `lib.overlays.suppressForUi()`

Temporarily hides all Lib overlays while a foreground ImGui configuration UI is open.

Returns a token:
- `token.release()`

Suppression is reference-counted by active tokens. Overlays are refreshed when the
first token is acquired and when the final token is released.

### `lib.overlays.isUiSuppressed()`

Returns whether any UI suppression token is currently active.

## `lib.hashing`

Hash/profile serialization and packed-bit helpers.

### `lib.hashing.getRoots(storage)`

Returns prepared root nodes that participate in hash/profile serialization.
The returned nodes are read-only metadata owned by Lib storage preparation; callers must not mutate them.

### `lib.hashing.getAliases(storage)`

Returns the prepared alias map.
The returned map and nodes are read-only metadata owned by Lib storage preparation; callers must not mutate them.

Includes:
- hash/profile root aliases
- non-hash staged aliases
- runtime-cache aliases
- packed child aliases

### `lib.hashing.valuesEqual(node, a, b)`

Storage-aware equality helper for comparing persisted/hash values.

### `lib.hashing.getPackWidth(node)`

Returns the derived pack width for a node type that supports packing.

### `lib.hashing.toHash(node, value)`

Encodes one storage value for hash/profile serialization.

### `lib.hashing.fromHash(node, str)`

Decodes one storage value from hash/profile serialization.

### `lib.hashing.readPackedBits(packed, offset, width)`

Raw numeric bit extraction helper.

### `lib.hashing.writePackedBits(packed, offset, width, value)`

Raw numeric bit write helper.

## `lib.mutation`

### `lib.mutation.createBackup()`

Returns:
- `backup(tbl, ...)`
- `restore()`

For reversible table mutation capture.

### `lib.mutation.createPlan()`

Creates a reversible mutation plan with:
- `plan:set(...)`
- `plan:setMany(...)`
- `plan:transform(...)`
- `plan:append(...)`
- `plan:appendUnique(...)`
- `plan:removeElement(...)`
- `plan:setElement(...)`
- `plan:apply()`
- `plan:revert()`


## `lib.lifecycle`

Framework/host-facing helpers for module lifecycle orchestration, built-in module controls, and staged session commits.

### `lib.lifecycle.inferMutation(def)`

Infers the mutation lifecycle shape:
- `patch`
- `manual`
- `hybrid`
- or `nil`

### `lib.lifecycle.registerCoordinator(packId, config)`

Registers coordinator config for a pack. Framework uses this during coordinator initialization.

### `lib.lifecycle.setEnabled(def, mutationBundle, host, store, enabled)`

Transitions persisted enabled state and applies/reverts mutation state as needed.

### `lib.lifecycle.setDebugMode(store, enabled)`

Writes the persisted debug-mode flag for a module store.

### `lib.lifecycle.affectsRunData(mutationBundle)`

Returns whether a mutation bundle declares live run-data mutation behavior.

### `lib.lifecycle.applyMutation(def, mutationBundle, host, store)`

Applies the module's mutation lifecycle.
Patch callbacks receive `(plan, host, store)`. Manual lifecycle hooks receive
`(host, store)`.

### `lib.lifecycle.revertMutation(def, mutationBundle, host, store)`

Reverts the module's mutation lifecycle.
Manual lifecycle hooks receive `(host, store)`.

### `lib.lifecycle.reapplyMutation(def, mutationBundle, host, store)`

Reverts and reapplies the module's mutation lifecycle.

### `lib.lifecycle.applyOnLoad(def, mutationBundle, host, store)`

Syncs live mutation state to the module's effective enabled state on load. Framework calls this for coordinated modules; `lib.standaloneHost(...)` calls it for standalone modules.

### `lib.lifecycle.resyncSession(def, session)`

Audits staged state against persisted config, logs drift, then reloads staged values from config.

### `lib.lifecycle.commitSession(def, mutationBundle, settingsObserver, host, store, session)`

Transactional commit helper for staged `session`.

Behavior:
- flushes staged persisted values to config
- if the module is enabled and the mutation bundle affects run data, reapplies mutation state
- calls `settingsObserver(host, store)` after a successful dirty commit when present
- on failure, restores the previous config snapshot and reloads `session`

`onSettingsCommitted` is a post-commit observer for rebuilding derived runtime/UI structures. It is not transactional; callback errors are warned and do not roll back the committed config.

### `lib.lifecycle.notifySettingsCommitted(def, settingsObserver, host, store)`

Runs `settingsObserver(host, store)` when present. Host flush paths use this after direct staged writes, so profile/hash imports and normal UI commits share the same observer boundary.

## Standalone Host

### `lib.createModuleHost(opts)`

Creates full and author-facing host objects around:
- optional `owner`
- `definition`
- `pluginGuid`
- `store`
- `session`
- optional `registerHooks`
- optional `registerPatchMutation`
- optional `registerManualMutation`
- optional `onSettingsCommitted`
- optional `registerIntegrations`
- `drawTab`
- optional `drawQuickContent`

`drawTab` and `drawQuickContent` receive a restricted author session:
- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`
- `session.getAliasSchema(alias)`
- `session.resetToDefaults(opts?)`

Returns the full host and the author-facing projection. Construction is side-effect
free; `host.activate()` or `authorHost.activate()` publishes the full host, refreshes hook and
integration generations for this module, runs optional registration callbacks,
and syncs initial runtime behavior. Commit and reload behavior stays on the full
host. Normal module code should use the author host returned by
`createModule(...)`.

### `lib.activateModuleHost(host)`

Activates a host created by `lib.createModuleHost(...)`. Normal author code
calls `authorHost.activate()`.

For hook refresh:
- `owner` must be a persistent table when `registerHooks` is provided
- Lib refreshes the host's hook owner during activation
- when provided, Lib runs `registerHooks(host, store)` inside that refresh
- ownerless hook declarations made through `lib.hooks.*` are refreshed as one registration pass for that owner

Activation refreshes the module's integration provider generation using
`definition.id` as the stable provider owner. If `registerIntegrations` is
provided, Lib runs `registerIntegrations(host, store)` during activation.
Registrations absent from the current activation pass are removed for that
module owner.

Returned author surface:
- `host.isEnabled()`
- `host.getIdentity()`
- `host.getMeta()`
- `host.log(fmt, ...)`
- `host.logIf(fmt, ...)`, which prints only when the module's `DebugMode` storage is enabled

`activateModuleHost(...)` is single-use for a constructed host. Calling it
twice for the same host is a state-machine error. Side-effecting full-host
methods such as `drawTab`, `commitIfDirty`, `setEnabled`, and `applyOnLoad`
require activation first.

Runtime host behavior is resolved internally through the live-host registry.

Use this as the bridge between module state and either:
- Framework hosting
- standalone window/menu hosting

Behavior:
- activation publishes the host to Lib's live-host registry
- activation refreshes optional hooks and integrations transactionally
- when a coordinator is already registered for `definition.modpack`, activation immediately syncs the module's live mutation state
- otherwise startup sync is owned by Framework or standalone hosting

### `lib.tryActivateModule(host)`

Safe wrapper around `lib.activateModuleHost(host)`.

Returns:
- `true, nil` when activation succeeds
- `false, err` when activation fails

The failure path logs `host.activate_failed`, rolls back activation side effects
through the same transaction path as `activateModuleHost(...)`, and leaves the
host unactivated. `host.tryActivate()` delegates to this helper. The author host
returned by `createModule(...)` also exposes `tryActivate()` as a safe subset of
the full host surface.

### `lib.standaloneHost(pluginGuid)`

Initializes standalone module hosting and returns window/menu-bar renderers.

Useful when the module is not framework-hosted.

`pluginGuid` must be the same plugin guid passed to `lib.createModuleHost(...)`
or `lib.createModule(...)`.

Returned surface:
- `runtime.renderWindow()`
- `runtime.addMenuBar()`
- `runtime.handleHostGuiClosed()`

Behavior:
- resolves the module's live host through the explicit `pluginGuid`
- applies on-load lifecycle state for non-coordinated modules
- suppresses the standalone window/menu when the module is coordinated
- releases overlay suppression when the host ImGui layer is hidden globally, matching Framework-hosted UI behavior
- renders built-in controls for:
  - `Enabled`
  - `Debug Mode`
  - `Resync Session`
- then calls `moduleHost.drawTab(...)`
- commits dirty staged state through `moduleHost.commitIfDirty()`

### `lib.getLiveModuleHost(pluginGuid)`

Returns the full runtime host registered by `lib.activateModuleHost(...)`.

This is an infrastructure API for Framework discovery, standalone hosting, and
Lib internals. Normal module code should keep the author host returned by
`lib.createModule(...)` and use `store`/callback sessions for state access.

## Module Coordination Queries

### `lib.isModuleCoordinated(packId)`

Returns whether a pack id is registered.

### `lib.isModuleEnabled(store, packId?)`

Returns whether a module should currently be treated as enabled, taking pack-level coordination into account when present.

## `lib.logging`

### `lib.logging.warnIf(packId, enabled, fmt, ...)`

Conditionally emits a module-scoped warning.

### `lib.logging.warn(packId, fmt, ...)`

Unconditionally emits a module-scoped warning.

### `lib.logging.logIf(name, enabled, fmt, ...)`

Conditionally emits a module-scoped log line.

## `lib.widgets`

Immediate-mode widget helpers.

Built-ins:
- `lib.widgets.separator(imgui)`
- `lib.widgets.text(imgui, text, opts?)`
- `lib.widgets.button(imgui, label, opts?)`
- `lib.widgets.confirmButton(imgui, id, label, opts?)`
- `lib.widgets.inputText(imgui, session, alias, opts?)`
- `lib.widgets.dropdown(imgui, session, alias, opts?)`
- `lib.widgets.mappedDropdown(imgui, session, alias, opts?)`
- `lib.widgets.packedDropdown(imgui, session, alias, opts?)`
- `lib.widgets.getPackedChoiceAlias(session, alias, opts?)`
- `lib.widgets.radio(imgui, session, alias, opts?)`
- `lib.widgets.mappedRadio(imgui, session, alias, opts?)`
- `lib.widgets.packedRadio(imgui, session, alias, opts?)`
- `lib.widgets.stepper(imgui, session, alias, opts?)`
- `lib.widgets.steppedRange(imgui, session, minAlias, maxAlias, opts?)`
- `lib.widgets.checkbox(imgui, session, alias, opts?)`
- `lib.widgets.packedCheckboxList(imgui, session, alias, opts?)`

These are direct immediate-mode helpers.

`getPackedChoiceAlias(...)` returns the selected child alias for packed dropdown/radio use cases, or `nil` when the selected choice is none or multiple. It uses the same `selectionMode` option as `packedDropdown(...)` and `packedRadio(...)`.

## `lib.imguiHelpers`

Low-level ImGui binding helpers used by Lib widgets and available to module UI code.

Exports:
- `lib.imguiHelpers.ImGuiComboFlags`
- `lib.imguiHelpers.ImGuiCol`
- `lib.imguiHelpers.ImGuiTreeNodeFlags`
- `lib.imguiHelpers.unpackColor(color)`

The enum tables normalize ReturnOfModding ImGui constants that are passed as raw integers in Lua.

## `lib.nav`

### `lib.nav.verticalTabs(imgui, opts)`

Simple immediate-mode vertical tab rail.

Inputs:
- `id`
- `tabs`
- `activeKey`
- optional `navWidth`
- optional `height`

Each tab entry may include:
- `key`
- `label`
- optional `group`
- optional `color`

Returns:
- next `activeKey`

### `lib.nav.isVisible(session, condition)`

Evaluates a `visibleIf`-style condition against `session.view`.

Supported forms:
- `"AliasName"`
- `{ alias = "AliasName", value = ... }`
- `{ alias = "AliasName", anyOf = { ... } }`

