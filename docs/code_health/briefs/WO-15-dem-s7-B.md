# WO-15 — dem S7 B-series: execute work orders B1–B6 (+B7) of the S7 design (demSolveContacts)

You execute a SETTLED design and decide nothing it leaves open: stop and report instead.

## Read first
1. `docs/code_health/RULES.md` (umbrella docs worktree `/home/frankp/Codes/suite/.claude/worktrees/suite-code-health`).
2. `docs/code_health/designs/dem-s7-design.md`: §6 (B design, binding), §7 (rows B1–B7 and the
   acceptance paragraph), §8 (gates).
3. `docs/code_health/briefs/WO-12-dem-s7-A.md`: the where, the machine rules, and the per-WO log
   command, which you use with `--recipe host-state-owner` and target
   `src/solve_driver.hpp::demSolveContacts`.
4. The last three entries of `docs/code_health/DECISIONS_LOG.md`, on what the A-series learned
   about GCC FMA contraction.

## Base
dem-health `code-health` HEAD **a37fcad**. Tool: cce-code-health 93a36d8.
Scripts are in `/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/s7/`:
`s7_side.sh`, `s7_cmp.sh`, `s7_branch_hash.py` (12 scenarios), `sass_gate.py`, `probe_fma.sh`,
`debt.sh`. Read their headers. Base-side artifacts at a37fcad may already exist there; if they do
not, build them.

## Gates per B step (session decision: G-fma is added to the design's host set)
- G-host: `codehealth gate --mode refactor --base <prev> --ref-base 3fd9b93 --require-gain`.
- G-sass: expect every kernel S0, or renamed with an identical body.
- **G-fma** and **G-branch** on both host builds, base == head. demSolveContacts is host code, but
  the A-series showed that FMA pairing moves with function seams, so it is checked.
- B4 also needs G-cuda (§8), because the fused-context path is CUDA-only host code.
- No G-time unless a step changes a device kernel's SASS (it should not).

## Rules
- One commit per WO, in design order: B1, B2, B3, B4, B5, B6. Run B7 only if demSolveContacts is
  still a brain function after B6.
- B2 and B3 assume `P.bodyOrphanVPeak` is never reallocated during the solve. B2 re-checks that
  with the `ensureCapacity(` grep (§6.2). If it is false, stop.
- If a step fails any gate: you may bisect it into the design's own sub-parts once, as WO-14 did.
  Land a passing subset only if it drops debt; otherwise stop. Do not invent seams the design
  does not name.
- Never push. Touch no other worktree except a detached base-side worktree of your own, which you
  remove at the end. At ~250k context, commit what has passed, write a ≤ 40-line handoff to
  `scratchpad/s7/HANDOFF-B.md`, and stop.

## Report (≤ 30 lines)
Per WO: commit, debt (dem and demSolveContacts), the gate lines, and any subset or stop reason.
At the end: demSolveContacts CCN, NLOC and debt, whether it is still a brain function, and dem's
brain count.
