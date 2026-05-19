local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost = {}

function TestModuleHost:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
    self.previousImGui = self.h.rom.ImGui
    self.previousImGuiCond = self.h.rom.ImGuiCond
end

function TestModuleHost:tearDown()
    self.h.rom.ImGui = self.previousImGui
    self.h.rom.ImGuiCond = self.previousImGuiCond
    self.h:restoreWarnings()
end

local function createActivatedHost(h, pluginGuid, opts, activationOpts)
    activationOpts = activationOpts or {}
    local host, authorHost = h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = opts.definition,
        store = opts.store,
        session = opts.session,
        registerHooks = activationOpts.registerHooks or opts.registerHooks,
        registerPatchMutation = opts.registerPatchMutation,
        onSettingsCommitted = opts.onSettingsCommitted,
        registerIntegrations = activationOpts.registerIntegrations or opts.registerIntegrations,
        registerOverlays = activationOpts.registerOverlays or opts.registerOverlays,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    authorHost.tryActivate()
    return host, authorHost
end

function TestModuleHost:testStandaloneHostWarnsWhenSessionCommitFails()
    local drawCalls = 0
    local pluginGuid = "test-standalone-commit"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "standalone-pack",
        id = "StandaloneTest",
        name = "Standalone Test",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)

    local function noop() end

    self.h.rom.ImGuiCond = { FirstUseEver = 1 }
    self.h.rom.ImGui = {
        BeginMenu = function() return true end,
        MenuItem = function() return true end,
        EndMenu = noop,
        SetNextWindowSize = noop,
        Begin = function() return true, true end,
        End = noop,
        Checkbox = function(_, current) return current, false end,
        Button = function() return false end,
        Separator = noop,
        Spacing = noop,
    }

    createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    local moduleHost = self.h.public.getLiveModuleHost(pluginGuid)
    moduleHost.commitIfDirty = function()
        return false, "commit boom", false
    end

    local runtime = self.h.public.standaloneHost(pluginGuid)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "Standalone Test session commit failed")
    lu.assertStrContains(self.h.warnings[1], "commit boom")
    lu.assertEquals(self.h.public.getLiveModuleHost(pluginGuid), moduleHost)
end

function TestModuleHost:testStandaloneHostCanResolveCurrentModuleHostFromLibRegistry()
    local pluginGuid = "test-standalone-registry"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "StandaloneRegistryHost",
        name = "Standalone Registry Host",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local _, authorHost = createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })
    local host = self.h.public.getLiveModuleHost(pluginGuid)

    local runtime = self.h.public.standaloneHost(pluginGuid)

    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(authorHost.isEnabled), "function")
    lu.assertEquals(self.h.public.getLiveModuleHost(pluginGuid), host)
end

function TestModuleHost:testFlushNotifiesSettingsObserver()
    local calls = 0
    local observedValue = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "SettingsObserverHost",
        name = "Settings Observer Host",
        storage = {
            { type = "bool", alias = "Value", default = false },
        },
    })
    local store, session = self.h:createModuleState({
        Value = false,
    }, definition)
    createActivatedHost(self.h, "test-settings-observer-host", {
        definition = definition,
        store = store,
        session = session,
        onSettingsCommitted = function(_, activeStore)
            calls = calls + 1
            observedValue = activeStore.read("Value")
        end,
        drawTab = function() end,
    })
    local host = self.h.public.getLiveModuleHost("test-settings-observer-host")

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestModuleHost:testPatchMutationReceivesAuthorHost()
    local target = { Value = false }
    local patchHost = nil
    local patchStore = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "PatchHostModule",
        name = "Patch Host Module",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = createActivatedHost(self.h, "test-patch-host", {
        definition = definition,
        store = store,
        session = session,
        registerPatchMutation = function(plan, activeHost, activeStore)
            patchHost = activeHost
            patchStore = activeStore
            plan:set(target, "Value", true)
        end,
        drawTab = function() end,
    })
    local ok, err = host.applyMutation()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(patchHost, authorHost)
    lu.assertEquals(patchStore, store)
    lu.assertTrue(target.Value)
end

function TestModuleHost:testSideEffectingHostMethodsRequireActivation()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "InactiveHost",
        name = "Inactive Host",
        storage = {},
    })
    local store, session = self.h:createModuleState({}, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = "test-inactive-host",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)
end

function TestModuleHost:testHostAndAuthorSessionResetToDefaultsDelegateToLibHelper()
    local capturedAuthorSession = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, session = self.h:createModuleState({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedHost(self.h, "test-reset-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(ctx)
            capturedAuthorSession = ctx.session
        end,
    })
    local host = self.h.public.getLiveModuleHost("test-reset-host")

    host.drawTab({})

    local changed, count = host.resetToDefaults()
    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 2)

    session.write("EnabledFlag", true)
    session.write("Count", 6)
    local authorChanged, authorCount = capturedAuthorSession.resetToDefaults({
        exclude = { Count = true },
    })
    lu.assertTrue(authorChanged)
    lu.assertEquals(authorCount, 1)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 6)
end

function TestModuleHost:testCreateModuleHostPassesAuthorHostToCallbacks()
    local callbackHost = nil
    local drawHost = nil
    local quickHost = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "author-pack",
        id = "AuthorHostModule",
        name = "Author Host Module",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    local _, returnedHost = createActivatedHost(self.h, "test-author-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(ctx)
            drawHost = ctx.host
        end,
        drawQuickContent = function(ctx)
            quickHost = ctx.host
        end,
    }, {
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
    })

    local host = self.h.public.getLiveModuleHost("test-author-host")
    host.drawTab({})
    host.drawQuickContent({})

    lu.assertEquals(returnedHost, callbackHost)
    lu.assertEquals(callbackHost, drawHost)
    lu.assertEquals(callbackHost, quickHost)
    lu.assertEquals(callbackHost.getIdentity().id, "AuthorHostModule")
    lu.assertEquals(callbackHost.getMeta().name, "Author Host Module")
    lu.assertTrue(callbackHost.isEnabled())
    lu.assertEquals(type(callbackHost.log), "function")
    lu.assertEquals(type(callbackHost.logIf), "function")
    lu.assertEquals(type(callbackHost.tryActivate), "function")
    lu.assertNil(callbackHost.read)
    lu.assertNil(callbackHost.setEnabled)

    local warningCount = #self.h.warnings
    callbackHost.log("plain %s", "message")
    callbackHost.logIf("debug %d", 7)
    lu.assertEquals(self.h.warnings[warningCount + 1], "[AuthorHostModule] plain message")
    lu.assertEquals(self.h.warnings[warningCount + 2], "[AuthorHostModule] debug 7")
    lu.assertEquals(#self.h.warnings, warningCount + 2)
end

function TestModuleHost:testFullHostOwnsAuthorHostCapabilities()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "FullHostCapabilities",
        name = "Full Host Capabilities",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = "test-full-host-capabilities",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getIdentity), "function")
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.log), "function")
    lu.assertEquals(type(host.logIf), "function")
    lu.assertEquals(type(host.tryActivate), "function")
    lu.assertEquals(authorHost.tryActivate, host.tryActivate)
end

function TestModuleHost:testCreateModuleHostSkipsImmediateCoordinatedSyncWhenFrameworkRebuildIsPending()
    local packId = "reload-pack"
    local rebuildReason = nil

    self.h.public.coordinator.register(packId, { ModEnabled = true })
    self.h.public.coordinator.registerRebuild(packId, function(reason)
        rebuildReason = reason
        return true
    end)
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    createActivatedHost(self.h, "reload-pack.ReloadHost", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local applyCalls = 0

    local previousState = self.h.moduleHost.getState(self.h.public.getLiveModuleHost("reload-pack.ReloadHost"))
    local prepared = self.h.moduleHost.prepareDefinition({
        _definitionStructuralFingerprint = previousState.definition._structuralFingerprint,
    }, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createActivatedHost(self.h, "reload-pack.ReloadHost", {
        definition = prepared,
        store = reloadStore,
        session = reloadSession,
        registerPatchMutation = function(plan)
            applyCalls = applyCalls + 1
            plan:set({}, "unused", true)
        end,
        drawTab = function() end,
    })
    local reloadedHost = self.h.public.getLiveModuleHost("reload-pack.ReloadHost")

    self.h.public.coordinator.register(packId, nil)
    self.h.public.coordinator.registerRebuild(packId, nil)
    lu.assertEquals(applyCalls, 0)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(self.h.public.getLiveModuleHost("reload-pack.ReloadHost"), reloadedHost)
end

function TestModuleHost:testActivationFailureRestoresLiveHostAndIntegrations()
    local pluginGuid = "test-activation-rollback"
    local integrationId = "test.activation.rollback"
    local providerId = "RollbackProvider"
    local previousApi = { value = "previous" }

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local firstStore, firstSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        drawTab = function() end,
    })
    self.h.public.integrations.register(integrationId, providerId, previousApi)

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local secondStore, secondSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        registerIntegrations = function()
            self.h.public.integrations.register(integrationId, providerId, { value = "replacement" })
            error("integration boom")
        end,
        drawTab = function() end,
    })

    local ok, err = secondAuthorHost.tryActivate()
    local api = self.h.public.integrations.get(integrationId)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "integration boom")
    lu.assertEquals(self.h.public.getLiveModuleHost(pluginGuid), firstHost)
    lu.assertEquals(api, previousApi)
    lu.assertErrorMsgContains("host.not_activated", function()
        secondHost.flush()
    end)

    self.h.public.integrations.unregisterProvider(providerId)
end

function TestModuleHost:testActivationFailureDropsNewStagedIntegrationProvider()
    local pluginGuid = "test-activation-new-integration-rollback"
    local integrationId = "test.activation.new.rollback"
    local providerId = "NewRollbackProvider"

    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationNewIntegrationRollback",
        name = "Activation New Integration Rollback",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        registerIntegrations = function()
            self.h.public.integrations.register(integrationId, providerId, { value = "candidate" })
            error("new integration boom")
        end,
        drawTab = function() end,
    })

    local ok, err = authorHost.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "new integration boom")
    lu.assertNil(self.h.public.getLiveModuleHost(pluginGuid))
    lu.assertNil(self.h.public.integrations.get(integrationId))
    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)

    self.h.public.integrations.unregisterProvider(providerId)
end

function TestModuleHost:testRuntimeSyncFailureRestoresPreviousPatchMutation()
    local packId = "activation-runtime-rollback-pack"
    local pluginGuid = "test-activation-runtime-rollback"
    local target = { Value = "base" }

    self.h.public.coordinator.register(packId, { ModEnabled = true })

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local firstStore, firstSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        registerPatchMutation = function(plan)
            plan:set(target, "Value", "first")
        end,
        drawTab = function() end,
    })

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local secondStore, secondSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        registerPatchMutation = function()
            error("replacement boom")
        end,
        drawTab = function() end,
    })

    local ok, err = secondAuthorHost.tryActivate()
    local liveHost = self.h.public.getLiveModuleHost(pluginGuid)
    local targetValue = target.Value

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "replacement boom")
    lu.assertEquals(liveHost, firstHost)
    lu.assertNotEquals(liveHost, secondHost)
    lu.assertEquals(targetValue, "first")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.activate_failed")
    lu.assertStrContains(self.h.warnings[1], "replacement boom")
end

function TestModuleHost:testTryActivateModuleReturnsErrorAndDoesNotPublishBrokenHost()
    local pluginGuid = "test-try-activate-failure"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "TryActivateFailure",
        name = "Try Activate Failure",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        registerIntegrations = function()
            error("try activate boom")
        end,
        drawTab = function() end,
    })

    local ok, err = authorHost.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "try activate boom")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.activate_failed")
    lu.assertStrContains(self.h.warnings[1], "try activate boom")
    lu.assertNil(self.h.public.getLiveModuleHost(pluginGuid))
    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)
end

function TestModuleHost:testTryActivateModuleSucceedsThroughFullHost()
    local pluginGuid = "test-try-activate-success"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "TryActivateSuccess",
        name = "Try Activate Success",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local ok, err = host.tryActivate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(self.h.public.getLiveModuleHost(pluginGuid), host)
end

function TestModuleHost:testActivationRefreshRemovesOmittedIntegrations()
    local pluginGuid = "test-activation-integration-refresh"
    local integrationId = "test.activation.refresh"
    local providerId = "ActivationRefresh"

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = providerId,
        name = "Activation Refresh",
        storage = {},
    })
    local firstStore, firstSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        drawTab = function() end,
    }, {
        registerIntegrations = function()
            self.h.public.integrations.register(integrationId, providerId, { value = "first" })
        end,
    })

    lu.assertNotNil(self.h.public.integrations.get(integrationId))

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = providerId,
        name = "Activation Refresh",
        storage = {},
    })
    local secondStore, secondSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    createActivatedHost(self.h, pluginGuid, {
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        drawTab = function() end,
    })

    lu.assertNil(self.h.public.integrations.get(integrationId))
    self.h.public.integrations.unregisterProvider(providerId)
end

function TestModuleHost:testActivationRejectsReentrantActivateCalls()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ReentrantActivate",
        name = "Reentrant Activate",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost
    host, authorHost = self.h.moduleHost.create({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        store = store,
        session = session,
        registerIntegrations = function()
            authorHost.tryActivate()
        end,
        drawTab = function() end,
    })

    local ok, err = authorHost.tryActivate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(self.h.public.getLiveModuleHost("test-reentrant-activate"), host)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.activation_in_progress")
end
