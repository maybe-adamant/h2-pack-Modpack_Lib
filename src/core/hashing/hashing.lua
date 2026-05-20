local deps = ...

local storageService = deps.storage
local StorageTypes = storageService.types
local hashing = {}

---@param storage StorageSchema
---@return StorageNode[]
function hashing.getRoots(storage)
    return storageService.getRoots(storage)
end

---@param storage StorageSchema
---@return table<string, StorageNode|PackedBitNode>
function hashing.getAliases(storage)
    return storageService.getAliases(storage)
end

---@param node StorageNode|PackedBitNode|nil
---@param a any
---@param b any
---@return boolean
function hashing.valuesEqual(node, a, b)
    return storageService.valuesEqual(node, a, b)
end

--- Returns the packed bit width for a node type, or nil when the node is not packable.
---@param node StorageNode|PackedBitNode
---@return number|nil
function hashing.getPackWidth(node)
    if type(node) ~= "table" then return nil end
    local storageType = StorageTypes[node.type]
    if storageType and storageType.packWidth then
        return storageType.packWidth(node)
    end
    return nil
end

---@param node StorageNode|PackedBitNode
---@param value any
---@return string|nil
function hashing.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.toHash(node, value)
end

---@param node StorageNode|PackedBitNode
---@param str string
---@return any
function hashing.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.fromHash(node, str)
end

---@param node StorageNode|PackedBitNode
---@param str string|nil
---@return boolean
function hashing.isHashTokenValid(node, str)
    return storageService.isHashTokenValid(node, str)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@return number
function hashing.readPackedBits(packed, offset, width)
    return storageService.packed.readPackedBits(packed, offset, width)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@param value number|nil
---@return number
function hashing.writePackedBits(packed, offset, width, value)
    return storageService.packed.writePackedBits(packed, offset, width, value)
end

return {
    framework = hashing,
}
