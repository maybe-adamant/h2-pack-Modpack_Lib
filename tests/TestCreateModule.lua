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
    lu.assertEquals(owner.store, store)
    lu.assertEquals(owner.host, host)
    lu.assertEquals(type(owner._definitionStructuralFingerprint), "string")
end

function TestCreateModule:testCreateModulePublishesStoreBeforeHookRefresh()
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
        registerHooks = function()
            hookSawStore = owner.store and owner.store.read("Flag") == true
            hookSawHost = owner.host ~= nil
        end,
        drawTab = function() end,
    })

    lu.assertEquals(owner.store, store)
    lu.assertEquals(owner.host, host)
    lu.assertTrue(hookSawStore)
    lu.assertFalse(hookSawHost)
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
    lu.assertNil(host.read)
    lu.assertNil(host.writeAndFlush)
    lu.assertNil(host.commitIfDirty)
    lu.assertNil(host.applyMutation)
    lu.assertNil(host.setEnabled)
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
