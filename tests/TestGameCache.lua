local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestGameCache = {}

function TestGameCache:setUp()
    self.harness = createLibHarness()
    self.gameCache = self.harness.public.gameCache
end

function TestGameCache:testGetCreatesNamespacedObjectStateOnce()
    local object = {}
    local calls = 0

    local first = self.gameCache.get(object, "pack-a", "module-a", "run", function()
        calls = calls + 1
        return { Count = 1 }
    end)
    first.Count = 2

    local second = self.gameCache.get(object, "pack-a", "module-a", "run", function()
        calls = calls + 1
        return { Count = 99 }
    end)

    lu.assertEquals(calls, 1)
    lu.assertIs(first, second)
    lu.assertEquals(second.Count, 2)
    lu.assertNotNil(object._AdamantModpackLibGameCache)
end

function TestGameCache:testNamespacesPreventPackAndModuleCollisions()
    local object = {}

    local a = self.gameCache.get(object, "pack-a", "module-a", "run")
    local b = self.gameCache.get(object, "pack-a", "module-b", "run")
    local c = self.gameCache.get(object, "pack-b", "module-a", "run")

    a.Value = "a"
    b.Value = "b"
    c.Value = "c"

    lu.assertEquals(self.gameCache.peek(object, "pack-a", "module-a", "run").Value, "a")
    lu.assertEquals(self.gameCache.peek(object, "pack-a", "module-b", "run").Value, "b")
    lu.assertEquals(self.gameCache.peek(object, "pack-b", "module-a", "run").Value, "c")
end

function TestGameCache:testPeekAndClearDoNotCreateBuckets()
    local object = {}

    lu.assertNil(self.gameCache.peek(object, "pack", "module", "run"))
    lu.assertNil(object._AdamantModpackLibGameCache)
    lu.assertFalse(self.gameCache.clear(object, "pack", "module", "run"))

    self.gameCache.get(object, "pack", "module", "run")
    lu.assertNotNil(self.gameCache.peek(object, "pack", "module", "run"))
    lu.assertTrue(self.gameCache.clear(object, "pack", "module", "run"))
    lu.assertNil(self.gameCache.peek(object, "pack", "module", "run"))
    lu.assertNil(object._AdamantModpackLibGameCache)
end

function TestGameCache:testGetRejectsInvalidInputs()
    lu.assertErrorMsgContains("object must be a table", function()
        self.gameCache.get(nil, "pack", "module", "run")
    end)
    lu.assertErrorMsgContains("packId must be a non-empty string", function()
        self.gameCache.get({}, "", "module", "run")
    end)
    lu.assertErrorMsgContains("factory must return a table", function()
        self.gameCache.get({}, "pack", "module", "run", function()
            return true
        end)
    end)
end

function TestGameCache:testGetRejectsCorruptedNamespaceBuckets()
    lu.assertErrorMsgContains("root bucket is not a table", function()
        self.gameCache.get({ _AdamantModpackLibGameCache = true }, "pack", "module", "run")
    end)

    lu.assertErrorMsgContains("pack bucket is not a table", function()
        self.gameCache.get({
            _AdamantModpackLibGameCache = {
                pack = true,
            },
        }, "pack", "module", "run")
    end)

    lu.assertErrorMsgContains("module bucket is not a table", function()
        self.gameCache.get({
            _AdamantModpackLibGameCache = {
                pack = {
                    module = true,
                },
            },
        }, "pack", "module", "run")
    end)
end
