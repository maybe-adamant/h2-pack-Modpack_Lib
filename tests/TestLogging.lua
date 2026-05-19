local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')
local DefaultViolationPolicy = dofile('src/core/logging/policies.lua')

TestLogging = {}

local ActiveLines = nil

local function CaptureHarnessPrint(harness)
    local previousPrint = harness.env.print
    if ActiveLines ~= nil then
        harness.env.print = function(msg)
            ActiveLines[#ActiveLines + 1] = msg
        end
    end
    return function()
        harness.env.print = previousPrint
    end
end

local function WithLoggingPolicy(policy, callback)
    local harness = createLibHarness({
        importOverrides = {
            ["core/logging/policies.lua"] = policy,
        },
    })
    local restorePrint = CaptureHarnessPrint(harness)
    local ok, err = pcall(callback, harness.logging, harness)
    restorePrint()
    if not ok then
        error(err, 0)
    end
end

function TestLogging:setUp()
    self.harness = createLibHarness()
    self.lines = {}
    ActiveLines = self.lines
    self.restorePrint = CaptureHarnessPrint(self.harness)
end

function TestLogging:tearDown()
    self.restorePrint()
    self.restorePrint = nil
    ActiveLines = nil
    self.harness = nil
end

function TestLogging:testViolationWarnUsesPolicyId()
    WithLoggingPolicy({
        ["test.warn"] = {
            severity = "warn",
            description = "Test warning policy.",
        },
    }, function(activeLogging)
        local severity, message = activeLogging.violate("test.warn", "hello %s", "world")

        lu.assertEquals(severity, "warn")
        lu.assertEquals(message, "[lib] test.warn: hello world")
        lu.assertEquals(self.lines, { "[lib] test.warn: hello world" })
    end)
end

function TestLogging.testViolationPolicyCarriesDescriptions()
    local policy = DefaultViolationPolicy["storage.hash_requires_persist"]

    lu.assertEquals(policy.severity, "error")
    lu.assertStrContains(policy.description, "persisted")
end

function TestLogging.testViolationPolicyMatchesSourceCallSites()
    local files = {
        "src/core/module_bootstrap/definition.lua",
        "src/core/game_cache/game_cache.lua",
        "src/core/hooks/hooks.lua",
        "src/core/hooks/private_dispatchers.lua",
        "src/core/hooks/private_registry.lua",
        "src/core/module_bootstrap/host.lua",
        "src/core/module_bootstrap/private_host_lifecycle.lua",
        "src/core/integrations/integrations.lua",
        "src/core/integrations/private_registry.lua",
        "src/core/coordinator/coordinator.lua",
        "src/core/module_bootstrap/module.lua",
        "src/core/overlays/overlays.lua",
        "src/core/overlays/private_renderer.lua",
        "src/core/overlays/private_retained_dispatch.lua",
        "src/core/overlays/private_retained.lua",
        "src/core/overlays/private_state.lua",
        "src/core/mutations/mutations.lua",
        "src/core/standalone_host/standalone_host.lua",
        "src/core/module_state/module_state.lua",
        "src/core/logging/logging.lua",
        "src/core/helpers/values.lua",
        "src/core/module_state/private_session.lua",
        "src/core/storage/storage.lua",
        "src/core/storage/storage_field.lua",
        "src/core/storage/private_packed.lua",
        "src/core/storage/private_table.lua",
        "src/core/storage/private_types.lua",
        "src/core/module_state/private_store.lua",
        "src/core/widgets/init.lua",
        "src/core/widgets/widget_helpers.lua",
    }

    for _, path in ipairs(files) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "[%w_]+%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            lu.assertNotNil(DefaultViolationPolicy[id], id)
        end
    end
end

function TestLogging.testViolationPolicyHasNoOrphanIds()
    local files = {
        "src/core/module_bootstrap/definition.lua",
        "src/core/game_cache/game_cache.lua",
        "src/core/hooks/hooks.lua",
        "src/core/hooks/private_dispatchers.lua",
        "src/core/hooks/private_registry.lua",
        "src/core/module_bootstrap/host.lua",
        "src/core/module_bootstrap/private_host_lifecycle.lua",
        "src/core/integrations/integrations.lua",
        "src/core/integrations/private_registry.lua",
        "src/core/coordinator/coordinator.lua",
        "src/core/module_bootstrap/module.lua",
        "src/core/overlays/overlays.lua",
        "src/core/overlays/private_renderer.lua",
        "src/core/overlays/private_retained_dispatch.lua",
        "src/core/overlays/private_retained.lua",
        "src/core/overlays/private_state.lua",
        "src/core/mutations/mutations.lua",
        "src/core/standalone_host/standalone_host.lua",
        "src/core/module_state/module_state.lua",
        "src/core/logging/logging.lua",
        "src/core/helpers/values.lua",
        "src/core/module_state/private_session.lua",
        "src/core/storage/storage.lua",
        "src/core/storage/storage_field.lua",
        "src/core/storage/private_packed.lua",
        "src/core/storage/private_table.lua",
        "src/core/storage/private_types.lua",
        "src/core/module_state/private_store.lua",
        "src/core/widgets/init.lua",
        "src/core/widgets/widget_helpers.lua",
    }
    local referenced = {}

    for _, path in ipairs(files) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "[%w_]+%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            referenced[id] = true
        end
    end

    for id in pairs(DefaultViolationPolicy) do
        lu.assertTrue(referenced[id], id)
    end
end

function TestLogging:testViolationDebugHonorsLibDebugMode()
    WithLoggingPolicy({
        ["test.debug"] = {
            severity = "debug",
            description = "Test debug policy.",
        },
    }, function(activeLogging, harness)
        activeLogging.violate("test.debug", "hidden")
        harness.config.DebugMode = true
        activeLogging.violate("test.debug", "visible")
    end)

    lu.assertEquals(self.lines, { "[lib] test.debug: visible" })
end

function TestLogging:testViolationIgnoreReturnsWithoutPrinting()
    WithLoggingPolicy({
        ["test.ignore"] = {
            severity = "ignore",
            description = "Test ignored policy.",
        },
    }, function(activeLogging)
        local severity, message = activeLogging.violate("test.ignore", "ignored")

        lu.assertEquals(severity, "ignore")
        lu.assertEquals(message, "[lib] test.ignore: ignored")
        lu.assertEquals(self.lines, {})
    end)
end

function TestLogging.testViolationErrorRaises()
    WithLoggingPolicy({
        ["test.error"] = {
            severity = "error",
            description = "Test error policy.",
        },
    }, function(activeLogging)
        lu.assertErrorMsgContains("[lib] test.error: broken", function()
            activeLogging.violate("test.error", "broken")
        end)
    end)
end

function TestLogging.testViolationRejectsInvalidSeverity()
    WithLoggingPolicy({
        ["test.invalid"] = {
            severity = "trace",
            description = "Test invalid policy.",
        },
    }, function(activeLogging)
        lu.assertErrorMsgContains("violation.invalid_severity", function()
            activeLogging.violate("test.invalid", "broken")
        end)
    end)
end

function TestLogging:testViolationRejectsUnknownId()
    lu.assertErrorMsgContains("violation.unknown_id", function()
        self.harness.logging.violate("test.missing", "broken")
    end)
end
