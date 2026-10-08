# Ownership and slot lifecycle

`FixedSlotPool<T>` owns allocation state; the caller owns payload meaning and initialization.
The generic implementation has no recoil, time, priority, logging or stealing policy.
`FixedSlotPoolOptions<T>` and the private `FixedSlotPoolImpl<T>` live beside each other in
the mirrored object type leaf. Only public types and the constructor cross the package root.
No separate port is introduced until a real consumer needs an independently narrow view.

The free stack is represented by slot indices. `_freeHead == 0` means full. For a slot,
`_nextFree[index] == -1` means acquired; a nonnegative value is its next free index (zero
terminates the stack). `_generations[index]` increases when that slot is acquired again.
No duplicate Boolean occupancy array or per-slot wrapper is needed.

`_indices[value]` privately resolves a payload to its slot. The constructor fills this map
once, rejecting duplicate values and NaN; table keys use reference identity. Public calls
return the original payload and a separate numeric generation token. They never allocate
a lease object or inject metadata into payloads. `release(record, generation)` rejects an
unknown record, free slot or stale token without resetting anything. Holding an old record
reference cannot release a new acquisition with its old token, but direct stale writes are
still the caller's responsibility. Scalars must be unique within the pool, and tokens remain
pool-local. The public indexed `values` array remains available for bounded iteration.

- Construction: O(capacity), fills all three arrays and the identity lookup, and creates every payload.
- Acquire: O(1), pops a free index, increments its generation, marks it acquired.
- Release: O(1) excluding the caller's reset work, looks up the record, validates its generation, resets,
  then pushes the slot back. Stale and double releases do no reset work.
- Clear: O(capacity) plus reset work. Does not rebuild arrays or reset generations.
- Overflow: returns nil without modifying a live slot or allocating extra capacity.

Payload slots are shallow-frozen once, so the table storing them cannot be resized or
overwritten. Their [read-only indexer type](https://github.com/luau-lang/rfcs/blob/master/docs/syntax-property-access-modifiers.md)
rejects replacement statically while leaving mutable payload fields writable. The pool
object's public fields/methods are read-only through types; the object itself is mutable
for private bookkeeping. This is a trusted-code contract, not a sandbox/security boundary.

Reset error handling uses a shared protected-call helper, not a new per-release closure.
Allocator mutation is rejected while reset executes. Errors restore that guard and retain
the original acquisition. Callbacks must not yield. External cleanup and partial payload
mutations are the callback owner's responsibility, including retry safety.

For future recoil integration, retain `(record, generation)` for each active shot, mutate its
payload in place and release expired slots. If full, recoil may select a victim, cancel its
remaining curve/bookkeeping, release its current acquisition and acquire the reusable slot.
Preserve delivered aggregate recovery; do not charge undelivered future kick to recovery.
Those cancellation/timing rules require consumer tests and are deliberately absent here.
Do not pool externally retained public handle objects without their own stale-access policy.

The package does not preallocate a global default capacity. Each owner selects its budget
and constructs the pool before the latency-sensitive workload. A caller allocating request
tables, closures, results or new payload internals can still produce GC pressure.
