local lu = require("luaunit")

TestRetainedOverlays = {}

function TestRetainedOverlays:setUp()
    self.previousScreenData = ScreenData
    self.previousHudScreen = HUDScreen
    self.previousModifyTextBox = ModifyTextBox
    self.previousSetAlpha = SetAlpha
    self.previousCreateComponentFromData = CreateComponentFromData
    self.previousDestroy = Destroy
    self.previousShowingCombatUI = ShowingCombatUI
    self.retainedState = AdamantModpackLib_OverlayState.retained
    self.rendererState = AdamantModpackLib_OverlayState.renderer
    self.previousRetainedTableRegistries = self.retainedState.tableRegistries
    self.previousRetainedExplicitRegistries = self.retainedState.explicitRegistries
    self.previousRetainedNextOwnerId = self.retainedState.nextOwnerId
    self.previousRetainedIntervalDriverRegistered = self.retainedState.intervalDriverRegistered
    self.previousRendererTextElements = self.rendererState.textElements
    self.previousRendererStackRows = self.rendererState.stackRows
    self.previousModUtil = modutil
    self.previousRomModUtil = rom.mods["SGG_Modding-ModUtil"]
    self.previousHooks = AdamantModpackLib_Internal.__adamantHooks

    AdamantModpackLib_Internal.__adamantHooks = nil
    self.rendererState.textElements = {}
    self.rendererState.stackRows = {}
    self.retainedState.tableRegistries = setmetatable({}, { __mode = "k" })
    self.retainedState.explicitRegistries = {}
    self.retainedState.nextOwnerId = 0
    self.retainedState.intervalDriverRegistered = true

    ShowingCombatUI = true
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    local nextId = 100
    CreateComponentFromData = function(_, data)
        nextId = nextId + 1
        return {
            Id = nextId,
            Name = data.Name,
        }
    end
    ModifyTextBox = function() end
    SetAlpha = function() end
    Destroy = function() end
end

function TestRetainedOverlays:tearDown()
    ScreenData = self.previousScreenData
    HUDScreen = self.previousHudScreen
    ModifyTextBox = self.previousModifyTextBox
    SetAlpha = self.previousSetAlpha
    CreateComponentFromData = self.previousCreateComponentFromData
    Destroy = self.previousDestroy
    ShowingCombatUI = self.previousShowingCombatUI
    self.retainedState.tableRegistries = self.previousRetainedTableRegistries
    self.retainedState.explicitRegistries = self.previousRetainedExplicitRegistries
    self.retainedState.nextOwnerId = self.previousRetainedNextOwnerId
    self.retainedState.intervalDriverRegistered = self.previousRetainedIntervalDriverRegistered
    self.rendererState.textElements = self.previousRendererTextElements
    self.rendererState.stackRows = self.previousRendererStackRows
    AdamantModpackLib_Internal.__adamantHooks = self.previousHooks
    modutil = self.previousModUtil
    rom.mods["SGG_Modding-ModUtil"] = self.previousRomModUtil
end

local function createHostWithOverlays(pluginGuid, registerOverlays, opts)
    opts = opts or {}
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = opts.id or "RetainedOverlayHost",
        name = opts.name or "Retained Overlay Host",
        storage = opts.storage or {},
    })
    local store, session = CreateModuleState(opts.config or {
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        registerOverlays = registerOverlays,
        onSettingsCommitted = opts.onSettingsCommitted,
        registerIntegrations = opts.registerIntegrations,
        drawTab = function() end,
    })
    return host, authorHost, store, session
end

function TestRetainedOverlays:testDefineSystemLineProjectsThroughCommitContext()
    local modified = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end

    lib.overlays.defineSystem("test.retained.line", function(overlays)
        overlays.createLine("summary.igt", {
            region = "middleRightStack",
            columns = {
                { key = "label", minWidth = 40 },
                { key = "time", minWidth = 80 },
            },
        })
        overlays.onCommit(function(ctx)
            ctx.setLine("summary.igt", { label = "IGT:", time = "01:23.45" })
            ctx.refresh("summary.igt")
        end)
    end)

    AdamantModpackLib_Internal.overlays.dispatchCommit("test.retained.line", {})

    lu.assertEquals(modified[#modified - 1].Text, "IGT:")
    lu.assertEquals(modified[#modified].Text, "01:23.45")
end

function TestRetainedOverlays:testDefineSystemRemovesOmittedDeclarations()
    local destroyed = {}
    Destroy = function(args)
        destroyed[#destroyed + 1] = args.Id
    end

    lib.overlays.defineSystem("test.retained.omit", function(overlays)
        overlays.createLine("transient", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)
    lu.assertNotNil(next(AdamantModpackLib_OverlayState.renderer.textElements))

    lib.overlays.defineSystem("test.retained.omit", function() end)

    lu.assertNil(next(AdamantModpackLib_OverlayState.renderer.stackRows))
    lu.assertNil(next(AdamantModpackLib_OverlayState.renderer.textElements))
    lu.assertTrue(#destroyed > 0)
end

function TestRetainedOverlays:testRetainedTableCapsRowsAndHidesUnusedRows()
    local modified = {}
    local alphas = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    local host, authorHost = createHostWithOverlays("test.retained.table", function(overlays)
        overlays.createTable("runs", {
            region = "middleRightStack",
            maxRows = 2,
            columns = {
                { key = "label", minWidth = 40 },
                { key = "time", minWidth = 80 },
            },
        })
        overlays.onCommit(function(ctx)
            ctx.setTable("runs", {
                { key = "one", label = "Run 1", time = "00:01.00" },
                { key = "two", label = "Run 2", time = "00:02.00" },
                { key = "three", label = "Run 3", time = "00:03.00" },
            })
            ctx.refresh("runs")
        end)
    end)
    authorHost.tryActivate()
    AdamantModpackLib_Internal.overlays.dispatchCommit(host, {})

    local text = {}
    for _, call in ipairs(modified) do
        text[call.Text] = true
    end
    lu.assertTrue(text["Run 1"])
    lu.assertTrue(text["00:01.00"])
    lu.assertTrue(text["Run 2"])
    lu.assertTrue(text["00:02.00"])
    lu.assertNil(text["Run 3"])
    lu.assertNil(text["00:03.00"])
    lu.assertTrue(#alphas > 0)
end

function TestRetainedOverlays:testRetainedTableRequiresPositiveMaxRows()
    local _, authorHost = createHostWithOverlays("test.retained.table.invalid", function(overlays)
        overlays.createTable("runs", {
            region = "middleRightStack",
            columns = {
                { key = "label", minWidth = 40 },
            },
        })
    end)
    local ok, err = authorHost.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "maxRows must be a positive integer")
end

function TestRetainedOverlays:testProjectionContextDoesNotExposeOwner()
    local exposedOwner = nil
    lib.overlays.defineSystem("test.retained.no-owner", function(overlays)
        overlays.createLine("line", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
        overlays.onCommit(function(ctx)
            exposedOwner = ctx.owner
        end)
    end)

    AdamantModpackLib_Internal.overlays.dispatchCommit("test.retained.no-owner", {})

    lu.assertNil(exposedOwner)
end

function TestRetainedOverlays:testHostCommitDispatchesOverlaysAfterSettingsObserver()
    local pluginGuid = "test-retained-overlay-commit"
    local order = {}
    local host, authorHost, _, session = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.onCommit(function()
            order[#order + 1] = "overlay"
        end)
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = false,
        },
        onSettingsCommitted = function()
            order[#order + 1] = "settings"
        end,
    })
    authorHost.tryActivate()

    session.write("Flag", true)
    local ok, err = host.flush()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(order, { "settings", "overlay" })
end

function TestRetainedOverlays:testHostCommitDispatchesOverlaysWhenSettingsObserverFails()
    CaptureWarnings()
    local pluginGuid = "test-retained-overlay-commit-observer-failure"
    local order = {}
    local host, authorHost, _, session = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.onCommit(function()
            order[#order + 1] = "overlay"
        end)
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = false,
        },
        onSettingsCommitted = function()
            order[#order + 1] = "settings"
            error("settings observer boom")
        end,
    })
    authorHost.tryActivate()

    session.write("Flag", true)
    local ok, err = host.flush()
    local warnings = Warnings
    RestoreWarnings()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertEquals(order, { "settings", "overlay" })
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "lifecycle.on_settings_committed_failed")
    lu.assertStrContains(warnings[1], "settings observer boom")
end

function TestRetainedOverlays:testHostInstallStagesOverlayRowsHiddenUntilCommit()
    local pluginGuid = "test-retained-overlay-staging"
    local host, authorHost, store = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("candidate", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)
    local pendingRowKey = "middleRightStack\0" .. pluginGuid .. ":pending:candidate"
    local currentRowKey = "middleRightStack\0" .. pluginGuid .. ":current:candidate"

    local receipt = AdamantModpackLib_Internal.overlays.installForHost(host, function(overlays)
        overlays.createLine("candidate", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, authorHost, store)

    lu.assertNil(self.rendererState.stackRows[currentRowKey])
    lu.assertNotNil(self.rendererState.stackRows[pendingRowKey])
    local stagedRows = 0
    for _, row in pairs(self.rendererState.stackRows) do
        stagedRows = stagedRows + 1
        lu.assertFalse(row.visible())
    end
    lu.assertTrue(stagedRows > 0)

    local ok, err = receipt.commit()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(self.rendererState.stackRows[pendingRowKey])
    lu.assertNotNil(self.rendererState.stackRows[currentRowKey])
    lu.assertTrue(self.rendererState.stackRows[currentRowKey].visible())

    ok, err = receipt.dispose()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(self.rendererState.stackRows[currentRowKey])
end

function TestRetainedOverlays:testHotReloadSameOverlayNameSurvivesOldHostRetirement()
    local pluginGuid = "test-retained-overlay-same-name-reload"
    local rowKey = "middleRightStack\0" .. pluginGuid .. ":current:shared"
    local firstHost, firstAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("shared", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedSameNameReload",
    })
    firstAuthorHost.tryActivate()

    local firstRow = self.rendererState.stackRows[rowKey]
    lu.assertNotNil(firstRow)

    local secondHost, secondAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("shared", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedSameNameReload",
    })
    secondAuthorHost.tryActivate()

    local secondRow = self.rendererState.stackRows[rowKey]
    local firstRegistry = AdamantModpackLib_OverlayState.retained.tableRegistries[firstHost]
    local secondRegistry = AdamantModpackLib_OverlayState.retained.tableRegistries[secondHost]

    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), secondHost)
    lu.assertNotNil(secondRow)
    lu.assertNotEquals(firstRow, secondRow)
    lu.assertTrue(firstRegistry == nil or firstRegistry.elements.shared == nil)
    lu.assertNotNil(secondRegistry.elements.shared)
end

function TestRetainedOverlays:testRetainedIntervalDispatchesWhenDue()
    local calls = 0
    createHostWithOverlays("test.retained.interval", function(overlays)
        overlays.onInterval("tick", 1.0, function()
            calls = calls + 1
        end)
    end):tryActivate()

    AdamantModpackLib_Internal.overlays.dispatchIntervals(0)
    AdamantModpackLib_Internal.overlays.dispatchIntervals(0.5)
    AdamantModpackLib_Internal.overlays.dispatchIntervals(1.1)

    lu.assertEquals(calls, 2)
end

function TestRetainedOverlays:testExplicitOwnerIntervalPredicateRunsOncePerDispatch()
    local whenCalls = 0
    createHostWithOverlays("test.retained.interval.once", function(overlays)
        overlays.onInterval("tick", 1.0, function() end, {
            when = function()
                whenCalls = whenCalls + 1
                return true
            end,
        })
    end):tryActivate()

    AdamantModpackLib_Internal.overlays.dispatchIntervals(0)

    lu.assertEquals(whenCalls, 1)
end

function TestRetainedOverlays:testAfterHookObservesResultsWithoutChangingReturn()
    local wrapped = nil
    local observed = nil
    modutil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    lu.assertEquals(path, "StartNewRunAfter")
                    wrapped = handler
                end,
            },
        },
    }
    rom.mods["SGG_Modding-ModUtil"] = modutil

    local pluginGuid = "test-retained-overlay-after-hook"
    local _, authorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunAfter", function(_, event)
            observed = {
                arg = event.args[1],
                result = event.result,
            }
        end)
    end)
    authorHost.tryActivate()

    local result = wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(result, "run:base")
    lu.assertEquals(observed, {
        arg = "run",
        result = "run:base",
    })
end

function TestRetainedOverlays:testDefineSystemDoesNotExposeHookOrIntervalEvents()
    lib.overlays.defineSystem("test.retained.system.surface", function(overlays)
        lu.assertNil(overlays.afterHook)
        lu.assertNil(overlays.onInterval)
        lu.assertNil(overlays.createTable)
    end)
end

function TestRetainedOverlays:testHostAfterHookIsRemovedWhenOmitted()
    local wrapped = nil
    local wrapCalls = 0
    local observed = false
    local pluginGuid = "test-retained-host-after-omit"
    modutil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    lu.assertEquals(path, "StartNewRunOmit")
                    wrapCalls = wrapCalls + 1
                    wrapped = handler
                end,
            },
        },
    }
    rom.mods["SGG_Modding-ModUtil"] = modutil

    local _, firstAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunOmit", function()
            observed = true
        end)
    end)
    firstAuthorHost.tryActivate()

    local _, secondAuthorHost = createHostWithOverlays(pluginGuid, function() end)
    secondAuthorHost.tryActivate()

    local result = wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(wrapCalls, 1)
    lu.assertEquals(result, "run:base")
    lu.assertFalse(observed)
end

function TestRetainedOverlays:testHostAfterHookRollsBackOnActivationFailure()
    local wrapped = nil
    local observed = nil
    local pluginGuid = "test-retained-host-after-rollback"
    modutil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    lu.assertEquals(path, "StartNewRunRollback")
                    wrapped = handler
                end,
            },
        },
    }
    rom.mods["SGG_Modding-ModUtil"] = modutil

    local _, firstAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunRollback", function()
            observed = "first"
        end)
    end)
    firstAuthorHost.tryActivate()

    local _, secondAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunRollback", function()
            observed = "second"
        end)
    end, {
        registerIntegrations = function()
            error("rollback after overlay hook")
        end,
    })
    local ok, err = secondAuthorHost.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "rollback after overlay hook")

    wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(observed, "first")
end

function TestRetainedOverlays:testActivationFailureRollsBackOverlayDeclarations()
    local pluginGuid = "test-retained-rollback"
    local firstHost, firstAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("stable", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedRollback",
    })
    firstAuthorHost.tryActivate()

    local _, secondAuthorHost = createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("replacement", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedRollback",
        registerIntegrations = function()
            error("rollback after overlays")
        end,
    })

    local ok, err = secondAuthorHost.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "rollback after overlays")
    local retained = AdamantModpackLib_OverlayState.retained.tableRegistries[firstHost]
    lu.assertNotNil(retained.elements.stable)
    lu.assertNil(retained.elements.replacement)
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), firstHost)
end
