# Game Cache

Game cache is a Lib-owned namespace for module runtime cache buckets attached
to live game tables such as `CurrentRun`, room data, loot data, or other
object-like game structures.

Use it when cache state should follow the lifetime of a specific game table. It
is not persisted, staged, hashed, profiled, or reset by Lib.

## Normal Shape

```lua
local runState = lib.gameCache.get(CurrentRun, PACK_ID, MODULE_ID, "run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

The namespace has four parts:

- `object`: the live game table
- `packId`: pack namespace
- `moduleId`: module namespace inside the pack
- `key`: cache bucket inside the module namespace

Lib stores the bucket under one private root on the object so modules do not attach ad hoc top-level keys.

## Public Surface

Use:

- `lib.gameCache.get(object, packId, moduleId, key, factory?)`
- `lib.gameCache.peek(object, packId, moduleId, key)`
- `lib.gameCache.clear(object, packId, moduleId, key)`

`get(...)` creates the cache bucket when missing. The optional factory runs
only on first creation and must return a table.

`peek(...)` returns an existing cache bucket without creating it.

`clear(...)` removes one cache bucket and prunes empty namespace tables.

## When To Use It

Use game cache for:

- per-run transient state attached to `CurrentRun`
- per-room state attached to room tables
- per-loot or per-encounter state attached to live game tables
- data that should disappear when the game table is replaced

Use managed storage instead when the value is module configuration or should persist through config.

## Common Mistakes

- Do not store config settings in game cache.
- Do not attach module keys directly to game tables.
- Do not use game cache for values that must participate in hashes or profiles.
- Do not let the factory return non-table values.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
