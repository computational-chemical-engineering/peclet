# WO-4 — dem S3: the PGS velocity solve out of `demSolveContacts` (gated refactor steps)

Read first: `docs/code_health/RULES.md`, then `dem-health/.codehealth/playbook.md` (now at 07f9dc5: note the
extract-kernel-phase "when not 10+ inputs" and the long-parameter-helper anti-pattern), then `dem-health/CLAUDE.md`
(settled decisions). Work ONLY in `/home/frankp/Codes/suite/dem-health`, branch `code-health` (HEAD 07f9dc5).
Never push. Never touch `.codehealth/`, `tests/`, `cmake/`, `CMakeLists.txt`.

## Context
S1 moved the colouring phases and the position phase out (`colorVelocityPhase`, `colorPositionPhase`,
`solvePositionPhase`); S2 introduced `ColorSchedule`, `HertzMaterials`, `VelocityPhaseViews`.
`demSolveContacts` (src/solve_driver.hpp, ~line 606) is still debt 258.3, CCN 196. The remaining bulk is the
warm-started PGS velocity solve with its stabilisation, multilevel and Poisson (event-restitution) paths and the
rank-level M/X paths. S1 skipped it because ~30 locals (`foldVel`, `syncVel`, `velOv`, `bankV`, `velM`, ...) are
shared between those paths.

## The pattern for this round (decided; do not invent another)
1. Inventory first: list the locals the velocity-solve region reads/writes and which later code reads them.
   Put that table (name, type, written in region?, read after region?) at the top of your report.
2. Group them into ONE OR TWO private aggregates named for what they are (e.g. the velocity-phase solve state),
   declared in solve_driver.hpp:
   - Views that the region never reassigns: members BY VALUE.
   - Scalars/Views/vectors the region writes AND the caller reads afterwards: members as REFERENCES to the
     caller's locals (`int& x;`), built at the call site; the caller's locals stay exactly where they are.
   - The moved body starts by unpacking the members into locals/references with the OLD names
     (`auto& foldVel = s.foldVel;` / `const auto bankV = s.bankV;`), so the body moves VERBATIM and every
     `KOKKOS_LAMBDA` captures exactly what it captured before (never capture the struct, never `this`).
3. Extract by the recipe extract-kernel-phase: one phase per step, `inline` template on `Hooks` when it calls
   hooks, same `if constexpr` branches, same launches/fences/MPI hook calls in the same order.
   Suggested order: the warm-started PGS sweep loop first; then the stabilisation/multilevel path; then the
   Poisson event-restitution path — whichever proves self-contained. Any helper with >10 parameters after
   grouping means the grouping is wrong: regroup or stop.

## Loop (per step) — as WO-2/WO-3, campaign dem-s3
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth     # now c5ee4df: gate JSON has function_debt, LOG prints target_debt
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo4_step<N>.json > /tmp/claude-1003/wo4_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo4_step<N>.log
$CH log --gate-json /tmp/claude-1003/wo4_step<N>.json --campaign dem-s3 --target src/solve_driver.hpp::peclet::dem::demSolveContacts --recipe extract-kernel-phase
```
PASS → commit exactly the gated tree (named paths), then log. FAIL → log, read only the failing tier in
`/tmp/codehealth-gate-dem-health.log` (grep/tail); a state_hash difference = the move was not verbatim (find it;
never change numerics); two failed attempts on one phase → `git checkout -- src/` and stop. Run gates in the
background and wait for the completion notification (no polling).

## Scope
Up to THREE steps. Stop earlier if the next phase cannot move under the pattern above.

## Stop and report (do not decide) when
- a local is written in the region AND in a later, non-moved region in an interleaved way (not a simple
  "write in region, read after");
- the move would change launch/fence/MPI order, colouring/sweep order, atomics/reductions, execution/memory space;
- a lambda would have to capture differently, or nvcc rejects the change and the fix is not obvious;
- any settled decision in dem CLAUDE.md would be touched.

## Report (≤ 30 lines)
The inventory table (compact), then per step: sha, function + line range moved, struct(s) and fields, gate line,
LOG target_debt before→after and new_in_file, tier times. Plus: demSolveContacts debt now, the riskiest line,
what you skipped and why.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
