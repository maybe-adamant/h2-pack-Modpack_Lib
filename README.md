# adamant-ModpackLib

Shared utility library for adamant modpack modules.

Start here for Lib documentation.
This page links to the current authoring and API references.
External repos and templates should link here rather than to individual Lib docs.

It owns:
- the store contract
- managed `uiState`
- storage/widget/layout registries
- lifecycle helpers for `affectsRunData` modules
- standalone regular/special UI helpers

## Docs

- [API.md](API.md)
  Reference for the public Lib API: store access, managed UI state, lifecycle helpers, and standalone helpers.
- [MODULE_AUTHORING.md](MODULE_AUTHORING.md)
  Authoring guide for regular and special modules using the current storage/UI contract.
- [FIELD_REGISTRY.md](FIELD_REGISTRY.md)
  Storage, widget, and layout registry model, including built-in node types and custom type extension.
- [SPECIAL_MODULE_PERFORMANCE.md](SPECIAL_MODULE_PERFORMANCE.md)
  Performance guidance for special-module draw paths and hot ImGui render loops.
- [IMGUI_LUA_REFERENCE.md](IMGUI_LUA_REFERENCE.md)
  Reference for the Dear ImGui Lua binding: cursor/layout APIs, size queries, style, item utilities, and behavioral gotchas.
- [RELOAD_MODUTIL_CHALK_REFERENCE.md](RELOAD_MODUTIL_CHALK_REFERENCE.md)
  Stack-level reference for ReLoad, ModUtil, and Chalk behavior as it affects module authoring.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib surface.

## Public Contract Freeze

The public Lib contract is intended to be stable:
- `createStore(...)`, `store.read/write`, and `store.uiState`
- storage declarations, UI nodes, and built-in registries
- lifecycle helpers for `affectsRunData` modules
- standalone regular/special UI helpers

Anything not documented in the public docs should be treated as internal.

## Validation

```bash
cd adamant-ModpackLib
lua tests/all.lua
```
