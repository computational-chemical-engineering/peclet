# WO-2 — dem S1: extract phases from `demSolveContacts` (gated refactor steps)

Read first: `docs/code_health/RULES.md`, then `dem-health/.codehealth/playbook.md` (rules, recipe
`extract-kernel-phase`, anti-patterns), then `dem-health/CLAUDE.md` (settled decisions). Work ONLY in
`/home/frankp/Codes/suite/dem-health`, branch `code-health`. Never push. Never touch `.codehealth/`, `tests/`,
`cmake/`, `CMakeLists.txt` (the gate rejects it).

## Target
`src/solve_driver.hpp:293` `peclet::dem::demSolveContacts` (template on `Hooks`, single-rank and distributed):
1160 lines, CCN 261, NLOC 912, debt 345 (the largest in dem; campaign base CB = 3fd9b93, dem debt 1871.8).
It interleaves: rank-level policy flags, colouring setup (velocity manifold graph, dense buckets, fused-sweep
setup), position colouring (units, incremental, buckets), the position projection, persistent-contact
restitution, the warm-started PGS velocity solve, rank-level M/X paths, event-level (Poisson) restitution,
velocity-phase copies. Comments cite `docs/contact_solve_framework.md` sections; keep every comment with its code.

## What one step is
Exactly one phase moved verbatim into an `inline` free function (or a static member of a private struct) in
the same header, called from the same place. Same launches in the same order, same fences, same Views, same
`if constexpr (Hooks::...)` branches, same MPI hook calls. Views by value; locals the caller still needs after
the call by reference (or returned). No renames of anything else, no logic edits, no comment rewording.
Name the function for what the phase does (no `Kokkos`/`Device`).

## Loop (per step)
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
# edit (uncommitted), then:
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo2_step<N>.json > /tmp/claude-1003/wo2_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo2_step<N>.log
```
The gate compares the working tree with HEAD (build, ctest 303, state_hash bitwise, CUDA compile, format).
- Log EVERY attempt: `$CH log --gate-json /tmp/claude-1003/wo2_step<N>.json --campaign dem-s1 --target src/solve_driver.hpp::peclet::dem::demSolveContacts --recipe extract-kernel-phase`
  (PASS: commit exactly the gated tree FIRST, then log; FAIL: log before resetting). A neutral step (no debt drop) is
  gated without --require-gain and logged with `--result accepted-neutral --reason "..."`.
- PASS → commit the step (named paths; message: phase moved, debt before→after from the gate line, "gate PASS").
- FAIL → read only the failing tier's lines in `/tmp/codehealth-gate-dem-health.log` (grep/tail). A state_hash
  difference means the move was not verbatim: find it; never "fix" by changing numerics. Format failure:
  `clang-format -i` the touched file. Two failed attempts on the same phase → `git checkout -- src/` and stop.
Run the gate blind in the background if your tooling allows; it takes ~10–30 min (cold base on the first step).

## Scope
Up to THREE steps (three phases), choosing the most self-contained phases first (suggested order: colouring
setup, position projection, PGS velocity solve). Stop earlier if the next phase cannot be moved without
violating a rule. Then stop.

## Stop and report (do not decide) when
- a phase shares mutable locals with the next phase so that moving it needs restructuring beyond pass-by-ref;
- moving it would change launch/fence/MPI order, colouring order, atomics/reductions, or execution/memory space;
- nvcc rejects the extracted function (build_cuda FAIL) and the fix is not obvious (e.g. needs a functor rewrite).

## Report (≤ 25 lines)
Per step: commit sha, function name and line range moved, gate line (debt before→after, PASS), tier times.
Plus: debt of `demSolveContacts` now, anything a reviewer should look at (the riskiest line), what you skipped and why.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
