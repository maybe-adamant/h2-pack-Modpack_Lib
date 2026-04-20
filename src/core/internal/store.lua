local internal = AdamantModpackLib_Internal

internal.store = internal.store or {}
local storeInternal = internal.store

local StoreState = setmetatable({}, { __mode = "k" })

function storeInternal.readNestedPath(tbl, key)
    if type(key) == "table" then
        if #key == 0 then return nil, nil, nil end
        for i = 1, #key - 1 do
            tbl = tbl[key[i]]
            if not tbl then return nil, nil, nil end
        end
        return tbl[key[#key]], tbl, key[#key]
    end
    return tbl[key], tbl, key
end

function storeInternal.writeNestedPath(tbl, key, value)
    if type(key) == "table" then
        for i = 1, #key - 1 do
            tbl[key[i]] = tbl[key[i]] or {}
            tbl = tbl[key[i]]
        end
        tbl[key[#key]] = value
        return
    end
    tbl[key] = value
end

function storeInternal.ClonePersistedValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

--- Registers internal callbacks for a managed store object.
---@param store ManagedStore
---@param state table
function storeInternal.bindManagedStore(store, state)
    StoreState[store] = state
end

--- Writes a persisted storage value through a managed store.
--- Internal plumbing only; ordinary state changes should go through session.
---@param store ManagedStore
---@param keyOrAlias string|table Alias, config key, or nested config path to write.
---@param value any Value to persist, normalized through the owning storage type when applicable.
function storeInternal.writePersisted(store, keyOrAlias, value)
    local state = store and StoreState[store] or nil
    if not state or type(state.write) ~= "function" then
        error("internal.store.writePersisted expects a managed store", 2)
    end
    return state.write(keyOrAlias, value)
end

---@param store ManagedStore
---@param alias string
---@return table[]
function storeInternal.getPackedAliases(store, alias)
    local state = store and StoreState[store] or nil
    if not state or type(state.getPackedAliases) ~= "function" then
        return {}
    end
    return state.getPackedAliases(alias)
end
