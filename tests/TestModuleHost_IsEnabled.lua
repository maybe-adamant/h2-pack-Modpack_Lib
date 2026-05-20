local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_IsEnabled = {}

function TestModuleHost_IsEnabled:setUp()
    self.h = createModuleHostHarness()
end

function TestModuleHost_IsEnabled:makeStore(enabled)
    local definition = self.h:prepareDefinition({}, {
        id = "IsEnabledStore",
        name = "Is Enabled Store",
        storage = {},
    })
    local store = self.h:createModuleState({ Enabled = enabled }, definition)
    return store
end

function TestModuleHost_IsEnabled:testEnabledUncoordinated()
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true), "test-pack"))
end

function TestModuleHost_IsEnabled:testDisabledUncoordinated()
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false), "test-pack"))
end

function TestModuleHost_IsEnabled:testEnabledNoPackId()
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true)))
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false)))
end

function TestModuleHost_IsEnabled:testEnabledWithCoordEnabled()
    self.h.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true), "test-pack"))
end

function TestModuleHost_IsEnabled:testDisabledWithCoordEnabled()
    self.h.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false), "test-pack"))
end

function TestModuleHost_IsEnabled:testEnabledWithCoordDisabled()
    self.h.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(true), "test-pack"))
end

function TestModuleHost_IsEnabled:testDisabledWithCoordDisabled()
    self.h.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false), "test-pack"))
end
