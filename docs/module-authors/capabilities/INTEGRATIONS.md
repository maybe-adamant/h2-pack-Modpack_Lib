# Integrations

Integrations are optional cross-module provider APIs. They let one module publish a small domain capability and let other modules consume it without hard dependency coupling.

Use integrations when modules can cooperate but should still work when the provider is absent.

## Provider Shape

Hosted modules should register providers inside `registerIntegrations(host, store)`:

```lua
local function registerIntegrations(host, store)
    lib.integrations.register("run-director.god-availability", MODULE_ID, {
        isActive = function()
            return host.isEnabled()
        end,
        isAvailable = function(godKey)
            return true
        end,
    })
end

local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    registerIntegrations = registerIntegrations,
    drawTab = ui.drawTab,
})
host.tryActivate()
```

`providerId` is the public provider identity returned to consumers. It does not need to match `pluginGuid`.

## Consumer Shape

Consumers should prefer `invoke(...)`:

```lua
local active = lib.integrations.invoke("run-director.god-availability", "isActive", false)
if active then
    return lib.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey) ~= false
end
return true
```

`invoke(...)` resolves the current preferred provider at call time and returns the fallback when the provider or method is absent.

## Public Surface

Use:

- `lib.integrations.register(id, providerId, api)`
- `lib.integrations.unregister(id, providerId)`
- `lib.integrations.unregisterProvider(providerId)`
- `lib.integrations.invoke(id, methodName, fallback, ...)`
- `lib.integrations.get(id)`
- `lib.integrations.list(id)`

Hosted provider registrations made during `registerIntegrations(...)` are owned by the activating host and are retired when that host is replaced.

Manual unregister calls are mainly for non-hosted or advanced provider ownership.

## Naming

Integration ids should describe domain behavior, not a specific consumer:

```text
run-director.god-availability
run-director.route-state
```

Provider ids should identify the module or provider implementation.

## Common Mistakes

- Do not make consumers require a provider to exist unless it is truly mandatory.
- Do not cache provider API tables across reloads; use `invoke(...)` unless you have a specific reason.
- Do not expose raw module internals through provider APIs.
- Do not assume provider id and `pluginGuid` are the same concept.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
