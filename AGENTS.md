# FixedSlotPool package

This is a standalone shared Luau package. Follow VoxelMMO's voxel-mmo-conventions
skill at ../VoxelMMO/ServiceDev/.agents/skills/voxel-mmo-conventions/SKILL.md when
available. Keep implementation contracts mirrored under src/fixedSlotPool/types,
use script-relative runtime imports, and export only the public constructor and
canonical public types from src/init.luau. No game-service dependency belongs here.

Use Rokit pins and scripts/verify/run.ps1. Do not invoke shadowing system tools.
Read docs/verification.md for checks and docs/design.md for the lifecycle contract.
Temporary test runtimes must stay under .lune-runtimes with runner-owned cleanup.
No remote creation, publication, push or recoil integration is authorized.
User explicitly selected local main; preserve it and leave work uncommitted for review.
