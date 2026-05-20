local deps = ...

local ModuleHostState = deps.moduleHostStateStore

local moduleHostState = {}

function moduleHostState.get(host)
    return ModuleHostState[host]
end

function moduleHostState.set(host, state)
    ModuleHostState[host] = state
end

return moduleHostState
