public.hooks = public.hooks or {}
public.hooks.Context = public.hooks.Context or {}
AdamantModpackLib_Internal.hooks = AdamantModpackLib_Internal.hooks or {}

local internal = AdamantModpackLib_Internal
local dispatchers = import 'core/hooks/private_dispatchers.lua'
local ActiveHostInstallStack = {}

local function parseRegistrationArgs(path, keyOrValue, maybeValue, valueName)
    if type(path) ~= "string" or path == "" then
        internal.violate("hooks.invalid_registration", "lib.hooks: path must be a non-empty string")
    end
    if maybeValue == nil then
        if keyOrValue == nil then
            internal.violate("hooks.invalid_registration", "lib.hooks: %s is required", valueName)
        end
        return path, keyOrValue
    end
    return tostring(keyOrValue), maybeValue
end

local function requireActiveInstall(apiName)
    local install = ActiveHostInstallStack[#ActiveHostInstallStack]
    if not install then
        internal.violate(
            "hooks.no_active_owner",
            "lib.hooks.%s requires an active registerHooks context",
            apiName
        )
    end
    return install
end

local function getHostPluginGuid(host)
    local moduleHost = internal.moduleHost
    local state = moduleHost and moduleHost.getState and moduleHost.getState(host) or nil
    local pluginGuid = state and state.pluginGuid or nil
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("hooks.invalid_registration", "internal.hooks.installForHost: host pluginGuid is required")
    end
    return pluginGuid
end

local function recordHookDeclaration(kind, path, key, value)
    local install = ActiveHostInstallStack[#ActiveHostInstallStack]
    if not install then
        return false
    end
    local byKind = install.declarations[kind]
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
    return true
end

--- Registers a host-owned ModUtil Path.Wrap handler in the active registerHooks pass.
---@param path string ModUtil path to wrap.
---@param keyOrHandler string|function Explicit hook key, or handler when no key is needed.
---@param maybeHandler function|nil Handler when an explicit key is supplied.
function public.hooks.Wrap(path, keyOrHandler, maybeHandler)
    requireActiveInstall("Wrap")
    local key, handler = parseRegistrationArgs(path, keyOrHandler, maybeHandler, "handler")
    if type(handler) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Wrap: handler must be a function")
    end
    recordHookDeclaration("wrap", path, key, handler)
end

function internal.hooks.installPhysicalWrap(physicalOwner, path, keyOrHandler, maybeHandler)
    local key, handler = parseRegistrationArgs(path, keyOrHandler, maybeHandler, "handler")
    if type(handler) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Wrap: handler must be a function")
    end

    dispatchers.installPhysicalWrap(physicalOwner, path, key, handler)
end

--- Registers a host-owned ModUtil Path.Override replacement in the active registerHooks pass.
---@param path string ModUtil path to override.
---@param keyOrReplacement string|function Explicit hook key, or replacement when no key is needed.
---@param maybeReplacement function|nil Replacement when an explicit key is supplied.
function public.hooks.Override(path, keyOrReplacement, maybeReplacement)
    requireActiveInstall("Override")
    local key, replacement = parseRegistrationArgs(path, keyOrReplacement, maybeReplacement, "replacement")
    if type(replacement) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Override: replacement must be a function")
    end
    recordHookDeclaration("override", path, key, replacement)
end

--- Registers a host-owned ModUtil Path.Context.Wrap handler in the active registerHooks pass.
---@param path string ModUtil path to context-wrap.
---@param keyOrContext string|function Explicit hook key, or context function when no key is needed.
---@param maybeContext function|nil Context function when an explicit key is supplied.
function public.hooks.Context.Wrap(path, keyOrContext, maybeContext)
    requireActiveInstall("Context.Wrap")
    local key, context = parseRegistrationArgs(path, keyOrContext, maybeContext, "context")
    if type(context) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Context.Wrap: context must be a function")
    end
    recordHookDeclaration("contextWrap", path, key, context)
end

function internal.hooks.installPhysicalContextWrap(physicalOwner, path, keyOrContext, maybeContext)
    local key, context = parseRegistrationArgs(path, keyOrContext, maybeContext, "context")
    if type(context) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Context.Wrap: context must be a function")
    end

    dispatchers.installPhysicalContextWrap(physicalOwner, path, key, context)
end

function internal.hooks.installForHost(host, register, authorHost, store)
    local pluginGuid = getHostPluginGuid(host)
    local install = {
        host = host,
        pluginGuid = pluginGuid,
        declarations = {
            wrap = {},
            override = {},
            contextWrap = {},
        },
        committed = false,
        slotsAttached = false,
        disposed = false,
        previousCurrentHost = nil,
    }

    if register ~= nil then
        if type(register) ~= "function" then
            internal.violate("hooks.invalid_registration", "internal.hooks.installForHost: register must be a function")
        end

        ActiveHostInstallStack[#ActiveHostInstallStack + 1] = install
        local ok, err = pcall(register, authorHost, store)
        ActiveHostInstallStack[#ActiveHostInstallStack] = nil
        if not ok then
            error(err, 0)
        end
    end

    return {
        commit = function()
            if install.disposed or install.committed then
                return true, nil
            end

            install.previousCurrentHost = dispatchers.getCurrentHost(pluginGuid)
            install.slotsAttached = true
            dispatchers.attachHost(pluginGuid, host, install.declarations)
            install.committed = true
            return true, nil
        end,
        dispose = function()
            if install.disposed then
                return true, nil
            end

            if install.committed or install.slotsAttached then
                dispatchers.detachHost(pluginGuid, host, install.declarations, install.previousCurrentHost)
            end

            install.slotsAttached = false
            install.disposed = true
            return true, nil
        end,
    }
end
