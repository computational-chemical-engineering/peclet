# WO-6 — dem S4 continued: bring the brain count back to ≤ 12 (gated refactor steps)

Read first: `docs/code_health/RULES.md`, `dem-health/.codehealth/playbook.md`, `dem-health/CLAUDE.md` (settled
decisions). Work ONLY in `/home/frankp/Codes/suite/dem-health`, branch `code-health` (HEAD bab8b36). Never push.
Never touch `.codehealth/`, `tests/`, `cmake/`, `CMakeLists.txt`.

## Why
Milestone exit rule (STATE.md, pre-registered): S4 closes only with dem brain count ≤ 12 (CB value). At bab8b36 it
is **14**. A brain function (tool rule) has CCN > 25 AND NLOC > 70; getting EITHER under its limit removes it.
Two of the 14 are helpers this campaign created, and are the targets:

| function (src/solve_driver.hpp) | debt | CCN | NLOC | params |
|---|---|---|---|---|
| `solvePositionPhase` | 39.8 | 35 | 108 | 16 |
| `solveVelocityPhase` | 32.4 | 27 | 114 | 10 |

Stretch target (step 3 only if 1 and 2 are done): `demSolveContacts` (95.1, CCN 83, NLOC 281): one more
contiguous self-contained phase out, with the S3/S4 pattern.

## What one step is
One target: move ONE contiguous, self-contained sub-phase (e.g. the graph/fused sweep loop of the position phase,
the Jacobi or one-shot branch of the velocity loop) into an `inline` helper in the same header, so the target
drops below CCN 25 or NLOC 70 and the new helper is NOT itself a brain. Bodies VERBATIM (token-identical; verify
with your script as in WO-5), helpers unpack struct members into old names at the top, no `KOKKOS_LAMBDA`/functor
body names a struct, same launches/fences/MPI hook calls/`if constexpr`/`#ifdef` in the same order, same atomics,
same spaces. ≤ 10 params per new helper (group with an existing struct — `VelocitySolveContext`, `ColorSchedule`,
`WarmStartContext` — before inventing one). A step that leaves the brain count unchanged is not acceptable.

## Loop (per step) — campaign dem-s4 (continues)
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo6_step<N>.json > /tmp/claude-1003/wo6_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo6_step<N>.log
$CH log --gate-json /tmp/claude-1003/wo6_step<N>.json --campaign dem-s4 --target src/solve_driver.hpp::peclet::dem::<target> --recipe extract-kernel-phase
$CH scan | tail -1     # brain count after the step
```
PASS → commit exactly the gated tree (named paths), then log. FAIL → log, read only the failing tier in
`/tmp/codehealth-gate-dem-health.log`; state_hash difference = not verbatim (find it; never touch numerics); two
failed attempts on one target → `git checkout -- src/` and stop. Gates in the background; wait for the notification.

## Scope / stop
Up to THREE steps. Stop and report (do not decide) when a target has no contiguous self-contained sub-phase that
gets it under a limit, or when a split would reorder launches/fences/MPI/atomics or change a lambda's captures, or
nvcc rejects it and the fix is not obvious.

## Report (≤ 25 lines)
Per step: sha, helper (name, CCN, NLOC, params, debt), LOG line verbatim, grep counts, token check, brain count
after, tier times. Then total debt + brain at HEAD, riskiest line, what you skipped.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
