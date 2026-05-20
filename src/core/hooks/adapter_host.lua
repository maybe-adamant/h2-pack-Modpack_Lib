local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local declarations = deps.declarations
local hostInstall = deps.hostInstall
local hostAdapter = {}

local function requireHostState(host, apiName)
    local state = hostState.get(host)
    if not state then
        logging.violate("hooks.invalid_registration", "%s: expected managed module host", apiName)
    end
    return state
end

function hostAdapter.installForHost(host, declare)
    local state = requireHostState(host, "hooks.installForHost")
    local ownerId = host.getHostId()
    local hookDeclarations
    if declare ~= nil then
        if type(declare) ~= "function" then
            logging.violate("hooks.invalid_registration", "hooks.installForHost: declare must be a function")
        end
        hookDeclarations = declarations.create()
        declare(declarations.createRegistrar(hookDeclarations, "hooks.installForHost"))
    else
        hookDeclarations = state.hookDeclarations or declarations.create()
    end
    return hostInstall.createReceipt(ownerId, host, hookDeclarations)
end

return hostAdapter
