# Author Host Facade Design

## Purpose

This note describes the proposed direction for module-author APIs in
ModpackLib.

The goal is to keep Lib backends stateless while making the module-facing API
host-shaped. Normal module authors should primarily learn:

1. create a host
2. declare module-owned capabilities on that host
3. activate the host

Capability implementations can remain isolated, testable, and mostly stateless
behind that facade.

## Current Pressure

The runtime model is already host-centered. Host activation owns:

- live-host publication
- hot-reload replacement
- hooks
- overlays
- integration provider ownership
- mutation sync and rollback
- session commit and runtime refresh
- draw dispatch

The module-author API is less cohesive. Authors create a host, then use a mix
of callback contracts and global Lib namespaces:

```lua
drawTab(ctx)
registerHooks(host, store)
registerOverlays(overlays, host, store)
registerPatchMutation(plan, host, store)
registerIntegrations(host, store)

lib.hooks.*
lib.overlays.*
lib.integrations.*
lib.mutation.*
lib.widgets.*
```

This works, but it creates a bifurcated design:

- Lib and Framework manage module lifecycle through a host-like object.
- Module authors interact with a host plus many separate global service
  surfaces.

The proposed design makes the module-facing API match the runtime shape without
making Lib itself stateful.

## Core Direction

Lib remains the stateless backend and construction namespace.

The author host becomes the module-facing bound facade:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})

host.hooks.wrap("SomeGameFunction", function(base, ...)
    if host.store.read("FeatureEnabled") then
        -- runtime behavior
    end
    return base(...)
end)

host.mutation.patch(function(plan)
    if host.store.read("PatchEnabled") then
        plan:set(SomeGameTable, "Enabled", true)
    end
end)

host.overlays.createLine("summary", {
    region = "middleRightStack",
})

host.integrations.register("run-director.some-provider", MODULE_ID, {
    isAvailable = function()
        return host.store.read("FeatureEnabled") == true
    end,
})

host.tryActivate()
```

Draw code receives the same author host:

```lua
function ui.drawTab(host)
    host.widgets.checkbox("FeatureEnabled", {
        label = "Enabled",
    })

    host.imgui.Separator()
end
```

The public lesson becomes:

```text
create host -> declare capabilities -> activate host
```

## Vocabulary

Use two role names when discussing the implementation:

- `lifecycleHost`: internal Lib/Framework-facing host. It owns activation,
  replacement, commit, sync, rollback, and Framework draw entrypoints.
- `authorHost`: module-facing facade. It owns author capability declarations
  and exposes scoped draw/runtime surfaces.

The author host is not merely a subset of the lifecycle host. They are two
views over one module runtime. Some methods overlap, such as identity, metadata,
logging, enabled state, and activation handoff, but their responsibilities are
different.

User-facing docs may simply call the author-facing object `host`; module
authors do not need to learn the internal distinction up front.

## Lib Surface Target

The long-term public Lib surface should be much smaller for normal module
authors.

Expected public Lib responsibilities:

- host construction, such as `lib.createModule(...)` and
  `lib.tryCreateModule(...)`
- hosting/bootstrap helpers
- neutral utilities
- advanced escape hatches

Normal module-owned capabilities should move behind author-host namespaces:

- `host.hooks.*`
- `host.overlays.*`
- `host.integrations.register(...)`
- `host.mutation.*`
- `host.widgets.*`
- `host.nav.*`

Existing global capability APIs may remain during migration. They should not be
the destination authoring model.

## Phase Model

Host capability declarations are immutable once activated.

The lifecycle has three author-visible phases:

```text
creation phase:
  author host exists
  capability declaration namespaces are open

activation:
  Lib snapshots and installs declared capabilities

activated phase:
  capability declaration namespaces reject new declarations
  draw/runtime/event facades open only during Lib-owned invocation windows
  lifecycle and status methods remain usable
```

Declaration surfaces that close after activation:

- `host.hooks.*`
- `host.overlays.create*`
- `host.overlays.on*`
- `host.integrations.register(...)`
- `host.mutation.patch(...)`

Runtime/status methods may remain usable after activation:

- `host.isEnabled()`
- `host.getIdentity()`
- `host.getMeta()`
- `host.log(...)`
- `host.logIf(...)`

The exact activation idempotency and retry behavior should remain owned by the
host lifecycle implementation.

## State Surfaces

Do not collapse staged and committed state into one phase-polymorphic
`host.read(...)`.

Keep the central state invariant visible:

```text
UI intent is staged.
Runtime behavior is committed.
```

Destination author surfaces:

- `host.session`: staged UI state, available during draw.
- `host.store`: committed runtime state facade, available during sanctioned
  runtime/event/mutation callbacks.

Typical use:

```lua
function ui.drawTab(host)
    host.widgets.checkbox("FeatureEnabled", {
        label = "Enabled",
    })

    local staged = host.session.read("FeatureEnabled")
end

host.hooks.wrap("SomeGameFunction", function(base, ...)
    if host.store.read("FeatureEnabled") then
        -- committed runtime behavior
    end
    return base(...)
end)
```

`host.store` should be an author-facing facade, not the raw managed store. The
facade can enforce phase and owner rules at method call time. This allows common
Lua patterns like:

```lua
local read = host.store.read
```

while still rejecting `read(...)` outside a Lib-owned runtime invocation window.

## Draw Facade

Draw is a Lib-owned invocation window.

The lifecycle host receives the Framework-facing call:

```lua
lifecycleHost.drawTab(imgui)
```

It should open the author host's draw phase, invoke the authored callback, and
always close the phase:

```lua
authorHost:_beginDraw(imgui)
local ok, result = pcall(drawTab, authorHost)
local closeOk, closeErr = pcall(authorHost._endDraw, authorHost)
```

During draw, these surfaces are available:

- `host.imgui`
- `host.widgets`
- `host.nav`
- `host.session`

After draw, those surfaces reject or become inert with clear phase errors.

This keeps the author API simple without pretending ImGui draw stack state is
globally valid.

## Hooks

Hooks are a strong candidate for host enclosure because it removes ownerless
ambient registration.

Destination:

```lua
host.hooks.wrap("GetEligibleLootNames", function(base, excludeLootNames)
    if not host.store.read("FeatureEnabled") then
        return base(excludeLootNames)
    end
    -- runtime behavior
end)
```

The author no longer calls `lib.hooks.*`. Ownership is structural because the
hook registrar is already bound to the module host.

Store access should be open during hook dispatch, not during general module
declaration. Hook handlers may capture `host.store.read`; the facade should
validate phase when the captured function is called.

## Overlays

Overlay declaration moves from a callback-scoped registrar to a host-scoped
declaration namespace:

```lua
host.overlays.createLine("summary", spec)

host.overlays.onCommit(function(ctx, commit)
    ctx.setLine("summary", {
        label = "Enabled",
        value = tostring(ctx.read("FeatureEnabled")),
    })
    ctx.refresh("summary")
end)
```

Overlay projection callbacks may keep their projection context. That context is
already event-specific and intentionally narrower than the author host.

The declaration namespace closes after activation. Projection callbacks run
later under Lib-owned overlay dispatch.

## Mutations

Mutations are lifecycle-owned and already have lower lingering side effects than
hooks or integration providers. Lib builds and applies plans during activation,
enable/disable, settings commit, reload, and rollback.

Destination:

```lua
host.mutation.patch(function(plan)
    if host.store.read("FeatureEnabled") then
        plan:set(SomeGameTable, "Enabled", true)
    end
end)
```

`host.store` should be open while Lib builds the mutation plan. Mutation plan
application and rollback remain internal lifecycle-host responsibilities.

## Integrations

Provider registration should be host-owned and use the host identity as the
default provider identity:

```lua
host.integrations.register("run-director.god-availability", {
    isActive = function()
        return host.isEnabled()
    end,
    isAvailable = function(godKey)
        return host.store.read(godKey) ~= false
    end,
})
```

The legacy/global backend shape can remain unchanged:

```lua
lib.integrations.register(integrationId, providerId, api)
```

The host facade does not need to expose `providerId` for normal authoring.
Lifecycle ownership is implicit because registration happens through the host,
and provider identity can default to the module id. If a real module needs
multiple public provider identities later, add an explicit advanced option
rather than making the common path noisier.

Consumer invocation should also be host-owned:

```lua
local ok = host.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey)
```

This makes the caller real in the implementation: Lib can know that host A
invoked provider code owned by host B. That caller identity is useful for
diagnostics, phase gating, and future policy. It should not be passed to
provider methods by default.

Provider APIs should stay domain-shaped:

```lua
isAvailable = function(godKey)
    return host.store.read(godKey) ~= false
end
```

Do not turn integrations into caller-aware RPC unless a concrete use case needs
that larger contract.

Migration/advanced surfaces:

- keep `lib.integrations.register(id, providerId, api)` unchanged
- keep `lib.integrations.invoke(...)` temporarily as migration or advanced API
- keep direct `get/list` as advanced escape hatches and prefer `invoke(...)`

Provider APIs also need careful wrapping if strict store-phase enforcement is a
goal. `invoke(...)` is easy to phase-scope because Lib owns the call boundary;
direct `get/list` can expose provider tables that bypass invocation wrapping.

## Game Cache

Game cache should move behind the author host, but it is not a capability
declaration like hooks or overlays.

The current global subsystem provides namespaced runtime cache buckets on live
game tables. It is not staged, persisted, hashed, profiled, or reset by Lib. Its
lifetime follows a game table rather than the module host.

The host facade should bind pack/module identity and expose concrete lifecycle
domains. The expected first domain is the active run:

```lua
local state = host.gameCache.currentRun.get("run", function()
    return {
        ForcedNPCPending = {},
    }
end)
```

Expected current-run surface:

```lua
host.gameCache.currentRun.get(key, factory)
host.gameCache.currentRun.peek(key)
host.gameCache.currentRun.clear(key)
```

This is intentionally more specific than `host.cache` or
`host.gameCache.get(...)`. It tells authors that the cache is tied to a game
lifecycle domain, not a general memoization table.

Future domains can be added when real call sites need them:

```lua
host.gameCache.currentRoom.get(key, factory)
host.gameCache.currentEncounter.get(key, factory)
```

A generic object-backed escape hatch may still be useful for advanced code:

```lua
host.gameCache.object.get(object, key, factory)
host.gameCache.object.peek(object, key)
host.gameCache.object.clear(object, key)
```

Do not introduce stringly typed domains such as
`host.gameCache.get("CurrentRun", key, factory)` unless the runtime grows a real
domain registry. Concrete domains keep supported lifetimes grep-visible and
documentable.

## Error Style

Phase errors should name the violated surface and phase clearly:

```text
host.widgets.checkbox requires an active draw phase
host.imgui requires an active draw phase
host.hooks.wrap cannot be called after host activation
host.overlays.createLine cannot be called after host activation
host.store.read requires a runtime callback phase
host.session.read requires an active draw phase
```

These are author mistakes, not internal impossibilities. They should fail at the
author boundary with direct messages.

## Hot Reload

Hot reload should keep the existing replacement model:

1. module file reload creates a fresh author host
2. module code declares the complete current capability set
3. `host.tryActivate()` creates a candidate lifecycle activation
4. Lib installs the new capability set or rolls back
5. omitted declarations are retired

Author declarations must be complete and repeatable. A reload should not rely on
mutating a previously activated author host.

## Migration Strategy

This is a destination design, not an immediate one-step migration.

Recommended migration path:

1. Add author-host declaration namespaces while keeping current callback options.
2. Route new namespaces through the existing stateless capability backends.
3. Add phase tracking and phase-gated store/session/draw facades.
4. Convert first-party modules to host declarations.
5. Update module-author docs to teach host-first authoring.
6. Keep legacy callback/global APIs temporarily.
7. Retire legacy author-facing global capability APIs after module conversion.

During migration, avoid making both models equally permanent. The destination is
host facade over stateless Lib backends.

## Non-Goals

- Do not make Lib capability modules stateful global services.
- Do not expose raw managed store/session objects directly through host.
- Do not make `host.read(...)` choose session or store by phase.
- Do not flatten all capability methods directly onto host.
- Do not turn the lifecycle host into the author capability surface.
- Do not force integration consumer APIs into this design before their call
  sites are audited.
- Do not make game cache a generic host cache or stringly typed event cache.

## Design Summary

The target architecture is:

```text
Lib:
  stateless construction and backend capability implementation

lifecycleHost:
  internal/framework-facing lifecycle owner

authorHost:
  module-facing bound capability facade

capability namespaces:
  host.hooks
  host.overlays
  host.integrations
  host.mutation
  host.widgets
  host.nav
  host.gameCache

state:
  host.session during draw
  host.store during sanctioned runtime/event/mutation callbacks
```

This aligns the module-author API with the lifecycle model the runtime already
uses, while keeping backend services stateless and testable.
