local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local registrations = deps.registrations
local invocation = deps.invocation
local author = {}

local function requireHostState(host, context)
    local state = hostState.get(host)
    if not state then
        logging.violate("integrations.invalid_args", "%s: expected managed module host state", context)
    end
    return state
end

local function requireRegistrationOpen(host)
    local state = requireHostState(host, "host.integrations.register")
    if state.activated == true or state.activating == true then
        logging.violate(
            "integrations.invalid_args",
            "host.integrations.register: cannot register after activation begins"
        )
    end
    return state
end

function author.create(host)
    return {
        register = function(id, opts)
            return registrations.stageAuthorRegistration(requireRegistrationOpen(host), id, opts)
        end,
        invoke = function(id, methodName, fallback, ...)
            requireHostState(host, "host.integrations.invoke")
            return invocation.invoke("host.integrations.invoke", id, methodName, fallback, ...)
        end,
    }
end

return author
