# WO-17 — dem S8: solveVelocityColoredGS and hertzWallForces (Frank, Decision Desk B: "S8 on the top 2", architect-free with the S7 recipe)

You are the engineer for this round. There is no architect note: you plan the steps yourself, using
the recipes below, and you stop on anything that needs a design decision those recipes do not cover.

## Read first
1. `docs/code_health/RULES.md`, in the umbrella docs worktree
   `/home/frankp/Codes/suite/.claude/worktrees/suite-code-health`.
2. `docs/code_health/designs/dem-s7-design.md`: §5.4 (the codegen rules), §8 (the gates) and the
   Appendix (sass_gate.py).
3. The S7 entries of `docs/code_health/DECISIONS_LOG.md`, from "S7 A1" to the end. In particular:
   - the GCC FMA-contraction findings;
   - the PRE-REGISTERED **G-fma-env v2** (the last entry). Use it exactly as written; do not alter it.
4. `.codehealth/playbook.md` in the dem worktree: the recipes extract-kernel-phase,
   launch-params-struct, dedup-colouring, and the anti-patterns.
5. Briefs WO-13, WO-14 and WO-16: the scripts, the scenarios and the counting-build method.

## Targets (dem-health `code-health` HEAD after the S7 close; the session gives you the sha)
- `solveVelocityColoredGS` (src/solver_velocity.hpp:~1783): NLOC 131, CCN 31, 20 params.
- `hertzWallForces` (src/solver_hertz.hpp:180): NLOC 184, CCN 29, 24 params.
Both are host launchers. Their complexity sits in KOKKOS_LAMBDA bodies.

## Recipes allowed
1. **launch-params-struct (S2).** Group the inputs into structs passed by const&, then unpack them
   into the old names before any lambda, so the captures stay byte-identical. At most 10
   parameters per function.
2. **Device-helper extraction (S7).** Use `KOKKOS_INLINE_FUNCTION` helpers in the lambda body.
   Preserve the expression trees: no reassociation, keep early exits in place, no success-flag
   pattern.

## Gates per step
- G-host (`--require-gain`): bitwise, tool 93a36d8.
- G-sass: S0/S1 only.
- G-fma: bitwise. If that fails, G-fma-env v2 decides, and only when the tier is VALID.
- G-branch: on both builds.
- G-cuda and G-time (both benches; the S7 bench with 10 pairs) on every step that changes a
  kernel's SASS. Otherwise G-sass all S0 suffices for the device side.
- **Coverage first.** Before step 1, prove with a counting build that G-branch plus state_hash
  execute both targets' kernels (for example ≥ 1000 kernel-body executions per changed branch
  family). Add scenarios as WO-13 did if they do not; hertzWallForces needs Hertz particles against
  walls, with friction. If you cannot reach coverage, stop.

## Rules
- One commit per step. Log each one: `codehealth log --campaign dem-s8 --target <file::fn> --recipe
  <recipe>`. A failed step is logged as gate-fail and reset.
- Bisect a failing step once; land a passing subset only if it drops debt.
- Never push. Touch no other worktree except a detached base-side worktree of your own, which you
  remove at the end. GPU jobs run under the flock. At ~250k context, write a handoff to
  `scratchpad/s8/HANDOFF.md` and stop.

## Report (≤ 30 lines)
Per step: commit, debt (dem and the function), the gate lines (including the G-fma-env v2 table if
it was used). At the end: both functions' CCN, NLOC and debt, whether each is still a brain
function, and dem's brain count and debt.
