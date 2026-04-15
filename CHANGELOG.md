# Changelog

## [Unreleased]

---

## [v2] — Layout Substrate Rewrite

Complete rewrite of the UI rendering substrate and registry model. This release is not backward-compatible with modules targeting v1.

### Breaking Changes

**Registry model**

- Single `FieldTypes` registry replaced by three separate registries: `lib.registry.storage`, `lib.registry.widgets`, `lib.registry.layouts`
- `definition.options` and `definition.stateSchema` are no longer supported; use `definition.storage` and `definition.ui`

**Layout types**

Old v1 layout types are removed: `separator`, `group`, `horizontalTabs`, `verticalTabs`, `panel`

Replacements:
- `group` → `vstack` (plain vertical grouping) or `collapsible` (collapsible section)
- `horizontalTabs` / `verticalTabs` → `tabs` with `orientation = "horizontal"` / `"vertical"`
- `panel` → `hstack` / `vstack` composition
- `separator` → `separator` widget (no longer a layout node)

**Widget draw contract**

Old: `draw(imgui, node, bound, width, uiState)`

New: `draw(imgui, node, bound, x, y, availWidth, availHeight, uiState)`

Widgets must return `consumedWidth, consumedHeight, changed`.

**Layout render contract**

Old: `render(imgui, node, drawChild)` returning `open` or `open, changed`

New: `render(imgui, node, drawChild, x, y, availWidth, availHeight, uiState, bound)` returning `consumedWidth, consumedHeight, changed`

**Geometry blocks removed**

`geometry = { slots = { ... } }` is no longer part of the widget contract. Replaced by direct node properties:
- `stepper` / `steppedRange` value slot: `valueWidth`, `valueAlign`
- `inputText` / `dropdown` / `mappedDropdown` control width: `controlWidth`
- `text` block width: `width`

`slots`, `dynamicSlots`, and `defaultGeometry` are removed from the custom widget type contract.

**API surface**

Flat `lib.*` names are replaced by a namespaced surface. Old names still work through `src/compat/legacy_api.lua` for existing modules but should not be used in new code.

### Added

**Storage types**

- `bool` — normalizes to `true`/`false`, hashes as `"1"`/`"0"`, packs as 1 bit
- `int` — normalizes with min/max clamp and floor, hashes as decimal string, packs with derivable width
- `string` — normalizes to string, optional `maxLen`
- `packedInt` — root type for alias-addressable packed bit partitions; child aliases are materialized automatically

**Widget types**

- `separator` — horizontal separator line; no binds
- `stepper` — `[−] value [+]` with optional `fastStep`; supports `displayValues`, `valueColors`
- `steppedRange` — paired min/max steppers sharing a label
- `button` — push button with optional `onClick` callback
- `confirmButton` — two-step confirmation button with configurable timeout
- `inputText` — text input bound to string storage; supports `controlWidth`
- `mappedDropdown` — dropdown with caller-supplied preview and option callbacks
- `packedDropdown` — dropdown over packed bit child aliases
- `mappedRadio` — radio group with caller-supplied option callbacks
- `packedRadio` — radio group over packed bit child aliases
- `packedCheckboxList` — checkbox list over packed child aliases; supports `filterText` and `filterMode` binds, `valueColors`

**Layout types**

- `vstack` — vertical child stack with configurable `gap`
- `hstack` — horizontal child stack with configurable `gap`
- `tabs` — horizontal or vertical tab container; supports `binds.activeTab` for alias-backed selection
- `collapsible` — collapsible section with `label` and `defaultOpen`
- `scrollRegion` — child-window-backed scrollable container
- `split` — two-pane split layout with `ratio`, `firstSize`, `secondSize`, and optional `gap`

**Managed UI state**

- `store.uiState` — transactional staging layer over persisted config
- `uiState.view` — read-only proxy for safe draw-path reads
- `uiState.get` / `uiState.set` / `uiState.update` / `uiState.toggle` / `uiState.reset`
- `uiState.flushToConfig` — flush staged changes to persisted config
- `uiState.isDirty` — check whether any staged value has diverged from config
- Mismatch detection and snapshot/restore for transactional rollback

**Transient storage roots**

Storage nodes may declare `lifetime = "transient"` instead of `configKey`. Transient roots participate in `uiState` staging but do not persist, hash, or flush.

**Mutation lifecycle**

- `lib.mutation.createPlan()` — reversible mutation plan with `set`, `setMany`, `transform`, `append`, `appendUnique`, `removeElement`, `setElement`, `apply`, `revert`
- `lib.mutation.createBackup()` — isolated backup/restore pair
- `lib.mutation.inferShape(def)` — infers lifecycle shape: `patch`, `manual`, `hybrid`
- `lib.mutation.apply` / `lib.mutation.revert` / `lib.mutation.reapply` / `lib.mutation.setEnabled`
- Modules may declare `affectsRunData = true` to opt into run-data mutation behavior

**Namespaced API surface**

- `lib.store.*`
- `lib.definition.*`
- `lib.mutation.*`
- `lib.ui.*`
- `lib.storage.*`
- `lib.special.*`
- `lib.coordinator.*`
- `lib.logging.*`
- `lib.accessors.*`
- `lib.registry.*`

**Special module helpers**

- `lib.special.runPass(opts)` — orchestrated UI pass with commit/flush/callback flow
- `lib.special.runDerivedText(uiState, entries, cache?)` — signature-cached derived alias recomputation
- `lib.special.getCachedPreparedNode(...)` — caller-owned prepared-node cache with rebuild detection
- `lib.special.auditAndResyncState(name, uiState)` — staged vs config drift audit
- `lib.special.commitState(def, store, uiState)` — flush + reapply with rollback on failure
- `lib.special.standaloneUI(def, store, uiState?, opts?)` — standalone window/menu-bar renderers for special modules

**Other**

- `visibleIf` on widget nodes — bool alias shorthand, `{ alias, value }`, or `{ alias, anyOf = { ... } }`
- `valueColors` on `checkbox`, `dropdown`, `radio`, `stepper`, `packedCheckboxList`
- `filterMode` bind on `packedCheckboxList` — `"all"`, `"checked"`, `"unchecked"`
- Printf-style logging — string formatting deferred past the enabled gate; no allocation when disabled
- `lib.registry.widgetHelpers.drawStructuredAt(...)` and `estimateRowAdvanceY(...)` as public helpers for custom widget authors

---

## [v1] — Initial Release

### Added

- `createStore(config, definition?)` — module store facade
- `standaloneUI()` — menu-bar toggle callback for modules without coordinator hosting
- `isEnabled()` — checks module store and coordinator master toggle
- `readPath()` / `writePath()` — string and table-path accessors for nested config keys
- `drawField()` — ImGui widget renderer delegating to the FieldTypes registry
- `validateSchema()` — declaration-time field descriptor validation and metadata caching
- `createBackupSystem()` — isolated backup/revert with first-call-only semantics
- FieldTypes registry with `checkbox`, `dropdown`, and `radio` built-in types
- Unit tests (LuaUnit, Lua 5.1) for field types, path helpers, validation, backup, special state, and `isEnabled`
- CI with Luacheck linting and branch protection on `main`
