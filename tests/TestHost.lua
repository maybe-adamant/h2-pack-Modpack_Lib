local lu = require('luaunit')

TestHost = {}

function TestHost:setUp()
    CaptureWarnings()
    self.previousImGui = rom.ImGui
    self.previousImGuiCond = rom.ImGuiCond
end

function TestHost:tearDown()
    rom.ImGui = self.previousImGui
    rom.ImGuiCond = self.previousImGuiCond
    RestoreWarnings()
end

local function createActivatedHost(pluginGuid, opts, activationOpts)
    activationOpts = activationOpts or {}
    opts.pluginGuid = pluginGuid
    opts.hookOwner = activationOpts.hookOwner
    opts.registerHooks = activationOpts.registerHooks
    opts.registerIntegrations = activationOpts.registerIntegrations
    local host, authorHost = lib.createModuleHost(opts)
    authorHost.activate()
    return host, authorHost
end

function TestHost:testStandaloneHostWarnsWhenSessionCommitFails()
    local drawCalls = 0
    local pluginGuid = "test-standalone-commit"
    local definition = lib.prepareDefinition({}, {
        modpack = "standalone-pack",
        id = "StandaloneTest",
        name = "Standalone Test",
        storage = {},
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)

    local function noop() end

    rom.ImGuiCond = { FirstUseEver = 1 }
    rom.ImGui = {
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

    createActivatedHost(pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    local moduleHost = lib.getLiveModuleHost(pluginGuid)
    moduleHost.commitIfDirty = function()
        return false, "commit boom", false
    end

    local runtime = lib.standaloneHost(pluginGuid)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Standalone Test session commit failed")
    lu.assertStrContains(Warnings[1], "commit boom")
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), moduleHost)
end

function TestHost:testStandaloneHostCanResolveCurrentModuleHostFromLibRegistry()
    local pluginGuid = "test-standalone-registry"
    local definition = lib.prepareDefinition({}, {
        id = "StandaloneRegistryHost",
        name = "Standalone Registry Host",
        storage = {},
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local _, authorHost = createActivatedHost(pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })
    local host = lib.getLiveModuleHost(pluginGuid)

    local runtime = lib.standaloneHost(pluginGuid)

    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(authorHost.isEnabled), "function")
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), host)
end

function TestHost:testHostFlushNotifiesSettingsObserver()
    local calls = 0
    local observedValue = nil
    local definition = lib.prepareDefinition({}, {
        id = "SettingsObserverHost",
        name = "Settings Observer Host",
        storage = {
            { type = "bool", alias = "Value", default = false },
        },
    })
    local store, session = lib.createStore({
        Value = false,
    }, definition)
    createActivatedHost("test-settings-observer-host", {
        definition = definition,
        store = store,
        session = session,
        onSettingsCommitted = function(activeStore)
            calls = calls + 1
            observedValue = activeStore.read("Value")
        end,
        drawTab = function() end,
    })
    local host = lib.getLiveModuleHost("test-settings-observer-host")

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestHost:testSideEffectingHostMethodsRequireActivation()
    local definition = lib.prepareDefinition({}, {
        id = "InactiveHost",
        name = "Inactive Host",
        storage = {},
    })
    local store, session = lib.createStore({}, definition)
    local host = lib.createModuleHost({
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

function TestHost:testHostAndAuthorSessionResetToDefaultsDelegateToLibHelper()
    local capturedAuthorSession = nil
    local definition = lib.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, session = lib.createStore({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedHost("test-reset-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, authorSession)
            capturedAuthorSession = authorSession
        end,
    })
    local host = lib.getLiveModuleHost("test-reset-host")

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

function TestHost:testCreateModuleHostPassesAuthorHostToCallbacks()
    local callbackHost = nil
    local drawHost = nil
    local quickHost = nil
    local definition = lib.prepareDefinition({}, {
        modpack = "author-pack",
        id = "AuthorHostModule",
        name = "Author Host Module",
        storage = {},
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local _, returnedHost = createActivatedHost("test-author-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, _, authorHost)
            drawHost = authorHost
        end,
        drawQuickContent = function(_, _, authorHost)
            quickHost = authorHost
        end,
    }, {
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
    })

    local host = lib.getLiveModuleHost("test-author-host")
    host.drawTab({})
    host.drawQuickContent({})

    lu.assertEquals(returnedHost, callbackHost)
    lu.assertEquals(callbackHost, drawHost)
    lu.assertEquals(callbackHost, quickHost)
    lu.assertEquals(callbackHost.getIdentity().id, "AuthorHostModule")
    lu.assertEquals(callbackHost.getMeta().name, "Author Host Module")
    lu.assertTrue(callbackHost.isEnabled())
    lu.assertNil(callbackHost.read)
    lu.assertNil(callbackHost.setEnabled)
end

function TestHost:testCreateModuleHostSkipsImmediateCoordinatedSyncWhenFrameworkRebuildIsPending()
    local applyCalls = 0
    local packId = "reload-pack"
    local rebuildReason = nil

    lib.lifecycle.registerCoordinator(packId, { ModEnabled = true })
    lib.lifecycle.registerCoordinatorRebuild(packId, function(reason)
        rebuildReason = reason
        return true
    end)
    local definition = lib.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    createActivatedHost("reload-pack.ReloadHost", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local originalApplyOnLoad = lib.lifecycle.applyOnLoad
    lib.lifecycle.applyOnLoad = function(...)
        applyCalls = applyCalls + 1
        return originalApplyOnLoad(...)
    end

    local owner = {
        _definitionStructuralFingerprint = definition._structuralFingerprint,
    }
    local prepared = lib.prepareDefinition(owner, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadSession = lib.createStore({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createActivatedHost("reload-pack.ReloadHost", {
        definition = prepared,
        store = reloadStore,
        session = reloadSession,
        drawTab = function() end,
    })
    local reloadedHost = lib.getLiveModuleHost("reload-pack.ReloadHost")

    lib.lifecycle.applyOnLoad = originalApplyOnLoad
    lib.lifecycle.registerCoordinator(packId, nil)
    lib.lifecycle.registerCoordinatorRebuild(packId, nil)
    lu.assertEquals(applyCalls, 0)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(lib.getLiveModuleHost("reload-pack.ReloadHost"), reloadedHost)
end

function TestHost:testActivationFailureRestoresLiveHostAndIntegrations()
    local pluginGuid = "test-activation-rollback"
    local integrationId = "test.activation.rollback"
    local providerId = "RollbackProvider"
    local previousApi = { value = "previous" }

    local firstDefinition = lib.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local firstStore, firstSession = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        drawTab = function() end,
    })
    lib.integrations.register(integrationId, providerId, previousApi)

    local secondDefinition = lib.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local secondStore, secondSession = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = lib.createModuleHost({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        registerIntegrations = function()
            lib.integrations.register(integrationId, providerId, { value = "replacement" })
            error("integration boom")
        end,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("integration boom", function()
        secondAuthorHost.activate()
    end)
    local api = lib.integrations.get(integrationId)

    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), firstHost)
    lu.assertEquals(api, previousApi)
    lu.assertErrorMsgContains("host.not_activated", function()
        secondHost.flush()
    end)

    lib.integrations.unregisterProvider(providerId)
end

function TestHost:testActivationRejectsReentrantActivateCalls()
    local definition = lib.prepareDefinition({}, {
        id = "ReentrantActivate",
        name = "Reentrant Activate",
        storage = {},
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost
    host, authorHost = lib.createModuleHost({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        store = store,
        session = session,
        registerIntegrations = function()
            authorHost.activate()
        end,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("already in progress", function()
        authorHost.activate()
    end)
    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)
end
