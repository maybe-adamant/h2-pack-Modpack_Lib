local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local registrations = deps.registrations
local hostAdapter = {}

local function requireHostState(host, context)
    local state = hostState.get(host)
    if not state then
        logging.violate("integrations.invalid_args", "%s: expected managed module host state", context)
    end
    return state
end

function hostAdapter.installForHost(host)
    local state = requireHostState(host, "integrations.installForHost")
    local ownerId = host.getHostId()
    return registrations.install(ownerId, state.integrationRegistrations)
end

return hostAdapter
