local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local declarations = deps.declarations
local overlayOrder = deps.order
local author = {}

local function requireHostState(host, apiName)
    local state = hostState.get(host)
    if not state then
        logging.violate("overlays.invalid_registration", "%s: expected managed module host", apiName)
    end
    return state
end

local function requireDeclarationOpen(host, apiName)
    local state = requireHostState(host, "host.overlays." .. apiName)
    if state.activating == true then
        logging.violate("overlays.invalid_registration", "host.overlays.%s cannot be called during host activation", apiName)
    end
    if state.activated == true then
        logging.violate("overlays.invalid_registration", "host.overlays.%s cannot be called after host activation", apiName)
    end
    return state
end

local function ensureHostDeclarations(state)
    if not state.overlayDeclarations then
        state.overlayDeclarations = declarations.create()
    end
    return state.overlayDeclarations
end

function author.create(host)
    return {
        order = overlayOrder,
        createLine = function(name, spec)
            local state = requireDeclarationOpen(host, "createLine")
            return declarations.declareLine(ensureHostDeclarations(state), "host.overlays.createLine", name, spec)
        end,
        createTable = function(name, spec)
            local state = requireDeclarationOpen(host, "createTable")
            return declarations.declareTable(ensureHostDeclarations(state), "host.overlays.createTable", name, spec)
        end,
        onCommit = function(callback)
            local state = requireDeclarationOpen(host, "onCommit")
            return declarations.declareCommit(ensureHostDeclarations(state), "host.overlays.onCommit", callback)
        end,
        onInterval = function(name, seconds, callback, opts)
            local state = requireDeclarationOpen(host, "onInterval")
            return declarations.declareInterval(
                ensureHostDeclarations(state),
                "host.overlays.onInterval",
                name,
                seconds,
                callback,
                opts
            )
        end,
        afterHook = function(path, callback)
            local state = requireDeclarationOpen(host, "afterHook")
            return declarations.declareAfterHook(ensureHostDeclarations(state), "host.overlays.afterHook", path, callback)
        end,
    }
end

return author
