# Game Cache

Game cache is a Lib-owned namespace for module runtime cache buckets attached
to `CurrentRun`.

Use it when cache state should follow the lifetime of the active run. It
is not persisted, staged, hashed, profiled, or reset by Lib.

## Normal Shape

```lua
local runState = host.gameCache.currentRun.get("run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

`currentRun.get(...)` returns `nil` when there is no active `CurrentRun`.

The author-host namespace binds the module's host id, which is backed by the
module's `pluginGuid`. Module code supplies only the cache domain and local key.
Internally, cache storage has three parts:

- `CurrentRun`: the live game run table
- owner id: the module's runtime owner identity, derived from `pluginGuid`
- `key`: cache bucket inside the owner namespace

Lib stores the bucket under one private root on `CurrentRun` so modules do not
attach ad hoc top-level keys. Pack and module ids remain Lib/Framework domain
metadata; `pluginGuid` is the module lifecycle identity that Lib maps to cache
ownership.

## Public Surface

Use:

- `host.gameCache.currentRun.get(key, factory?)`
- `host.gameCache.currentRun.peek(key)`
- `host.gameCache.currentRun.clear(key)`

`get(...)` creates the cache bucket when missing. The optional factory runs
only on first creation and must return a table.

`peek(...)` returns an existing cache bucket without creating it.

`clear(...)` removes one cache bucket and prunes empty namespace tables.

## When To Use It

Use game cache for:

- per-run transient state attached to `CurrentRun`
- data that should disappear when `CurrentRun` is replaced

Use managed storage instead when the value is module configuration or should persist through config.

## Common Mistakes

- Do not store config settings in game cache.
- Do not attach module keys directly to `CurrentRun`.
- Do not use game cache for values that must participate in hashes or profiles.
- Do not let the factory return non-table values.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
