# Code-health campaign — STATE (rewritten in place; rules in RULES.md)

**Objective.** Lower code debt across the peclet suite with behaviour proved unchanged, using
cce-code-health (debt metrics + base-vs-head gate). Peclet side: this campaign; tool side: session `code_health`.

**Tool pin.** cce-code-health a59effb in `~/.venvs/codehealth` (cpp@0, C++ self-test, same_lines).

## Where we are (2026-11-13)
- Repo 1 = **dem** (worktree `suite/dem-health`, branch `code-health`, off main e375b97). Nothing pushed.
  - 548c66b gate config; 0424510 WO-1 renames (97 `*Kokkos` ids, state_hash ALL IDENTICAL, 303/303);
    246837a PecletDeps prints resolved header path both branches; 7538e81 same_lines guard; 3fd9b93 `.codehealth/playbook.md`.
    **Campaign base CB = 3fd9b93** (every `.codehealth/` file exists before CB; steps may not touch it).
  - **S1 (WO-2) done**: 5c2bb0a `colorVelocityPhase`, a842970 `colorPositionPhase`, 913d709 `solvePositionPhase`;
    each GATE PASS 13/13 bitwise, logged (`runs/dem-s1.jsonl`, 3 accepted). demSolveContacts debt 345→258.3,
    CCN 261→196, NLOC 912→693; dem debt 1871.8→1858.2. Session review: moves verbatim (color-moved diff:
    only wrappers + clang-format reflow), Hooks const& unchanged, moved locals stay local. Independent check: HEAD 913d709 state_hash vs the pre-rename reference (main e375b97) ALL IDENTICAL.
  - Baseline at CB: debt 1871.8 (143.56/kNLOC), 13038 NLOC, brain 12 → `dem/.git/codehealth/runs/dem-s1-base.json`.
  - Self-test PASS (state_hash caught solver_hertz.hpp:59 4.0->7.0). Full-tier smoke gate (comment-only change vs base 7538e81): GATE PASS 12/12, 1789 s wall incl. cold base build (build_host 350, ctest 513, state_hash 360, build_cuda 545 s at load ~80).
- Baseline scan (scope `src/*`, before WO-1): 26 files, 13063 NLOC, debt 1872.6, health 5.49, brain 12.

## Next actions
1. S2 launch-params-struct: `solvePositionPhase` (19 params, brain, debt 43.1) and the 14–33-param launchers;
   then the PGS velocity solve (~30 shared locals with stab/multilevel/Poisson) via a param struct, not by args.
2. Then dedup-colouring. Each step: `codehealth gate --require-gain` green, logged.
3. Then pnm, flow (after sharpvisc-land), voro last.

## Gates (dem, measured 11-13 on TRS2 at load ~80)
| tier | pass criterion | time |
|---|---|---|
| clang_format | 0 diffs (CI blocking set) | <1 s |
| build_host / build_cuda | builds (CUDA with tests + MPI) | ~150 s / ~340 s |
| ctest_host | 303/303, no skip | ~345 s |
| state_hash | hashes.json byte-identical to base | 6 s |
| clang_tidy (campaign) | per-file/check counts do not rise (baseline 2514 warnings) | ~530 s |

## Open decisions (default in force)
- Push `.codehealth/` to dem main → waiting for the user.
- `performance-unnecessary-value-param` (947 hits, mostly `Kokkos::View` by value, which is idiomatic) → leave it, never "fix" it; propose excluding it in dem's `.clang-tidy`.

## Anchors
`dem-health/src/solve_driver.hpp:606` demSolveContacts (debt 258.3), `:457` solvePositionPhase; `dem-health/.codehealth/config.toml`.
