# Migrating To Plugin-Guid Runtime Identity

This note covers the module lifecycle identity change that removes normal
module-authored `owner` tokens.

## What Changed

- `lib.createModule(...)` and `lib.tryCreateModule(...)` no longer accept
  `owner`.
- `pluginGuid` is the stable lookup identity for a module host.
- The committed host is the managed lifecycle owner for hooks, overlays,
  integrations, activation metadata, and structural hot-reload comparison.
- Mutation runtime is still plugin-scoped because raw game-table edits are
  process-global.
- `definition.id` remains the module's domain/UI/profile/hash identity.
- `modpack` remains coordinator grouping.

## Module Migration

Before:

```lua
local host = lib.tryCreateModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = internal.definition,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
})
```

After:

```lua
local definition = import("mods/definition.lua")
local logic = import("mods/logic.lua")
local ui = import("mods/ui.lua")

local host = lib.tryCreateModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = definition,
    registerHooks = logic.registerHooks,
    drawTab = ui.drawTab,
})
```

Modules should use `lib.standaloneUiBridge(pluginGuid)` for stable standalone
GUI callbacks instead of keeping private persistent tables for standalone UI
handles. Private persistent tables are still valid for truly module-owned cached
data, but they should not be passed to Lib as lifecycle owners.

## Hook And Overlay Notes

Normal module hooks stay ownerless inside `registerHooks(host, store)`:

```lua
local function registerHooks(host, store)
    lib.hooks.Wrap("SomeGameFunction", function(base, ...)
        return base(...)
    end)
end
```

Lib scopes those declarations to the module's `pluginGuid`. Explicit-owned APIs
were retired for normal authoring. Lib and Framework infrastructure should use
the narrow `lib.overlays.defineSystem(...)` HUD-line surface instead of general
owner tokens.

## Integration Notes

`registerIntegrations(host, store)` is refreshed by the module's `pluginGuid`.
The `providerId` passed to `lib.integrations.register(id, providerId, api)` is
still the public integration provider identity, not the lifecycle owner. It can
remain a module/domain id chosen for consumers.
