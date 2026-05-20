local deps = ...

local runtime = deps.runtime
-- Hot-reload-stable mutation runtime. Active plans must remain revertible
-- across Lib re-imports because they may already be applied to run data.
runtime.mutation = runtime.mutation or {}
local mutationState = runtime.mutation
mutationState.ownerRuntime = mutationState.ownerRuntime or {}
mutationState.planExecutors = mutationState.planExecutors or setmetatable({}, { __mode = "k" })

local plan = import('core/mutations/plan.lua', nil, {
    values = deps.values,
    planExecutors = mutationState.planExecutors,
})

local lifecycle = import('core/mutations/lifecycle.lua', nil, {
    logging = deps.logging,
    coordinator = deps.coordinator,
    setupRunData = deps.gameDeps.runData.SetupRunData,
    mutationState = mutationState,
    plan = plan,
})

local service = import('core/mutations/adapter_host.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    lifecycle = lifecycle,
})

local author = import('core/mutations/adapter_author.lua', nil, {
    logging = deps.logging,
    hostState = deps.hostState,
    lifecycle = lifecycle,
})

return {
    service = service,
    author = author,
    plan = plan,
}
