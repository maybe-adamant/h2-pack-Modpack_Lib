local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_CreateModule = {}

function TestModuleHost_CreateModule:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
end

function TestModuleHost_CreateModule:tearDown()
    self.h:restoreWarnings()
end

function TestModuleHost_CreateModule:testCreateModuleRunsCanonicalPipeline()
    local callbackHost = nil
    local drawHost = nil
    local drawImgui = nil
    local drawWidgets = nil
    local authorSchemaNode = nil
    local authorRowValue = nil
    local authorRootField = nil
    local authorRowField = nil
    local config = {}

    local host, store = self.h.public.createModule({
        pluginGuid = "test-create-module",
        config = config,
        modpack = "create-module-pack",
        id = "CreateModule",
        name = "Create Module",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
        drawTab = function(ctx)
            drawImgui = ctx.imgui
            drawHost = ctx.host
            drawWidgets = ctx.widgets
            authorSchemaNode = ctx.session.getAliasSchema("Flag")
            authorRootField = ctx.field("Flag")
            local row = ctx.session.table("Rows"):rowHandle(1)
            authorRowField = row:field("Limit")
            authorRowValue = row.read("Limit")
            ctx.session.write("Flag", true)
        end,
    })

    lu.assertNil(self.h:liveHost("test-create-module"))
    host.tryActivate()
    local liveHost = self.h:liveHost("test-create-module")
    liveHost.drawTab({})

    lu.assertEquals(host, callbackHost)
    lu.assertEquals(host, drawHost)
    lu.assertNotNil(drawImgui)
    lu.assertEquals(type(drawWidgets.checkbox), "function")
    lu.assertNil(drawWidgets.forSession)
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(store.read("Flag"), false)
    liveHost.flush()
    lu.assertEquals(store.read("Flag"), true)
    lu.assertNotNil(authorSchemaNode)
    lu.assertEquals(authorSchemaNode.alias, "Flag")
    lu.assertEquals(authorSchemaNode.type, "bool")
    lu.assertEquals(authorRowValue, 2)
    lu.assertEquals(authorRootField:alias(), "Flag")
    lu.assertEquals(authorRootField:schema().alias, "Flag")
    lu.assertEquals(authorRowField:alias(), "Limit")
    lu.assertEquals(authorRowField:read(), 2)
    local liveState = self.h.moduleHost.getState(liveHost)
    lu.assertEquals(type(liveState.definition._structuralFingerprint), "string")
end

function TestModuleHost_CreateModule:testCreateModulePassesRuntimeHandlesToHookRefresh()
    local hookSawStore = false
    local hookSawHost = false

    local host, store = self.h.public.createModule({
        pluginGuid = "test-create-module-publish-store",
        config = {},
        modpack = "create-module-pack",
        id = "PublishStore",
        name = "Publish Store",
        storage = {
            { type = "bool", alias = "Flag", default = true },
        },
        registerHooks = function(authorHost, activeStore)
            hookSawStore = activeStore and activeStore.read("Flag") == true
            hookSawHost = authorHost ~= nil
        end,
        drawTab = function() end,
    })

    lu.assertFalse(hookSawStore)
    host.tryActivate()
    lu.assertTrue(hookSawStore)
    lu.assertTrue(hookSawHost)
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(store.read("Flag"), true)
end

function TestModuleHost_CreateModule:testCreateModuleReturnsOnlyAuthorHostSurface()
    local host = self.h.public.createModule({
        pluginGuid = "test-create-module-author-surface",
        config = {},
        modpack = "create-module-pack",
        id = "AuthorSurface",
        name = "Author Surface",
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getIdentity), "function")
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.log), "function")
    lu.assertEquals(type(host.logIf), "function")
    lu.assertEquals(type(host.tryActivate), "function")
    lu.assertNil(host.read)
    lu.assertNil(host.writeAndFlush)
    lu.assertNil(host.commitIfDirty)
    lu.assertNil(host.applyMutation)
    lu.assertNil(host.setEnabled)
end

function TestModuleHost_CreateModule:testTryCreateModuleReturnsErrorAndLogsWarning()
    local host, store, err = self.h.public.tryCreateModule({
        pluginGuid = "test-try-create-module-invalid",
        config = {},
        id = "TryCreateInvalid",
        drawTab = function() end,
    })

    lu.assertNil(host)
    lu.assertNil(store)
    lu.assertStrContains(err, "definition.missing_name")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.create_failed")
    lu.assertStrContains(self.h.warnings[1], "definition.missing_name")
    lu.assertNil(self.h:liveHost("test-try-create-module-invalid"))
end

function TestModuleHost_CreateModule:testCreateModuleActivationIsSingleUse()
    local host = self.h.public.createModule({
        pluginGuid = "test-create-module-single-activate",
        config = {},
        modpack = "create-module-pack",
        id = "SingleActivate",
        name = "Single Activate",
        drawTab = function() end,
    })

    host.tryActivate()
    local ok, err = host.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "already activated")
end

function TestModuleHost_CreateModule:testCreateModuleRejectsOwnerOption()
    lu.assertErrorMsgContains("unknown option 'owner'", function()
        self.h.public.createModule({
            owner = {},
            pluginGuid = "test-create-module-hooks-no-owner",
            config = {},
            id = "HooksNoOwner",
            name = "Hooks No Owner",
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleRejectsLegacyDefinitionOption()
    lu.assertErrorMsgContains("definition table is no longer supported", function()
        self.h.public.createModule({
            pluginGuid = "test-create-module-legacy-definition",
            config = {},
            definition = {
                id = "LegacyDefinition",
                name = "Legacy Definition",
            },
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsManualMutationAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerManualMutation'", function()
        self.h.public.createModule({
            pluginGuid = "test-create-module-manual-mutation-unknown",
            config = {},
            id = "ManualMutationUnknown",
            name = "Manual Mutation Unknown",
            registerManualMutation = {
                apply = function() end,
                revert = function() end,
            },
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleFingerprintTracksQuickContentPresenceOnly()
    local stableHost = self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-stable",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentStable",
        name = "Quick Content Stable",
        drawTab = function() end,
        drawQuickContent = function() end,
    })
    stableHost.tryActivate()

    self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-stable",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentStable",
        name = "Quick Content Stable",
        drawTab = function() end,
        drawQuickContent = function() end,
    })

    lu.assertEquals(#self.h.warnings, 0)

    local addedHost = self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-added",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentAdded",
        name = "Quick Content Added",
        drawTab = function() end,
    })
    addedHost.tryActivate()

    self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-added",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentAdded",
        name = "Quick Content Added",
        drawTab = function() end,
        drawQuickContent = function() end,
    })

    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end
