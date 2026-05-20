local deps = ...

local registry = import('core/integrations/registry.lua', nil, {
    runtime = deps.runtime,
})

local registrations = import('core/integrations/registrations.lua', nil, {
    logging = deps.logging,
    registry = registry,
})

local invocation = import('core/integrations/invocation.lua', nil, {
    logging = deps.logging,
    registry = registry,
})

local service = import('core/integrations/adapter_host.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    registrations = registrations,
})

local author = import('core/integrations/adapter_author.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    registrations = registrations,
    invocation = invocation,
})

return {
    service = service,
    author = author,
}
