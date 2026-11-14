# WO-16 — dem S7 A4 under the host-FMA envelope (Frank, Decision Desk, verified)

Follows WO-12/13/14. Read WO-14 (`briefs/WO-14-dem-s7-A3-A4.md`) and WO-13 for the where, machine rules,
gate set and stop rules — all still hold except G-fma, which changes as below. Read the last three
entries of `docs/code_health/DECISIONS_LOG.md`, especially the PRE-REGISTERED G-fma-env criterion.
Base: dem-health `code-health` HEAD **5353296** (B6). Tool 93a36d8. Scripts in `scratchpad/s7/`
(`probe_a4.sh`, `edit_a4*.py`, `s7_side.sh`, `s7_cmp.sh`, `s7_branch_hash.py`, `sass_gate.py`, ...).

## The changed gate: G-fma-env (pre-registered; do not alter)
Per scenario (the 9 state_hash cases + the 12 G-branch scenarios; compare positions, velocities and
quaternions as ARRAYS, so save them, not only hashes):
  max|head_fma − base_fma| ≤ 1.5 × max|base_fma − base_off|.
Report the per-scenario ratio. Everything else is unchanged and still bitwise or as before: G-host
(the off build) bitwise, G-branch on the off build bitwise, G-sass S0/S1 only, G-cuda envelope,
G-time (both benches, the S7 bench with 10 pairs).

## Scope
G-sass is NOT relaxed. `frictionImpulse` and `coneProject` failed G-sass in WO-14, so they stay out.
Candidates are `slipError`, `pairVelocity` and `tangentialPredictor` (each passed G-sass alone,
nested in the inline friction block).
1. Try all three together as A4′. If G-sass or G-fma-env fails, try the 2-of-3 subsets, then single
   seams. Land the largest passing set that drops debt. Commit and log it
   (`--recipe device-split-solveone`, hypothesis line with the max G-fma-env ratio).
2. If nothing passes, stop.

Report in ≤ 30 lines: what landed, the per-scenario G-fma-env ratios (max and the worst scenario),
the SASS counts, the envelope and bench numbers, and solveOne's CCN, NLOC and debt (brain or not).
Never push. Remove any base worktree you create. Stop at ~250k tokens of context with a handoff.
