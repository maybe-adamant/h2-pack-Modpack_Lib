local internal = AdamantModpackLib_Internal

public.overlays = public.overlays or {}

-- Public API: shared overlay order bands used by module and system retained overlays.
public.overlays.order = public.overlays.order or {
    framework = 0,
    module = 1000,
    debug = 2000,
}

internal.overlays = internal.overlays or {}

local overlayState = import('core/overlays/private_state.lua')

-- Shared overlay visibility gate. UI suppression is global because foreground
-- configuration UI and gameplay overlays should not compete for screen space.
local function isUiSuppressed()
    return next(overlayState.uiSuppressors) ~= nil
end

local renderer = import('core/overlays/private_renderer.lua', nil, {
    state = overlayState.renderer,
    isUiSuppressed = isUiSuppressed,
})

local retained = import('core/overlays/private_retained.lua', nil, {
    state = overlayState.retained,
    renderer = renderer,
})

-- Module overlay declarations are public by callback surface, not by global
-- function. Host activation passes a scoped registrar into registerOverlays(...)
-- with createLine/createTable/onCommit/onInterval/afterHook.

-- Public API: acquire a token that hides all Lib-managed gameplay overlays while
-- foreground configuration UI is open.
function public.overlays.suppressForUi()
    overlayState.nextUiSuppressorId = overlayState.nextUiSuppressorId + 1
    local id = overlayState.nextUiSuppressorId
    local wasSuppressed = isUiSuppressed()
    overlayState.uiSuppressors[id] = true
    if not wasSuppressed then
        renderer.refreshAll()
    end

    local released = false
    return {
        release = function()
            if released then
                return
            end
            released = true
            overlayState.uiSuppressors[id] = nil
            if not isUiSuppressed() then
                renderer.refreshAll()
            end
        end,
    }
end

-- Public API: read whether any UI suppression token is currently active.
function public.overlays.isUiSuppressed()
    return isUiSuppressed()
end

local function createAfterHookReceipt(host, paths)
    if #paths == 0 then
        return nil
    end

    return internal.hooks.installForHost(host, function()
        for _, path in ipairs(paths) do
            local hookPath = path
            public.hooks.Wrap(hookPath, "overlay.after:" .. hookPath, function(base, ...)
                local args = { ... }
                local results = { base(...) }
                internal.overlays.dispatchAfterHook(host, hookPath, args, results)
                return table.unpack(results)
            end)
        end
    end)
end

local function disposeReceipt(receipt)
    if not receipt then
        return true, nil
    end
    return receipt.dispose()
end

function internal.overlays.installForHost(host, register, authorHost, store)
    if type(host) ~= "table" then
        internal.violate("overlays.invalid_registration", "internal.overlays.installForHost: host is required")
    end

    local state = internal.moduleHost and internal.moduleHost.getState and internal.moduleHost.getState(host) or nil
    local pluginGuid = state and state.pluginGuid or nil
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("overlays.invalid_registration", "internal.overlays.installForHost: host pluginGuid is required")
    end

    local stagingOwner = {}
    local pendingOwnerId = pluginGuid .. ":pending"
    local currentOwnerId = pluginGuid .. ":current"
    local transaction = retained.beginTransaction(stagingOwner)
    local afterHookReceipt = nil
    local afterHookReceiptCommitted = false
    local committed = false
    local disposed = false

    local ok, err = pcall(function()
        retained.refresh(stagingOwner, pendingOwnerId, authorHost, store, function(overlays)
            if register then
                return register(overlays, authorHost, store)
            end
        end, { hidden = true })
        afterHookReceipt = createAfterHookReceipt(host, retained.getAfterHookPaths(stagingOwner))
    end)

    if not ok then
        transaction.rollback()
        error(err, 0)
    end

    return {
        commit = function()
            if disposed or committed then
                return true, nil
            end
            if afterHookReceipt then
                local hookOk, hookErr = afterHookReceipt.commit()
                if not hookOk then
                    return false, hookErr
                end
                afterHookReceiptCommitted = true
            end
            local clearOk, clearErr = retained.clearTableRegistriesByOwnerId(currentOwnerId, host)
            if not clearOk then
                if afterHookReceiptCommitted then
                    disposeReceipt(afterHookReceipt)
                    afterHookReceiptCommitted = false
                end
                return false, clearErr
            end
            transaction.commit()
            retained.promoteTableRegistry(stagingOwner, host, currentOwnerId, authorHost, store)
            committed = true
            return true, nil
        end,
        dispose = function()
            if disposed then
                return true, nil
            end
            if not committed then
                transaction.rollback()
                if afterHookReceiptCommitted then
                    disposeReceipt(afterHookReceipt)
                    afterHookReceiptCommitted = false
                end
                disposed = true
                return true, nil
            end

            local disposeTransaction = retained.beginTransaction(host)
            local disposeOk, disposeErr = pcall(function()
                retained.refresh(host, currentOwnerId, nil, nil, function() end)
            end)
            local hookOk, hookErr = disposeReceipt(afterHookReceipt)
            afterHookReceiptCommitted = false
            if disposeOk then
                disposeTransaction.commit()
                disposed = true
                if not hookOk then
                    return false, hookErr
                end
                return true, nil
            end

            disposeTransaction.rollback()
            disposed = true
            return false, disposeErr
        end,
    }
end

-- Internal API: dispatch overlay projections after settings commit.
function internal.overlays.dispatchCommit(owner, commit)
    return retained.dispatchCommit(owner, commit)
end

-- Internal API: dispatch retained interval projections from the ImGui tick driver.
function internal.overlays.dispatchIntervals(now)
    return retained.dispatchIntervals(now)
end

-- Internal API: dispatch an overlay after-hook projection registered by a retained owner.
function internal.overlays.dispatchAfterHook(owner, path, args, results)
    return retained.dispatchAfterHook(owner, path, args, results)
end

-- Public API: declare narrow retained HUD lines for Lib/Framework systems that
-- are not owned by a module host.
function public.overlays.defineSystem(ownerId, register)
    if type(ownerId) ~= "string" or ownerId == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.defineSystem: ownerId must be a non-empty string")
    end

    retained.refresh(ownerId, ownerId, nil, nil, register, { system = true })
    internal.overlays.dispatchCommit(ownerId, {})
    return true
end
