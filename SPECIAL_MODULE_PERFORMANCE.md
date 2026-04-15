# Special Module Performance

Reference for writing or auditing special modules (`special = true`) without re-deriving render
performance analysis from scratch. Most patterns here reduce GC pressure, but some are general
per-frame CPU / C-boundary optimizations. All guidance comes from profiling FirstHammer and the
Framework draw loop in v2.

---

## Why special modules need render-path care

Special modules have their own sidebar tab and a `DrawQuickContent` / full-tab draw function called
every imgui frame (~60 fps). Any allocation inside those draw paths runs 60 times per second.
Lua 5.1 does not have a generational GC — every allocation contributes to the same sweep cycle.
Even small per-frame allocations can accumulate into visible stutter when the draw path is
complex. Repeated C-boundary calls and avoidable table scans also matter at 60 fps, even when
they do not allocate.

---

## Current contract assumptions

This document assumes the live special-module contract:

- `config`, `chalk`, and `reload` stay local to `main.lua`
- `local dataDefaults = import("config.lua")` and `public.store = lib.store.create(config, public.definition, dataDefaults)` are the boundary where raw config stops
- `store = public.store` may be shared across module files
- special-module draw functions receive `uiState`, not raw config
- runtime/gameplay code reads persisted state through `store.read(...)`
- Lib/Framework own `uiState` commit timing through `runUiStatePass(...)` and transactional `commitUiState(...)`

So when this document says "runtime reads persisted state", read that as:

```lua
local enabled = store.read("SomeFlag")
```

not:

```lua
local enabled = config.SomeFlag
```

---

## Per-frame render checklist

Audit every line in `DrawQuickContent`, the full-tab draw function, and any helpers they call.
Flag and fix each of these patterns:

### 1. String concatenation inside draw functions

```lua
-- BAD: new string allocated every frame
local label = "Equipped: " .. aspectLabels[currentWeapon]
imgui.Text(label)

-- GOOD: cache and rebuild only when the value changes
local _lastAspect, _lastLabel
local function getEquippedLabel()
    local cur = GetEquippedAspect()
    if cur ~= _lastAspect then
        _lastAspect = cur
        _lastLabel  = "Equipped: " .. (aspectLabels[cur] or "Unknown")
    end
    return _lastLabel
end
```

Apply this pattern to any string that is derived from slow-changing game state (equipped weapon,
run phase, current selection). Strings derived from constants are fine — they're interned.

### 2. Inline table literals as fallbacks or constants

```lua
-- BAD: new table allocated every frame (for each module checked)
local opts = staging.options[m.id] or {}

-- GOOD: module-level sentinel; or {} path is never taken in the common case
local _EMPTY_OPTS = {}
...
local opts = staging.options[m.id] or _EMPTY_OPTS
```

```lua
-- BAD: new table allocated every frame in the standalone (no-coordinator) path
local headerColor = (colors and colors.info) or { 1, 1, 1, 1 }

-- GOOD: module-level constant
local _DEFAULT_HEADER_COLOR = { 1, 1, 1, 1 }
...
local headerColor = (colors and colors.info) or _DEFAULT_HEADER_COLOR
```

Rule: any `or { ... }` or `local t = { ... }` inside a draw function is a per-frame alloc.
Move it to module scope.

### 3. `table.unpack` inside loops

```lua
-- BAD: unpack called N times (once per weapon)
for _, weaponKey in ipairs(weaponDrawOrder) do
    local r, g, b, a = table.unpack(headerColor)
    ui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
end

-- GOOD: unpack once before the loop
local hcR, hcG, hcB, hcA = table.unpack(headerColor)
for _, weaponKey in ipairs(weaponDrawOrder) do
    ui.PushStyleColor(ImGuiCol.Text, hcR, hcG, hcB, hcA)
end
```

### 4. Repeated C boundary calls for the same value

```lua
-- BAD: GetWindowWidth() crosses the C boundary twice per call site
ui.SetCursorPosX(ui.GetWindowWidth() * labelOffset)
ui.PushItemWidth(ui.GetWindowWidth() * fieldMedium)

-- GOOD: cache once per function call
local winW = ui.GetWindowWidth()
ui.SetCursorPosX(winW * labelOffset)
ui.PushItemWidth(winW * fieldMedium)
```

Cache any `ui.Get*` value that is read more than once in the same draw function. These cross
the C boundary on every call.

### 5. tostring() on values that rarely change

```lua
-- BAD: tostring on a number every frame (stepper display)
imgui.Text(tostring(currentValue))

-- GOOD: cache string, rebuild only on change
if field._lastStepperVal ~= currentValue then
    field._lastStepperStr = tostring(currentValue)
    field._lastStepperVal = currentValue
end
imgui.Text(field._lastStepperStr)
```

Cache per-field on the field descriptor itself (`field._lastStepperStr`, `field._lastStepperVal`).

---

## Let Lib/Framework own `uiState` commit timing

Do not hand-roll flush logic inside a special module.

Current hosted and standalone flows already:

- render from `uiState.view`
- apply edits through `uiState.set/update/toggle`
- commit through `lib.special.runPass(...)`
- use transactional `lib.special.commitState(...)` for `affectsRunData` modules

That means modules should not do their own equivalents of:

- manual `flushToConfig()` calls from draw code
- custom "flush after draw" helpers
- old config-snapshot bypass detectors

The module's job is:

- render from `uiState`
- stage edits into `uiState`
- let Lib/Framework own commit and rollback behavior

If you add extra debug checks around draw code, make sure they are not full-schema scans running
every frame in production.

---

## `uiState` read contract: default to `.view`

`uiState` exposes two read paths:

| Path | What it returns | Safe for tables? |
|---|---|---|
| `uiState.view.SomeField` | read-only proxy (throws on write) | Yes - proxy wraps nested tables too |
| `uiState.get("SomeField")` | raw staging value | No - gives mutable reference to table fields |

Default to `uiState.view` in draw functions. `uiState.get` is fine for scalar fields
(numbers, strings, booleans) where mutating the returned value has no effect on staging, but it
should not be the default read path for table-backed state. The proxy is the correctness
guarantee; bypassing it should be an intentional choice, not the norm.

---

## `uiState` write contract: UI writes, runtime reads

For managed special-module state, keep the boundary strict:

- UI / draw code writes through `uiState.set/update/toggle`
- gameplay/runtime code reads persisted state through `store.read(...)`
- gameplay/runtime code should not write schema-backed UI state directly

If you have a shared helper used by both UI and runtime code:

- shared reads are fine
- shared writes should require `uiState`

This avoids the most important managed-state failure mode: runtime code silently mutating
persisted state while the live UI is still rendering from `uiState`.

If a runtime path truly needs to mutate UI-managed fields, treat that as an explicit design case,
not a fallback behavior. Either:

- add a deliberate sync/reload boundary, or
- keep that state out of the managed UI schema

---

## UI batch actions belong in the state/helper layer, not gameplay logic

Operations like:

- `Ban All`
- `Reset`
- `Reset All Bans`
- `Reset All Rarity`

are not gameplay logic. They are state-edit helpers driven by the UI.

Keep them next to the storage helpers they rely on:

- packed config readers/writers
- rarity readers/writers
- count recomputation helpers

Do **not** leave these in gameplay hook files just because they existed there in a monolith.
That makes the runtime layer own UI-only mutations and muddies the architecture.

---

## After helper-driven writes, refresh stale local snapshots

This is an easy bug to introduce when converting old UI code to helper-driven state mutation.

```lua
-- BUGGY: helper writes state, but currentBans stays stale
local currentBans = internal.GetBanConfig(godName, uiState)
if ui.Button("Ban All") then
    internal.BanAllGodBans(godName, uiState)
end
...
internal.SetBanConfig(godName, currentBans, uiState) -- overwrites the helper write
```

If a button handler mutates state through a helper, refresh any local cached snapshot before
continuing the draw:

```lua
if ui.Button("Ban All") then
    if internal.BanAllGodBans(godName, uiState) then
        currentBans = internal.GetBanConfig(godName, uiState)
    end
end
```

Otherwise the draw function can render stale state and even write the old value back at the end
of the frame.

---

## Initialization-order hazard: never bind shared tables through `or {}`

When moving helpers across files, be careful with module-shared tables on `internal.*`.

```lua
-- BUGGY: captures a private fallback table if another file initializes later
local godInfo = internal.godInfo or {}
```

If another imported file later does:

```lua
internal.godInfo = internal.godInfo or {}
```

you now have two different tables.

Correct pattern:

```lua
internal.godInfo = internal.godInfo or {}
local godInfo = internal.godInfo
```

This is especially important in hot-reloadable multi-file modules where helper files are imported
before the runtime/data population file.

---

## Second-pass optimizations: pre-build lookup structures at module load time

For dropdown-heavy special modules that map a selection to an index:

### Reverse index (replaces O(n) linear scan)

```lua
-- At module load, after building data tables:
for _, weaponName in ipairs(weaponDrawOrder) do
    local data = hammerData[weaponName]
    data.valueIndex = {}
    for i, v in ipairs(data.values) do
        data.valueIndex[v] = i
    end
end

-- In draw function (O(1) instead of O(n)):
local currentIndex = data.valueIndex[currentId] or 1
```

### Pre-built path tables (replaces inline table alloc on every selection)

`uiState.set` takes a path table `{"Parent", "Child"}`. If you allocate this inline on
every user selection, a new table is created on each click. Pre-build at module load:

```lua
local _hammerPaths = {}
for _, weaponName in ipairs(weaponDrawOrder) do
    local aspects = WeaponAspectMapping[weaponName]
    if aspects then
        for _, aspectName in ipairs(aspects) do
            _hammerPaths[aspectName] = { "FirstHammers", aspectName }
        end
    end
end

-- In draw function:
uiState.set(_hammerPaths[aspectKey], data.values[i])
```

This is worthwhile when the path shape is fixed and can be known at load time. It is a second-pass
optimization, not a baseline requirement for every special module.

---

## Hide group headers when the active accordion lock suppresses the whole group

If a special tab hides non-active accordions once one item is expanded, make sure group headers are
gated by “this group can actually render an entry” rather than just “this group has candidates”.

```lua
-- BAD: header can render even though all entries are suppressed by openGodName
if shouldDraw then
    if not drewEntry then
        DrawColoredText(ui, headingColor, group)
    end
end

-- GOOD: include the accordion-lock check
local canRenderAccordion = shouldDraw and (not openGodName or openGodName == godName)
if canRenderAccordion then
    if not drewEntry then
        DrawColoredText(ui, headingColor, group)
    end
end
```

This is not a performance issue by itself, but it is a common UI correctness bug when optimizing
grouped special tabs.

---

## Logging: let `lib.log` handle cheap debug gating

If a debug path is just a direct log call, do not also wrap it in:

```lua
if store.read("DebugMode") then
    Log("...")
end
```

when `Log(...)` already calls `lib.log(moduleId, store.read("DebugMode") == true, ...)`.

Keep explicit `if store.read("DebugMode") then` only when it prevents real extra work:

- building joined strings
- scanning tables just for the log
- dumping a queue / list
- preparing multiple values only used in debug mode

This keeps hot code cleaner and avoids redundant debug branches.

---

## vararg functions: avoid `{...}` table allocation

If you write a helper that accepts varargs and iterates them:

```lua
-- BAD: allocates a table on every call
local function myHelper(tbl, ...)
    local keys = { ... }
    for _, k in ipairs(keys) do ...end
end

-- GOOD: iterate with select, no table allocated
local function myHelper(tbl, ...)
    for i = 1, select('#', ...) do
        local k = select(i, ...)
        ...
    end
end
```

`lib.mutation.createBackup()` returns a backup function that uses this pattern — follow it for any module-level vararg helpers.

---

## Quick audit workflow for a new special module

Additional checks from the Run Director migration:

- shared helpers may support runtime reads, but helper writes should require `uiState`
- button handlers that call helper mutations should refresh any stale local snapshot afterward
- moved helpers should not bind shared tables through `internal.someTable or {}`
- grouped tabs with accordion lock should hide headers when no entry in that group can actually render

1. Read the full `DrawQuickContent` and full-tab draw function.
2. Search for: `.. `, `or {}`, `or { `, `table.unpack(` inside loops, repeated `ui.Get*` calls,
   `tostring(` inside draw paths.
3. Check for hand-rolled `flushToConfig()` / post-draw commit logic - remove it unless the module
   has a very explicit reason to bypass standard Lib/Framework helpers.
4. Check `uiState.get` - replace with `uiState.view` unless the field is scalar.
5. Check dropdown logic — if there is a linear scan over `data.values`, add a `valueIndex` map.
6. Check `uiState.set` path arguments - if inline `{ "Parent", "Child" }`, pre-build.
7. Check any strings derived from game state (equipped weapon, phase, selection) — add label cache.
8. Check any `or { literal }` fallbacks or constant color tables — hoist to module scope.

