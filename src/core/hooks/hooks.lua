local deps = ...

local dispatchers = import('core/hooks/dispatchers.lua', nil, {
    modutil = deps.modutil,
    logging = deps.logging,
    runtime = deps.runtime,
})

local declarations = import('core/hooks/declarations.lua', nil, {
    logging = deps.logging,
})

local hostInstall = import('core/hooks/host_install.lua', nil, {
    logging = deps.logging,
    dispatchers = dispatchers,
})

local hostAdapter = import('core/hooks/adapter_host.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    declarations = declarations,
    hostInstall = hostInstall,
})

local author = import('core/hooks/adapter_author.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    declarations = declarations,
})

local system = import('core/hooks/adapter_system.lua', nil, {
    logging = deps.logging,
    declarations = declarations,
    hostInstall = hostInstall,
})

local service = {
    installForHost = hostAdapter.installForHost,
}

return {
    service = service,
    author = author,
    system = system,
}
