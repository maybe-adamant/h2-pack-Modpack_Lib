local deps = ...
local externals = deps.externals

AdamantModpackLib_Runtime = AdamantModpackLib_Runtime or {}
local runtime = AdamantModpackLib_Runtime
local gameDeps = externals.gameDeps or import('core/game_deps/game_deps.lua', nil, {
    rom = externals.rom,
})

local logging = import('core/logging/logging.lua', nil, {
    config = deps.config,
})

local values = import('core/helpers/values.lua')

local storage = import('core/storage/storage.lua', nil, {
    logging = logging,
    values = values,
})

import('core/hashing/hashing.lua', nil, {
    storage = storage,
})

local moduleState = import('core/module_state/module_state.lua', nil, {
    chalk = externals.chalk,
    logging = logging,
    storage = storage,
    values = values,
})

import('core/game_cache/game_cache.lua', nil, {
    logging = logging,
})

local coordinator = import('core/coordinator/coordinator.lua', nil, {
    logging = logging,
    runtime = runtime,
})

local hostState = import('core/module_host_state.lua', nil, {
    runtime = runtime,
})

local definition = import('core/module_bootstrap/definition.lua', nil, {
    plugin = externals.plugin,
    logging = logging,
    storage = storage,
    values = values,
    coordinator = coordinator,
    hostState = hostState,
})
local integrations = import('core/integrations/integrations.lua', nil, {
    logging = logging,
    runtime = runtime,
    hostState = hostState,
})
local hooks = import('core/hooks/hooks.lua', nil, {
    modutil = externals.modutil,
    logging = logging,
    hostState = hostState,
    runtime = runtime,
})
local overlays = import('core/overlays/overlays.lua', nil, {
    gameDeps = gameDeps,
    logging = logging,
    hooks = hooks,
    hostState = hostState,
    runtime = runtime,
    values = values,
})
local mutation = import('core/mutations/mutations.lua', nil, {
    gameDeps = gameDeps,
    logging = logging,
    values = values,
    hostState = hostState,
    coordinator = coordinator,
    runtime = runtime,
})
import('core/widgets/init.lua', nil, {
    logging = logging,
    storage = storage,
})
local moduleHost = import('core/module_bootstrap/host.lua', nil, {
    logging = logging,
    values = values,
    definition = definition,
    hostState = hostState,
    moduleState = moduleState,
    integrations = integrations,
    hooks = hooks,
    overlays = overlays,
    mutation = mutation,
    coordinator = coordinator,
    storage = storage,
    widgets = public.widgets,
})
import('core/standalone_host/standalone_host.lua', nil, {
    gameDeps = gameDeps,
    rom = externals.rom,
    modutil = externals.modutil,
    logging = logging,
    moduleHost = moduleHost,
    coordinator = coordinator,
    overlays = overlays,
    runtime = runtime,
})
import('core/module_bootstrap/module.lua', nil, {
    logging = logging,
    moduleHost = moduleHost,
    moduleState = moduleState,
})

return {
    coordinator = coordinator,
}
