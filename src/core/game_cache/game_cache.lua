local deps = ...

local logging = deps.logging
local gameCachePublic = {}

local ROOT_KEY = "_AdamantModpackLibGameCache"

local function tableIsEmpty(value)
    return next(value) == nil
end

local function getModuleBucket(object, packId, moduleId, key, create)
    if type(object) ~= "table" then
        logging.violate("game_cache.invalid_args", "lib.gameCache object must be a table")
    end
    if type(packId) ~= "string" or packId == "" then
        logging.violate("game_cache.invalid_args", "lib.gameCache packId must be a non-empty string")
    end
    if type(moduleId) ~= "string" or moduleId == "" then
        logging.violate("game_cache.invalid_args", "lib.gameCache moduleId must be a non-empty string")
    end
    if type(key) ~= "string" or key == "" then
        logging.violate("game_cache.invalid_args", "lib.gameCache key must be a non-empty string")
    end

    local root = rawget(object, ROOT_KEY)
    if root == nil and create then
        root = {}
        rawset(object, ROOT_KEY, root)
    end
    if type(root) ~= "table" then
        if create then
            logging.violate("game_cache.invalid_bucket", "lib.gameCache root bucket is not a table")
        end
        return nil
    end

    local packBucket = root[packId]
    if packBucket == nil and create then
        packBucket = {}
        root[packId] = packBucket
    end
    if type(packBucket) ~= "table" then
        if create then
            logging.violate("game_cache.invalid_bucket", "lib.gameCache pack bucket is not a table")
        end
        return nil
    end

    local moduleBucket = packBucket[moduleId]
    if moduleBucket == nil and create then
        moduleBucket = {}
        packBucket[moduleId] = moduleBucket
    end
    if type(moduleBucket) ~= "table" then
        if create then
            logging.violate("game_cache.invalid_bucket", "lib.gameCache module bucket is not a table")
        end
        return nil
    end

    return moduleBucket, packBucket, root
end

--- Gets or creates a module-owned runtime cache table scoped to a live game table.
---@param object table Live game table such as `CurrentRun`, room data, or loot data.
---@param packId string Pack namespace.
---@param moduleId string Module namespace inside the pack.
---@param key string Cache bucket key inside the module namespace.
---@param factory fun(): table|nil Optional initializer. Defaults to `{}`.
---@return table state Namespaced cache table.
function gameCachePublic.get(object, packId, moduleId, key, factory)
    local moduleBucket = getModuleBucket(object, packId, moduleId, key, true)
    local state = moduleBucket[key]
    if state == nil then
        if factory ~= nil then
            if type(factory) ~= "function" then
                logging.violate("game_cache.invalid_factory", "lib.gameCache.get factory must be a function")
            end
            state = factory()
        end
        if state == nil then
            state = {}
        end
        if type(state) ~= "table" then
            logging.violate("game_cache.invalid_factory", "lib.gameCache.get factory must return a table")
        end
        moduleBucket[key] = state
    end
    if type(state) ~= "table" then
        logging.violate("game_cache.invalid_bucket", "lib.gameCache cache bucket is not a table")
    end
    return state
end

--- Returns an existing module-owned runtime cache table without creating it.
---@param object table Live game table.
---@param packId string Pack namespace.
---@param moduleId string Module namespace inside the pack.
---@param key string Cache bucket key inside the module namespace.
---@return table|nil state Existing cache table, when present.
function gameCachePublic.peek(object, packId, moduleId, key)
    local moduleBucket = getModuleBucket(object, packId, moduleId, key, false)
    local state = moduleBucket and moduleBucket[key] or nil
    if type(state) == "table" then
        return state
    end
    return nil
end

--- Clears one module-owned runtime cache table from a live game table.
---@param object table Live game table.
---@param packId string Pack namespace.
---@param moduleId string Module namespace inside the pack.
---@param key string Cache bucket key inside the module namespace.
---@return boolean cleared True when a bucket existed and was removed.
function gameCachePublic.clear(object, packId, moduleId, key)
    local moduleBucket, packBucket, root = getModuleBucket(object, packId, moduleId, key, false)
    if not moduleBucket or moduleBucket[key] == nil then
        return false
    end
    moduleBucket[key] = nil
    if tableIsEmpty(moduleBucket) then
        packBucket[moduleId] = nil
        if tableIsEmpty(packBucket) then
            root[packId] = nil
            if tableIsEmpty(root) then
                rawset(object, ROOT_KEY, nil)
            end
        end
    end
    return true
end

public.gameCache = gameCachePublic
