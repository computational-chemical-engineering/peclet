# WO-3 — dem S2: parameter objects for the long launchers (gated refactor steps)

Read first: `docs/code_health/RULES.md`, then `dem-health/.codehealth/playbook.md` (rules, recipe
`launch-params-struct`, anti-patterns "Defaulted-argument drift", "Public surface change", "Grab-bag helper"
in the seed), then `dem-health/CLAUDE.md` (settled decisions). Work ONLY in `/home/frankp/Codes/suite/dem-health`,
branch `code-health` (HEAD 913d709 after S1). Never push. Never touch `.codehealth/`, `tests/`, `cmake/`,
`CMakeLists.txt` (the gate rejects it).

## Targets (pick by evidence, largest first)
1. `src/solve_driver.hpp:457` `solvePositionPhase` (19 params, brain function, debt 43.1), made in S1.
2. The Kokkos launchers with 14–33 parameters (`codehealth scan` / `hotspots` lists them). Pick the ones
   where the SAME group of 4+ Views/scalars travels through 2+ functions and forms one concept (body state,
   manifold arrays, PGS accumulators, position-phase context).

## What one step is
One concept → one private aggregate `struct` in the header that owns the concept (or a shared private header
already in `src/`), holding Views BY VALUE (trivially copyable; captured by value into device lambdas — never
capture the struct through `this` or by reference in a `KOKKOS_LAMBDA`; unpack to locals first if the lambda
used the old parameters directly, so captures stay exactly as before). Replace that group in every function
and call site that carries it, in one step. Defaults: if any old parameter had a default argument, the member
default must reproduce it exactly. No renames of anything else, no logic edits, no reordering of launches,
fences, atomics or MPI calls; same execution and memory space. Name the struct for what it is (no
`Kokkos`/`Device`, no `Params2`/`Ctx` grab-bags covering unrelated fields).

## Loop (per step) — as WO-2
```bash
source /home/frankp/Codes/suite/.venv/bin/activate
export PECLET_SUITE=/home/frankp/Codes/suite
CH=~/.venvs/codehealth/bin/codehealth
$CH gate --ref-base 3fd9b93 --require-gain --json /tmp/claude-1003/wo3_step<N>.json > /tmp/claude-1003/wo3_step<N>.log 2>&1; echo rc=$?
tail -16 /tmp/claude-1003/wo3_step<N>.log
```
Log EVERY attempt: `$CH log --gate-json /tmp/claude-1003/wo3_step<N>.json --campaign dem-s2 --target <file>::<qualified function> --recipe launch-params-struct`
(PASS: commit exactly the gated tree FIRST, then log; FAIL: log before resetting). Commit message: struct
introduced, functions re-signed, debt before→after from the gate line, "gate PASS". FAIL handling as WO-2:
read only the failing tier's lines in `/tmp/codehealth-gate-dem-health.log`; a state_hash difference means the
change was not inert — find it, never touch numerics; two failed attempts on the same target → `git checkout -- src/` and stop.
Also report the FUNCTION-level debt before/after for each target (`$CH scan` at HEAD), since the gate line is per file.

## Scope
Up to THREE steps. Stop earlier if the next candidate group is used by one function only (recipe "when not").

## Stop and report (do not decide) when
- a launcher you would re-sign is called from `tests/` or reachable from `src/dem_bindings.cpp` (public surface);
- the group's members live in different memory spaces, or a lambda would need to capture the struct differently;
- nvcc rejects the change (build_cuda FAIL) and the fix is not obvious;
- the "concept" needs a judgement call about what belongs together that the recipe does not settle.

## Report (≤ 25 lines)
Per step: commit sha, struct name + fields, functions re-signed, gate line (file debt), function debt
before→after, tier times. Plus: the riskiest line for a reviewer, what you skipped and why.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
