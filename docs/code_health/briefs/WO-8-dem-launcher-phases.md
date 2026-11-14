# WO-8 — dem S6: phase extraction in the long launchers (gated refactor steps)

Read first: `docs/code_health/RULES.md`, `dem-health/.codehealth/playbook.md` (recipes extract-kernel-phase,
functor-from-lambda; anti-patterns "Debt by lambda shuffling", "phase helper with a parameter list as long as
the phase"), `dem-health/CLAUDE.md` (settled decisions; multilevel coarse bodies are rigid 6-DOF aggregates, the
8·g·dt slip gate). Work ONLY in `/home/frankp/Codes/suite/dem-health`, branch `code-health` (HEAD ba64656, S5
closed). Never push. Never touch `.codehealth/`, `tests/`, `cmake/`, `CMakeLists.txt`.

## Targets (brain functions at ba64656, host launchers that contain several kernels)
| function | file | debt | CCN | NLOC | params |
|---|---|---|---|---|---|
| `buildContactHierarchy` | src/solver_multilevel.hpp:347 | 86.1 | 65 | 241 | 19 |
| `generateSdf` | src/output_sdf.hpp:29 | 66.5 | 53 | 165 | 16 |
| `hertzWallForces` | src/solver_hertz.hpp:180 | 49.4 | 29 | 184 | 24 |
Out of scope: `PGSManifoldSweep::solveOne` (device inner loop), `demSolveContacts` (parked design item), the
`*Incremental` colouring pair (declined in S5).

## What one step is
One target → its body read as a sequence of phases (a host loop, a kernel launch, a scan, a reduction) and ONE OR
MORE contiguous phases moved verbatim into `inline` helpers in the same header, so the target drops out of brain
(CCN ≤ 25 or NLOC ≤ 70) and no new helper is a brain. A phase is a meaningful unit with a name (e.g. "aggregate
bodies into coarse vertices", "per-wall closest-point pass"), never "the second half": a helper that is one
`parallel_for` with its lambda and nothing else is lambda shuffling unless the name explains the kernel better than
the old comment did — say which in the report. Bodies token-identical (verify with a script as in WO-5/6); kernel
lambdas keep their captures (same names, same types, by value); same launches/fences/atomics/reductions in the
same order; same spaces; ≤ 10 params per helper (group with an existing struct, e.g. `HertzMaterials`, before
making a new one); defaults reproduced exactly. One target per step.

## Loop (per step) — campaign dem-s6
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo8_step<N>.json > /tmp/claude-1003/wo8_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo8_step<N>.log
$CH log --gate-json /tmp/claude-1003/wo8_step<N>.json --campaign dem-s6 --target <file>::peclet::dem::<target> --recipe extract-kernel-phase
$CH scan | tail -1
```
PASS → commit exactly the gated tree (named paths), then log. FAIL → log; read only the failing tier in
`/tmp/codehealth-gate-dem-health.log`; a state_hash difference = not verbatim (find it; never touch numerics); two
failed attempts on one target → `git checkout -- src/` and stop. Gates in the background; wait for the notification.
The orchestrator runs the CUDA device check and GPU timing after the round — leave the GPU alone.

## Scope / stop
Up to THREE steps (one per target, in the table's order). Stop and report (do not decide) when a target has no
contiguous meaningful phase that gets it out of brain without a >10-param helper, when a move would reorder
launches/fences/atomics or change a capture, or when nvcc rejects it and the fix is not obvious.

## Report (≤ 25 lines)
Per step: sha, helpers (name, CCN, NLOC, params, debt), LOG line verbatim (incl. relocated %), token check,
lambda-shuffling verdict, brain after, tier times. Then total debt + brain at HEAD, the riskiest line, skipped.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
