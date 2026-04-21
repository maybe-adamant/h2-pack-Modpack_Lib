# adamant-ModpackLib

Reusable runtime library for Hades II mod authors building modpacks, large
configuration-heavy mods, or coordinated feature bundles.

ModpackLib provides the common plumbing that those projects usually need:

- typed storage definitions for module settings
- a staged UI `session` model for responsive ImGui config screens
- a persistent `store` model for runtime hook logic
- profile and hash helpers for saving, loading, and identifying settings
- mutation helpers for modules that patch run data
- module host helpers for coordinated and standalone usage
- reusable ImGui widgets and navigation helpers

The library is designed around immediate-mode UI. Module authors write normal
draw functions, then expose them through a module host:

```lua
public.host = lib.createModuleHost({
    definition = public.definition,
    store = store,
    session = session,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

## Docs

- [GETTING_STARTED.md](GETTING_STARTED.md)
  Start here for the core concepts, file roles, and first module flow.
- [API.md](API.md)
  Public namespaces, functions, and data contracts.
- [MODULE_AUTHORING.md](MODULE_AUTHORING.md)
  Deeper authoring guide for storage, sessions, lifecycle, and hosting.
- [WIDGETS.md](WIDGETS.md)
  Widget and navigation helpers for module UIs.
- [UI_PERFORMANCE.md](UI_PERFORMANCE.md)
  Render-path guidance for responsive ImGui screens.
- [IMGUI_LUA_REFERENCE.md](IMGUI_LUA_REFERENCE.md)
  Notes on the Dear ImGui Lua binding used by the stack.
- [RELOAD_MODUTIL_CHALK_REFERENCE.md](RELOAD_MODUTIL_CHALK_REFERENCE.md)
  Stack reference for ReLoad, ModUtil, and Chalk behavior.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib contract.

## Public Surface

- `lib.config`
- `lib.logging`
- `lib.lifecycle`
- `lib.mutation`
- `lib.hashing`
- `lib.widgets`
- `lib.nav`

Common top-level helpers:
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`

Most authors start with `lib.createStore(...)` and `lib.createModuleHost(...)`.
See [GETTING_STARTED.md](GETTING_STARTED.md) for the recommended project shape.

## Validation

```bash
cd adamant-ModpackLib
lua5.2 tests/all.lua
```
