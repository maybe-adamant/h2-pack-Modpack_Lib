local deps = ...

local gameDeps = deps.gameDeps

local currentRunCache = import('core/game_cache/current_run_cache.lua', nil, {
    logging = deps.logging,
})

local service = {}

local function getCurrentRun()
    return gameDeps.gameCache.CurrentRun()
end

service.currentRun = {
    get = function(ownerId, key, factory)
        return currentRunCache.get(getCurrentRun(), ownerId, key, factory)
    end,
    peek = function(ownerId, key)
        return currentRunCache.peek(getCurrentRun(), ownerId, key)
    end,
    clear = function(ownerId, key)
        return currentRunCache.clear(getCurrentRun(), ownerId, key)
    end,
}

local author = import('core/game_cache/adapter_author.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    service = service,
})

return {
    service = service,
    author = author,
}
