# Verification

Use PowerShell 7 and Rokit. Pins follow the already-installed VoxelMMO toolchain; no tools
are upgraded in another repository. `scripts/verify/tools.ps1` resolves `~/.rokit/bin`,
checks versions and supports the existing exact-version `LUAU_LSP_OVERRIDE` exception.

```powershell
rokit install
pwsh -NoProfile -File scripts/verify/run.ps1
```

Individual checks: `-Check stylua`, `selene`, `tests`, `harness`, `analyze`, `build`, `package`.
Formatting is check-only; agents may format explicit task-owned files with pinned StyLua.
The package check runs Pesde install against the private dependency-free manifest; it does
not publish anything. Rojo build writes `.verification/fixedSlotPool.rbxm`, never Studio.

The analyzer needs Roblox definitions at `scripts/luau-lsp/globalTypes.d.luau` (ignored).
This initial workspace uses an exact local copy of Tempo's existing definitions. On another
machine provide equivalent definitions and record their SHA-256 with the tool versions.
The analyzer checks all runtime/type leaves and `tests/types.luau` for zero diagnostics, then
requires diagnostics at every EXPECT_ERROR expression in the negative contract fixture.
This includes preventing slot replacement, public-field writes and invalid release signatures.
The Rojo sourcemap is also inspected for duplicate sibling names.

Lune tests execute the actual package through a host-only script-relative import adapter.
The runner assigns an exclusive, unique `.lune-runtimes/<token>` folder and removes only its
owned generated data in finally, including setup/test failure. It checks resolved paths,
ownership, Git tracking and reparse points. Hard-terminated runs are reclaimed only when
their recorded process is no longer alive and the lock is available. `harness` exercises
success, setup failure, assertion failure, abandoned-run cleanup and concurrent isolation.
No generated runtime belongs in the repository or a published package.

The behavioral suite covers fixed capacity, distinct payloads, identity reuse, scalar/false
values, out-of-order completion, stale/double release, callback reset/failure/reentrancy,
partial clear failure, invalid inputs, generation exhaustion and 50,000 model-checked operations.
Factory counts prove payload creation stops at capacity; they do not measure all VM allocations.

The initial authoring run exposed an unsupported shorthand for the read-only array type;
using the explicit read-only numeric indexer resolved it. Tempo's older host adapter also
required Lune 0.10 relative-import support from VoxelMMO. Both corrections preserved the
intended API/behavior. See the handoff for final results and remaining integration work.
