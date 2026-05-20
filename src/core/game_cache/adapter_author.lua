local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local service = deps.service
local author = {}

local function getHostOwnerId(host, context)
    if not hostState.get(host) then
        logging.violate("game_cache.invalid_args", "%s: expected managed module host state", context)
    end
    return host.getHostId()
end

function author.create(host)
    return {
        currentRun = {
            get = function(key, factory)
                local ownerId = getHostOwnerId(host, "host.gameCache.currentRun.get")
                return service.currentRun.get(ownerId, key, factory)
            end,
            peek = function(key)
                local ownerId = getHostOwnerId(host, "host.gameCache.currentRun.peek")
                return service.currentRun.peek(ownerId, key)
            end,
            clear = function(key)
                local ownerId = getHostOwnerId(host, "host.gameCache.currentRun.clear")
                return service.currentRun.clear(ownerId, key)
            end,
        },
    }
end

return author
