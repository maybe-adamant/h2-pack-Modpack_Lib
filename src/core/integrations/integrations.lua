local internal = AdamantModpackLib_Internal
local registry = import 'core/integrations/private_registry.lua'

public.integrations = public.integrations or {}
internal.integrations = internal.integrations or {}

local ActiveHostInstallStack = {}

local function makeNoopReceipt()
    local closed = false
    return {
        commit = function()
            closed = true
            return true, nil
        end,
        dispose = function()
            if closed then
                closed = true
            end
            return true, nil
        end,
    }
end

local function recordStagedRegistration(install, id, providerId, api)
    local key = id .. "\0" .. providerId
    local entry = install.byKey[key]
    if not entry then
        entry = {
            id = id,
            providerId = providerId,
            api = api,
        }
        install.byKey[key] = entry
        install.entries[#install.entries + 1] = entry
    else
        entry.api = api
    end
    return api
end

function internal.integrations.installForHost(host, register, authorHost, store)
    if register == nil then
        return makeNoopReceipt()
    end
    if type(host) ~= "table" then
        internal.violate("integrations.invalid_args", "internal.integrations.installForHost: host is required")
    end
    if type(register) ~= "function" then
        internal.violate("integrations.invalid_args", "internal.integrations.installForHost: register must be a function")
    end

    local install = {
        host = host,
        entries = {},
        byKey = {},
        previous = {},
        committed = false,
        disposed = false,
    }

    ActiveHostInstallStack[#ActiveHostInstallStack + 1] = install
    local ok, err = pcall(register, authorHost, store)
    ActiveHostInstallStack[#ActiveHostInstallStack] = nil

    if not ok then
        error(err, 0)
    end

    return {
        commit = function()
            if install.disposed or install.committed then
                return true, nil
            end
            for _, entry in ipairs(install.entries) do
                local bucket = registry.getBucket(entry.id, false)
                local key = entry.id .. "\0" .. entry.providerId
                install.previous[key] = {
                    id = entry.id,
                    providerId = entry.providerId,
                    existed = bucket and bucket.providers[entry.providerId] ~= nil or false,
                    api = bucket and bucket.providers[entry.providerId] or nil,
                    owner = bucket and bucket.owners and bucket.owners[entry.providerId] or nil,
                    orderIndex = bucket and registry.getProviderOrderIndex(bucket, entry.providerId) or nil,
                }
                registry.setProvider(entry.id, entry.providerId, entry.api, host)
            end
            install.committed = true
            return true, nil
        end,
        dispose = function()
            if install.disposed then
                return true, nil
            end
            if install.committed then
                for index = #install.entries, 1, -1 do
                    local entry = install.entries[index]
                    local key = entry.id .. "\0" .. entry.providerId
                    local previous = install.previous[key]
                    local bucket = registry.getBucket(entry.id, previous and previous.existed or false)
                    if bucket and registry.getProviderOwner(entry.id, entry.providerId) == host then
                        if previous and previous.existed then
                            bucket.providers[entry.providerId] = previous.api
                            bucket.owners[entry.providerId] = previous.owner
                            registry.insertProviderOrder(bucket, entry.providerId, previous.orderIndex)
                        else
                            registry.removeProviderFromBucket(bucket, entry.providerId, host)
                            registry.pruneBucket(entry.id, bucket)
                        end
                    end
                end
            end
            install.disposed = true
            return true, nil
        end,
    }
end

--- Registers or replaces an optional cross-module integration provider.
--- Re-registering the same `id` and `providerId` updates the API in place.
---@param id string Domain-named integration id, e.g. "run-director.god-availability".
---@param providerId string Public provider identity, independent from module lifecycle ownership.
---@param api table Provider API table exposed to consumers.
---@return table api The registered API table.
function public.integrations.register(id, providerId, api)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: id must be a non-empty string")
    end
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: providerId must be a non-empty string")
    end
    if type(api) ~= "table" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: api must be a table")
    end

    local activeInstall = ActiveHostInstallStack[#ActiveHostInstallStack]
    if activeInstall then
        return recordStagedRegistration(activeInstall, id, providerId, api)
    end

    return registry.setProvider(id, providerId, api, providerId)
end

--- Unregisters one provider for one integration id.
---@param id string Integration id.
---@param providerId string Public provider identity.
---@return boolean removed True when a provider was removed.
function public.integrations.unregister(id, providerId)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.unregister: id must be a non-empty string")
    end
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.unregister: providerId must be a non-empty string")
    end

    local bucket = registry.getBucket(id, false)
    local removed = registry.removeProviderFromBucket(bucket, providerId)
    registry.pruneBucket(id, bucket)
    return removed
end

--- Unregisters a provider from all integration ids.
---@param providerId string Public provider identity.
---@return number count Number of removed provider registrations.
function public.integrations.unregisterProvider(providerId)
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate(
            "integrations.invalid_args",
            "lib.integrations.unregisterProvider: providerId must be a non-empty string"
        )
    end

    local count = 0
    for id, bucket in pairs(registry.getRegistry()) do
        if registry.removeProviderFromBucket(bucket, providerId) then
            count = count + 1
            registry.pruneBucket(id, bucket)
        end
    end
    return count
end

--- Returns the preferred provider API for an integration id.
--- When multiple providers exist, the most recently registered provider wins.
---@param id string Integration id.
---@return table|nil api Provider API table, or nil when absent.
---@return string|nil providerId Provider id for the returned API.
function public.integrations.get(id)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.get: id must be a non-empty string")
    end

    return registry.getPreferredProvider(id)
end

--- Resolves the current preferred provider and invokes one method immediately.
--- This is the preferred consumer path because it avoids caching stale provider APIs.
---@param id string Integration id.
---@param methodName string Provider API method name.
---@param fallback any Value returned when the provider or method is absent, or when the method fails.
---@return any result Provider method result, or fallback.
---@return string|nil providerId Provider id that handled the call.
function public.integrations.invoke(id, methodName, fallback, ...)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.invoke: id must be a non-empty string")
    end
    if type(methodName) ~= "string" or methodName == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.invoke: methodName must be a non-empty string")
    end

    local api, providerId = registry.getPreferredProvider(id)
    local method = api and api[methodName] or nil
    if type(method) ~= "function" then
        return fallback, providerId
    end

    local ok, result = pcall(method, ...)
    if not ok then
        internal.violate(
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

--- Lists all providers for an integration id in registration order.
---@param id string Integration id.
---@return table[] providers Array of `{ providerId = string, api = table }` entries.
function public.integrations.list(id)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.list: id must be a non-empty string")
    end

    local bucket = registry.getBucket(id, false)
    local providers = {}
    if not bucket then
        return providers
    end

    for _, providerId in ipairs(bucket.order) do
        local api = bucket.providers[providerId]
        if api ~= nil then
            table.insert(providers, {
                providerId = providerId,
                api = api,
            })
        end
    end

    return providers
end
