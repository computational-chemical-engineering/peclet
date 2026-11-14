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
0. **Milestone exit rule (pre-registered 11-13):** a round closes only with dem brain ≤ 12 (CB value) AND debt
   below the previous milestone, plus the CUDA device check; single steps may relocate.
1. **dem PAUSED after S6 (11-14)** at dem 6df7eb6: debt 1649.4 (CB 1871.8, −11.9 %), brain 9 (CB 12), 16 steps,
   all bitwise on host; S6 CUDA check PASS (ctest 303/303, envelope ≤ 1.13×), GPU timing median 0.999 (bench does
   not run the multilevel path; its kernels are token-identical). Remaining brains are device inner loops
   (solveOne 97, hertzWallForces 49, generateSdf splat, solveVelocity, solveVelocityColoredGS), packState, the
   declined *Incremental pair → a device-function recipe would need its own CUDA A/B design (open, not scheduled).
   **Batch for the user:** dem `code-health` = 22 commits on e375b97 (rename, PecletDeps log, gate config + guards,
   playbook ×2, 16 steps; `git log e375b97..6df7eb6`), push pending the user.
1b. **pnm onboarded 11-14** (worktree suite/pnm-health, branch code-health off 0ccf947): 49df044 PecletDeps log
   line (as dem 246837a), **CB b65b4a2** (config + playbook with A7 keep-out). Self-test PASS (pore_kernels.hpp:373
   mutation caught by state_hash), smoke 13/13. Baseline: 2642 NLOC, debt 319.3, brain 2, health 6.18. Gate ~15 min
   cold / ~8.5 min cached. ALL top-10 targets sit in A7 heavy-overlap files → A7 freed extract_pore_network_mpi +
   steepest (11-14) → P1 (WO-10) running; the rest waits for junction-law on main (A7 pings).
2. **Design item (parked, not a step):** the rest of `demSolveContacts` (87.7) holds the `[&]` host lambdas
   (foldVel, syncVel, voteInvariant, withConsensus, growSlots, noteInvariant) and blocks that declare later-used
   locals; needs a think/architect pass on how the solve's host-side state is owned before any further move.
3. Then: `PGSManifoldSweep::solveOne` 97.4, `buildContactHierarchy` 86.1, solver_velocity.hpp duplication
   (dedup-colouring), halo baseline group, dead `haloPack/UnpackVelocityStateB` (removal = separate decision).
4. Per round end: the CUDA device check (below). Then flow (vof: after sharpvisc-land, asked 11-14); voro WAITS for the M7 branches (voronoi 11-14).

## Gates (dem, measured 11-13 on TRS2 at load ~80)
| tier | pass criterion | time |
|---|---|---|
| clang_format | 0 diffs (CI blocking set) | <1 s |
| build_host / build_cuda | builds (CUDA with tests + MPI) | ~150 s / ~340 s |
| ctest_host | 303/303, no skip | ~345 s |
| state_hash | hashes.json byte-identical to base | 6 s |
| CUDA device check (per round, by hand: `scratchpad/cuda_ref.sh`, worktree `suite/dem-cudaref`) | CUDA ctest 303/303; state_hash ×3 base vs ×3 head: A-vs-B max\|Δ\| ≤ 1.5× max(within-A, within-B) per scenario (GPU is NOT run-to-run deterministic) | ~25 min |
| GPU timing (rounds that change kernels; `scratchpad/cuda_bench.sh` ABBA, examples/bench_step.py np1 N=4000, 5 pairs) | median speedup base/head ≥ 0.95; 0.90–0.95 → rerun with 10 pairs; < 0.90 = MISS. Pre-registered 11-14 from A/A: median 0.999, pair range 0.891–1.015 (3.4 ms/step, load ~80) | ~5 min |
| clang_tidy (campaign) | per-file/check counts do not rise (baseline 2514 warnings) | ~530 s |

## Open decisions (default in force)
- Push `.codehealth/` to dem main → waiting for the user.
- `performance-unnecessary-value-param` (947 hits, mostly `Kokkos::View` by value, which is idiomatic) → leave it, never "fix" it; propose excluding it in dem's `.clang-tidy`.

## Anchors
`dem-health/src/solve_driver.hpp:606` demSolveContacts (debt 258.3), `:457` solvePositionPhase; `dem-health/.codehealth/config.toml`.
