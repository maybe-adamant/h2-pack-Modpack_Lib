local deps = ...

local logging = deps.logging

local systemScope = {}

local function validateOwnerId(ownerId)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("system_scope.invalid_owner", "createSystem: ownerId must be a non-empty string")
    end
end

function systemScope.create(ownerId, capabilities)
    validateOwnerId(ownerId)
    capabilities = capabilities or {}

    local scope = {}
    function scope.getOwnerId()
        return ownerId
    end

    if capabilities.hooks then
        scope.hooks = capabilities.hooks.create(scope, ownerId)
    end
    if capabilities.overlays then
        scope.overlays = capabilities.overlays.create(scope, ownerId)
    end

    return scope
end

return systemScope
