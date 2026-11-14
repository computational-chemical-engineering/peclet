# WO-10 — pnm P1: phases out of `extract_pore_network_mpi` (gated refactor steps)

Read first: `docs/code_health/RULES.md` (pnm keep-out from A7), `pnm-health/.codehealth/playbook.md`,
`pnm-health/CLAUDE.md` (settled decisions). Work ONLY in `/home/frankp/Codes/suite/pnm-health`, branch
`code-health` (CB b65b4a2). Never push. Never touch `.codehealth/`, `tests/`, `cmake/`, `CMakeLists.txt`, and never
the pnm main checkout, `junction-law`, `suite/pnm-junction-law`, `suite/pnm-netflow-momentum`.

## Target and A7's conditions (session `pnm`, 11-14, binding)
`extract_pore_network_mpi` (src/pore_extraction_mpi.hpp:343): debt 47.2, CCN 37, NLOC 242, brain.
- A behaviour-preserving refactor is OK; A7 rebases (junction-law changes ~6 lines here: the `labels=` entry, and
  WO-D1p may hook a flood/scene segmentation option in).
- **Keep the parameter list unchanged and the segmentation-dispatch point recognizable** — it stays in
  `extract_pore_network_mpi` itself, not moved into a helper.
- NOT in scope (A7 is modifying them; wait for junction-law): `extract_network_flow_mpi`, `extract_network_flow_k`,
  `kernels::throatFlux`, every flow-mapping stage kernel, the `extract_network_flow(_mpi)` binding block.

## What one step is
Move ONE contiguous, named phase of `extract_pore_network_mpi` (e.g. the halo/ghost exchange set-up, the global
pore-id assignment, the throat assembly / gather) verbatim into an `inline` helper in the same header, so the
target heads out of brain (CCN ≤ 25 or NLOC ≤ 70) and no helper is a brain. Bodies token-identical (verify with a
script: moved block + caller remainder), kernel lambdas keep their captures, same launches/fences/MPI calls
(collectives, their order and their communicators) and the same rank-local ordering (the "local order is never
arrival order" class of trap applies here as in dem); ≤ 10 params per helper (unpack a struct into old names at
the top if needed). One phase per step.

## Loop (per step) — campaign pnm-p1
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
$CH gate --ref-base b65b4a2 --require-gain --json /tmp/claude-1003/wo10_step<N>.json > /tmp/claude-1003/wo10_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo10_step<N>.log
$CH log --gate-json /tmp/claude-1003/wo10_step<N>.json --campaign pnm-p1 --target src/pore_extraction_mpi.hpp::<qualified extract_pore_network_mpi> --recipe extract-kernel-phase
$CH scan | tail -1
```
PASS → commit exactly the gated tree (named paths), then log. FAIL → log; read only the failing tier in
`/tmp/codehealth-gate-pnm-health.log`; state_hash difference = not verbatim (find it; never touch numerics); two
failed attempts → `git checkout -- src/` and stop. Gates in the background; wait for the notification.

## Scope / stop
Up to TWO steps. Stop and report (do not decide) if the only phases that would get it out of brain contain the
segmentation dispatch, or would reorder MPI calls / launches / fences, or nvcc rejects a move.

## Report (≤ 20 lines)
Per step: sha, helper (name, CCN, NLOC, params, debt), LOG line verbatim, token check, tier times. Then pnm debt
+ brain at HEAD, the riskiest line, and the commit list for A7 (sha + one line each).
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
