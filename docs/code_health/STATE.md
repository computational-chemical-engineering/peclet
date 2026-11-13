# Code-health campaign — STATE (rewritten in place; rules in RULES.md)

**Objective.** Lower code debt across the peclet suite with behaviour proved unchanged, using
cce-code-health (debt metrics + base-vs-head gate). Peclet side: this campaign; tool side: session `code_health`.

**Tool pin.** cce-code-health 00b1849 (relocated %; from S3 end; c5ee4df S3, a59effb S1–S2) in `~/.venvs/codehealth` (cpp@0, C++ self-test, same_lines).

## Where we are (2026-11-13)
- Repo 1 = **dem** (worktree `suite/dem-health`, branch `code-health`, off main e375b97). Nothing pushed.
  - 548c66b gate config; 0424510 WO-1 renames (97 `*Kokkos` ids, state_hash ALL IDENTICAL, 303/303);
    246837a PecletDeps prints resolved header path both branches; 7538e81 same_lines guard; 3fd9b93 `.codehealth/playbook.md`.
    **Campaign base CB = 3fd9b93** (every `.codehealth/` file exists before CB; steps may not touch it).
  - **S1 (WO-2) done**: 5c2bb0a `colorVelocityPhase`, a842970 `colorPositionPhase`, 913d709 `solvePositionPhase`;
    each GATE PASS 13/13 bitwise, logged (`runs/dem-s1.jsonl`, 3 accepted). demSolveContacts debt 345→258.3,
    CCN 261→196, NLOC 912→693; dem debt 1871.8→1858.2. Session review: moves verbatim (color-moved diff:
    only wrappers + clang-format reflow), Hooks const& unchanged, moved locals stay local.
  - **S2 (WO-3) done**: fcb957c `ColorSchedule`, 54315b3 `HertzMaterials`, 38d9cab `VelocityPhaseViews` (12 halo
    kernels); each GATE PASS 13/13 first attempt; dem debt 1858.2→1799.3. Review: launchers unpack the struct into
    locals with the old names, kernel bodies/captures untouched; ColorSchedule built once is safe (colour Views only
    reallocated in growContactBuffers before the solve). HEAD 38d9cab state_hash vs pre-rename ref ALL IDENTICAL.
  - **S3 (WO-4) done**: 36ef1a9 solveVelocityPhase, d609439 stabilizeVelocityPhase, d9e8aa8 closeVelocityPhase;
    `VelocitySolveContext` = context bag (24 by-value members, logged as such). demSolveContacts 258.1→114.6 but
    step 2 relocated 95 %: brain 12→15, health 5.49→4.98, dem debt 1799.3→1784.6. CUDA device check PASS (below).
  - 07f9dc5 playbook docs commit (seed c5ee4df anti-pattern); tool re-pinned c5ee4df (no self-test: tier/comparator code unchanged). Independent check: HEAD 913d709 state_hash vs the pre-rename reference (main e375b97) ALL IDENTICAL.
  - Baseline at CB: debt 1871.8 (143.56/kNLOC), 13038 NLOC, brain 12 → `dem/.git/codehealth/runs/dem-s1-base.json`.
  - Self-test PASS (state_hash caught solver_hertz.hpp:59 4.0->7.0). Full-tier smoke gate (comment-only change vs base 7538e81): GATE PASS 12/12, 1789 s wall incl. cold base build (build_host 350, ctest 513, state_hash 360, build_cuda 545 s at load ~80).
- Baseline scan (scope `src/*`, before WO-1): 26 files, 13063 NLOC, debt 1872.6, health 5.49, brain 12.

## Next actions
0. **Milestone exit rule (pre-registered 11-13, before S4 results):** a milestone (round) closes only with
   dem brain count ≤ its value at CB (12) AND debt below the previous milestone; single steps may relocate.
   S4 does not close until brain ≤ 12 (now 15); more WO-5-style steps follow if needed.
1. S4: WO-5 (16d9a45, bab8b36) + WO-6 (0a31e05 launchFusedVelocityLoop, 68c567d runOverlapProjection with
   PositionSolveContext, de67b0b countRankLevelActivity): dem debt 1693.5, **brain 12** (exit rule met), health 5.08.
   Closes after the CUDA device check at de67b0b passes (ctest 303/303 + envelope ≤ 1.5×).
2. Then: `PGSManifoldSweep::solveOne` 97.4, `buildContactHierarchy` 86.1, solver_velocity.hpp duplication
   (dedup-colouring), halo baseline group, dead `haloPack/UnpackVelocityStateB` (removal = separate decision).
3. Per round end: the CUDA device check (below). Then pnm, flow (after sharpvisc-land), voro last.

## Gates (dem, measured 11-13 on TRS2 at load ~80)
| tier | pass criterion | time |
|---|---|---|
| clang_format | 0 diffs (CI blocking set) | <1 s |
| build_host / build_cuda | builds (CUDA with tests + MPI) | ~150 s / ~340 s |
| ctest_host | 303/303, no skip | ~345 s |
| state_hash | hashes.json byte-identical to base | 6 s |
| CUDA device check (per round, by hand: `scratchpad/cuda_ref.sh`, worktree `suite/dem-cudaref`) | CUDA ctest 303/303; state_hash ×3 base vs ×3 head: A-vs-B max\|Δ\| ≤ 1.5× max(within-A, within-B) per scenario (GPU is NOT run-to-run deterministic) | ~25 min |
| clang_tidy (campaign) | per-file/check counts do not rise (baseline 2514 warnings) | ~530 s |

## Open decisions (default in force)
- Push `.codehealth/` to dem main → waiting for the user.
- `performance-unnecessary-value-param` (947 hits, mostly `Kokkos::View` by value, which is idiomatic) → leave it, never "fix" it; propose excluding it in dem's `.clang-tidy`.

## Anchors
`dem-health/src/solve_driver.hpp:606` demSolveContacts (debt 258.3), `:457` solvePositionPhase; `dem-health/.codehealth/config.toml`.
