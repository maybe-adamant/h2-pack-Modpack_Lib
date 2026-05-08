local internal = AdamantModpackLib_Internal
public.lifecycle = public.lifecycle or {}

local lifecycleApi = public.lifecycle
local mutationInternal = internal.mutation

function lifecycleApi.notifySettingsCommitted(def, settingsObserver, store)
    if type(settingsObserver) ~= "function" then
        return true, nil
    end

    local ok, result = pcall(settingsObserver, store)
    if not ok then
        internal.violate("lifecycle.on_settings_committed_failed", "%s: onSettingsCommitted failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return true, nil
    end
    if result == false then
        internal.violate("lifecycle.on_settings_committed_false", "%s: onSettingsCommitted returned false",
            tostring(def.name or def.id or "module"))
    end
    return true, nil
end

---@class CoordinatorConfig
---@field ModEnabled boolean

---@class EnabledStore
---@field read fun(alias: string): any

--- Returns whether a pack id has coordinator metadata registered.
---@param packId string Unique coordinator pack identifier.
---@return boolean coordinated True when the pack id is registered with the coordinator.
function public.isModuleCoordinated(packId)
    return internal.coordinators[packId] ~= nil
end

--- Returns whether a coordinated or standalone module should currently be treated as enabled.
---@param store EnabledStore|nil Managed module store to read the Enabled flag from.
---@param packId string|nil Unique coordinator pack identifier.
---@return boolean enabled True when the module should be considered enabled.
function public.isModuleEnabled(store, packId)
    local coord = packId and internal.coordinators[packId]
    if coord and not coord.ModEnabled then
        return false
    end
    if not store then
        return false
    end
    return store.read("Enabled") == true
end

--- Registers coordinator metadata for a coordinated module pack.
--- Framework-facing API; feature modules should query through top-level module helpers.
---@param packId string Unique coordinator pack identifier.
---@param config CoordinatorConfig Coordinator configuration table.
function lifecycleApi.registerCoordinator(packId, config)
    if type(packId) ~= "string" or packId == "" then
        internal.violate(
            "coordinator.invalid_registration",
            "registerCoordinator: packId must be a non-empty string"
        )
    end
    if config ~= nil and type(config) ~= "table" then
        internal.violate(
            "coordinator.invalid_registration",
            "registerCoordinator: config must be a table when provided"
        )
    end
    if config ~= nil and type(config.ModEnabled) ~= "boolean" then
        internal.violate(
            "coordinator.invalid_registration",
            "registerCoordinator: config.ModEnabled must be a boolean"
        )
    end
    internal.coordinators[packId] = config
end

--- Registers a pack-level rebuild callback used when coordinated module structure changes.
---@param packId string Unique coordinator pack identifier.
---@param callback fun(reason: table)|nil Callback invoked when Lib requests a framework rebuild.
function lifecycleApi.registerCoordinatorRebuild(packId, callback)
    if callback == nil then
        internal.coordinatorRebuilds[packId] = nil
        return
    end

    if type(callback) ~= "function" then
        internal.violate(
            "coordinator.invalid_rebuild_callback",
            "registerCoordinatorRebuild: callback must be a function when provided"
        )
    end
    internal.coordinatorRebuilds[packId] = callback
end

--- Requests a coordinated pack-level rebuild after a structural module change.
---@param packId string Unique coordinator pack identifier.
---@param reason table Reason metadata describing the rebuild request.
---@return boolean requested True when a rebuild callback was registered and accepted the request.
function lifecycleApi.requestCoordinatorRebuild(packId, reason)
    local callback = packId and internal.coordinatorRebuilds[packId] or nil
    if type(callback) ~= "function" then
        return false
    end

    return callback(reason or {}) == true
end

--- Infers which mutation lifecycle a module definition exposes.
---@param def ModuleDefinition Candidate module definition table.
---@return MutationShape|nil shape Inferred lifecycle shape: `patch`, `manual`, `hybrid`, or nil.
---@return MutationInfo info Flags describing which lifecycle hooks are present on the definition.
function lifecycleApi.inferMutation(mutationBundle)
    return mutationInternal.inferMutation(mutationBundle)
end

--- Returns whether a module declares that it affects live run data.
---@param mutationBundle table|nil Candidate mutation bundle.
---@return boolean affects True when the definition opts into run-data mutation behavior.
function lifecycleApi.affectsRunData(mutationBundle)
    return mutationInternal.affectsRunData(mutationBundle)
end

--- Applies a module's current mutation lifecycle to live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function lifecycleApi.applyMutation(def, mutationBundle, store)
    return mutationInternal.apply(def, mutationBundle, store)
end

--- Reverts a module's current mutation lifecycle from live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function lifecycleApi.revertMutation(def, mutationBundle, store)
    return mutationInternal.revert(def, mutationBundle, store)
end

--- Reverts and reapplies a module's mutation lifecycle.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reapplied successfully.
---@return string|nil err Error message when the reapply step fails.
function lifecycleApi.reapplyMutation(def, mutationBundle, store)
    return mutationInternal.reapply(def, mutationBundle, store)
end

--- Applies the current effective startup lifecycle state for a module.
--- Used by Framework for coordinated modules and by standaloneHost for standalone modules.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore Managed module store associated with the definition.
---@return boolean ok True when startup lifecycle sync completed.
---@return string|nil err Error message when startup mutation application fails.
function lifecycleApi.applyOnLoad(def, mutationBundle, store)
    if public.isModuleEnabled(store, def and def.modpack) then
        local ok, err = lifecycleApi.applyMutation(def, mutationBundle, store)
        if not ok then
            return false, err
        end
    else
        local ok, err = mutationInternal.revertActive(def, store)
        if not ok then
            return false, err
        end
    end

    -- Standalone only; Framework.init handles this centrally for coordinated packs.
    if lifecycleApi.affectsRunData(mutationBundle) and not public.isModuleCoordinated(def and def.modpack) then
        rom.game.SetupRunData()
    end

    return true, nil
end

--- Audits staged session values against persisted config values and reloads staged values from config.
---@param def ModuleDefinition Module definition used for diagnostic labels.
---@param session Session Session exposing config mismatch and reload helpers.
---@return table mismatches List of alias names whose staged values drifted from persisted config.
function lifecycleApi.resyncSession(def, session)
    local mismatches = session.auditMismatches()
    if #mismatches > 0 then
        local name = def and (def.name or def.id) or "module"
        internal.violate("lifecycle.session_drift_detected", "%s: session drift detected; reloading staged values for: %s",
            tostring(name),
            table.concat(mismatches, ", "))
        session._reloadFromConfig()
    end
    return mismatches
end

--- Commits staged session values back to config and reapplies live mutations when required.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param settingsObserver fun(store: ManagedStore)|nil Post-commit observer.
---@param store ManagedStore Managed module store associated with the definition.
---@param session Session Session exposing transactional flush and reload helpers.
---@return boolean ok True when the commit completed successfully.
---@return string|nil err Error message when the commit or rollback path fails.
function lifecycleApi.commitSession(def, mutationBundle, settingsObserver, store, session)
    if not session.isDirty() then
        return true, nil
    end

    local snapshot = session._captureDirtyConfigSnapshot()
    session._flushToConfig()

    local shouldReapply = lifecycleApi.affectsRunData(mutationBundle)
        and store.read("Enabled") == true

    if not shouldReapply then
        return lifecycleApi.notifySettingsCommitted(def, settingsObserver, store)
    end

    local ok, err = lifecycleApi.reapplyMutation(def, mutationBundle, store)
    if ok then
        return lifecycleApi.notifySettingsCommitted(def, settingsObserver, store)
    end

    session._restoreConfigSnapshot(snapshot)
    session._reloadFromConfig()

    local rollbackOk, rollbackErr = lifecycleApi.reapplyMutation(def, mutationBundle, store)
    if not rollbackOk then
        internal.violate("lifecycle.session_rollback_reapply_failed", "%s: session rollback reapply failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(rollbackErr))
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end

--- Sets a module's enabled flag and runs mutation lifecycle changes when needed.
--- Host/framework-facing API. Module draw code should use session widgets instead.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore Managed module store associated with the definition.
---@param enabled boolean Desired enabled state.
---@return boolean ok True when the enabled state transition completed successfully.
---@return string|nil err Error message when the transition fails.
function lifecycleApi.setEnabled(def, mutationBundle, store, enabled)
    local nextEnabled = enabled == true
    local current = store.read("Enabled") == true

    local ok, err
    if nextEnabled and current then
        ok, err = lifecycleApi.reapplyMutation(def, mutationBundle, store)
    elseif nextEnabled then
        ok, err = lifecycleApi.applyMutation(def, mutationBundle, store)
    elseif current then
        ok, err = lifecycleApi.revertMutation(def, mutationBundle, store)
    else
        ok, err = true, nil
    end

    if not ok then
        return false, err
    end

    internal.store.writePersisted(store, "Enabled", nextEnabled)
    return true, nil
end

--- Sets a module store's persisted debug-mode flag.
--- Host/framework-facing API. Module draw code should use session widgets instead.
---@param store ManagedStore
---@param enabled boolean
function lifecycleApi.setDebugMode(store, enabled)
    internal.store.writePersisted(store, "DebugMode", enabled == true)
end
