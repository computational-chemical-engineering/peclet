# Proposal (for Frank to approve): split dem src/solver_multilevel.hpp

Status: PROPOSAL. The plan file `.codehealth/restructure/<id>.toml` is the human's to write and
commit (refactor-loop skill, "Restructure"). Nothing is done until it exists.

## Why
dem S6 (6df7eb6) took `src/solver_multilevel.hpp` from NLOC 957 to 1003 (cpp@0 limit 1000). This is
a NEW large_file smell. `codehealth diff --base 3fd9b93` and the campaign gate (tool 965de38) both
FAIL on it; it is the only failing check. A 4-line shave to slip under the limit is rejected as
gaming. The file holds two separable jobs, so a split is the honest fix.

## The split (measured 11-14, by name use per half of the file)
- NEW `src/solver_multilevel_hierarchy.hpp` (~540 NLOC): building the contact hierarchy, today's
  lines 45-678. It holds the constants (kMlMaxLevels, kMlSlotSkip, kMlPendingSkipBit),
  ContactHierarchy, MlScratch, MlBodyViews, namespace mldetail (effMass, the gate bits, eligible,
  canonical, memberOffset, spinInertiaTimes, symMul, D3/crossD/rotateD), buildMlLevelGeometry,
  MlEligibility, matchMlLevelGroups, colorMlLevelManifolds and buildContactHierarchy.
- `src/solver_multilevel.hpp` keeps the coarse cycle (~460 NLOC): buildCoarseBuckets, MlCoarseSweep,
  makeMlCoarseSweep, MlFusedMeta/MlFusedCtx, the fused-loop kernels, demMakeMlFusedCtx and
  multilevelCoarseCycle. It `#include`s the new header first, so every existing include path
  (solve_driver.hpp, particles.hpp, tests/kokkos/test_multilevel_rigid.cpp) still works unchanged.
- Shared names the cycle half uses from the hierarchy half: kMlMaxLevels, MlScratch, MlBodyViews,
  ContactHierarchy, effMass, canonical, memberOffset, spinInertiaTimes, symMul. They live in the new
  header and are reached through the include, so the direction is one-way (cycle → hierarchy).
- new_public: none. Every name keeps its namespace and spelling; it is a verbatim move.

## Plan fields (for Frank to write)
id = "dem-multilevel-split"; approved_by = <Frank>; reason = as above;
new_files = ["src/solver_multilevel_hierarchy.hpp"]; new_public = [].

## Verification
`codehealth gate --mode restructure --plan .codehealth/restructure/dem-multilevel-split.toml
--base 6df7eb6 --ref-base 3fd9b93` (bitwise at all host tiers), then the campaign gate, then the
CUDA device check (ctest 303/303, the envelope rule). Token-identity check of the moved block.

## Alternative
Revert S6 (6df7eb6): the file goes back to 957 NLOC, debt +19.5, brain 9 → 10.
