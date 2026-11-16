# Code-health campaign — STATE (rewritten in place; rules in RULES.md; history in DECISIONS_LOG.md)

**Objective.** Lower code debt across the peclet suite with behaviour proved unchanged, using
cce-code-health (debt metrics + base-vs-head gate). Peclet side: this campaign; tool side: session `code_health`.

**Tool pin.** cce-code-health 719092b (log --external-fail, relative gate_json, docs OFF) in `~/.venvs/codehealth`, since 11-15.
Earlier pins: 93a36d8, 569c85b (restructure gain), 965de38 (file-smell step check), 00b1849, c5ee4df, a59effb.

## Where we are (2026-11-15)
- **dem S9 LANDED 11-15** (WO-19, PR #14, dem main 9c36779): shock path kept + covered by a new test, shared ShockGate
  predicate; debt 1475.6 → 1468.3, brain 7. Umbrella pointer not bumped (waits for Frank's OK on umbrella pushes).
- **dem LANDED 11-15**: PR #13 merged, dem main 2ed8411, umbrella 3138c71. (worktree `suite/dem-health`, branch `code-health`; CB 3fd9b93.)
  - S1–S6 closed (6df7eb6: debt 1649.4, brain 9). S7 closed (5353296 + tidy 43fb299: debt 1505.2, brain 8;
    solveOne 97.4 → 54.9 still brain; demSolveContacts 87.7 → 21.2 out). S8 landed 43fb299..3a65d08:
    hertzWallForces 49.4 → 29.0 (out of brain), solveVelocityColoredGS 42.1 → 30.1 (still brain: dead
    shock-propagation block left, see log 11-15). **dem now: debt 1475.6 (CB 1871.8, −21 %), brain 7 (CB 12).**
  - Run logs `dem/.git/codehealth/runs/dem-s1..s8.jsonl` + `dem-s1-base.json`.
- **pnm** (worktree `suite/pnm-health`, CB b65b4a2): P1 done (debt 319.3 → 299.4, brain 2 → 1). HELD until A7's
  junction-law lands (Desk pnm-push = B), then PR.
- **flow F1 CLOSED 11-15** (WO-20, branch f1 42bdc15..73a6f63): CutcellMG buildAmg 59.1→0, initMpi 92.0→19.6,
  solvePCGResident 74.5→48.1; flow 5799.4 → 5657.1, brain 48 → 46. **LANDED 11-16: PR peclet-flow#15, flow main 28e18d1.**
- **flow F2 CLOSED 11-16** (WO-21, branch f2 off f1, ..97ec11f, local): decomposition 40→1, PCG/FCG/BiCGStab attempts;
  **flow → 5606.2, brain 43**; all gates bitwise incl. GPU. **LANDED 11-16: PR peclet-flow#16, flow main ed61f38.**
- **flow ONBOARDED 11-15** (worktree `suite/flow-health`, branch code-health, CB b148fe1 (src = eed2fa4); core via
  detached `suite/core-health-flowpin` 7cec32a, do not move). Baseline debt 5799.4, brain 48, health 4.5. Step gate
  ≈ 40 min (ctest 275 + state_hash + sharp_vof); campaign adds ctest_long, build_cuda, clang_tidy. Keep-out: RULES.md. **voro** waits for the M7 branches.

## Next actions
1. flow F3 CLOSED (WO-22, branch f3 b15a3eb..9ccc338, local): flow 5558.9, brain 42. Landing = Desk card flow-f3-land. Deferred: scalar_krylov.hpp (no owner; heavy gates), cut_cell_ibm.hpp (vof keep-out). Umbrella pointer bumps (dem 9c36779, flow) wait for Frank.
2. pnm PR when A7 pings that junction-law landed (Desk pnm-push = B).
3. Next dem/pnm round: pin core to a detached worktree (shared suite/core moved 11-15 12:49).
4. flow (a) DONE: the 4 OMP=1 failures predate eed2fa4 (same at f9eb1e0); sent to vof as a tolerance question.
5. Re-pin to cce-code-health v0.2.0 (7b8449d) at the start of the next round.
6. Housekeeping: remove dem worktrees dem-cudaref / dem-cudahead when no further dem round is planned.

## Milestone exit rule (pre-registered 11-13)
A round closes only with dem brain ≤ 12 AND debt below the previous milestone AND the CUDA device check.

## Gates (dem)
| tier | pass criterion |
|---|---|
| G-host (`codehealth gate --mode refactor --base <prev> --ref-base 3fd9b93 --require-gain`) | 13/13: format, builds, ctest 303/303, state_hash bitwise, tidy ratchet, debt gain |
| G-sass (`scratchpad/s7/sass_gate.py`) | every kernel S0 (identical) or S1 (same multiset, regs ≤ base) |
| G-fma / G-branch | host `-march=native -ffp-contract=fast` build bitwise base == head (valid only if fma ≠ off); 12 S7 + 5 S8 branch scenarios on both builds. G-fma-env v2 pre-registered (log 11-14) for fma drift |
| CUDA device check (per round; `scratchpad/cuda_ref.sh`) | CUDA ctest 303/303; A-vs-B max\|Δ\| ≤ 1.5 × max(within-A, within-B) per scenario |
| GPU timing (`scratchpad/cuda_bench.sh`, ABBA bench_step.py np1, 5 pairs) | median base/head ≥ 0.95; 0.90–0.95 → 10 pairs; < 0.90 MISS |

## Open decisions (default in force)
- shock-propagation block: Frank 11-15 KEEP (refactor allowed, round-off OK) → WO-19.
- solveOne friction channel (A4): stays inline; G-fma-env v2 may reopen it in a later round.
- solver_multilevel.hpp split: plan committed (ca50b3e), split dropped (no gain); branch split-attempt-2.

## Anchors
`dem-health/src/solver_velocity.hpp` (solveOne, solveVelocityColoredGS), `src/solver_hertz.hpp:180` hertzWallForces,
`src/solve_driver.hpp` demSolveContacts; `dem-health/.codehealth/{config.toml,playbook.md}`; designs/dem-s7-design.md.
