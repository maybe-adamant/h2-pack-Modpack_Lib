local deps = ...

local logging = deps.logging
local registry = deps.registry
local invocation = {}

local function validateIntegrationId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("integrations.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateMethodName(context, methodName)
    if type(methodName) ~= "string" or methodName == "" then
        logging.violate("integrations.invalid_args", "%s: methodName must be a non-empty string", context)
    end
end

function invocation.invoke(context, id, methodName, fallback, ...)
    validateIntegrationId(context, id)
    validateMethodName(context, methodName)

    local api, providerId = registry.getPreferredProvider(id)
    local method = api and api[methodName] or nil
    if type(method) ~= "function" then
        return fallback, providerId
    end

    local ok, result = pcall(method, ...)
    if not ok then
        logging.violate(
            "integrations.provider_failed",
            "%s.%s provider '%s' failed: %s",
            tostring(id),
            tostring(methodName),
            tostring(providerId),
            tostring(result))
        return fallback, providerId
    end

    return result, providerId
end

return invocation
