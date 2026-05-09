local internal = AdamantModpackLib_Internal

---@class ModuleCreateOpts
---@field owner table
---@field pluginGuid string
---@field config table
---@field definition ModuleDefinition
---@field registerHooks fun()|nil
---@field registerPatchMutation fun(plan: table, store: ManagedStore)|nil
---@field registerManualMutation table|nil
---@field onSettingsCommitted fun(store: ManagedStore)|nil
---@field registerIntegrations fun(host: AuthorHost)|nil
---@field drawTab fun(imgui: table, session: AuthorSession, host: AuthorHost)
---@field drawQuickContent fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil

local KnownModuleOpts = {
    owner = true,
    pluginGuid = true,
    config = true,
    definition = true,
    registerHooks = true,
    registerPatchMutation = true,
    registerManualMutation = true,
    onSettingsCommitted = true,
    registerIntegrations = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts)
    for key in pairs(opts) do
        if not KnownModuleOpts[key] then
            internal.violate("host.unknown_opt", "createModule: unknown option '%s'", tostring(key))
        end
    end
end

--- Creates a module through the canonical prepare -> store -> host pipeline.
---@param opts ModuleCreateOpts
---@return AuthorHost host
---@return ManagedStore store
function public.createModule(opts)
    if type(opts) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModule: opts must be a table")
    end
    ValidateKnownOpts(opts)
    if type(opts.config) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModule: config is required")
    end
    if type(opts.owner) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModule: owner is required")
    end

    local definition = public.prepareDefinition(opts.owner, opts.definition)
    local store, session = public.createStore(opts.config, definition)
    opts.owner.store = store
    local host = public.createModuleHost({
        pluginGuid = opts.pluginGuid,
        definition = definition,
        store = store,
        session = session,
        hookOwner = opts.owner,
        registerHooks = opts.registerHooks,
        registerPatchMutation = opts.registerPatchMutation,
        registerManualMutation = opts.registerManualMutation,
        onSettingsCommitted = opts.onSettingsCommitted,
        registerIntegrations = opts.registerIntegrations,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    opts.owner.host = host

    return host, store
end
