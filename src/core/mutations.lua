public.mutation = public.mutation or {}
local mutation = public.mutation
local internal = AdamantModpackLib_Internal
internal.mutation = internal.mutation or {}
local mutationInternal = internal.mutation

---@class MutationPlan
---@field set fun(self: MutationPlan, tbl: table, key: any, value: any): MutationPlan
---@field setMany fun(self: MutationPlan, tbl: table, kv: table): MutationPlan
---@field transform fun(self: MutationPlan, tbl: table, key: any, fn: fun(current: any, key: any, tbl: table): any): MutationPlan
---@field append fun(self: MutationPlan, tbl: table, key: any, value: any): MutationPlan
---@field appendUnique fun(self: MutationPlan, tbl: table, key: any, value: any, eqFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field removeElement fun(self: MutationPlan, tbl: table, key: any, value: any, eqFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field setElement fun(self: MutationPlan, tbl: table, key: any, oldVal: any, newVal: any, eq: fun(any, any): boolean?): MutationPlan
---@field apply fun(): boolean
---@field revert fun(): boolean

--- Creates backup and restore helpers for reversible table mutations.
---@return function backup Captures original values on a table before mutation.
---@return function restore Restores all captured values back onto their original tables.
function mutation.createBackup()
    return mutationInternal.createBackup()
end

--- Creates a reversible mutation plan that can batch table updates and roll them back later.
---@return MutationPlan plan Mutable mutation plan with operation builders plus apply/revert methods.
function mutation.createPlan()
    return mutationInternal.createPlan() --[[@as MutationPlan]]
end
