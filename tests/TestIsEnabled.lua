local lu = require('luaunit')

-- =============================================================================
-- isEnabled
-- =============================================================================

TestIsEnabled = {}

local function makeStore(enabled)
    return lib.createStore({ Enabled = enabled })
end

-- Reset the "test-pack" coordinator slot before each test.
function TestIsEnabled:setUp()
    lib.registerCoordinator("test-pack", nil)
end

-- no coordinator registered
function TestIsEnabled:testEnabledStandalone()
    lu.assertTrue(lib.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledStandalone()
    lu.assertFalse(lib.isEnabled(makeStore(false), "test-pack"))
end

function TestIsEnabled:testEnabledNoPackId()
    lu.assertTrue(lib.isEnabled(makeStore(true)))
    lu.assertFalse(lib.isEnabled(makeStore(false)))
end

-- coordinator registered with ModEnabled = true
function TestIsEnabled:testEnabledWithCoordEnabled()
    lib.registerCoordinator("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordEnabled()
    lib.registerCoordinator("test-pack", { ModEnabled = true })
    lu.assertFalse(lib.isEnabled(makeStore(false), "test-pack"))
end

-- coordinator registered with ModEnabled = false (pack-level off overrides module)
function TestIsEnabled:testEnabledWithCoordDisabled()
    lib.registerCoordinator("test-pack", { ModEnabled = false })
    lu.assertFalse(lib.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordDisabled()
    lib.registerCoordinator("test-pack", { ModEnabled = false })
    lu.assertFalse(lib.isEnabled(makeStore(false), "test-pack"))
end

-- =============================================================================
-- isCoordinated
-- =============================================================================

TestIsCoordinated = {}

function TestIsCoordinated:setUp()
    lib.registerCoordinator("test-pack", nil)
    lib.registerCoordinator("other-pack", nil)
end

function TestIsCoordinated:testNotCoordinatedByDefault()
    lu.assertFalse(lib.isCoordinated("test-pack"))
end

function TestIsCoordinated:testCoordinatedAfterRegister()
    lib.registerCoordinator("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.isCoordinated("test-pack"))
end

function TestIsCoordinated:testUnrelatedPackNotCoordinated()
    lib.registerCoordinator("other-pack", { ModEnabled = true })
    lu.assertFalse(lib.isCoordinated("test-pack"))
end

function TestIsCoordinated:testClearedByNilRegister()
    lib.registerCoordinator("test-pack", { ModEnabled = true })
    lib.registerCoordinator("test-pack", nil)
    lu.assertFalse(lib.isCoordinated("test-pack"))
end

-- =============================================================================
-- registerCoordinator — multiple packs coexist
-- =============================================================================

TestRegisterCoordinator = {}

function TestRegisterCoordinator:setUp()
    lib.registerCoordinator("pack-a", nil)
    lib.registerCoordinator("pack-b", nil)
end

function TestRegisterCoordinator:testMultiplePacksIndependent()
    lib.registerCoordinator("pack-a", { ModEnabled = true })
    lib.registerCoordinator("pack-b", { ModEnabled = false })
    lu.assertTrue(lib.isCoordinated("pack-a"))
    lu.assertTrue(lib.isCoordinated("pack-b"))
    lu.assertTrue(lib.isEnabled(makeStore(true), "pack-a"))
    lu.assertFalse(lib.isEnabled(makeStore(true), "pack-b"))
end
