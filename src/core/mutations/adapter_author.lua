local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local lifecycle = deps.lifecycle
local author = {}

local function requireHostState(host, apiName)
    local state = hostState.get(host)
    if not state then
        logging.violate("mutation.invalid_registration", "%s: expected managed module host state", apiName)
    end
    return state
end

local function requireDeclarationOpen(host, apiName)
    local state = requireHostState(host, "host.mutation." .. apiName)
    if state.activating == true then
        logging.violate("mutation.invalid_registration", "host.mutation.%s cannot be called during host activation", apiName)
    end
    if state.activated == true then
        logging.violate("mutation.invalid_registration", "host.mutation.%s cannot be called after host activation", apiName)
    end
    return state
end

function author.create(host)
    return {
        patch = function(callback)
            local state = requireDeclarationOpen(host, "patch")
            return lifecycle.declarePatch(state.mutationBundle, callback)
        end,
    }
end

return author
