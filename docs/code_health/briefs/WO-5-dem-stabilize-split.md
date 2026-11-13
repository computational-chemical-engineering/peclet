# WO-5 — dem S4: split `stabilizeVelocityPhase` by mode; group the warm-start block (gated refactor steps)

Read first: `docs/code_health/RULES.md`, `dem-health/.codehealth/playbook.md` (07f9dc5), `dem-health/CLAUDE.md`
(settled decisions: staged symmetric + one-sided stabilization, K = 64, multilevel rigid 6-DOF aggregates, the
8·g·dt slip gate). Work ONLY in `/home/frankp/Codes/suite/dem-health`, branch `code-health` (HEAD d9e8aa8).
Never push. Never touch `.codehealth/`, `tests/`, `cmake/`, `CMakeLists.txt`.

## Why this round
S3 moved the velocity solve out of `demSolveContacts` (258.1 → 114.6), but step 2 relocated most of it:
`stabilizeVelocityPhase` (src/solve_driver.hpp) is a new brain function, debt 96.4, CCN 70, NLOC 304, and dem's
brain count rose 12 → 15 (health 5.49 → 4.98). This round must REMOVE complexity, not move it. The tool
(now c5ee4df → **00b1849**) prints `X% of it relocated` on the LOG line; a step that relocates ≥ 90 % without the
new helpers falling below the brain threshold (CCN ≤ 25 and NLOC ≤ 70) is not an acceptable step here.

## Targets, in order
1. `stabilizeVelocityPhase`: one-sided, multilevel, ordered and escalation modes plus the CUDA-only fused
   multilevel loop. If a runtime mode/flag selects disjoint branches: recipe split-flag-argument (+ table-dispatch
   if uniform): one helper per mode, the selection stays in a thin selector or in the caller, in the SAME order of
   tests as today. Each mode helper should land under the brain threshold; if a mode is itself too big, extract
   its own sub-phases in the same step only if they are contiguous and self-contained.
2. The warm-start / orphan-transfer block still inline in `demSolveContacts` (gather, scatterOrphanBanks with its
   gid-map KOKKOS_LAMBDA, warmStartApply, the openings). It runs before `VelocitySolveContext` is complete and
   needs ~12 inputs: give it its OWN small grouping (≤ 10 params after grouping), not the S3 context.

## Rules for every step (as WO-4, plus)
- Bodies move VERBATIM; helpers unpack struct members into locals with the old names at the top (`const auto& x =
  s.x;`), before any lambda. No `KOKKOS_LAMBDA`/functor body may name a struct. Grep each moved region for the
  struct variable names and for `KOKKOS_LAMBDA` and report both counts. A moved region containing a
  KOKKOS_LAMBDA (target 2 does): its captures must be the same names with the same types as before (a reference
  local captured `[=]` copies the View, which is what the old code did; state this per lambda in the report).
- Same launches/fences/MPI hook calls/`if constexpr`/`#ifdef KOKKOS_ENABLE_CUDA` blocks, in the same order;
  same atomics/reductions; same execution and memory space. Never alter a settled decision.
- The CUDA-only fused loop is not executed by the host gate. Keep it byte-identical inside whatever helper holds it.

## Loop (per step) — campaign dem-s4
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo5_step<N>.json > /tmp/claude-1003/wo5_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo5_step<N>.log
$CH log --gate-json /tmp/claude-1003/wo5_step<N>.json --campaign dem-s4 --target src/solve_driver.hpp::<qualified target> --recipe <split-flag-argument|table-dispatch|extract-kernel-phase|launch-params-struct>
```
`<qualified target>` = `peclet::dem::stabilizeVelocityPhase` for target 1, `peclet::dem::demSolveContacts` for target 2.
PASS → commit exactly the gated tree (named paths), then log. FAIL → log, read only the failing tier in
`/tmp/codehealth-gate-dem-health.log`; state_hash difference = not verbatim (find it, never touch numerics); two
failed attempts on one target → `git checkout -- src/` and stop. Gates in the background; wait for the notification.

## Scope
Up to THREE steps. Stop when target 1 and 2 are done or a stop condition holds.

## Stop and report (do not decide) when
- the modes are not disjoint (a later mode reads state an earlier one wrote in an interleaved way) so a split would
  reorder work;
- a split would change the order in which modes are tested or executed, or any launch/fence/MPI/atomic order;
- a lambda would capture differently, or nvcc rejects the change and the fix is not obvious.

## Report (≤ 30 lines)
Per step: sha, helpers created (name, CCN, NLOC, debt from `$CH scan`), LOG line verbatim (incl. relocated %),
struct/lambda grep counts, tier times. Then dem brain count and total debt at HEAD (`$CH scan | tail -1`), the
riskiest line, what you skipped and why.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
