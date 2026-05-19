# Hooks

Hooks let a module participate in game or ModUtil call paths without owning the physical hook lifetime directly.

Use hooks when the module needs to inspect, transform, or replace runtime behavior at a named path. Do not use hooks for configuration UI or declarative run-data edits; use [WIDGETS.md](WIDGETS.md) and [MUTATIONS.md](MUTATIONS.md) for those.

## Normal Shape

Declare hooks inside `registerHooks(host, store)` and pass that callback to `lib.createModule(...)`:

```lua
local function registerHooks(host, store)
    lib.hooks.Wrap("GetEligibleLootNames", function(base, ...)
        local result = base(...)
        if host.isEnabled() and store.read("FeatureEnabled") then
            -- inspect or transform result here
        end
        return result
    end)
end

local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    registerHooks = registerHooks,
    drawTab = ui.drawTab,
})
host.tryActivate()
```

Ownerless hook calls inside `registerHooks(...)` are scoped to the activating module host. The hook file does not need an owner token.

## Supported Hook Forms

Use:

- `lib.hooks.Wrap(path, handler)`
- `lib.hooks.Wrap(path, key, handler)`
- `lib.hooks.Override(path, replacement)`
- `lib.hooks.Override(path, key, replacement)`
- `lib.hooks.Context.Wrap(path, context)`
- `lib.hooks.Context.Wrap(path, key, context)`

Use a keyed overload when one module needs more than one registration for the same path.

## Lifecycle

`host.tryActivate()` runs the hook registration pass. Lib owns:

- installing the stable physical dispatcher
- refreshing behavior on module reload
- removing hook behavior omitted by a later registration pass for the same `pluginGuid`
- rolling back activation when hook setup fails

Hook declarations should be repeatable. A hot reload should be able to run `registerHooks(...)` again and describe the complete current hook set.

## Runtime State

Hook callbacks should read committed state from `store`:

```lua
if host.isEnabled() and store.read("FeatureEnabled") then
    -- enabled committed behavior
end
```

Do not read draw-session state inside hook callbacks. Draw sessions are staged UI state; hooks run against committed runtime behavior.

## Wrap vs Override

Prefer `Wrap` when the original behavior should still run. Use `Override` only when the module must fully replace the target path.

Overrides are inherently higher risk because only one replacement behavior can own the path at a time. Keep override handlers small, stable, and easy to reason about.

## Common Mistakes

- Do not call `lib.hooks.*` at file top level for a hosted module.
- Do not use random keys for keyed hooks; keys are part of hook identity.
- Do not capture staged UI session state in runtime hooks.
- Do not use hooks for declarative table edits that fit mutation plans.

See also:
- [MUTATIONS.md](MUTATIONS.md)
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
