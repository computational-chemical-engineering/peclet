# WO-1 — dem: retire the `*Kokkos` identifier suffix (bit-identical rename)

Read `docs/code_health/RULES.md` first. Work ONLY in `/home/frankp/Codes/suite/dem-health` (branch `code-health`).
Do not push. Do not touch any other repo or worktree.

## Why
Suite decision (docs/DECISIONS.md): "identifiers name what a thing is, never where it runs; 'device'/'Kokkos' are
banned qualifiers". dem's `src/` still has 97 distinct identifiers ending in `Kokkos` (list:
`grep -ohE "\b[a-zA-Z0-9_]+Kokkos\b" src/*.hpp src/*.cpp | sort -u`), e.g. `demSolveContacts` callees
`solveVelocityKokkos`, `buildContactHierarchyKokkos`, `hertzWallForcesKokkos`, `detectContactsKokkos`.

## What
Rename every such identifier to drop the `Kokkos` suffix, across `src/`, `tests/`, `examples/` and `docs/`
(comments and Markdown too), in ONE commit. Pure rename: no signature, order, logic, formatting-beyond-clang-format,
or numerics change.

Do NOT rename: anything from Kokkos itself (`Kokkos::...`, macros `KOKKOS_*`), CMake option/target names, file names,
the `PECLET_DEM_*` macros, Python-visible names (none expected — check `src/dem_bindings.cpp` `.def(...)` strings stay
unchanged). If an identifier's suffix is part of a Python-visible string, STOP and report.

## Known collisions (bare name already exists) — resolve as stated, or STOP if the case differs
Measured: 11 bare names already occur. Most are only in comments that already use the bare name (fine). Real ones:
- `Simulation::computeOverlaps` and `Simulation::restBankStats` (members, `src/sim.hpp`) vs free functions
  `computeOverlapsKokkos` / `restBankStatsKokkos`. Inside a member body an unqualified call to the renamed free
  function would bind to the member. Qualify such calls (`peclet::dem::computeOverlaps(...)` or `::peclet::dem::`)
  rather than renaming the member (the members back the Python API).
- `tests/kokkos_mpi/test_ownership_mpi.cpp:313` has a test-local `static void detectContacts(...)` (a host oracle).
  Rename THAT one to `detectContactsOracle` (test-local, host oracle per the suite convention), then rename the
  library function.
- `vertexDegree` is a View member of a particles struct (`src/particles.hpp:425`) and `vertexDegreeKokkos` a function:
  if both are visible in one scope and the rename makes a call ambiguous or shadowed, name the function
  `computeVertexDegree` instead. Report which choice you made.
For any other collision you find (compile error, shadowing, overload ambiguity): pick a name that says what the
thing IS, report it in your summary; if unsure, STOP and report.

## Gates (all must pass; quote the numbers)
Environment: `source /home/frankp/Codes/suite/.venv/bin/activate; export PECLET_SUITE=/home/frankp/Codes/suite`.
1. Reference BEFORE editing: `PYTHONPATH=$PWD/build_host:$PECLET_SUITE/core/build_health_py python
   tests/regression/state_hash.py --save /tmp/claude-1003/wo1_ref` (build_host is already built at e375b97+config;
   rebuild first with `cmake --build build_host -j32` if unsure).
2. After the rename: `cmake --build build_host -j32`, then `--check /tmp/claude-1003/wo1_ref` → every case identical,
   MPI cases included (no "mpi cases skipped").
3. `OMP_NUM_THREADS=1 OMP_PROC_BIND=false PYTHONPATH=$PECLET_SUITE/core/build_health_py ctest --test-dir build_host
   -LE bench --timeout 1200 > /tmp/claude-1003/wo1_ctest.log 2>&1` → 303/303, zero `***Skipped`.
4. CUDA compile: `PATH=/usr/local/cuda/bin:$PATH cmake --build build_health_cuda -j32` (already configured with tests
   + MPI) → success.
5. `clang-format --dry-run --Werror $(git ls-files 'src/*.hpp' 'src/*.cpp' 'tests/*.hpp' 'tests/*.cpp')` → clean
   (run `clang-format -i` on touched C++ files if line lengths changed).
6. `grep -rnE "\b[a-zA-Z0-9_]+Kokkos\b" src tests examples docs | grep -v "Kokkos::"` → empty, or every remaining hit
   justified in the report.
Run long things blind (log to file, one summary line). Never read a whole log.

## Deliverable
One commit on `code-health` (named paths only; message: what, the collision choices, the gate numbers; end with the
attribution lines from your instructions if any). Report ≤ 25 lines: commit sha, files touched, collisions and
choices, each gate's result with numbers.

## Out of scope
Any other cleanup, any refactor, docs rewording beyond the identifier, the gate config, pushing.
