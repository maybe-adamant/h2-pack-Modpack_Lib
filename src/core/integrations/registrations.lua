local deps = ...

local logging = deps.logging
local registry = deps.registry
local registrations = {}

local function validateIntegrationId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("integrations.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateProviderId(context, providerId)
    if type(providerId) ~= "string" or providerId == "" then
        logging.violate("integrations.invalid_args", "%s: providerId must be a non-empty string", context)
    end
end

local function validateApi(context, api)
    if type(api) ~= "table" then
        logging.violate("integrations.invalid_args", "%s: api must be a table", context)
    end
end

local function createRegistrationSet()
    return {
        entries = {},
        byKey = {},
    }
end

local function hasRegistrationEntries(registrationSet)
    return registrationSet and #registrationSet.entries > 0
end

local function makeNoopReceipt()
    return {
        commit = function()
            return true, nil
        end,
        dispose = function()
            return true, nil
        end,
    }
end

local function ensureHostRegistrations(state)
    if not state.integrationRegistrations then
        state.integrationRegistrations = createRegistrationSet()
    end
    return state.integrationRegistrations
end

local function recordStagedRegistration(registrationSet, id, providerId, api)
    local key = id .. "\0" .. providerId
    local entry = registrationSet.byKey[key]
    if not entry then
        entry = {
            id = id,
            providerId = providerId,
            api = api,
        }
        registrationSet.byKey[key] = entry
        registrationSet.entries[#registrationSet.entries + 1] = entry
    else
        entry.api = api
    end
    return api
end

function registrations.stageAuthorRegistration(state, id, opts)
    local context = "host.integrations.register"
    validateIntegrationId(context, id)
    if type(opts) ~= "table" then
        logging.violate("integrations.invalid_args", "%s: opts must be a table", context)
    end
    validateProviderId(context, opts.providerId)
    validateApi(context, opts.api)
    return recordStagedRegistration(ensureHostRegistrations(state), id, opts.providerId, opts.api)
end

function registrations.install(ownerId, hostRegistrations)
    if not hasRegistrationEntries(hostRegistrations) then
        return makeNoopReceipt()
    end

    local install = {
        ownerId = ownerId,
        ownerToken = {},
        entries = {},
        byKey = {},
        previous = {},
        committed = false,
        disposed = false,
    }

    for _, entry in ipairs(hostRegistrations.entries) do
        recordStagedRegistration(install, entry.id, entry.providerId, entry.api)
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
                    ownerId = bucket and registry.getProviderOwnerId(entry.id, entry.providerId) or nil,
                    ownerToken = bucket and registry.getProviderOwnerToken(entry.id, entry.providerId) or nil,
                    orderIndex = bucket and registry.getProviderOrderIndex(bucket, entry.providerId) or nil,
                }
                registry.setProvider(entry.id, entry.providerId, entry.api, ownerId, install.ownerToken)
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
                    if bucket
                        and registry.getProviderOwnerId(entry.id, entry.providerId) == install.ownerId
                        and registry.getProviderOwnerToken(entry.id, entry.providerId) == install.ownerToken
                    then
                        if previous and previous.existed then
                            bucket.providers[entry.providerId] = previous.api
                            bucket.ownerIds[entry.providerId] = previous.ownerId
                            bucket.ownerTokens[entry.providerId] = previous.ownerToken
                            registry.insertProviderOrder(bucket, entry.providerId, previous.orderIndex)
                        else
                            registry.removeProviderFromBucket(
                                bucket,
                                entry.providerId,
                                install.ownerId,
                                install.ownerToken)
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

return registrations
