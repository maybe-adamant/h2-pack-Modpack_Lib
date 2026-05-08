local mutationPlan = ...
local internal = AdamantModpackLib_Internal
internal.mutation = internal.mutation or {}

local mutationInternal = internal.mutation
local storeRuntime = setmetatable({}, { __mode = "k" })
local moduleRuntime = {}

---@alias MutationShape "patch"|"manual"|"hybrid"

---@class MutationInfo
---@field hasPatch boolean
---@field hasApply boolean
---@field hasRevert boolean
---@field hasManual boolean

local function GetRuntimeKey(def, store)
    if def and type(def.id) == "string" and def.id ~= "" then
        local packId = type(def.modpack) == "string" and def.modpack or ""
        return "module:" .. packId .. ":" .. def.id, moduleRuntime
    end
    if store then
        return store, storeRuntime
    end
    return nil, nil
end

local function GetRuntimeState(def, store)
    local key, bucket = GetRuntimeKey(def, store)
    if not bucket then
        return nil, nil, nil
    end
    return bucket[key], key, bucket
end

local function SetRuntimeState(def, store, state)
    local key, bucket = GetRuntimeKey(def, store)
    if not bucket then
        return
    end
    if state == nil or (state.plan == nil and state.manualRevert == nil) then
        bucket[key] = nil
        return
    end
    bucket[key] = state
end

local function SetActiveMutationPlan(def, store, plan)
    local runtime = GetRuntimeState(def, store) or {}
    runtime.plan = plan
    SetRuntimeState(def, store, runtime)
end

local function SetActiveManualRevert(def, store, revertFn)
    local runtime = GetRuntimeState(def, store) or {}
    runtime.manualRevert = revertFn
    SetRuntimeState(def, store, runtime)
end

local function BuildMutationPlan(mutationBundle, store)
    local builder = mutationBundle and mutationBundle.patchMutation
    if type(builder) ~= "function" then
        return nil
    end

    local plan = mutationPlan.createPlan()
    builder(plan, store)
    return plan
end

local function RevertActivePlan(def, store)
    local runtime = GetRuntimeState(def, store)
    local activePlan = runtime and runtime.plan or nil
    if not activePlan then
        return true, nil, false
    end

    local okPlan, errPlan = pcall(activePlan.revert, activePlan)
    runtime.plan = nil
    SetRuntimeState(def, store, runtime)
    if not okPlan then
        return false, errPlan, true
    end
    return true, nil, true
end

local function RevertActiveManual(def, store)
    local runtime = GetRuntimeState(def, store)
    local revertFn = runtime and runtime.manualRevert or nil
    if type(revertFn) ~= "function" then
        return true, nil, false
    end

    local okManual, errManual = pcall(revertFn, store)
    runtime.manualRevert = nil
    SetRuntimeState(def, store, runtime)
    if not okManual then
        return false, errManual, true
    end
    return true, nil, true
end

local function RevertActiveMutation(def, store)
    local firstErr = nil
    local didActive = false

    local okManual, errManual, didManual = RevertActiveManual(def, store)
    if not okManual and not firstErr then
        firstErr = errManual
    end
    didActive = didActive or didManual

    local okPlan, errPlan, didPlan = RevertActivePlan(def, store)
    if not okPlan and not firstErr then
        firstErr = errPlan
    end
    didActive = didActive or didPlan

    if firstErr then
        return false, firstErr, didActive
    end

    return true, nil, didActive
end

--- Infers which mutation lifecycle a module exposes.
---@param mutationBundle table|nil Candidate mutation bundle.
---@return MutationShape|nil shape Inferred lifecycle shape: `patch`, `manual`, `hybrid`, or nil.
---@return MutationInfo info Flags describing which lifecycle hooks are present on the definition.
function mutationInternal.inferMutation(mutationBundle)
    local manual = mutationBundle and mutationBundle.manualMutation or nil
    local hasPatch = mutationBundle and type(mutationBundle.patchMutation) == "function" or false
    local hasApply = manual and type(manual.apply) == "function" or false
    local hasRevert = manual and type(manual.revert) == "function" or false
    local hasManual = hasApply and hasRevert

    local inferred = nil
    if hasPatch and hasManual then
        inferred = "hybrid"
    elseif hasPatch then
        inferred = "patch"
    elseif hasManual then
        inferred = "manual"
    end

    return inferred, {
        hasPatch = hasPatch,
        hasApply = hasApply,
        hasRevert = hasRevert,
        hasManual = hasManual,
    }
end

--- Returns whether a module declares that it affects live run data.
---@param mutationBundle table|nil Candidate mutation bundle.
---@return boolean affects True when the definition opts into run-data mutation behavior.
function mutationInternal.affectsRunData(mutationBundle)
    return mutationBundle and mutationBundle.affectsRunData == true or false
end

--- Applies a module's current mutation lifecycle to live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function mutationInternal.apply(def, mutationBundle, store)
    local inferred, info = mutationInternal.inferMutation(mutationBundle)

    local okActive, errActive = RevertActiveMutation(def, store)
    if not okActive then
        return false, errActive
    end

    if not inferred then
        if not mutationInternal.affectsRunData(mutationBundle) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local builtPlan = nil
    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, mutationBundle, store)
        if not okBuild then
            return false, result
        end
        builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(builtPlan.apply, builtPlan)
            if not okApply then
                return false, errApply
            end
            SetActiveMutationPlan(def, store, builtPlan)
        end
    end

    if info.hasManual then
        local manual = mutationBundle.manualMutation
        local okManual, errManual = pcall(manual.apply, store)
        if not okManual then
            if builtPlan then
                pcall(builtPlan.revert, builtPlan)
                SetActiveMutationPlan(def, store, nil)
            end
            return false, errManual
        end
        SetActiveManualRevert(def, store, manual.revert)
    end

    return true, nil
end

--- Reverts any active tracked mutation state without invoking fallback lifecycle hooks.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when active mutation state was absent or reverted successfully.
---@return string|nil err Error message when active cleanup fails.
function mutationInternal.revertActive(def, store)
    local ok, err = RevertActiveMutation(def, store)
    return ok, err
end

--- Reverts a module's current mutation lifecycle from live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function mutationInternal.revert(def, mutationBundle, store)
    local inferred, info = mutationInternal.inferMutation(mutationBundle)
    if not inferred then
        local okActive, errActive, didActive = RevertActiveMutation(def, store)
        if not okActive then
            return false, errActive
        end
        if didActive or not mutationInternal.affectsRunData(mutationBundle) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local firstErr = nil

    if info.hasManual then
        local manual = mutationBundle.manualMutation
        local okActiveManual, errActiveManual, didActiveManual = RevertActiveManual(def, store)
        if not okActiveManual and not firstErr then
            firstErr = errActiveManual
        elseif not didActiveManual then
            local okManual, errManual = pcall(manual.revert, store)
            if not okManual and not firstErr then
                firstErr = errManual
            end
        end
    end

    local okPlan, errPlan = RevertActivePlan(def, store)
    if not okPlan and not firstErr then
        firstErr = errPlan
    end

    if firstErr then
        return false, firstErr
    end

    return true, nil
end

--- Reverts and reapplies a module's mutation lifecycle.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reapplied successfully.
---@return string|nil err Error message when the reapply step fails.
function mutationInternal.reapply(def, mutationBundle, store)
    local okRevert, errRevert = mutationInternal.revert(def, mutationBundle, store)
    if not okRevert then
        return false, errRevert
    end

    local okApply, errApply = mutationInternal.apply(def, mutationBundle, store)
    if not okApply then
        return false, errApply
    end

    return true, nil
end
