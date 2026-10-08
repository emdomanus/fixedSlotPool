# Local package handoff

Workspace: `C:/Users/edwar/Documents/RobloxProjects/fixedSlotPool`.
Branch: user-requested `main`. Initial implementation checkpoint committed as
`ae0b041d16b29278bc230087320c1ac773aab346` after the full package verification passed.
The subsequent record/token API changes were accepted by the user and included in the next local commit. No remote is configured. Tracking context: [VMMO-7](https://voxelmmo.youtrack.cloud/issue/VMMO-7).

Implemented the agreed generic fixed-slot pool with preallocated payloads and index metadata,
direct typed payload access, optional reset and generation-checked lifecycle calls. Capacity
is caller-selected; no expansion or built-in stealing. The shared implementation and canonical
types mirror Tempo's semantic package/domain layout. Tests and verification tooling stay outside
runtime source. No type function merges metadata into T and no wrapper table is allocated per lease.

This work changes only the standalone package. It does not alter VoxelMMO recoil, installed
dependencies, Studio, Tempo or TimestampedBuffer. Recoil integration and its overflow/cancellation
policy remain separate review work.

## Record/token API update

Acquisition returns `(record, generation)` and release takes that same pair. The slot index
is private; a constructor-populated lookup resolves record identity without a handle table.
Payloads require unique non-nil/non-NaN keys. Their fields stay mutable and receive no internal
metadata. Generation tokens must be retained separately from recycled records to distinguish
old leases from new ones. Tests cover foreign records, stale tokens after reuse, frozen payloads,
unchanged payload shape, duplicate rejection and the existing lifecycle/model contracts.

## Follow-up allocation audit

[VMMO-45: Audit transient allocations before visualizer and systems refactors](https://voxelmmo.youtrack.cloud/issue/VMMO-45)
records the requested audit of audio/SFX, VFX/hit markers/damage text and client projectile visuals.
Schedule it before the character visualizer and broader systems refactors. It includes deciding
where measured allocation guidance belongs in docs/conventions/an existing or new skill. No broad
audit or skill modification was performed here. Choose overflow policy per system, rather than
applying stealing blindly to every object or authoritative state.

## Verification

- StyLua: clean for source, positive/negative typing fixtures and host tests.
- Selene: 0 errors, 0 warnings, 0 parse errors.
- Lune: all 14 behavioral groups pass, including 50,000 model-checked mixed operations.
- Harness: success, setup failure, test failure, abandoned-run recovery and concurrent
  isolation pass; no owned runtime directories remain. The empty ignored scratch root remains;
  automatic approval review blocked its optional removal.
- Luau-LSP 1.70.1: zero runtime/type/positive-fixture diagnostics; all eight negative contract
  expressions rejected, with no unexpected fixture diagnostics. Rojo tree has no duplicate siblings.
- Rojo 7.7.1 build succeeds: ignored `.verification/fixedSlotPool.rbxm`.
- Pesde install validates the private dependency-free manifest and generates `pesde.lock`.
  Tool validation accounts for Pesde reporting 0.7.4 without the pinned registry build metadata.
- All PowerShell files parse without syntax errors.

Analyzer used the existing local 1.70.1 override (SHA-256
`70ACFB339476F2909CD3AE57D384B8ABF6000352E8730300D2D0FC7694986798`). Copied Roblox definitions
SHA-256: `816A806309CA4332ABEAFDA229DA1FBE8C4378C30039F50C9BECDDB50E541FFC`.
The new package has no inherited analyzer baseline and requires zero diagnostics. VoxelMMO's
source checks were not rerun because its source and dependencies were not changed.

User accepted the record/token API. Remaining: separate recoil integration and overflow behavior tests;
optional allocation profiling in the real consumer. No claim of measured zero VM allocations or
Studio integration is made. Creation counts and identity tests prove bounded payload reuse only.
