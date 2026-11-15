# Code-health campaign — STATE (rewritten in place; rules in RULES.md; history in DECISIONS_LOG.md)

**Objective.** Lower code debt across the peclet suite with behaviour proved unchanged, using
cce-code-health (debt metrics + base-vs-head gate). Peclet side: this campaign; tool side: session `code_health`.

**Tool pin.** cce-code-health 93a36d8 (clang_tidy ratchet summed per check over touched files) in `~/.venvs/codehealth`.
Earlier pins: 569c85b (restructure gain), 965de38 (file-smell step check), 00b1849, c5ee4df, a59effb.

## Where we are (2026-11-15)
- **dem LANDED 11-15**: PR #13 merged, dem main 2ed8411, umbrella 3138c71. (worktree `suite/dem-health`, branch `code-health`; CB 3fd9b93.)
  - S1–S6 closed (6df7eb6: debt 1649.4, brain 9). S7 closed (5353296 + tidy 43fb299: debt 1505.2, brain 8;
    solveOne 97.4 → 54.9 still brain; demSolveContacts 87.7 → 21.2 out). S8 landed 43fb299..3a65d08:
    hertzWallForces 49.4 → 29.0 (out of brain), solveVelocityColoredGS 42.1 → 30.1 (still brain: dead
    shock-propagation block left, see log 11-15). **dem now: debt 1475.6 (CB 1871.8, −21 %), brain 7 (CB 12).**
  - Run logs `dem/.git/codehealth/runs/dem-s1..s8.jsonl` + `dem-s1-base.json`.
- **pnm** (worktree `suite/pnm-health`, CB b65b4a2): P1 done (debt 319.3 → 299.4, brain 2 → 1). HELD until A7's
  junction-law lands (Desk pnm-push = B), then PR.
- **flow** freed by vof (keep-out: src/vof/sharp_viscous.hpp, src/vof/curvature_field.hpp, src/flow_ibm*.hpp, sv
  setters in flow_bindings.cpp) but WAITS: Frank "finish dem first". **voro** waits for the M7 branches.

## Next actions
1. flow onboarding WO-18 RUNNING (engineer; worktree suite/flow-health off origin/main eed2fa4; brief briefs/WO-18-flow-onboarding.md). flow landing method (PR vs direct push) to clear with Frank before any flow push.
2. pnm PR when A7 pings that junction-law landed (Desk pnm-push = B).
3. Open for Frank (default keep): delete dem's dead shock-propagation block in solveVelocityColoredGS (DECISIONS.md:441) → Desk card dem-shock-block (filed 11-15; act only on VERIFIED).
4. Re-pin the tool to cce-code-health 719092b (log --external-fail, relative gate_json, docs OFF) after WO-18 finishes.
5. Housekeeping: remove dem worktrees dem-cudaref / dem-cudahead when no further dem round is planned.

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
- solveVelocityColoredGS dead shock-propagation block: delete? (registered feature, DECISIONS.md:441) → default keep.
- solveOne friction channel (A4): stays inline; G-fma-env v2 may reopen it in a later round.
- solver_multilevel.hpp split: plan committed (ca50b3e), split dropped (no gain); branch split-attempt-2.

## Anchors
`dem-health/src/solver_velocity.hpp` (solveOne, solveVelocityColoredGS), `src/solver_hertz.hpp:180` hertzWallForces,
`src/solve_driver.hpp` demSolveContacts; `dem-health/.codehealth/{config.toml,playbook.md}`; designs/dem-s7-design.md.
