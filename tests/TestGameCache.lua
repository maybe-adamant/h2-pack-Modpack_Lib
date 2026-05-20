local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestGameCache = {}

function TestGameCache:setUp()
    self.harness = createLibHarness()
    self.gameCache = self.harness.gameCache
end

function TestGameCache:testCurrentRunCreatesNamespacedStateOnce()
    local currentRun = {}
    self.harness.env.CurrentRun = currentRun
    local calls = 0

    local first = self.gameCache.currentRun.get("owner-a", "run", function()
        calls = calls + 1
        return { Count = 1 }
    end)
    first.Count = 2

    local second = self.gameCache.currentRun.get("owner-a", "run", function()
        calls = calls + 1
        return { Count = 99 }
    end)

    lu.assertEquals(calls, 1)
    lu.assertIs(first, second)
    lu.assertEquals(second.Count, 2)
    lu.assertNotNil(currentRun._AdamantModpackLibGameCache)
end

function TestGameCache:testCurrentRunNamespacesPreventOwnerCollisions()
    self.harness.env.CurrentRun = {}

    local a = self.gameCache.currentRun.get("owner-a", "run")
    local b = self.gameCache.currentRun.get("owner-b", "run")

    a.Value = "a"
    b.Value = "b"

    lu.assertEquals(self.gameCache.currentRun.peek("owner-a", "run").Value, "a")
    lu.assertEquals(self.gameCache.currentRun.peek("owner-b", "run").Value, "b")
end

function TestGameCache:testCurrentRunPeekAndClearDoNotCreateBuckets()
    local currentRun = {}
    self.harness.env.CurrentRun = currentRun

    lu.assertNil(self.gameCache.currentRun.peek("owner", "run"))
    lu.assertNil(currentRun._AdamantModpackLibGameCache)
    lu.assertFalse(self.gameCache.currentRun.clear("owner", "run"))

    self.gameCache.currentRun.get("owner", "run")
    lu.assertNotNil(self.gameCache.currentRun.peek("owner", "run"))
    lu.assertTrue(self.gameCache.currentRun.clear("owner", "run"))
    lu.assertNil(self.gameCache.currentRun.peek("owner", "run"))
    lu.assertNil(currentRun._AdamantModpackLibGameCache)
end

function TestGameCache:testCurrentRunRejectsInvalidInputs()
    self.harness.env.CurrentRun = {}

    lu.assertErrorMsgContains("ownerId must be a non-empty string", function()
        self.gameCache.currentRun.get("", "run")
    end)
    lu.assertErrorMsgContains("key must be a non-empty string", function()
        self.gameCache.currentRun.get("owner", "")
    end)
    lu.assertErrorMsgContains("factory must be a function", function()
        self.gameCache.currentRun.get("owner", "run", true)
    end)
    lu.assertErrorMsgContains("factory must return a table", function()
        self.gameCache.currentRun.get("owner", "run", function()
            return true
        end)
    end)
end

function TestGameCache:testCurrentRunRejectsCorruptedNamespaceBuckets()
    lu.assertErrorMsgContains("root bucket is not a table", function()
        self.harness.env.CurrentRun = { _AdamantModpackLibGameCache = true }
        self.gameCache.currentRun.get("owner", "run")
    end)

    lu.assertErrorMsgContains("owner bucket is not a table", function()
        self.harness.env.CurrentRun = {
            _AdamantModpackLibGameCache = {
                owner = true,
            },
        }
        self.gameCache.currentRun.get("owner", "run")
    end)
end

function TestGameCache:testAuthorHostCurrentRunCacheBindsOwnerIdentity()
    local currentRun = {}
    self.harness.env.CurrentRun = currentRun

    local host = self.harness.public.createModule({
        pluginGuid = "test-game-cache-host",
        config = {},
        modpack = "test-pack",
        id = "CacheHost",
        name = "Cache Host",
        drawTab = function() end,
    })

    local state = host.gameCache.currentRun.get("run", function()
        return { Count = 1 }
    end)
    state.Count = 2

    lu.assertEquals(self.gameCache.currentRun.peek("test-game-cache-host", "run").Count, 2)
    lu.assertIs(host.gameCache.currentRun.peek("run"), state)
    lu.assertTrue(host.gameCache.currentRun.clear("run"))
    lu.assertNil(self.gameCache.currentRun.peek("test-game-cache-host", "run"))
end

function TestGameCache:testAuthorHostCurrentRunCacheReturnsEmptyWhenNoCurrentRun()
    self.harness.env.CurrentRun = nil

    local host = self.harness.public.createModule({
        pluginGuid = "test-game-cache-no-run",
        config = {},
        modpack = "test-pack",
        id = "NoRunCacheHost",
        name = "No Run Cache Host",
        drawTab = function() end,
    })

    lu.assertNil(host.gameCache.currentRun.get("run"))
    lu.assertNil(host.gameCache.currentRun.peek("run"))
    lu.assertFalse(host.gameCache.currentRun.clear("run"))
end

function TestGameCache:testAuthorHostCurrentRunCacheRejectsInvalidInputsWithoutCurrentRun()
    self.harness.env.CurrentRun = nil

    local host = self.harness.public.createModule({
        pluginGuid = "test-game-cache-invalid-host",
        config = {},
        id = "InvalidCacheHost",
        name = "Invalid Cache Host",
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("key must be a non-empty string", function()
        host.gameCache.currentRun.get("")
    end)
    lu.assertErrorMsgContains("factory must be a function", function()
        host.gameCache.currentRun.get("run", true)
    end)
end

function TestGameCache:testAuthorCurrentRunCacheRejectsUnmanagedHost()
    local host = self.harness.gameCacheBundle.author.create({})

    lu.assertErrorMsgContains("expected managed module host state", function()
        host.currentRun.get("run")
    end)
end
