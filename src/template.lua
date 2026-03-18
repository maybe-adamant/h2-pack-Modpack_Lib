-- =============================================================================
-- ADAMANT MODULE TEMPLATE
-- =============================================================================
-- Copy this file as src/main.lua in a new mod folder.
-- Fill in the sections marked FILL below.
--
-- Works standalone with its own ImGui toggle.
-- When adamant-Modpack_Core is installed, the core handles UI — standalone UI is skipped.

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
chalk = mods['SGG_Modding-Chalk']
reload = mods['SGG_Modding-ReLoad']
local lib = mods['adamant-Modpack_Lib']

config = chalk.auto('config.lua')
public.config = config

local backup, restore = lib.createBackupSystem()

-- =============================================================================
-- FILL: Module definition
-- =============================================================================

public.definition = {
    id           = "",       -- Unique key, e.g. "CorrosionFix"
    name         = "",       -- Display name, e.g. "Corrosion Fix"
    category     = "",       -- "BugFixes" | "RunModifiers" | "QoLSettings"
    group        = "",       -- UI group header, e.g. "NPC & Encounters"
    tooltip      = "",       -- Hover text
    default      = true,     -- Default enabled state
    dataMutation = true,     -- true if apply() modifies game tables, false for hook-only mods
}

-- =============================================================================
-- FILL: apply() — mutate game data (use backup before changes)
-- =============================================================================

local function apply()
    -- backup(TraitData.SomeTrait, "SomeProperty")
    -- TraitData.SomeTrait.SomeProperty = newValue
end

-- =============================================================================
-- FILL: registerHooks() — wrap game functions
-- =============================================================================

local function registerHooks()
    -- modutil.mod.Path.Wrap("SomeGameFunction", function(baseFunc, ...)
    --     if not config.Enabled then return baseFunc(...) end
    --     return baseFunc(...)
    -- end)
end

-- =============================================================================
-- Wiring (do not modify)
-- =============================================================================

public.definition.enable = apply
public.definition.disable = restore

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        registerHooks()
        if config.Enabled then apply() end
        if public.definition.dataMutation and not mods['adamant-Modpack_Core'] then
            SetupRunData()
        end
    end)
end)

-- Standalone UI — menu-bar toggle when Core is not installed
local uiCallback = lib.standaloneUI(public.definition, config, apply, restore)
rom.gui.add_to_menu_bar(uiCallback)
