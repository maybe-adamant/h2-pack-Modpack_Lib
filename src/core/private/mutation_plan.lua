local mutationPlan = {}
local values = AdamantModpackLib_Internal.values

local function CloneMutationValue(value)
    return values.deepCopy(value)
end

function mutationPlan.createBackup()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local v = tbl[key]
                saved[key] = (v == nil) and NIL or values.deepCopy(v)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, v in pairs(keys) do
                if v == NIL then
                    tbl[key] = nil
                elseif type(v) == "table" then
                    tbl[key] = values.deepCopy(v)
                else
                    tbl[key] = v
                end
            end
        end
        for tbl in pairs(savedValues) do
            savedValues[tbl] = nil
        end
    end

    return backup, restore
end

function mutationPlan.createPlan()
    local backup, restore = mutationPlan.createBackup()
    local operations = {}
    local applied = false
    local plan = {}

    local function appendOperation(op)
        operations[#operations + 1] = op
        return plan
    end

    function plan.set(_, tbl, key, value)
        return appendOperation({
            kind = "set",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    function plan.setMany(_, tbl, kv)
        return appendOperation({
            kind = "setMany",
            tbl = tbl,
            kv = kv,
        })
    end

    function plan.transform(_, tbl, key, fn)
        return appendOperation({
            kind = "transform",
            tbl = tbl,
            key = key,
            fn = fn,
        })
    end

    function plan.append(_, tbl, key, value)
        return appendOperation({
            kind = "append",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    function plan.appendUnique(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "appendUnique",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    function plan.removeElement(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "removeElement",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    function plan.setElement(_, tbl, key, oldValue, newValue, equivalentFn)
        return appendOperation({
            kind = "setElement",
            tbl = tbl,
            key = key,
            oldValue = CloneMutationValue(oldValue),
            newValue = CloneMutationValue(newValue),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    local function applyOperations()
        for _, op in ipairs(operations) do
            local tbl = op.tbl
            local key = op.key

            if op.kind == "set" then
                if tbl[key] ~= op.value then
                    backup(tbl, key)
                    tbl[key] = CloneMutationValue(op.value)
                end
            elseif op.kind == "setMany" then
                for mapKey, value in pairs(op.kv) do
                    if tbl[mapKey] ~= value then
                        backup(tbl, mapKey)
                        tbl[mapKey] = CloneMutationValue(value)
                    end
                end
            elseif op.kind == "transform" then
                backup(tbl, key)
                tbl[key] = op.fn(tbl[key], key, tbl)
            elseif op.kind == "append" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan append requires table at key '%s'"):format(tostring(key)), 0)
                else
                    backup(tbl, key)
                end
                list[#list + 1] = CloneMutationValue(op.value)
            elseif op.kind == "appendUnique" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan appendUnique requires table at key '%s'"):format(tostring(key)), 0)
                end

                local exists = false
                for _, entry in ipairs(list) do
                    if op.equivalentFn(entry, op.value) then
                        exists = true
                        break
                    end
                end
                if not exists then
                    backup(tbl, key)
                    list[#list + 1] = CloneMutationValue(op.value)
                end
            elseif op.kind == "removeElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.value) then
                            backup(tbl, key)
                            table.remove(list, index)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan removeElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            elseif op.kind == "setElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.oldValue) then
                            backup(tbl, key)
                            list[index] = CloneMutationValue(op.newValue)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan setElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            end
        end
    end

    function plan.apply()
        if applied then
            return false
        end

        local ok, err = pcall(applyOperations)
        if not ok then
            restore()
            error(err, 0)
        end

        applied = true
        return true
    end

    function plan.revert()
        if not applied then
            return false
        end
        restore()
        applied = false
        return true
    end

    return plan
end

return mutationPlan
