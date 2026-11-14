# WO-13 — dem S7: A2 without normalImpulse, release coverage for G-branch, then A3 and A4

Follows WO-12. Read WO-12 (`briefs/WO-12-dem-s7-A.md`) for the where, the machine rules, the per-WO
gate list and the stop conditions; all of it still holds. Rules: `docs/code_health/RULES.md`. Design:
`docs/code_health/designs/dem-s7-design.md` (§5, §7, §8, Appendix). Base: dem-health `code-health`
HEAD **afc1a35** (A1, accepted). Tool: `~/.venvs/codehealth` at cce-code-health 93a36d8.

## What WO-12 found (do not redo)
- A1 afc1a35 passed every gate: SASS 622 S0 + 5 S1, envelope ≤ 1.02, bench 0.990, S7 bench 0.979
  (10 pairs). The S7 bench's A/A range was 0.992–1.133, so it always runs with 10 pairs.
- A2 as designed FAILS G-fma, the host `-march=native -ffp-contract=fast` build: `xpbd_sleep_on/off`
  and all 9 branch scenarios differ from A1, while the `-ffp-contract=off` side is identical. The
  cause is the `normalImpulse` seam. Once normalImpulse is its own function, GCC pairs one multiply
  with a different add (FMA count unchanged at 1801, +1 vmulss). The design's C6 fallback does not
  help (same hashes). gatherRow + weighRow with the normal channel left inline (nested
  PairVelocity) is byte-identical to A1 on G-fma.
- The failed patch, the probe modes and all the gate scripts are in
  `/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/s7/`:
  `a2_failed_gfma.patch`, `edit_a2.py` (modes `flat`/`nonormal`), `s7_side.sh`, `s7_cmp.sh`,
  `s7_branch_hash.py`, `sass_gate.py`, `bench_step_s7.py`, `cuda_bench_s7.sh`, `probe_fma.sh`,
  `debt.sh`. Reuse them and read their headers.
- G-branch has almost no release coverage. The `poisson_drop` scenario gives 0 release increments
  in a counting build. `poisson_stack` (touching columns, spacing 1.0, z0 0.6) gives 6. Whether
  `drawOrphans` (the orphan draw) runs at all is unknown.

## Session decisions (logged; you do not reopen them)
- **A2′ = A2 without `normalImpulse`.** PairVelocity, Row, gatherRow and weighRow land as designed.
  The normal channel stays inline in solveOne behind the unpack header (the `nonormal` probe that
  passed G-fma). `normalImpulse` does not land in S7.
- **Release coverage before A3.** A3 moves the release channel, so G-branch must exercise it first.

## Tasks, in order
1. **A2′.** Implement it, run the full gate set (G-host with `--require-gain`, G-sass, G-fma,
   G-branch, G-cuda, G-time with both benches; the S7 bench with 10 pairs), commit, and log it
   (`--recipe device-split-solveone`).
   If G-host's `--require-gain` fails because A2′ alone drops no debt, stop and report the numbers.
   Do not fold in anything else.
2. **Release-covering G-branch scenarios.** Start from the dem tests that already drive the
   Poisson model (`tests/python/test_restitution_target.py`, and grep tests/ for
   `set_restitution_model`). Build 1–3 scenarios into `s7_branch_hash.py`. Verify with a counting
   build (instrumented copy, never committed) that, over the run:
   - release increments ≥ 1000;
   - `drawOrphans`, the orphan draw, executes ≥ 100 times;
   - friction with β ≠ 0 is active for A4.
   Record the counts. If you cannot reach these thresholds with documented API calls, stop and
   report what you tried and the counts reached.
   Run the new scenarios base == head at afc1a35 vs A2′ on both host builds (off and fma), as a
   check of A2′.
3. **A3**, then **A4**, as in the design §7, with the full gate set including the new scenarios.
   Commit and log each one.
   If any seam in A3/A4 fails G-fma the way normalImpulse did, apply the same rule: try the
   variant that leaves the offending arithmetic inline only if the design or this brief names it.
   Otherwise stop and report.

## Stop and report (≤ 30 lines)
Per step: commit, debt (dem and solveOne), SASS counts, G-fma and G-branch results (with the
coverage counts), envelope max ratio, bench medians. Stop at ~250k tokens of context with a
≤ 40-line handoff `scratchpad/s7/HANDOFF-A2.md`. Never push. Remove any base worktree you create.
