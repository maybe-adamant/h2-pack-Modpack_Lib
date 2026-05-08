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
            },
        },
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
        drawTab = function(_, authorSession, authorHost)
            drawHost = authorHost
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
    lu.assertEquals(type(owner._definitionStructuralFingerprint), "string")
end
