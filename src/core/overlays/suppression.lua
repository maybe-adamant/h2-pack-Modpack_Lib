local deps = ...

local overlayState = deps.state
local renderer = deps.renderer
local isUiSuppressed = deps.isUiSuppressed
local suppression = {}

function suppression.suppressForUi()
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

function suppression.isUiSuppressed()
    return isUiSuppressed()
end

return suppression
