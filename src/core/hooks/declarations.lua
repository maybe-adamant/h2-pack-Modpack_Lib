local deps = ...

local logging = deps.logging
local declarations = {}

local function createDeclarations()
    return {
        wrap = {},
        override = {},
        contextWrap = {},
    }
end

local function parseRegistrationArgs(context, path, keyOrValue, maybeValue, valueName)
    if type(path) ~= "string" or path == "" then
        logging.violate("hooks.invalid_registration", "%s: path must be a non-empty string", context)
    end
    if maybeValue == nil then
        if keyOrValue == nil then
            logging.violate("hooks.invalid_registration", "%s: %s is required", context, valueName)
        end
        return path, keyOrValue
    end
    if type(keyOrValue) ~= "string" or keyOrValue == "" then
        logging.violate("hooks.invalid_registration", "%s: explicit key must be a non-empty string", context)
    end
    return keyOrValue, maybeValue
end

local function recordHookDeclaration(target, kind, path, key, value)
    local byKind = target[kind]
    local pathHooks = byKind[path]
    if not pathHooks then
        pathHooks = {
            order = {},
            slots = {},
        }
        byKind[path] = pathHooks
    end
    local slot = pathHooks.slots[key]
    if not slot then
        slot = {
            key = key,
        }
        pathHooks.slots[key] = slot
        pathHooks.order[#pathHooks.order + 1] = key
    end
    slot.value = value
end

function declarations.create()
    return createDeclarations()
end

function declarations.declareWrap(target, context, path, keyOrHandler, maybeHandler)
    local key, handler = parseRegistrationArgs(context, path, keyOrHandler, maybeHandler, "handler")
    if type(handler) ~= "function" then
        logging.violate("hooks.invalid_registration", "%s: handler must be a function", context)
    end
    recordHookDeclaration(target, "wrap", path, key, handler)
end

function declarations.declareOverride(target, context, path, keyOrReplacement, maybeReplacement)
    local key, replacement = parseRegistrationArgs(context, path, keyOrReplacement, maybeReplacement, "replacement")
    if type(replacement) ~= "function" then
        logging.violate("hooks.invalid_registration", "%s: replacement must be a function", context)
    end
    recordHookDeclaration(target, "override", path, key, replacement)
end

function declarations.declareContextWrap(target, context, path, keyOrContext, maybeContext)
    local key, hookContext = parseRegistrationArgs(context, path, keyOrContext, maybeContext, "context")
    if type(hookContext) ~= "function" then
        logging.violate("hooks.invalid_registration", "%s: context must be a function", context)
    end
    recordHookDeclaration(target, "contextWrap", path, key, hookContext)
end

function declarations.createRegistrar(target, contextPrefix)
    return {
        wrap = function(path, keyOrHandler, maybeHandler)
            return declarations.declareWrap(target, contextPrefix .. ".wrap", path, keyOrHandler, maybeHandler)
        end,
        override = function(path, keyOrReplacement, maybeReplacement)
            return declarations.declareOverride(
                target,
                contextPrefix .. ".override",
                path,
                keyOrReplacement,
                maybeReplacement
            )
        end,
        contextWrap = function(path, keyOrContext, maybeContext)
            return declarations.declareContextWrap(
                target,
                contextPrefix .. ".contextWrap",
                path,
                keyOrContext,
                maybeContext
            )
        end,
    }
end

return declarations
