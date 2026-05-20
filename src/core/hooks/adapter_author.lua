local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local declarations = deps.declarations
local author = {}

local function requireHostState(host, apiName)
    local state = hostState.get(host)
    if not state then
        logging.violate("hooks.invalid_registration", "%s: expected managed module host", apiName)
    end
    return state
end

local function requireDeclarationOpen(host, apiName)
    local state = requireHostState(host, "host.hooks." .. apiName)
    if state.activating == true then
        logging.violate("hooks.invalid_registration", "host.hooks.%s cannot be called during host activation", apiName)
    end
    if state.activated == true then
        logging.violate("hooks.invalid_registration", "host.hooks.%s cannot be called after host activation", apiName)
    end
    return state
end

local function ensureHostDeclarations(state)
    if not state.hookDeclarations then
        state.hookDeclarations = declarations.create()
    end
    return state.hookDeclarations
end

function author.create(host)
    return {
        wrap = function(path, keyOrHandler, maybeHandler)
            local state = requireDeclarationOpen(host, "wrap")
            return declarations.declareWrap(
                ensureHostDeclarations(state),
                "host.hooks.wrap",
                path,
                keyOrHandler,
                maybeHandler
            )
        end,
        override = function(path, keyOrReplacement, maybeReplacement)
            local state = requireDeclarationOpen(host, "override")
            return declarations.declareOverride(
                ensureHostDeclarations(state),
                "host.hooks.override",
                path,
                keyOrReplacement,
                maybeReplacement
            )
        end,
        contextWrap = function(path, keyOrContext, maybeContext)
            local state = requireDeclarationOpen(host, "contextWrap")
            return declarations.declareContextWrap(
                ensureHostDeclarations(state),
                "host.hooks.contextWrap",
                path,
                keyOrContext,
                maybeContext
            )
        end,
    }
end

return author
