local lu = require('luaunit')

TestCreateModule = {}

function TestCreateModule:setUp()
    CaptureWarnings()
end

function TestCreateModule:tearDown()
    RestoreWarnings()
end

function TestCreateModule:testCreateModuleRunsCanonicalPipeline()
    local owner = {}
    local callbackHost = nil
    local drawHost = nil
    local authorSchemaNode = nil
    local authorRowValue = nil
    local config = {}

    local host, store = lib.createModule({
        owner = owner,
        pluginGuid = "test-create-module",
        config = config,
        definition = {
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
        },
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
        drawTab = function(_, authorSession, authorHost)
            drawHost = authorHost
            authorSchemaNode = authorSession.getAliasSchema("Flag")
            local row = authorSession.table("Rows"):rowHandle(1)
            authorRowValue = row.read("Limit")
            authorSession.write("Flag", true)
        end,
    })

    lu.assertNil(lib.getLiveModuleHost("test-create-module"))
    host.activate()
    local liveHost = lib.getLiveModuleHost("test-create-module")
    liveHost.drawTab({})

    lu.assertEquals(host, callbackHost)
    lu.assertEquals(host, drawHost)
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(store.read("Flag"), false)
    liveHost.flush()
    lu.assertEquals(store.read("Flag"), true)
    lu.assertNotNil(authorSchemaNode)
    lu.assertEquals(authorSchemaNode.alias, "Flag")
    lu.assertEquals(authorSchemaNode.type, "bool")
    lu.assertEquals(authorRowValue, 2)
    lu.assertNil(owner.store)
    lu.assertNil(owner.host)
    lu.assertEquals(type(owner._definitionStructuralFingerprint), "string")
end

function TestCreateModule:testCreateModulePassesRuntimeHandlesToHookRefresh()
    local owner = {}
    local hookSawStore = false
    local hookSawHost = false

    local host, store = lib.createModule({
        owner = owner,
        pluginGuid = "test-create-module-publish-store",
        config = {},
        definition = {
            modpack = "create-module-pack",
            id = "PublishStore",
            name = "Publish Store",
            storage = {
                { type = "bool", alias = "Flag", default = true },
            },
        },
        registerHooks = function(activeStore, authorHost)
            hookSawStore = activeStore and activeStore.read("Flag") == true
            hookSawHost = authorHost ~= nil
        end,
        drawTab = function() end,
    })

    lu.assertNil(owner.store)
    lu.assertNil(owner.host)
    lu.assertFalse(hookSawStore)
    host.activate()
    lu.assertTrue(hookSawStore)
    lu.assertTrue(hookSawHost)
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(store.read("Flag"), true)
end

function TestCreateModule:testCreateModuleReturnsOnlyAuthorHostSurface()
    local host = lib.createModule({
        owner = {},
        pluginGuid = "test-create-module-author-surface",
        config = {},
        definition = {
            modpack = "create-module-pack",
            id = "AuthorSurface",
            name = "Author Surface",
        },
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getIdentity), "function")
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.activate), "function")
    lu.assertNil(host.read)
    lu.assertNil(host.writeAndFlush)
    lu.assertNil(host.commitIfDirty)
    lu.assertNil(host.applyMutation)
    lu.assertNil(host.setEnabled)
end

function TestCreateModule:testCreateModuleActivationIsSingleUse()
    local host = lib.createModule({
        owner = {},
        pluginGuid = "test-create-module-single-activate",
        config = {},
        definition = {
            modpack = "create-module-pack",
            id = "SingleActivate",
            name = "Single Activate",
        },
        drawTab = function() end,
    })

    host.activate()
    lu.assertErrorMsgContains("already activated", function()
        host.activate()
    end)
end

function TestCreateModule:testCreateModuleRequiresOwner()
    lu.assertErrorMsgContains("owner is required", function()
        lib.createModule({
            pluginGuid = "test-create-module-hooks-no-owner",
            config = {},
            definition = {
                id = "HooksNoOwner",
                name = "Hooks No Owner",
            },
            drawTab = function() end,
        })
    end)
end
