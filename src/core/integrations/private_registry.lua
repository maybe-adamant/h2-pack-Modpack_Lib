local internal = AdamantModpackLib_Internal

internal.integrations = internal.integrations or {
    registry = {},
}
internal.integrations.registry = internal.integrations.registry or {}

local registry = internal.integrations.registry

local function GetRegistry()
    return registry
end

local function GetBucket(id, create)
    local bucket = registry[id]
    if not bucket and create then
        bucket = {
            providers = {},
            owners = {},
            order = {},
        }
        registry[id] = bucket
    end
    if bucket then
        bucket.owners = bucket.owners or {}
    end
    return bucket
end

local function RemoveProviderFromBucket(bucket, providerId, expectedOwner)
    if not bucket or bucket.providers[providerId] == nil then
        return false
    end
    if expectedOwner ~= nil and bucket.owners and bucket.owners[providerId] ~= expectedOwner then
        return false
    end

    bucket.providers[providerId] = nil
    if bucket.owners then
        bucket.owners[providerId] = nil
    end
    for index, currentProviderId in ipairs(bucket.order) do
        if currentProviderId == providerId then
            table.remove(bucket.order, index)
            break
        end
    end

    return true
end

local function PruneBucket(id, bucket)
    if bucket and #bucket.order == 0 then
        registry[id] = nil
    end
end

local function GetPreferredProvider(id)
    local bucket = GetBucket(id, false)
    if not bucket then
        return nil, nil
    end

    for index = #bucket.order, 1, -1 do
        local providerId = bucket.order[index]
        local api = bucket.providers[providerId]
        if api ~= nil then
            return api, providerId
        end
    end

    return nil, nil
end

local function GetProviderOrderIndex(bucket, providerId)
    for index, currentProviderId in ipairs(bucket.order) do
        if currentProviderId == providerId then
            return index
        end
    end
    return nil
end

local function InsertProviderOrder(bucket, providerId, index)
    if GetProviderOrderIndex(bucket, providerId) then
        return
    end
    if index and index <= #bucket.order then
        table.insert(bucket.order, index, providerId)
    else
        table.insert(bucket.order, providerId)
    end
end

local function SetProvider(id, providerId, api, owner)
    local bucket = GetBucket(id, true)
    InsertProviderOrder(bucket, providerId)
    bucket.providers[providerId] = api
    bucket.owners[providerId] = owner
    return api
end

local function GetProviderOwner(id, providerId)
    local bucket = GetBucket(id, false)
    return bucket and bucket.owners and bucket.owners[providerId] or nil
end

return {
    getRegistry = GetRegistry,
    getBucket = GetBucket,
    removeProviderFromBucket = RemoveProviderFromBucket,
    pruneBucket = PruneBucket,
    getPreferredProvider = GetPreferredProvider,
    getProviderOrderIndex = GetProviderOrderIndex,
    insertProviderOrder = InsertProviderOrder,
    setProvider = SetProvider,
    getProviderOwner = GetProviderOwner,
}
