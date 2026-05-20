local deps = ...

local runtime = deps.runtime
runtime.moduleHost = runtime.moduleHost or {}

-- Centralized hot-reload-stable Lib anchors. Adding a new persistent runtime
-- table should be a conscious change in this file.
runtime.moduleHost.liveHosts = runtime.moduleHost.liveHosts or {}
runtime.moduleHost.pluginInfo = runtime.moduleHost.pluginInfo or {}
runtime.moduleHost.pendingCoordinatorRebuilds = runtime.moduleHost.pendingCoordinatorRebuilds
    or setmetatable({}, { __mode = "k" })
runtime.moduleHost.hostState = runtime.moduleHost.hostState or setmetatable({}, { __mode = "k" })

local liveHosts = runtime.moduleHost.liveHosts
local pluginInfo = runtime.moduleHost.pluginInfo
local pendingCoordinatorRebuilds = runtime.moduleHost.pendingCoordinatorRebuilds
local moduleHostStateStore = runtime.moduleHost.hostState

local registry = {}

function registry.getModuleHostStateStore()
    return moduleHostStateStore
end

function registry.getLiveHost(pluginGuid)
    return liveHosts[pluginGuid]
end

function registry.setLiveHost(pluginGuid, host)
    liveHosts[pluginGuid] = host
end

function registry.getPluginInfo(pluginGuid)
    return pluginInfo[pluginGuid]
end

function registry.setPluginInfo(pluginGuid, info)
    pluginInfo[pluginGuid] = info
end

function registry.getPendingCoordinatorRebuild(definition)
    return pendingCoordinatorRebuilds[definition]
end

function registry.setPendingCoordinatorRebuild(definition, rebuild)
    pendingCoordinatorRebuilds[definition] = rebuild
end

return registry
