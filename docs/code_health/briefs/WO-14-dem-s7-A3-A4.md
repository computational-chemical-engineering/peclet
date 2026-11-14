# WO-14 — dem S7: A3″ and A4

Follows WO-13 (`briefs/WO-13-dem-s7-A2-A4.md`). Read it first: the where, the machine rules, the gate set
and the stop conditions all still hold. Then read the WO-13 results in `docs/code_health/DECISIONS_LOG.md`
(the last two entries) and the S7 design (§5, §7, §8).

Base: dem-health `code-health` HEAD **48cd181** (A2′, accepted). Base-side artifacts `a2p_*` in
`scratchpad/s7/` (the .so, the off/fma state_hash, the 12-line branch files) are at 48cd181. The tool
is 93a36d8. G-branch = the 12 scenarios in `scratchpad/s7/s7_branch_hash.py`, including
poisson_impact, poisson_impact_ml and the Newton twin.

## Session decision (do not reopen)
**A3″** = `normalVelocity` (used in weighRow) + `pairVelocity` + `drawOrphans` + `releaseIncrement`.
`releaseBudget` and `releaseImpulse` stay inline in solveOne. Every pair of these seams passed G-fma,
but the combination is untested: run the full gate set on it.

## Tasks
1. A3″: implement (start from `edit_a3.py` / `a3_failed_gfma.patch`, minus the two inline parts),
   run the full gate set, then commit and log (`--recipe device-split-solveone`).
   - If G-fma fails, bisect only among the four A3″ seams. The largest passing subset may land, but
     only if it contains releaseIncrement or drawOrphans, i.e. it moves release code. Otherwise stop.
2. A4: the friction split (`edit_a4.py`, normal channel kept inline), on top of what A3 landed,
   then the full gate set, commit and log.
   - If G-fma fails, the same rule applies: bisect among the A4 seams, and land the largest passing
     subset if it still drops debt.
3. After the last landed step, report solveOne's CCN, NLOC and debt, and whether it is still a
   brain function (CCN > 25 and NLOC > 70).

Stop and report in ≤ 30 lines, in the WO-13 format, at ~250k context (handoff `scratchpad/s7/HANDOFF-A3.md`).
Never push. Remove any base worktree you create.
