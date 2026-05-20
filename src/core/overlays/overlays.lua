local deps = ...

local service = {}

-- Shared overlay order bands used by module and system retained overlays.
local overlayOrder = {
    framework = 0,
    module = 1000,
    debug = 2000,
}

local overlayState = import('core/overlays/state.lua', nil, {
    runtime = deps.runtime,
})

-- Shared overlay visibility gate. UI suppression is global because foreground
-- configuration UI and gameplay overlays should not compete for screen space.
local function isUiSuppressed()
    return next(overlayState.uiSuppressors) ~= nil
end

local renderer = import('core/overlays/renderer.lua', nil, {
    gameDeps = deps.gameDeps.overlays,
    state = overlayState.renderer,
    isUiSuppressed = isUiSuppressed,
    logging = deps.logging,
    values = deps.values,
    order = overlayOrder,
    system = deps.rendererSystem,
})

local retained = import('core/overlays/retained.lua', nil, {
    state = overlayState.retained,
    renderer = renderer,
    logging = deps.logging,
    order = overlayOrder,
    rom = deps.rom,
    dispatchIntervals = function(now)
        return service.dispatchIntervals(now)
    end,
})

local declarations = import('core/overlays/declarations.lua', nil, {
    logging = deps.logging,
})

local hostAdapter = import('core/overlays/adapter_host.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    hooks = deps.hooks,
    retained = retained,
    declarations = declarations,
})

local author = import('core/overlays/adapter_author.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    declarations = declarations,
    order = overlayOrder,
})

local system = import('core/overlays/adapter_system.lua', nil, {
    logging = deps.logging,
    retained = retained,
    order = overlayOrder,
})

local suppression = import('core/overlays/suppression.lua', nil, {
    state = overlayState,
    renderer = renderer,
    isUiSuppressed = isUiSuppressed,
})

service.installForHost = hostAdapter.installForHost
service.suppressForUi = suppression.suppressForUi
service.isUiSuppressed = suppression.isUiSuppressed

local framework = import('core/overlays/adapter_framework.lua', nil, {
    logging = deps.logging,
    suppression = suppression,
    system = system,
    order = overlayOrder,
})

-- Internal API: dispatch overlay projections after settings commit.
function service.dispatchCommit(owner, commit)
    return retained.dispatchCommit(owner, commit)
end

-- Internal API: dispatch retained interval projections from the ImGui tick driver.
function service.dispatchIntervals(now)
    return retained.dispatchIntervals(now)
end

-- Internal API: dispatch an overlay after-hook projection registered by a retained owner.
function service.dispatchAfterHook(owner, path, args, results)
    return retained.dispatchAfterHook(owner, path, args, results)
end

return {
    service = service,
    author = author,
    system = system,
    framework = framework,
}
