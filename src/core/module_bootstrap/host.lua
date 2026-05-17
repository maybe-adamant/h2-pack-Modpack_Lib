local internal = AdamantModpackLib_Internal
internal.moduleHost = internal.moduleHost or {}

local HostState = setmetatable({}, { __mode = "k" })
local hostLifecycle = import('core/module_bootstrap/private_host_lifecycle.lua', nil, {
    internal = internal,
    mutation = internal.mutation,
    clone = internal.values.deepCopy,
})

function internal.moduleHost.getState(host)
    return type(host) == "table" and HostState[host] or nil
end

function internal.moduleHost.addEffectReceipt(host, name, receipt)
    local state = type(host) == "table" and HostState[host] or nil
    if not state then
        internal.violate("host.invalid_activate_opts", "moduleHost.addEffectReceipt: host is required")
    end
    if state.activated ~= true then
        internal.violate("host.not_activated", "moduleHost.addEffectReceipt requires an activated host")
    end
    if type(name) ~= "string" or name == "" then
        internal.violate("host.invalid_activate_opts", "moduleHost.addEffectReceipt: receipt name is required")
    end
    if type(receipt) ~= "table" or type(receipt.dispose) ~= "function" then
        internal.violate("host.invalid_activate_opts", "moduleHost.addEffectReceipt: receipt dispose function is required")
    end

    state.effectReceipts = state.effectReceipts or {}
    state.effectReceipts[#state.effectReceipts + 1] = {
        name = name,
        receipt = receipt,
    }
end

---@class AuthorHost
---@field isEnabled fun(): boolean
---@field getIdentity fun(): table
---@field getMeta fun(): table
---@field log fun(fmt: string, ...): nil
---@field logIf fun(fmt: string, ...): nil
---@field tryActivate fun(): boolean, string|nil

---@class ModuleHostOpts
---@field definition ModuleDefinition
---@field pluginGuid string
---@field store ManagedStore
---@field session Session
---@field registerHooks fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerPatchMutation fun(plan: table, host: AuthorHost, store: ManagedStore)|nil
---@field onSettingsCommitted fun(host: AuthorHost, store: ManagedStore, commit: table)|nil
---@field registerIntegrations fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerOverlays fun(overlays: table, host: AuthorHost, store: ManagedStore)|nil
---@field drawTab fun(imgui: table, session: AuthorSession, host: AuthorHost)
---@field drawQuickContent fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil

---@class ModuleHost
---@field getIdentity fun(): table
---@field getMeta fun(): table
---@field affectsRunData fun(): boolean
---@field getHashHints fun(): table|nil
---@field getStorage fun(): StorageSchema|nil
---@field read fun(alias: string): any
---@field writeAndFlush fun(alias: string, value: any): boolean
---@field stage fun(alias: string, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
---@field resetToDefaults fun(opts: table|nil): boolean, number
---@field commitIfDirty fun(): boolean, string|nil, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string|nil
---@field setDebugMode fun(enabled: boolean)
---@field applyMutation fun(): boolean, string|nil
---@field revertMutation fun(): boolean, string|nil
---@field tryActivate fun(): boolean, string|nil
---@field drawTab fun(imgui: table)
---@field drawQuickContent fun(imgui: table)|nil

function public.getLiveModuleHost(pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        return nil
    end
    return internal.liveModuleHosts[pluginGuid]
end

local KnownHostOpts = {
    definition = true,
    pluginGuid = true,
    store = true,
    session = true,
    registerHooks = true,
    registerPatchMutation = true,
    onSettingsCommitted = true,
    registerIntegrations = true,
    registerOverlays = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts, context)
    for key in pairs(opts) do
        if not KnownHostOpts[key] then
            internal.violate("host.unknown_opt", "%s: unknown option '%s'", context, tostring(key))
        end
    end
end

local function BuildMutationBundle(opts)
    local patchMutation = opts.registerPatchMutation

    if patchMutation ~= nil and type(patchMutation) ~= "function" then
        internal.violate("host.invalid_create_opts", "moduleHost.create: registerPatchMutation must be a function")
    end
    if opts.onSettingsCommitted ~= nil and type(opts.onSettingsCommitted) ~= "function" then
        internal.violate("host.invalid_create_opts", "moduleHost.create: onSettingsCommitted must be a function")
    end

    return {
        affectsRunData = patchMutation ~= nil,
        patchMutation = patchMutation,
    }, opts.onSettingsCommitted
end

---@param host ModuleHost
---@return AuthorHost authorHost Module-safe projection of the full host surface.
local function CreateAuthorHost(host)
    return {
        isEnabled = host.isEnabled,
        getIdentity = host.getIdentity,
        getMeta = host.getMeta,
        tryActivate = host.tryActivate,
        log = function(fmt, ...)
            return host.log(fmt, ...)
        end,
        logIf = function(fmt, ...)
            return host.logIf(fmt, ...)
        end,
    }
end

--- Creates full and author-facing host objects for Framework and standalone hosting.
--- Activation is explicit through the returned author host.
---@param opts ModuleHostOpts
---@return ModuleHost host Full module host.
---@return AuthorHost authorHost Module author host view.
function internal.moduleHost.create(opts)
    if type(opts) ~= "table" then
        internal.violate("host.invalid_create_opts", "moduleHost.create: opts must be a table")
    end
    ValidateKnownOpts(opts, "moduleHost.create")
    local def = opts.definition
    local pluginGuid = opts.pluginGuid
    local store = opts.store
    local session = opts.session
    local registerHooks = opts.registerHooks
    local registerIntegrations = opts.registerIntegrations
    local registerOverlays = opts.registerOverlays
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        internal.violate("host.invalid_create_opts", "moduleHost.create: prepared definition is required")
    end
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("host.invalid_create_opts", "moduleHost.create: pluginGuid is required")
    end
    if not (store and type(store.read) == "function") then
        internal.violate("host.invalid_create_opts", "moduleHost.create: store is required")
    end
    if not (session and type(session.isDirty) == "function" and type(session.write) == "function"
        and type(session.getAliasSchema) == "function") then
        internal.violate("host.invalid_create_opts", "moduleHost.create: session is required")
    end

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local mutationBundle, settingsObserver = BuildMutationBundle(opts)

    if type(drawTab) ~= "function" then
        internal.violate("host.invalid_create_opts", "moduleHost.create: drawTab is required")
    end
    if registerHooks ~= nil then
        if type(registerHooks) ~= "function" then
            internal.violate("host.invalid_create_opts", "moduleHost.create: registerHooks must be a function")
        end
    end
    if registerIntegrations ~= nil and type(registerIntegrations) ~= "function" then
        internal.violate("host.invalid_create_opts", "moduleHost.create: registerIntegrations must be a function")
    end
    if registerOverlays ~= nil then
        if type(registerOverlays) ~= "function" then
            internal.violate("host.invalid_create_opts", "moduleHost.create: registerOverlays must be a function")
        end
    end
    ---@type ModuleHost
    local host = {}

    local function notifySettingsCommitted(activeHost, activeStore, commit)
        local observerOk = true
        local observerResult = nil
        if settingsObserver ~= nil then
            observerOk, observerResult = pcall(settingsObserver, activeHost, activeStore, commit)
        end

        local overlayOk, overlayErr = pcall(internal.overlays.dispatchCommit, host, commit)
        if not observerOk then
            if not overlayOk then
                error(tostring(observerResult) .. " (overlay dispatch failed: " .. tostring(overlayErr) .. ")", 0)
            end
            error(observerResult, 0)
        end
        if not overlayOk then
            error(overlayErr, 0)
        end
        return observerResult
    end

    local authorSession = internal.moduleState.createAuthorSession(session, {
        resetToDefaults = function(resetOpts)
            return public.resetStorageToDefaults(def.storage, session, resetOpts)
        end,
    })

    ---@type AuthorHost
    local authorHost

    local function requireActivated(methodName)
        local state = HostState[host]
        if not state or state.activated ~= true then
            internal.violate("host.not_activated", "host.%s requires host.tryActivate() before it can run", methodName)
        end
    end

    function host.getIdentity()
        return {
            id = def.id,
            modpack = def.modpack,
        }
    end

    function host.getMeta()
        return {
            name = def.name,
            shortName = def.shortName,
            tooltip = def.tooltip,
        }
    end

    function host.affectsRunData()
        return internal.mutation.affectsRunData(mutationBundle)
    end

    function host.getHashHints()
        return def.hashGroupPlan
    end

    function host.getStorage()
        return def.storage
    end

    function host.read(alias)
        return store.read(alias)
    end

    function host.writeAndFlush(alias, value)
        requireActivated("writeAndFlush")
        session.write(alias, value)
        local ok, err = hostLifecycle.commitSession(def, mutationBundle, notifySettingsCommitted, authorHost, store, session,
            pluginGuid)
        return ok, err
    end

    function host.stage(alias, value)
        session.write(alias, value)
        return true
    end

    function host.flush()
        requireActivated("flush")
        if not session.isDirty() then
            return true
        end
        return hostLifecycle.commitSession(def, mutationBundle, notifySettingsCommitted, authorHost, store, session,
            pluginGuid)
    end

    function host.reloadFromConfig()
        requireActivated("reloadFromConfig")
        session._reloadFromConfig()
    end

    function host.resync()
        requireActivated("resync")
        return hostLifecycle.resyncSession(def, session)
    end

    function host.resetToDefaults(resetOpts)
        requireActivated("resetToDefaults")
        return public.resetStorageToDefaults(def.storage, session, resetOpts)
    end

    function host.commitIfDirty()
        requireActivated("commitIfDirty")
        if not session.isDirty() then
            return true, nil, false
        end
        local ok, err = hostLifecycle.commitSession(def, mutationBundle, notifySettingsCommitted, authorHost, store, session,
            pluginGuid)
        return ok, err, ok == true
    end

    function host.isEnabled()
        return hostLifecycle.isEnabled(store, def.modpack)
    end

    function host.setEnabled(enabled)
        requireActivated("setEnabled")
        return hostLifecycle.setEnabled(def, mutationBundle, authorHost, store, enabled, pluginGuid)
    end

    function host.setDebugMode(enabled)
        requireActivated("setDebugMode")
        return hostLifecycle.setDebugMode(store, enabled)
    end

    local logPrefix = "[" .. tostring(def.id or pluginGuid) .. "] "

    function host.log(fmt, ...)
        print(internal.formatLogMessage(logPrefix, fmt, ...))
    end

    function host.logIf(fmt, ...)
        if store.read("DebugMode") == true then
            host.log(fmt, ...)
        end
    end

    function host.applyMutation()
        requireActivated("applyMutation")
        return internal.mutation.applyForPlugin(pluginGuid, def, mutationBundle, authorHost, store)
    end

    function host.revertMutation()
        requireActivated("revertMutation")
        return internal.mutation.revertForPlugin(pluginGuid, def, mutationBundle, authorHost, store)
    end

    function host.tryActivate()
        return internal.moduleHost.tryActivate(host)
    end

    authorHost = CreateAuthorHost(host)

    function host.drawTab(imgui)
        requireActivated("drawTab")
        return drawTab(imgui, authorSession, authorHost)
    end

    if type(drawQuickContent) == "function" then
        function host.drawQuickContent(imgui)
            requireActivated("drawQuickContent")
            return drawQuickContent(imgui, authorSession, authorHost)
        end
    end

    HostState[host] = {
        definition = def,
        mutationBundle = mutationBundle,
        pluginGuid = pluginGuid,
        store = store,
        registerHooks = registerHooks,
        registerIntegrations = registerIntegrations,
        registerOverlays = registerOverlays,
        authorSession = authorSession,
        authorHost = authorHost,
        effectReceipts = {},
        activated = false,
    }

    return host, authorHost
end

local function callReceipt(receipt, methodName)
    if not (receipt and type(receipt[methodName]) == "function") then
        return true, nil
    end

    local ok, result, err = pcall(receipt[methodName])
    if not ok then
        return false, result
    end
    if result == false then
        return false, err
    end
    return true, nil
end

local function warnReceiptDisposal(warningId, warningPrefix, errors)
    if warningId == "host.retire_failed" then
        internal.violate("host.retire_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    elseif warningId == "host.activation_rollback_failed" then
        internal.violate("host.activation_rollback_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    end
end

local function disposeReceipts(receipts, warningId, warningPrefix)
    local errors = {}
    for index = #receipts, 1, -1 do
        local entry = receipts[index]
        local ok, err = callReceipt(entry.receipt, "dispose")
        if not ok then
            errors[#errors + 1] = tostring(entry.name or "receipt") .. ": " .. tostring(err)
        end
    end
    if #errors > 0 then
        warnReceiptDisposal(warningId, warningPrefix, errors)
    end
    return errors
end

local function commitReceipt(entry)
    local ok, err = callReceipt(entry.receipt, "commit")
    if not ok then
        return false, tostring(entry.name or "receipt") .. " commit failed: " .. tostring(err)
    end
    return true, nil
end

local function retireOldHost(previousHost, replacementLabel)
    local oldState = HostState[previousHost]
    local receipts = oldState and oldState.effectReceipts or nil
    if type(receipts) ~= "table" or #receipts == 0 then
        return
    end
    disposeReceipts(receipts, "host.retire_failed", tostring(replacementLabel) .. " old host retirement failed")
    oldState.effectReceipts = {}
end

--- Activates a constructed module host by registering external side effects.
---@param host ModuleHost
---@return AuthorHost host Module author host view.
function internal.moduleHost.activate(host)
    local state = type(host) == "table" and HostState[host] or nil
    if not state then
        internal.violate("host.invalid_activate_opts", "moduleHost.activate: host is required")
    end

    local pluginGuid = state.pluginGuid
    local registerHooks = state.registerHooks
    local registerIntegrations = state.registerIntegrations
    local registerOverlays = state.registerOverlays
    local store = state.store
    local authorHost = state.authorHost
    local def = state.definition

    if state.activated == true then
        internal.violate("host.already_activated", "moduleHost.activate: host is already activated")
    end
    if state.activating == true then
        internal.violate("host.activation_in_progress", "moduleHost.activate: host activation is already in progress")
    end
    local identity = host.getIdentity()
    local meta = host.getMeta()
    local packId = identity.modpack
    local pendingCoordinatorRebuild = internal.pendingCoordinatorRebuilds[def]
    local hasPendingCoordinatorRebuild = pendingCoordinatorRebuild ~= nil
    local previousHost = internal.liveModuleHosts[pluginGuid]
    local candidateReceipts = {}
    local retireReceipts = {}
    local published = false
    state.activating = true

    local function addReceipt(name, receipt, retire)
        local entry = {
            name = name,
            receipt = receipt,
        }
        candidateReceipts[#candidateReceipts + 1] = entry
        if retire == true then
            retireReceipts[#retireReceipts + 1] = entry
        end
        return entry
    end

    local ok, err = pcall(function()
        addReceipt("integrations", internal.integrations.installForHost(host, registerIntegrations, authorHost, store), true)
        addReceipt("hooks", internal.hooks.installForHost(host, registerHooks, authorHost, store), true)
        addReceipt("overlays", internal.overlays.installForHost(host, registerOverlays, authorHost, store), true)

        if not hasPendingCoordinatorRebuild then
            addReceipt("mutation", internal.mutation.syncForHost(host, state.mutationBundle, authorHost, store), false)
        elseif hasPendingCoordinatorRebuild then
            local requested = public.coordinator.requestRebuild(packId, pendingCoordinatorRebuild)
            if requested then
                internal.pendingCoordinatorRebuilds[def] = nil
            else
                internal.violate(
                    "host.structural_rebuild_unavailable",
                    "%s structural definition changed during hot reload; full reload required",
                    tostring(meta.name or identity.id or "module"))
            end
        end

        for _, entry in ipairs(candidateReceipts) do
            if entry.name == "mutation" then
                local commitOk, commitErr = commitReceipt(entry)
                if not commitOk then
                    error(commitErr, 0)
                end
            end
        end

        for _, entry in ipairs(candidateReceipts) do
            if entry.name ~= "mutation" then
                local commitOk, commitErr = commitReceipt(entry)
                if not commitOk then
                    error(commitErr, 0)
                end
            end
        end

        state.effectReceipts = retireReceipts
        state.activating = false
        state.activated = true
        internal.liveModuleHosts[pluginGuid] = host
        published = true
    end)

    if not ok then
        state.activating = false
        state.activated = false
        disposeReceipts(candidateReceipts, "host.activation_rollback_failed",
            tostring(meta.name or identity.id or "module") .. " activation rollback failed")
        if published then
            internal.liveModuleHosts[pluginGuid] = previousHost
        end
        error(err, 0)
    end

    retireOldHost(previousHost, meta.name or identity.id or "module")
    return authorHost
end

--- Safely activates a constructed module host by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param host ModuleHost
---@return boolean ok
---@return string|nil err
function internal.moduleHost.tryActivate(host)
    local ok, err = pcall(internal.moduleHost.activate, host)
    if ok then
        return true, nil
    end

    err = tostring(err)
    internal.violate("host.activate_failed", "host.tryActivate failed; skipping module: %s", err)
    return false, err
end
