# Module Authoring

This guide describes the current supported module contract in Lib.

It is written for the live surface:
- namespaced public API
- managed storage and explicit `session`
- immediate-mode widgets
- direct `DrawTab(ui, session)` authoring

It does not document the old declarative `definition.ui` model.

## Preferred Lib Surface

New module code should use:
- `lib.config`
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`
- `lib.hashing.*`
- `lib.mutation.*`
- `lib.lifecycle.*`
- `lib.widgets.*`
- `lib.nav.*`

Old flat compatibility aliases should not be used for new code.

## Basic Module Shape

Typical coordinated module:

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    tooltip = "What this module does.",
    default = false,
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    },
}

public.store, public.session = lib.createStore(config, public.definition, dataDefaults)
store = public.store
session = public.session

function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "EnabledFlag", {
        label = "Enabled",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 180,
    })
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 140,
    })
end

public.DrawTab = internal.DrawTab
public.DrawQuickContent = internal.DrawQuickContent
```

This example assumes coordinated/framework hosting.
For standalone-only modules, `DrawQuickContent` is optional and only matters if some external host uses it.

## Definition Rules

Meaningful module definition fields:
- `modpack`
- `id`
- `name`
- `shortName`
- `tooltip`
- `default`
- `storage`
- `hashGroups`
- `affectsRunData`
- `patchPlan`
- `apply`
- `revert`

Ignored under the current lean contract:
- `category`
- `subgroup`
- `placement`
- `ui`
- `customTypes`
- `selectQuickUi`

If you keep those fields around, Lib will warn in debug mode.

Coordinated modules should declare:
- `modpack`
- `id`
- `name`
- `storage`

Under the current framework contract:
- every coordinated module gets its own tab
- `shortName` is used as the shorter tab label when present

## Store and State Rules

After store creation:
- use `store.read(alias)` for persisted runtime state
- use the explicit `session` return for staged UI state
- keep raw Chalk config local to `main.lua`

Draw code should usually read from:
- `session.view`

Runtime/gameplay code should usually read from:
- `store.read(...)`

Lifecycle/framework plumbing can persist built-in host state through:
- `lib.lifecycle.setEnabled(def, store, enabled)`
- `lib.lifecycle.setDebugMode(store, enabled)`

Hash/profile plumbing should stage arbitrary decoded aliases through:
- `session.write(alias, value)`
- `session.flushToConfig()`

Do not write schema-backed persisted values directly from draw code through raw config or `lib.lifecycle.*` helpers.

Also avoid:
- `store.read(...)` for transient aliases
- direct persisted writes from draw code

Use `session` for those instead.

## Storage Authoring

### Persisted roots

```lua
{ type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
{ type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 }
{ type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 }
```

### Transient roots

```lua
{ type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 }
```

Rules:
- persisted roots use `configKey`
- transient roots use `lifetime = "transient"`
- `configKey` and `lifetime` are mutually exclusive
- transient roots do not hash

### Packed storage

Use `packedInt` when you need alias-addressable packed children:

```lua
{
    type = "packedInt",
    alias = "PackedAphrodite",
    configKey = "PackedAphrodite",
    bits = {
        { alias = "AttackBanned", offset = 0, width = 1, type = "bool", default = false },
        { alias = "RarityOverride", offset = 1, width = 2, type = "int", default = 0 },
    },
}
```

If the module only treats the packed value as a raw mask, keep it as a plain root `int` instead.

## Immediate-Mode UI

Current module UI should be authored directly in Lua draw functions.

Typical patterns:
- `lib.widgets.checkbox(...)`
- `lib.widgets.dropdown(...)`
- `lib.widgets.radio(...)`
- `lib.widgets.stepper(...)`
- `lib.widgets.packedCheckboxList(...)`
- `lib.nav.verticalTabs(...)`

Use raw ImGui layout as needed:
- `ui.Text(...)`
- `ui.SameLine()`
- `ui.BeginTabBar(...)`
- `ui.BeginChild(...)`

Lib widgets are helpers, not a full layout runtime.

## Quick Content

Framework Quick Setup now reads only:
- coordinator `renderQuickSetup(ctx)`
- module `DrawQuickContent(ui, session)`

There is no quick-node discovery from `definition.ui`.
Standalone host does not consume `DrawQuickContent`.

## Mutation Lifecycle

Use `affectsRunData = true` only when the module actually mutates live run data.

Supported lifecycle shapes:
- patch only: `patchPlan(plan, store)`
- manual only: `apply(store)` + `revert(store)`
- hybrid: both

Patch-plan example:

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "Enabled", true)
    plan:appendUnique(SomeTable, "Pool", "NewEntry")
end
```

Lib helpers:
- `lib.lifecycle.setEnabled(def, store, enabled)`
- `lib.lifecycle.applyMutation(def, store)`
- `lib.lifecycle.revertMutation(def, store)`
- `lib.lifecycle.reapplyMutation(def, store)`

## Coordinated Modules

Framework-hosted modules should export:
- `public.definition`
- `public.store`
- `public.session`
- `public.host`
- `public.DrawTab`
- optional `public.DrawQuickContent`

Framework discovery requires:
- `definition.modpack`
- `definition.id`
- `definition.name`
- `definition.storage`
- public `host`
- public `store`
- public `session`
- public `DrawTab`

Framework behavior:
- each coordinated module gets its own top-level tab
- `DrawTab` is the normal rendering contract
- `DrawQuickContent` participates only in Quick Setup

## Standalone Modules

For non-framework hosting, use:

```lua
public.host = lib.createModuleHost({
    definition = public.definition,
    store = public.store,
    session = public.session,
    drawTab = public.DrawTab,
    drawQuickContent = public.DrawQuickContent,
})

local runtime = lib.standaloneHost(public.host)

rom.gui.add_imgui(runtime.renderWindow)
rom.gui.add_to_menu_bar(runtime.addMenuBar)
```

Notes:
- `lib.standaloneHost(...)` suppresses its window/menu when the module is coordinated
- `lib.standaloneHost(...)` applies startup lifecycle state for non-coordinated modules
- the standalone window includes built-in:
  - `Enabled`
  - `Debug Mode`
  - `Resync Session`
- the standalone window only calls `DrawTab`; it does not use `DrawQuickContent`

## Complete Example

This is a minimal end-to-end module shape showing:
- `main.lua`
- storage
- `DrawTab`
- optional `DrawQuickContent`
- standalone wiring

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
local chalk = mods["SGG_Modding-Chalk"]
local reload = mods["SGG_Modding-ReLoad"]
lib = mods["adamant-ModpackLib"]

local dataDefaults = import("config.lua")
local config = chalk.auto("config.lua")

local PACK_ID = "example-pack"
ExampleModule_Internal = ExampleModule_Internal or {}
local internal = ExampleModule_Internal

public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    shortName = "Example",
    tooltip = "Demonstrates the current Lib module contract.",
    default = dataDefaults.Enabled,
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "FeatureEnabled", configKey = "FeatureEnabled", default = false },
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
        {
            type = "packedInt",
            alias = "PackedFlags",
            configKey = "PackedFlags",
            default = 0,
            bits = {
                { alias = "PackedFlags_Attack", label = "Attack", type = "bool", offset = 0, width = 1, default = false },
                { alias = "PackedFlags_Special", label = "Special", type = "bool", offset = 1, width = 1, default = false },
            },
        },
    },
}

public.store = nil
public.session = nil
public.host = nil
store = nil
session = nil
internal.standaloneUi = nil

function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "FeatureEnabled", {
        label = "Enable Feature",
        tooltip = "Turns the feature logic on for this module.",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 180,
    })

    lib.widgets.inputText(ui, session, "FilterText", {
        label = "Filter",
        controlWidth = 180,
    })

    ui.Separator()
    lib.widgets.text(ui, "Packed Flags")
    lib.widgets.packedCheckboxList(ui, session, "PackedFlags", store, {
        optionsPerLine = 2,
    })
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 140,
    })
end

local function registerHooks()
    public.DrawTab = internal.DrawTab
    public.DrawQuickContent = internal.DrawQuickContent
end

local function init()
    import_as_fallback(rom.game)

    public.store, public.session = lib.createStore(config, public.definition, dataDefaults)
    store = public.store
    session = public.session
    registerHooks()

    public.host = lib.createModuleHost({
        definition = public.definition,
        store = public.store,
        session = public.session,
        drawTab = public.DrawTab,
        drawQuickContent = public.DrawQuickContent,
    })

    internal.standaloneUi = lib.standaloneHost(public.host)
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(init, init)
end)

rom.gui.add_imgui(function()
    if internal.standaloneUi and internal.standaloneUi.renderWindow then
        internal.standaloneUi.renderWindow()
    end
end)

rom.gui.add_to_menu_bar(function()
    if internal.standaloneUi and internal.standaloneUi.addMenuBar then
        internal.standaloneUi.addMenuBar()
    end
end)
```

Notes on the example:
- `config` and `reload` stay local to `main.lua`
- `store` is recreated on every reload
- `public.host` owns the behavior contract used by framework or standalone hosting
- `DrawTab` uses raw ImGui for structure and `lib.widgets.*` for controls
- `DrawQuickContent` is optional
- packed widgets need the module `store`





