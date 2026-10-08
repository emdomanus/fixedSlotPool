# FixedSlotPool

A dependency-free, fixed-capacity pool of reusable payloads for shared Roblox Luau.
All payloads are created at construction. Acquisition and release reuse slots without
allocating wrapper/handle tables or growing storage. Exhaustion returns nil; the caller
owns overflow policy. This is a slot pool, not a chronological history buffer.

```luau
local FixedSlotPool = require(game.ReplicatedStorage.packages.fixedSlotPool)

type Record = { amount: number, target: Instance? }
local pool: FixedSlotPool.FixedSlotPool<Record> = FixedSlotPool.new(64, {
    create = function(_index: number): Record
        return { amount = 0, target = nil }
    end,
    reset = function(record: Record)
        record.amount = 0
        record.target = nil
    end,
})

local record, generation = pool:tryAcquire()
if record ~= nil and generation ~= nil then
    record.amount = 0.9
    assert(pool:release(record, generation))
    assert(not pool:release(record, generation)) -- already released
end
```

| API | Contract |
| --- | --- |
| `new<T>(capacity, {create, reset?})` | Calls `create(index)` exactly once for every slot; unique, non-nil, non-NaN payload required. |
| `values` | Stable, shallow-frozen indexed payload array with a read-only indexer type. Table payloads remain mutable. |
| `capacity` | Read-only construction capacity. |
| `tryAcquire()` | Returns `record, generation`, or `nil, nil` when full. |
| `release(record, generation)` | Resets and frees a matching acquisition; returns false for a foreign record or stale/already-free acquisition. |
| `isAcquired(record, generation?)` | Checks record ownership and occupancy, optionally checking the acquisition generation. |
| `count()` | Current acquired count. A getter keeps this mutable counter private. |
| `clear()` | Releases currently acquired slots through the same reset policy; repeated clear is harmless. |

Generations must be positive safe integers; malformed tokens raise errors. Generation
exhaustion raises before mutation instead of wrapping. Retain the returned numeric token
separately from the reusable record: a stale reference observes the same table as a later
acquisition, so storing the only token in that table would lose stale-release protection.
The tuple requires no handle allocation. Tokens belong to their originating pool; keep the
pool reference with them. Equal scalar values shared across pools are not distinct identities.

An acquired payload is borrowed until release. Direct references are not revocable:
never continue mutating one after release, even though the table is still reachable.
Generation checks protect release operations, not writes through stale table references.
Do not mutate free payloads or private bookkeeping. For mutable table payloads, factories
must return a distinct table per slot. A private reverse lookup maps each payload to its slot;
duplicate payloads (including equal scalars) and NaN are rejected at construction. Scalar and frozen payloads also work; they cannot
be replaced through `values`. No nested `entry` or `inUse` field is added to `T`.

Reset callbacks are optional, synchronous and non-yielding. They may mutate the payload
and observe the pool, but cannot acquire, release or clear that same pool. If reset throws,
the original failure propagates and the slot remains acquired for retry; payload mutations
are not rolled back. A failing clear may already have released earlier slots. Reset is not
called at construction or on rejected releases. Without reset, payload contents persist.
Drop all pool/payload references after clearing when the owner is destroyed; the pool does
not infer how to destroy Roblox Instances or external resources.

Three arrays are preallocated: values, free-stack links/occupancy and generations.
A private payload-to-index map is populated once during construction and never changed.
Construction allocates the arrays, lookup, pool and factory-created values. The library's successful
acquire/release methods construct no tables or closures; caller callbacks and VM internals
are outside this claim. No instrumented claim of globally zero allocations or GC is made.

See [design](docs/design.md), [verification](docs/verification.md) and [handoff](docs/handoff.md).
The source layout follows Tempo: `src/init.luau`, package-owned shared components and mirrored
types, with package-local docs, tests and verification scripts. Host import adapters are adapted
from Tempo and VoxelMMO and never ship inside runtime source.

Local-only development on `main`; no remote, publication or VoxelMMO dependency change.
Pesde metadata is private and provisional. No license or remote repository URL was inferred.
