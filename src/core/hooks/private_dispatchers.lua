local internal = AdamantModpackLib_Internal
local physicalHooks = import 'core/hooks/private_registry.lua'

-- `moduleDispatchers` own the physical ModUtil adapter for each path.
-- `moduleSlots` choose which host for a plugin is currently visible to those adapters.
internal.hooks.moduleSlots = internal.hooks.moduleSlots or {}
internal.hooks.moduleDispatchers = internal.hooks.moduleDispatchers or {
    wrap = {},
    override = {},
    contextWrap = {},
}

local moduleSlots = internal.hooks.moduleSlots
local moduleDispatchers = internal.hooks.moduleDispatchers

local function getModuleSlot(pluginGuid)
    local slot = moduleSlots[pluginGuid]
    if not slot then
        slot = {}
        moduleSlots[pluginGuid] = slot
    end
    return slot
end

local function getCurrentHost(pluginGuid)
    local slot = moduleSlots[pluginGuid]
    return slot and slot.currentHost or nil
end

local function getDispatcher(kind, path)
    local bucket = moduleDispatchers[kind]
    local dispatcher = bucket[path]
    if not dispatcher then
        dispatcher = {
            kind = kind,
            path = path,
            physicalOwner = {},
            pluginOrder = {},
            pluginSeen = {},
            handlers = {},
            installed = false,
        }
        bucket[path] = dispatcher
    end
    dispatcher.pluginSeen = dispatcher.pluginSeen or {}
    dispatcher.handlers = dispatcher.handlers or {}
    return dispatcher
end

local function addPluginOrder(dispatcher, pluginGuid)
    if dispatcher.pluginSeen[pluginGuid] then
        return
    end
    dispatcher.pluginSeen[pluginGuid] = true
    dispatcher.pluginOrder[#dispatcher.pluginOrder + 1] = pluginGuid
end

local function getCommittedHostSlots(dispatcher, pluginGuid)
    local host = getCurrentHost(pluginGuid)
    local byPlugin = dispatcher.handlers[pluginGuid]
    return host and byPlugin and byPlugin[host] or nil
end

local function removeSlotKey(hostSlots, key, expectedSlot)
    if hostSlots.slots[key] ~= expectedSlot then
        return
    end

    hostSlots.slots[key] = nil
    for index = #hostSlots.order, 1, -1 do
        if hostSlots.order[index] == key then
            table.remove(hostSlots.order, index)
            return
        end
    end
end

local refreshOverrideDispatcher

local function dispatcherHasPluginHandlers(dispatcher, pluginGuid)
    local byPlugin = dispatcher.handlers[pluginGuid]
    return type(byPlugin) == "table" and next(byPlugin) ~= nil
end

local function dispatcherHasAnyHandlers(dispatcher)
    for pluginGuid in pairs(dispatcher.handlers or {}) do
        if dispatcherHasPluginHandlers(dispatcher, pluginGuid) then
            return true
        end
    end
    return false
end

local function removePluginOrder(dispatcher, pluginGuid)
    if not dispatcher.pluginSeen[pluginGuid] then
        return
    end

    dispatcher.pluginSeen[pluginGuid] = nil
    for index = #dispatcher.pluginOrder, 1, -1 do
        if dispatcher.pluginOrder[index] == pluginGuid then
            table.remove(dispatcher.pluginOrder, index)
            return
        end
    end
end

local function pruneDispatcherPlugin(dispatcher, pluginGuid)
    if dispatcherHasPluginHandlers(dispatcher, pluginGuid) then
        return
    end
    dispatcher.handlers[pluginGuid] = nil
    removePluginOrder(dispatcher, pluginGuid)
end

local function pruneDispatcher(kind, path, dispatcher)
    if dispatcherHasAnyHandlers(dispatcher) then
        return
    end

    dispatcher.pluginOrder = {}
    dispatcher.pluginSeen = {}

    -- Wrap/context dispatchers are also the physical ModUtil wrapper anchors.
    -- Keep those path entries so a future registration reuses the same wrapper.
    if kind == "override" and not dispatcher.installed then
        moduleDispatchers.override[path] = nil
    end
end

local function pruneModuleSlot(pluginGuid)
    if not moduleSlots[pluginGuid] then
        return
    end

    for _, dispatchers in pairs(moduleDispatchers) do
        for _, dispatcher in pairs(dispatchers) do
            if dispatcherHasPluginHandlers(dispatcher, pluginGuid) then
                return
            end
        end
    end

    moduleSlots[pluginGuid] = nil
end

local function wrapChain(handler, nextBase)
    return function(...)
        return handler(nextBase, ...)
    end
end

local function dispatchWrap(dispatcher, base, ...)
    local chain = base
    for pluginIndex = 1, #dispatcher.pluginOrder do
        local pluginGuid = dispatcher.pluginOrder[pluginIndex]
        local hostSlots = getCommittedHostSlots(dispatcher, pluginGuid)
        if hostSlots then
            for slotIndex = 1, #hostSlots.order do
                local slot = hostSlots.slots[hostSlots.order[slotIndex]]
                if slot and type(slot.value) == "function" then
                    chain = wrapChain(slot.value, chain)
                end
            end
        end
    end
    return chain(...)
end

local function dispatchContextWrap(dispatcher, ...)
    for pluginIndex = #dispatcher.pluginOrder, 1, -1 do
        local pluginGuid = dispatcher.pluginOrder[pluginIndex]
        local hostSlots = getCommittedHostSlots(dispatcher, pluginGuid)
        if hostSlots then
            for slotIndex = #hostSlots.order, 1, -1 do
                local slot = hostSlots.slots[hostSlots.order[slotIndex]]
                if slot and type(slot.value) == "function" then
                    slot.value(...)
                end
            end
        end
    end
end

local function resolveOverride(dispatcher)
    for pluginIndex = #dispatcher.pluginOrder, 1, -1 do
        local pluginGuid = dispatcher.pluginOrder[pluginIndex]
        local hostSlots = getCommittedHostSlots(dispatcher, pluginGuid)
        if hostSlots then
            for slotIndex = #hostSlots.order, 1, -1 do
                local slot = hostSlots.slots[hostSlots.order[slotIndex]]
                if slot and type(slot.value) == "function" then
                    return slot.value
                end
            end
        end
    end
    return nil
end

local function dispatchOverride(dispatcher, ...)
    local replacement = resolveOverride(dispatcher)
    if replacement then
        return replacement(...)
    end
    return nil
end

local function physicalDispatcherIsCurrent(dispatcher)
    return dispatcher.installed and _G[dispatcher.path] == dispatcher.installedTarget
end

local function resetPhysicalDispatcher(dispatcher)
    dispatcher.physicalOwner = {}
    dispatcher.installed = false
    dispatcher.installedTarget = nil
    dispatcher.state = nil
end

local function installPhysicalWrap(physicalOwner, path, key, handler)
    return physicalHooks.installWrap(physicalOwner, path, key, handler)
end

local function installPhysicalContextWrap(physicalOwner, path, key, context)
    return physicalHooks.installContextWrap(physicalOwner, path, key, context)
end

local function ensureWrapDispatcher(dispatcher)
    if physicalDispatcherIsCurrent(dispatcher) then
        return
    end
    if dispatcher.installed then
        resetPhysicalDispatcher(dispatcher)
    end
    installPhysicalWrap(dispatcher.physicalOwner, dispatcher.path, "__module_dispatcher", function(base, ...)
        return dispatchWrap(dispatcher, base, ...)
    end)
    dispatcher.installed = true
    dispatcher.installedTarget = _G[dispatcher.path]
end

local function ensureContextWrapDispatcher(dispatcher)
    if physicalDispatcherIsCurrent(dispatcher) then
        return
    end
    if dispatcher.installed then
        resetPhysicalDispatcher(dispatcher)
    end
    installPhysicalContextWrap(dispatcher.physicalOwner, dispatcher.path, "__module_dispatcher", function(...)
        return dispatchContextWrap(dispatcher, ...)
    end)
    dispatcher.installed = true
    dispatcher.installedTarget = _G[dispatcher.path]
end

function refreshOverrideDispatcher(dispatcher)
    local replacement = resolveOverride(dispatcher)
    if replacement ~= nil then
        if physicalDispatcherIsCurrent(dispatcher) then
            return
        end
        if dispatcher.installed then
            resetPhysicalDispatcher(dispatcher)
        end
        dispatcher.state = physicalHooks.installOverride(dispatcher.physicalOwner, dispatcher.path, "__module_dispatcher", function(...)
            return dispatchOverride(dispatcher, ...)
        end)
        dispatcher.installed = true
        dispatcher.installedTarget = _G[dispatcher.path]
        return
    end

    if dispatcher.installed and dispatcher.state then
        physicalHooks.deactivateSlot(dispatcher.state)
        dispatcher.installed = false
        dispatcher.installedTarget = nil
        dispatcher.state = nil
    end
end

local function refreshOverrideDispatchersForPlugin(pluginGuid)
    for _, dispatcher in pairs(moduleDispatchers.override) do
        if dispatcher.handlers and dispatcher.handlers[pluginGuid] then
            refreshOverrideDispatcher(dispatcher)
        end
    end
end

local function attachHostSlotsToDispatcher(dispatcher, pluginGuid, host, pathHooks)
    addPluginOrder(dispatcher, pluginGuid)
    dispatcher.handlers[pluginGuid] = dispatcher.handlers[pluginGuid] or {}
    local hostSlots = dispatcher.handlers[pluginGuid][host]
    if not hostSlots then
        hostSlots = {
            order = {},
            slots = {},
        }
        dispatcher.handlers[pluginGuid][host] = hostSlots
    end
    for _, key in ipairs(pathHooks.order) do
        if hostSlots.slots[key] == nil then
            hostSlots.order[#hostSlots.order + 1] = key
        end
        hostSlots.slots[key] = pathHooks.slots[key]
    end
end

local function detachHostSlotsFromDispatcher(dispatcher, pluginGuid, host, pathHooks)
    local byPlugin = dispatcher.handlers[pluginGuid]
    if byPlugin then
        local hostSlots = byPlugin[host]
        if hostSlots then
            for _, key in ipairs(pathHooks.order) do
                removeSlotKey(hostSlots, key, pathHooks.slots[key])
            end
            if #hostSlots.order == 0 then
                byPlugin[host] = nil
            end
        end
    end
end

local function detachHostSlots(kind, path, pluginGuid, host, pathHooks)
    local dispatcher = getDispatcher(kind, path)
    detachHostSlotsFromDispatcher(dispatcher, pluginGuid, host, pathHooks)
    if kind == "override" then
        refreshOverrideDispatcher(dispatcher)
    end
    pruneDispatcherPlugin(dispatcher, pluginGuid)
    pruneDispatcher(kind, path, dispatcher)
end

local function attachHost(pluginGuid, host, declarations)
    for path, pathHooks in pairs(declarations.wrap) do
        local dispatcher = getDispatcher("wrap", path)
        attachHostSlotsToDispatcher(dispatcher, pluginGuid, host, pathHooks)
        ensureWrapDispatcher(dispatcher)
    end
    for path, pathHooks in pairs(declarations.contextWrap) do
        local dispatcher = getDispatcher("contextWrap", path)
        attachHostSlotsToDispatcher(dispatcher, pluginGuid, host, pathHooks)
        ensureContextWrapDispatcher(dispatcher)
    end
    for path, pathHooks in pairs(declarations.override) do
        local dispatcher = getDispatcher("override", path)
        attachHostSlotsToDispatcher(dispatcher, pluginGuid, host, pathHooks)
        addPluginOrder(dispatcher, pluginGuid)
    end

    getModuleSlot(pluginGuid).currentHost = host
    refreshOverrideDispatchersForPlugin(pluginGuid)
end

local function detachHost(pluginGuid, host, declarations, previousCurrentHost)
    local slot = getModuleSlot(pluginGuid)
    if slot.currentHost == host then
        slot.currentHost = previousCurrentHost
    end

    for path, pathHooks in pairs(declarations.wrap) do
        detachHostSlots("wrap", path, pluginGuid, host, pathHooks)
    end
    for path, pathHooks in pairs(declarations.contextWrap) do
        detachHostSlots("contextWrap", path, pluginGuid, host, pathHooks)
    end
    for path, pathHooks in pairs(declarations.override) do
        detachHostSlots("override", path, pluginGuid, host, pathHooks)
    end
    pruneModuleSlot(pluginGuid)
end

return {
    getCurrentHost = getCurrentHost,
    installPhysicalWrap = installPhysicalWrap,
    installPhysicalContextWrap = installPhysicalContextWrap,
    attachHost = attachHost,
    detachHost = detachHost,
}
