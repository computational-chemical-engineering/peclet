# WO-7 — dem S5: dedup the colouring routines (gated refactor steps)

Read first: `docs/code_health/RULES.md`, `dem-health/.codehealth/playbook.md` (recipe **dedup-colouring**, its
"when not"), `dem-health/CLAUDE.md` (settled: colourings never exceed 64 colours, hubs get local copies;
`set_incremental_coloring(False)` CHANGES results because the colouring fixes the Gauss–Seidel order). Work ONLY
in `/home/frankp/Codes/suite/dem-health`, branch `code-health` (HEAD de67b0b, S4 closed). Never push. Never touch
`.codehealth/`, `tests/`, `cmake/`, `CMakeLists.txt`.

## Targets (4 of dem's 12 brain functions; scan at de67b0b)
| function | file | debt | CCN | NLOC |
|---|---|---|---|---|
| `colorManifoldsIncremental` | src/solver_velocity.hpp:458 | 44.5 | 39 | 135 |
| `colorContactsIncremental` | src/solver_position.hpp:298 | 41.8 | 36 | 138 |
| `colorManifolds` | src/solver_velocity.hpp:323 | 30.4 | 30 | 104 |
| `colorContacts` | src/solver_position.hpp:180 | 24.6 | 26 | 96 |
Both files carry the `duplication` smell. The velocity routines colour manifolds (body pairs); the position
routines colour position units (whole contact pairs / units).

## Step 0 — analysis before any edit (in your report, ≤ 12 lines)
Diff each pair (full vs full, incremental vs incremental) and classify every difference: edge source / key
accessor; iteration order; tie-breaking; colour-cap (64) and hub-copy handling; sleeping masks; kernel launch
sequence and execution space; atomics. The recipe applies ONLY if the pair differs in the edge source/key (and
things expressible as a compile-time accessor). If they differ in iteration order, tie-breaking or cap handling:
STOP and report the table — do not edit.

## What one step is
One pair → one shared helper template parameterized by an edge accessor that is a COMPILE-TIME type (a small
struct with `KOKKOS_INLINE_FUNCTION` members holding Views by value), never a runtime flag, function pointer or
virtual call: the generated device code must be the same work in the same order. Both old functions remain as thin
wrappers with their EXACT current signatures (call sites, Python-reachable paths and tests unchanged), calling the
helper. Same kernels, same launch order, same atomics and reductions (type, order), same fences, same spaces, the
64-colour cap and hub copies exactly as now. No other edits.

## Loop (per step) — campaign dem-s5
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo7_step<N>.json > /tmp/claude-1003/wo7_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo7_step<N>.log
$CH log --gate-json /tmp/claude-1003/wo7_step<N>.json --campaign dem-s5 --target <file>::peclet::dem::<the larger of the pair> --recipe dedup-colouring
$CH scan | tail -1
```
state_hash bitwise equal is the proof that the colourings (hence the GS order) are unchanged at one thread; the
python battery covers `coloring_conflicts()`. PASS → commit exactly the gated tree (named paths), then log. FAIL →
log; read only the failing tier; a state_hash difference means the colouring changed — find it, never accept it;
two failed attempts on one pair → `git checkout -- src/` and stop. Gates in the background; wait for the notification.

## Scope
Up to THREE steps: the incremental pair, the full pair, and (only if natural) a shared piece both helpers use.
Brain count after the round must be ≤ 12 and should fall.

## Stop and report (do not decide) when
- step 0 finds a non-accessor difference (above);
- a shared helper would need a runtime branch inside a kernel;
- nvcc rejects the accessor and the fix is not obvious.
The orchestrator runs the CUDA device check and a GPU timing comparison (bench) after the round — leave the GPU alone.

## Report (≤ 30 lines)
Step-0 table; per step: sha, helper + accessor names, wrappers kept, LOG line verbatim, tier times, brain after.
Then total debt + brain at HEAD, the riskiest line, what you skipped.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
