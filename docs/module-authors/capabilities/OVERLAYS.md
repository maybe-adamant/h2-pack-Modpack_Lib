# Overlays

Overlays are retained HUD projections owned by a module host. They are useful for gameplay-facing status text, counters, timers, or compact tables that should appear in Lib-managed HUD regions.

Use overlays when the module needs a retained display. Use widgets when the module needs configuration UI.

## Normal Shape

Declare overlays inside `registerOverlays(overlays, host, store)` and pass that callback to `lib.createModule(...)`:

```lua
local function registerOverlays(overlays, host, store)
    overlays.createLine("summary.igt", {
        region = "middleRightStack",
        order = lib.overlays.order.module,
        columnGap = 20,
        columns = {
            { key = "label", minWidth = 40 },
            { key = "time", minWidth = 80 },
        },
    })

    overlays.onCommit(function(ctx)
        ctx.setLine("summary.igt", {
            label = "IGT:",
            time = "00:00.00",
        })
        ctx.refresh("summary.igt")
    end)
end
```

Then pass it into module creation:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    registerOverlays = registerOverlays,
    drawTab = ui.drawTab,
})
host.tryActivate()
```

## Retained Elements

Use:

- `overlays.createLine(name, spec)`
- `overlays.createTable(name, spec)`

Retained element names are local to the module's `pluginGuid` lifecycle. Different modules can reuse the same local element names without colliding.

The shared managed region currently exposed to modules is:

- `middleRightStack`

Order bands:

- `lib.overlays.order.framework`
- `lib.overlays.order.module`
- `lib.overlays.order.debug`

## Projection Events

Overlay projections can update retained elements from:

- `overlays.onCommit(function(ctx, commit) ... end)`
- `overlays.onInterval(name, seconds, function(ctx, event) ... end, opts)`
- `overlays.afterHook(path, function(ctx, event) ... end)`

The projection context exposes:

- `ctx.read(alias)`
- `ctx.isEnabled()`
- `ctx.log(fmt, ...)`
- `ctx.logIf(fmt, ...)`
- `ctx.setLine(name, values)`
- `ctx.setTable(name, rows)`
- `ctx.setCell(tableName, rowKey, columnKey, value)`
- `ctx.refresh(name)`
- `ctx.refreshRegion(region)`
- `ctx.refreshAll()`

Use `ctx.read(alias)` for committed store values. Do not capture UI session state in overlay callbacks.

## Visibility And UI Suppression

Overlay visibility has multiple gates:

- Lib applies the global game-HUD gate.
- Each overlay can provide its own `visible` boolean or callback.
- Framework and standalone configuration UI suppress the entire overlay layer while open.

Module code normally does not need to call suppression APIs directly. They are available when a custom foreground ImGui UI must temporarily hide Lib overlays:

```lua
local token = lib.overlays.suppressForUi()
-- later
token.release()
```

Suppression is reference-counted. Always release the token you acquire.

## Common Mistakes

- Do not render overlay text directly from draw-tab UI code.
- Do not use overlays for editable configuration.
- Do not keep suppression tokens forever.
- Do not read staged session values from projection callbacks.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [WIDGETS.md](WIDGETS.md)
- [../../../API.md](../../../API.md)
