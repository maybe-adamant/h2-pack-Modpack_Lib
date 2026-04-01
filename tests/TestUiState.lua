local lu = require('luaunit')

TestStore = {}

function TestStore:testCreateStoreReadWriteUsesPersistedConfig()
    local config = {
        Enabled = false,
        Nested = { Mode = "Fast" },
    }

    local store = lib.createStore(config)

    lu.assertFalse(store.read("Enabled"))
    lu.assertEquals(store.read({ "Nested", "Mode" }), "Fast")

    store.write("Enabled", true)
    store.write({ "Nested", "Mode" }, "Slow")

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.Nested.Mode, "Slow")
end

function TestStore:testCreateStoreHidesConfigInternals()
    local config = { Enabled = false }
    local store = lib.createStore(config)

    lu.assertNil(store._config)
    lu.assertNil(store._backend)
end

function TestStore:testCreateStoreWithDefinitionExposesUiState()
    local config = { Strict = false }
    local definition = {
        stateSchema = {
            { type = "checkbox", configKey = "Strict", default = false },
        },
    }

    local store = lib.createStore(config, definition)

    lu.assertNotNil(store.uiState)
    lu.assertEquals(store.uiState.view.Strict, false)
    store.uiState.set("Strict", true)
    store.uiState.flushToConfig()
    lu.assertTrue(store.read("Strict"))
end

function TestStore:testCreateStoreWithRegularOptionsExposesUiState()
    local config = { Strict = false }
    local definition = {
        options = {
            { type = "checkbox", configKey = "Strict", default = false },
            { type = "separator", label = "Section" },
        },
    }

    local store = lib.createStore(config, definition)

    lu.assertNotNil(store.uiState)
    lu.assertFalse(store.uiState.view.Strict)
end

function TestStore:testCreateStoreWithNestedRegularOptionsSkipsUiState()
    local previousDebug = lib.config.DebugMode
    lib.config.DebugMode = true
    CaptureWarnings()

    local config = { Parent = { Strict = false } }
    local definition = {
        id = "NestedRegular",
        options = {
            { type = "checkbox", configKey = { "Parent", "Strict" }, default = false },
        },
    }

    local store = lib.createStore(config, definition)

    local warnings = Warnings
    RestoreWarnings()
    lib.config.DebugMode = previousDebug

    lu.assertNil(store.uiState)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "regular definition.options configKey must be a flat string")
end

function TestStore:testCreateStoreWithSpecialDefinitionMissingStateSchemaSkipsUiState()
    local previousDebug = lib.config.DebugMode
    lib.config.DebugMode = true
    CaptureWarnings()

    local config = { Enabled = false }
    local definition = {
        special = true,
        name = "Broken Special",
    }

    local store = lib.createStore(config, definition)

    local warnings = Warnings
    RestoreWarnings()
    lib.config.DebugMode = previousDebug

    lu.assertNil(store.uiState)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "special modules must declare definition.stateSchema")
end

TestUiState = {}

function TestUiState:setUp()
    CaptureWarnings()
end

function TestUiState:tearDown()
    RestoreWarnings()
end

function TestUiState:testStagingMirrorsConfig()
    local config = { Mode = "Fast", Strict = true }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
        { type = "checkbox", configKey = "Strict" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState

    lu.assertEquals(uiState.view.Mode, "Fast")
    lu.assertEquals(uiState.view.Strict, true)
end

function TestUiState:testSnapshotReReadsConfig()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    lu.assertEquals(uiState.view.Mode, "Fast")

    config.Mode = "Slow"
    uiState.reloadFromConfig()
    lu.assertEquals(uiState.view.Mode, "Slow")
end

function TestUiState:testSyncFlushesToConfig()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    uiState.set("Mode", "Slow")

    lu.assertEquals(config.Mode, "Fast") -- not yet synced
    uiState.flushToConfig()
    lu.assertEquals(config.Mode, "Slow")
end

function TestUiState:testNestedConfigKey()
    local config = { Parent = { Child = "value" } }
    local schema = {
        { type = "dropdown", configKey = {"Parent", "Child"}, values = { "value", "other" }, default = "value" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    lu.assertEquals(uiState.view.Parent.Child, "value")

    uiState.set({"Parent", "Child"}, "other")
    uiState.flushToConfig()
    lu.assertEquals(config.Parent.Child, "other")

    config.Parent.Child = "value"
    uiState.reloadFromConfig()
    lu.assertEquals(uiState.view.Parent.Child, "value")
end

function TestUiState:testReadonlyViewRejectsWrites()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    local ok = pcall(function()
        uiState.view.Mode = "Slow"
    end)

    lu.assertFalse(ok)
end

function TestUiState:testSetMarksDirtyAndSyncClearsDirty()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    lu.assertFalse(uiState.isDirty())

    uiState.set("Strict", true)
    lu.assertTrue(uiState.isDirty())
    lu.assertEquals(uiState.view.Strict, true)

    uiState.flushToConfig()
    lu.assertFalse(uiState.isDirty())
    lu.assertTrue(config.Strict)
end

function TestUiState:testUpdateUsesCurrentValue()
    local config = { Count = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Count", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    uiState.update("Count", function(current)
        if current == "Fast" then return "Slow" end
        return "Fast"
    end)

    lu.assertTrue(uiState.isDirty())
    lu.assertEquals(uiState.view.Count, "Slow")

    uiState.flushToConfig()
    lu.assertEquals(config.Count, "Slow")
end

function TestUiState:testToggleFlipsBooleanField()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    uiState.toggle("Strict")
    lu.assertEquals(uiState.view.Strict, true)
    lu.assertTrue(uiState.isDirty())

    uiState.toggle("Strict")
    lu.assertEquals(uiState.view.Strict, false)
end

function TestUiState:testReloadFromConfigClearsUnsyncedViewChanges()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    uiState.set("Mode", "Slow")
    lu.assertEquals(uiState.view.Mode, "Slow")
    lu.assertTrue(uiState.isDirty())

    uiState.reloadFromConfig()
    lu.assertEquals(uiState.view.Mode, "Fast")
    lu.assertFalse(uiState.isDirty())
end

function TestUiState:testFlushOnlyWritesDirtyKeys()
    local config = {
        FlagA = false,
        FlagB = false,
    }
    local schema = {
        { type = "checkbox", configKey = "FlagA", default = false },
        { type = "checkbox", configKey = "FlagB", default = false },
    }

    local uiState = lib.createStore(config, { stateSchema = schema }).uiState
    uiState.set("FlagA", true)

    -- Simulate an unrelated runtime update that should not be clobbered by flush.
    config.FlagB = true

    uiState.flushToConfig()

    lu.assertTrue(config.FlagA)
    lu.assertTrue(config.FlagB)
    lu.assertFalse(uiState.isDirty())
end

function TestUiState:testChalkEntryFastPathBypassesWrapperReadsAndWrites()
    local previousOriginal = rom.mods['SGG_Modding-Chalk'].original

    local values = {
        Mode = "Fast",
        Strict = false,
    }
    local rawConfig = { entries = {} }
    local function addEntry(section, key, valueKey)
        local descriptor = { section = section, key = key }
        rawConfig.entries[descriptor] = {
            get = function()
                return values[valueKey]
            end,
            set = function(_, value)
                values[valueKey] = value
            end,
        }
    end
    addEntry("config", "Mode", "Mode")
    addEntry("config", "Strict", "Strict")

    local wrapper = setmetatable({}, {
        __index = function()
            error("wrapper read should not be used", 2)
        end,
        __newindex = function()
            error("wrapper write should not be used", 2)
        end,
    })

    rom.mods['SGG_Modding-Chalk'].original = function(obj)
        if obj == wrapper then
            return rawConfig
        end
        return obj
    end

    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local uiState = lib.createStore(wrapper, { stateSchema = schema }).uiState
    local flushed = lib.runUiStatePass({
        name = "ChalkFastPath",
        uiState = uiState,
        draw = function(_, state)
            state.set("Mode", "Slow")
            state.set("Strict", true)
        end,
    })

    rom.mods['SGG_Modding-Chalk'].original = previousOriginal

    lu.assertTrue(flushed)
    lu.assertEquals(values.Mode, "Slow")
    lu.assertTrue(values.Strict)
end

function TestUiState:testCollectConfigMismatchesReturnsExactKeys()
    local config = {
        FlagA = false,
        FlagB = false,
    }
    local uiState = lib.createStore(config, {
        options = {
            { type = "checkbox", configKey = "FlagA", default = false },
            { type = "checkbox", configKey = "FlagB", default = false },
        },
    }).uiState

    config.FlagB = true

    lu.assertEquals(uiState.collectConfigMismatches(), { "FlagB" })
end

function TestUiState:testAuditAndResyncWarnsAndReloadsUiState()
    CaptureWarnings()

    local config = { Mode = "Fast" }
    local uiState = lib.createStore(config, {
        stateSchema = {
            { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
        },
    }).uiState

    uiState.set("Mode", "Slow")
    local mismatches = lib.auditAndResyncUiState("AuditTest", uiState)

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(mismatches, { "Mode" })
    lu.assertEquals(uiState.view.Mode, "Fast")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[AuditTest] UI state drift detected")
    lu.assertStrContains(warnings[1], "Mode")
end

function TestUiState:testAuditAndResyncIsSilentWhenStateMatchesConfig()
    CaptureWarnings()

    local config = { Flag = false }
    local uiState = lib.createStore(config, {
        options = {
            { type = "checkbox", configKey = "Flag", default = false },
        },
    }).uiState

    local mismatches = lib.auditAndResyncUiState("SilentAudit", uiState)

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(mismatches, {})
    lu.assertEquals(#warnings, 0)
    lu.assertFalse(uiState.isDirty())
    lu.assertFalse(uiState.view.Flag)
end
