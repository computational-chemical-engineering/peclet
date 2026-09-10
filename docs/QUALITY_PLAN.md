# Suite quality plan — making 1.0.0 the foundation

> Status: **active work list**, opened 2026-09-08 after a read-only audit of all seven repos
> (six audit passes: flow, dem, voro, core, pnm+coupling+morton, cross-cutting). Every finding
> below cites a path. Items marked **DONE** were executed the same day; the rest are ordered
> work packages with an effort estimate. This file supersedes the "additive, never breaking"
> rule of [NAMING.md](NAMING.md) §0 for the one release that becomes 1.0.0 (decisions D1, D9).

## 0. Is the next release (planned as 0.8.0) ready?

**Mechanically, yes. As a foundation, no.** The release workflow is proven (0.7.0–0.7.2 shipped
2026-09-05/06), every test matrix is green on host and CUDA, and `tools/release/check_release_state.sh`
flags only the expected pre-tag version bumps. What the audit found is not broken code but
accumulated shape: the same concept spelled two ways in every API, instruments shipped beside
physics, campaign notes standing in for documentation, CI that is green because tests skip
themselves, and a "shared core" that is 56 % a second flow solver. Releasing from this
state would bake all of that into the first version with a physical-units API — the version
every later script will be written against.

The recommendation is therefore: **the next release is the clean-break release, and because it
breaks every API it is 1.0.0** — family and every package (decision D9). Do work packages A–D
(one spelling per concept, dead code and artefacts out, versions single-sourced, CI honest)
before tagging; ship E–H (the structural refactors) across 1.x under the alias ladder.

## 1. Decisions

- **D1 — Clean break at 1.0.0.** There are no external users. Every non-canonical spelling is
  *removed*, not aliased; keyword arguments are renamed outright. The CHANGELOG lists every
  removal with its replacement. NAMING.md §0's alias ladder is suspended for this one release
  and becomes binding from 1.0.0 on, and NAMING.md says so.
- **D2 — Two tiers of Python API.** *Public*: what a user of the method needs (flow single-phase
  ≈ 35 methods, VoF ≈ 65 of today's 266). *Diagnostics*: instruments, ablations, timers, census
  calls, test hooks — bound under a `diagnostics` sub-object (`solver.diagnostics.wall_area_probe()`)
  or an underscore prefix, excluded from the API pages. Retired modes are deleted, not kept
  "unreachable".
- **D3 — No environment variable changes numerics.** An env var may switch logging or
  profiling. Anything that changes a result (flow: 8 of 30 `getenv` sites; dem: 16 constructor and
  step knobs; core: `PECLET_CORE_GPS_*`) becomes an explicit setter or is deleted. Function-static
  first-call caches go with them.
- **D4 — One version source per repo.** `pyproject.toml` is the source; CMake `project(VERSION)`,
  `packaging/pyproject-cuda.toml`, `CITATION.cff`, Doxyfile and the consumers' `PECLET_*_TAG` derive
  from or are checked against it by the pre-flight script, which becomes step 1 of every `release.yml`.
- **D5 — CI tests what it claims.** A test that cannot run in a configuration is *skipped* by
  ctest (`SKIP_RETURN_CODE`), never silently green. The MPI suites (flow 103, dem 24, voro 18, pnm 6
  ctests) run at np=1,2,4 somewhere in CI. coupling gets a CI.
- **D6 — core is infrastructure; AMR is preserved, as its own package.** AMR is under active
  development and nothing of it is deleted. The whole `core/include/peclet/core/amr/` tree — the
  Navier–Stokes solver AND the octree infrastructure under it — is *relocated with its history*
  into a new eighth package, **`peclet-amr`** (`peclet.amr`), which depends on `peclet-core` and on
  nothing else in the suite. The released core is then decomposition, halo, geometry and load
  balancing: the layer the method codes actually use. (Maintainer, 2026-09-08: "AMR is being
  developed. So, do not throw it away. You might move things to a development branch."; decision
  refined 2026-09-10 after the dependency audit in G.2.)
- **D7 — Docs describe the code that exists.** Campaign notes move to `archive/`; INTERFACES.md's
  six unrealised concepts are either implemented as `concepts.hpp` with `static_assert`s or the
  file is rewritten as the duck-typed contract; STYLE.md's namespace and CI sections are corrected.
- **D9 — 1.0.0, then semver.** An API-breaking release is a major release: the clean break
  ships as peclet 1.0.0 with every package at 1.0.0 (RELEASE.md's bump table is rewritten
  accordingly at tag time). After 1.0.0 a breaking change needs a major bump, which is what makes
  the alias ladder worth its cost.
- **D8 — Old identifiers go.** `transport_core`/`tpx_*`/`PECLET_TPX_TAG`, `sdflow`, `vorflow`,
  `mortonarith`, `DEM_MPI`: renamed in CMake, `.gitmodules`, docs and CI in one pass.

## 2. The rename table (D1, applied at 1.0.0)

| module | removed | use instead |
|---|---|---|
| flow | `get_spacing()`, `get_resolution()`, `global_resolution()` | `spacing`, `cells`, `global_cells` (`get_ox/oy/oz` are the openness *fields*, not origin accessors — they stay, with real docstrings) |
| flow | `cell_centres()`, `scene_instance_count()`, `vof_block_colour()` | `cell_centers()`, `num_scene_instances()`, `vof_block_color()` |
| flow | `set_velocity_streams()` (a no-op) | — |
| flow | `set_solid(…, pressure_coarse=)` (commented-out parameter shown in docs) | drop from docs |
| dem | `initialize()` (different defaults from `initialize_shape`) | `initialize_shape(...)` |
| dem | `enable_periodicity(x,y,z)`, `pbc_enabled` | `set_periodic(x,y,z)`, `periodic` |
| dem | `get_domain_min()/get_domain_max()`, positional `set_domain(lx,ly,lz,px,py,pz)` | `origin`, `origin + extent`, `set_domain(extent=, origin=, periodic=)` |
| dem | `get_num_contacts()/get_num_manifolds()/get_max_overlap()` | `num_contacts`, `num_manifolds`, `max_overlap` |
| voro | `set_box(L)` on `Tessellation`/`Simulation`; `step(n, dt)`'s `dt` | `set_domain(extent=)`; `set_dt(dt)` + `step(n)` |
| voro | `sphere_centres=` kwarg | `sphere_centers=` |
| pnm | `extract_topology_gpu(shape=)` | `extract_topology(shape_zyx=)` |
| coupling | `CfdDem(smooth_width=, h=)` | `smooth_length=`; the spacing comes from the flow solver |
| coupling | `ResolvedCfdDem(rho_f=, periodic=bool, move=)` | `rho=`, `periodic=(bx,by,bz)`, `move_particles=` (same words as `CfdDem`) |
| core | `Octree(brick=)`, `h0` | `Octree(cells=)`, `spacing` |
| core | `Migrator(origin, size, gsize)`, class names `Migrator`/`Halo` | `ParticleMigrator(origin, extent, cells)`, `ParticleHalo` |

Everything in NAMING.md §2 marked *aliased* is in this table; the table in NAMING.md is updated to
*removed 1.0.0* as each lands.

## 3. Work packages

Effort: S < 1 day · M 1–3 days · L > 3 days. "Breaking" = Python API changes.

### A. One spelling per concept (S–M per repo, breaking) — **the 1.0.0 gate**

**DONE 2026-09-08** in all seven repos (A.1–A.4; NAMING.md §2 = the record); the gallery sources are
rewritten (peclet-examples 948173d, 2f75f39, 282534b — not pushed, not re-rendered: that needs the 1.0.0 wheels).

1. Apply §2 in `flow/src/flow_bindings.cpp`, `dem/src/dem_bindings.cpp`, `voro/src/voro_bindings.cpp`,
   `pnm/src/pnm_bindings.cpp`, `coupling/python/peclet_coupling/{driver,resolved}.py`,
   `core/python/{amr,mpi}_bindings.cpp`; update every in-suite caller (scripts, tests, README,
   CLAUDE.md) and the `peclet-examples` gallery pages; rebuild host modules and run each repo's
   test battery.
2. coupling: one `eps_min` default (driver 0.25 / binding 0.2 / README 0.4 today), drop
   `_coupling` from `__all__`, drop duplicate drag-name aliases (`bvk`/`beetstra`, `bvk2`/`tang`).
3. voro: unify getters (`Tess.volumes()` vs `Sim.get_volumes()` vs `Flow.get_cell_volume()`,
   `kinetic_energy()` vs `get_kinetic_energy()`, `neighbor_counts()` vs `get_num_neighbors()`)
   per NAMING §1.2; docstrings on the 11 undocumented `FlowSolver` methods.
4. core: `geom` added to `__all__`; regenerate `.pyi` stubs with nanobind's stubgen for all
   three modules (the tracked `core_amr.pyi` misses ≥ 9 members; `mpi`/`geom` have none); flow's
   tracked `sdflow.pyi` (pybind11-era, 37 of 266 members) is deleted and replaced the same way.

### B. Dead code and artefacts out (S per repo, not breaking)

**DONE 2026-09-08** for every row of the table below except the umbrella "move out" items (the
maintainer's own files, listed not moved) and the worktree prune; the dem script *sort* and flow's
`tests/study` move are still open (the dem agent's move-where list is in commit `b9a9b17`'s report).

| repo | delete / untrack | why |
|---|---|---|
| flow | `doc/1-s2.0-S0010465523004113-main.pdf` (5.5 MB) | third-party Elsevier paper in a public repo |
| flow | `output/*.png`, `notebooks/output/*.png` (14 files), `build_project.sh` (bare `cmake ..`, cannot work), `codebase_to_text.py`, `sdflow.pyi`, `cfd_utils/` (not installed, not in the wheel) | artefacts and scratch, some already in `.gitignore` |
| flow | `tests/cuda_bench/bench_rbgs.cu` + its `LANGUAGES CXX CUDA` CMake | raw CUDA after "CUDA retired"; `CUDA_ARCHITECTURES 120` hard-coded |
| dem | `verify_output.txt` (2.5 MB, 44 % of tracked bytes), `stacking_test.vtp`, `test.vtp`, `.vscode/`, `activate_env.sh`, `requirements.txt` | artefacts; the venv is the suite's |
| dem | `mpi/` C++ harness (includes `core/include/tpx/...`, gone), `mpi/test_device_halo.cu`, `tests/test_periodicity_corner.cpp` (includes a non-existent `simulation.h`), 0-byte `tests/inspect_vti.py`, `tests/generate_dense_packing.py`, byte-identical `tests/test_hollow_cylinder_overlap{,_2}.py`, `python/{simulation_script,visualizer}.py` ("placeholder") | provably dead |
| dem | root `debug_*.py`, `diag_*.py`, `phase{0,1,2}_*.py`, `verify_packing_hollow_cylinders_test.py`, `tests/debug_*.py`, `tests/convergence_test.py`, `tests/study_sphere_packing.py`, `tests/verify_sdf_{sphere,cylinder,cylinder_highres}.py`, `tests/verify_vti_periodic.py`, `tests/verify_cylinders.py`, `tests/verify_flexible.py` | one-off investigations (Dec-2025 … Jun-2026) |
| voro | `include/peclet/voro/voronoi.zip` (the retired half-edge engine, *installed* by `install(DIRECTORY include/)`), `docs/__pycache__/*.pyc`, `docs/create_document.py`, `docs/Doxyfile` (never read), `physics/interface.hpp` (zero callers), `extern_bench/` | retired / orphaned |
| morton | `legacy/` (no target, not included; needs C++20 in a C++17 library), `third_party/libmorton_morton.h` (byte-identical duplicate) | history lives in git |
| core | `python/build_td_*.log`; decide `docs/data/*.log` (31 campaign logs, cited by the AMR notes → move with them to `docs/archive/data/`) | |
| coupling | `build_td_*.log` ×4; add `*.log` to `.gitignore` | |
| umbrella | `full.log`; `.gitignore` the `flow-*`/`tel/` worktrees and `*.log`; **move out** `69503dc29254db50bfdf4f41/` (a paper's LaTeX repo), `.sdf-campaign-probes/` (→ `flow/tests/study/`); prune the 13 merged flow worktrees (~12 GB) once their sessions close. **DONE 2026-09-08:** `sphere-cfd-validation/` (its own git repo) and `proposal/` moved to `~/Codes/`; voro's PR-required branch protection removed so all eight repos have the same (none); `morton/octree/` removed, its 151-line std::map octree kept as core's test-local oracle (`core/tests/oracle/`) | |

Also in B: dem's remaining root scripts are *sorted*, not deleted — assert-bearing ones
(`test_hertz.py`, `test_hertz_shapes.py`, `test_pair_materials.py`, `test_cone_friction.py`,
`test_colored_gs.py`, `tests/verify_{sdf_particle,rotating_drum,restitution}.py`,
`mpi/validate_*.py`, `mpi/verify_*.py`) become `tests/python/test_*.py` under pytest; demos
(`verify_packing_*.py`, `verify_collision_*.py`, `verify_stacking*.py`, `pack*.py`,
`generate_particles.py`) go to `examples/`. flow's `tests/study/` (76 files, 1.4 MB JSON, two
absolute `/home/frankp/...` paths) moves to `studies/` or peclet-examples.

### C. One version source, old identifiers gone (S, CMake-breaking only)

**DONE 2026-09-08**: C.1 (CMake reads pyproject in all seven; the pre-flight flags a drifting literal and
morton's vcpkg manifest), C.2 (`peclet_core`/`peclet::core`, `PECLET_CORE_TAG`/`PECLET_CORE_DIR`/
`PECLET_CORE_INCLUDE`, `peclet_flow`, vorflow/mortonarith gone; `.gitmodules` names still `transport-core`/
`sdflow`/`vorflow` — cosmetic, open), C.4, C.5. **Open:** C.3 (one shared cmake module; today the
pnm/dem/voro/coupling `PecletDeps.cmake` are byte-identical and flow's differs only by its sibling-override block).

1. CMake reads the version from `pyproject.toml` (`file(STRINGS … REGEX "^version")`) in every
   repo; fixes morton (`VERSION 0.1.0` vs pyproject 0.2.1; conan/vcpkg 0.1.0 too) and voro
   (`VERSION 1.0.0`). `check_release_state.sh` gains `--ci` and runs first in every `release.yml`.
2. `project(transport_core)` → `peclet_core`; targets `tpx_core`/`tpx::core`/`tpx_halo` →
   `peclet_core`/`peclet::core`/`peclet::halo`; `PECLET_TPX_TAG` → `PECLET_CORE_TAG`; flow target
   `sdflow` → `peclet_flow`; `.gitmodules` names `transport-core`/`sdflow`/`vorflow` → `core`/`flow`/`voro`;
   voro's `add_vorflow_kokkos_test`, `VORFLOW_*`, `project(vorflow_mpi_tests)`; morton's
   `morton_arithmetic`/`libmortonarith_c`/`mortonarith`; dem's `-DDEM_MPI` in README and CI.
3. `cmake/PecletDeps.cmake` (five hand-synced copies, already diverged: flow's has the
   `PECLET_SIBLING_*` override) and `SuiteNanobind.cmake` (two copies) come from one place — a
   `peclet-cmake` FetchContent or the core sdist — with a byte-identity check in the pre-flight.
4. voro `CMAKE_CXX_STANDARD 17` → 20 (every target already forces 20); core
   `python/CMakeLists.txt` mpi bindings 17 → 20; `add_compile_options(-Wno-…)` blanket in voro removed.
5. coupling `pyproject` sibling floors `peclet-flow>=0.3.0`, `peclet-dem>=0.3.2` → the 1.0.0 numbers.

### D. CI that is honest (M, not breaking)

**pnm DONE 2026-09-08** (`ec646c8`…`72cf6f4`): 0 → 9 registered ctests (single-rank contract with
hand-derived counts, determinism, Python smoke, the 7199-pore gate that SKIPS without the data file,
MPI np=1,2,4), CI runs them all (39 s + 74 s with the Kokkos cache), blocking clang-format after one
reformat commit.

**dem DONE 2026-09-08** (`5bb9bfd`, `edf07dc`, `8124d57`): three standalone test trees (8 + 2 + 24)
and unregistered Python scripts → one tree: `-DPECLET_DEM_BUILD_TESTS=ON` registers 11 (kokkos +
arborx + pytest), `+ -DPECLET_DEM_MPI=ON` 47 (+24 kokkos_mpi, +12 Python MPI at np=1,2,4); every test
`SKIP_RETURN_CODE 77`, MPI ones labelled `mpi` with `PROCESSORS`. The 34 root-level scripts sorted:
13 → `tests/python/test_*.py`, 4 → `tests/python/mpi/`, 17 → `examples/` (all smoke-run); the statics
battery cut 96k→1.7k grains, the drum ω 2→0.5 (ω=2 was centrifuging). CI: `single-rank` 2 m 47 s
(also configures against the default `PECLET_CORE_TAG` as the stale-pin check) + `mpi` 3 m 17 s
(np=1,2,4 oversubscribed) + Quality 9 s; clang-format blocking after one reformat (375 violations,
20 files); `.clang-tidy` = voro's; artifact actions v7/v8. Findings: `tests/arborx` had bit-rotted
(fixed); the MPI scripts were dead against the current API (ported); three legacy scripts "passed"
while printing FAILURE (velocity solve is off by default, no default gravity, the `(N,4)` w column is
the inverse mass — recorded in dem's CLAUDE.md); `docs/mpi.md`'s "np=2/4 differ by float noise" is
false on the stiff random IC (per-particle max 0.11, even np=1 at 2 threads gives 0.08 — asserted as
measured). **Open numerics finding (not D):** single-rank periodic wrap contacts whose far partner
sits more than one radius beyond the face are resolved one-sidedly (`sim.hpp` `ghostBand = maxRad`);
the MPI step is symmetric. Fix under G.4.

**core DONE 2026-09-08** (`69d6b0f`, `3ccf838`, `f3a2a34`, `6bd091d`): every morton-guarded binary (49 +
4 studies + `bench_amr_flow`) exits 77 through one registration helper (`cmake/PecletCoreTest.cmake`,
labels `mpi`/`np8`/`bench`/`python`); `tests/python` registered (7 ctests: `test_mpi.py` np=1,2,4,8,
`test_amr.py` serial + np=2, ndarray interop); 104 → 109 plain, 158 → 164 Kokkos, 0 → 7 Python. CI:
gcc/clang × Debug/Release with morton v0.2.1 checked out beside it (nothing skipped), Kokkos-OpenMP
+ MPI np=1,2,4 + the Python modules (15 min), a no-MPI stub job, Quality with blocking clang-format
(one 60-file reformat, token-stream verified identical; `amr/` excluded from the check until the AMR
branch lands — 19 of 35 AMR headers still differ). Findings: the Python MPI ctests had been running N
singletons (ParaView's `mpiexec` cached — the CLAUDE.md trap; now pinned by
`cmake/PecletCorePinMpiexec.cmake` and the scripts fail when `comm.size != PECLET_CORE_TEST_NP`); a
rank exiting 77 before `MPI_Init` aborts prterun (Open MPI 5) → `tests/test_skip_mpi.hpp` inits
first; the old CI matrix had no gcc job (`include:` overwrote the axis). `PECLET_CORE_BUILD_TESTS`
stays default ON (the wheel builds from `python/`, not the root).

**voro DONE 2026-09-08** (`1cbf005`, `a487777`): one tree (`-DPECLET_VORO_BUILD_TESTS=ON`, default OFF)
registers 24 + 18 MPI = 42 (`tests/kokkos_mpi` folded in, standalone form kept); the 10 `bench_*`
binaries + the Voro++ fetch opt-in under `PECLET_VORO_BUILD_BENCHMARKS` (Voro++ pinned to commit
`b0dac575` — its only tag, v0.4.6 of 2013, predates its CMake); warnings 622 → 145 (all 51 in
`include/` fixed; the 120 left are morton's `__int128` `-Wpedantic`, 25 in `tests/`); CI runs all
single-rank tests (`-LE bench`, 2 threads) + a new `mpi` job np=1,2,4 (3 m 55 s) + a configure
against the pinned sibling tags (`PECLET_VENDOR_SIBLINGS=ON`) + `quality.yml` with blocking
clang-format after one 20-file reformat. **Silent-green trap closed:** `find_package(MPI)` took
ParaView's MPICH `mpiexec` while linking OpenMPI, so every np=N test ran N singletons and "agreed"
with single-rank trivially (same trap as core's Python tree); the launcher now comes from beside
`MPI_CXX_COMPILER` and the binaries fail when the communicator size ≠ `PECLET_VORO_EXPECT_NP`.
**Honestly red, then fixed the same day** (`9ce81c8`, `ce698c1`): `test_sdf_curved` (never in the old
7-test regex) failed in CI with cavity sagitta 2.311e-4 vs the 2e-4 gate, and the wall-facet count
varied run to run at fixed threads. Root cause = two silent caps in the cold build whose victims are
chosen by the OpenMP order of the atomic scatter slot: `ConvexCell::clip` counted every committed
plane (including ones later made redundant) against `MAXP` and published a zero-volume cell at the
cap (one 29-face cavity cell = the whole missing volume), and the facet over-buffer sized at the
Poisson–Voronoi mean silently published `facetCount = 0` for the 400–600 cells that finished last.
Fix: compact the plane set at the cap, overflow only on live planes; exact-demand reserve with one
re-run at the measured size. Sagitta 4.3e-7 with identical facet counts at 1/2/4/8 threads (3 runs
each), 42/42, gate unchanged. `test_sdf_dynamic`'s tol1e-4 flake is probably the same class.

**flow DONE 2026-09-08** (`5b2b73b`, `92c99d5`, `ee7ac7f`): `option(PECLET_FLOW_BUILD_TESTS OFF)` folds
`tests/kokkos` (44) and, with `PECLET_FLOW_MPI`, `tests/kokkos_mpi` (106 at np=1,2,4[,8]) into the
module's own tree — ~110 `build_*` directories collapse to one per backend, both test directories
still configure standalone; the regression suite and three verify scripts are ctests with
`SKIP_RETURN_CODE 77`; `vof_timing` + `bench_rbgs` labelled `bench`. `ctest -N` = 155. CI: `build-test`
at `OMP_NUM_THREADS=2` with `-j1 --timeout 1200 -LE bench` (the unbounded pool is what starved the
4-core runner in run 34173816982), then the Python gates, then a **configure-only** pass at the
default `PECLET_CORE_TAG`; a new `mpi` job runs np=1,2 always and np=4/8 oversubscribed when np=2
stayed under 20 min; nanobind pinned; clang-format blocking after one reformat (`92c99d5`), the six
files the `vof-w4` worktree edits excluded with the reason in the workflow. **Release pre-flight
item (D4):** the tag pass is configure-only because `PECLET_CORE_TAG` v0.6.1 predates `VofMetric`/
`vofPhysNormal` — re-pin the tag at release and make it a compile.
flow in progress.

1. core: 50 of 80 test binaries `return 0` with "skipping" when morton is absent, and CI never
   provides morton → every AMR/octree test is green-by-no-op. Add morton (tag) + a Kokkos-OpenMP
   job; convert the skips to `SKIP_RETURN_CODE`; add an `ENABLE_MPI=OFF` job; wire
   `python/test_amr.py`, `test_mpi.py`, `tests/python/test_ndarray_interop.py` into ctest.
2. voro: run all 23 tests, not the 7 named in `ci.yml:74`; pin the Voro++ tag (`master` today);
   `tools/check_include_graph.sh` checks files that no longer exist and `continue`s — rewrite for
   the real header set so `test_include_graph` can fail.
3. flow/dem/voro/pnm: fold `tests/kokkos_mpi` into the main CMake under `<PKG>_BUILD_TESTS`
   (today: separate projects with `TPX_DIR` hard-wired to `../../../core`, three trees per
   backend, hence flow's ~110 `build_*` directories); run np=1,2,4 on the host runner. flow's
   regression suite + three small verify scripts in CI; `test_vof_timing` labelled `bench`.
4. coupling: `ci.yml` building flow + dem + coupling on the OpenMP prefix, running the four
   single-rank tests as pytest functions (they are `__main__` scripts today, not collectable).
5. pnm: a single-rank test target (synthetic SDF from `test_pnm_mpi.cpp:28`) registered by the
   root CMake; MPI np=1,2 in CI; `quality.yml` + `.clang-format`.
6. Suite-level: one composite action for the Kokkos bootstrap (six inline copies today) that
   calls `tools/bootstrap_deps.sh`; pin `nanobind==` in CI; one `cibuildwheel` and one
   artifact-action major per repo (dem mixes v7/v4); build against the core *tag* as well as `main`.
7. Style: the 62-line `.clang-format` into core (different file), pnm, coupling; voro's
   `.clang-tidy` everywhere; a repo-wide reformat commit per repo (flow 826 violations in three
   files, voro 761) and then `--Werror` blocking. A `ruff.toml` beyond the four critical codes.

### E. Environment variables → API (S–M per repo, breaks campaign scripts only)

flow: `PECLET_FLOW_{APERTURE_ORDER,APERTURE_FLOOR,OUTFLOW_RHO,OUTFLOW_COEFF,VRES,ADV_WALLVEL,
ADV_FILL_MODE,UBC_EXCHANGE,CA,DECOMP_LEVELS,TELESCOPE,MG_BCGHOST}` and the process-global
`CutcellMG::setDecompositionLevels` static. dem: the 16 `PECLET_DEM_*` reads in the `Simulation`
constructor and `solve_driver*.hpp` (`_REST_MODEL`, `_SLEEP*`, `_VERLET_SKIN`, `_NO_GRAPH`,
`_NO_FUSED`, `_NO_INCR_COLOR`, `_REST_NEWTON_OFF`, `_REST_ONESIDED`, `_ML_GATES`, …). core:
`PECLET_CORE_GPS_RHO/MAXN` (the only numerics-changing reads in core; both in `amr/`, so core's E is
folded into G.2 — the AMR relocation — rather than touching `amr/` twice). Each becomes a setter with a documented default, or is deleted with
the ablation it served. Keep `*_DEBUG`, `*_VERBOSE`, `*_PROFILE*`, `*_TIMEOUT`, `GPU_AWARE_MPI`.

**flow DONE 2026-09-08** (`ad917b1`): 31 reads / 25 distinct variables, not the 12 the plan named
(it missed `MG_ASPECT`, `MG_RESFILL`, `MG_DIAGRESUM`, `AGGLOM_EXTENT`, `DECOMP_MAX_IMBALANCE`,
`TELESCOPE_MIN_EXTENT`, `EXACT_RESIDUAL`, `VOF_WISP_EPS`, `VMG_AUTO_CELLS`/`_MIN_GLOBAL`,
`HOST_SERIAL_CELLS`, `PRESSURE_STRICT` and the unprefixed `PECLET_PC_DEPOSIT_FALLBACK`); `src/` is
down to five reads, all `*_DEBUG`, and a `no_env_knobs` ctest fails if another appears.
`CutcellMG::setDecompositionLevels` and every other numerics-affecting function static are gone —
`decomposition()` takes `levels`/`maxImbalance`, `IbmSolver` holds them per solver, `flow.mpi_block()`
takes them as keywords; only a host launch-size cutoff stays process-wide, as a `constexpr`.
`PECLET_FLOW_CA`'s four states became `set_comm_avoiding('both'|'off'|'momentum'|'pressure')`.
**The finding, and the reason D3 exists:** the exact-residual flag was process-wide, so an earlier
gate's `enableVof()` silently changed a LATER single-phase solver's pressure solve
(`test_vof_bc.cpp` `composedGate`, `max|div|` 2e-15 → 9e-11 once the leak was closed; the gate now
asks for it explicitly and its printed output is byte-identical to the old binary). Gate: SHA-256 of
`u,v,w,p[,C]` identical before/after on lid cavity, cut-cell sphere, VoF bubble and outflow duct at 1
and 4 threads; four setter-vs-env variants bit-identical to the old env runs; 154/154; CI green.
Also fixed: CLAUDE.md documented `PECLET_FLOW_BFS_RE800`, which never existed.

**dem DONE 2026-09-08** (`c7a89ec`, `54ca44c`): the reads were in four files, not two (`sim.hpp`,
`solve_driver.hpp`, `solver_fused.hpp`, `solve_driver_force.hpp`); 11 vars → setters (six of them into
one `set_sleeping(...)`), four deleted with their code paths (`_FUSED_GRID`, `_ML_GATES`,
`_REST_NEWTON_OFF`, `_REST_ONESIDED` — the two Poisson ablations took five dead `PGSManifoldSweep`
members with them), `_HERTZ_PROFILE` + the compile-time macros kept; `getenv` in `src/` is one call
and `tests/python/test_no_env_knobs.py` greps for a return. Gate: SHA-256 of final positions identical
before/after on XPBD (sleeping on/off), Hertz, `step_mpi` np=1,2 at one thread; eight setter-vs-env
variants each distinct and setter == env; 47/47; CUDA build smoke-run (graph/fused paths are
CUDA-only). Findings: `PECLET_DEM_SYMMETRIC_PGS` and `_STAB_MODE` never existed in code — the gallery's
Dosta production scripts set the former (no-op; `set_stabilization_mode('off')` was meant);
`benchmarks/porous-scaling/snellius/probe_dem6.sh` sets the four GPU-submission vars → setters;
the XPBD path is not run-to-run deterministic at 4 threads (record for G.4). F should tier
`set_cuda_graphs`/`set_fused_sweeps` (pure performance) into `diagnostics`.

### F. API tiering (M per repo, breaking) — D2

flow: ~180 of 266 members move to `diagnostics` (the `*_diagnostics/_stats/_census/_budget/
_ledger/_probe/_timing` families, `set_vof_timing`, `vof_block_census`, `wall_area_probe`, …);
retired `set_face_interp` modes (1/2/10 throw; 3–7, 11–13 are ablations) and `gauge-2a` deleted
with their kernels; `set_face_interp`/`set_collocated_scheme`/`set_ghost_projection` collapse to
one; on/off pairs (`set_contact_angle_dynamic`/`_off`, `set_phase_change_thermal`/`_off`,
`_energy`/`_off`) become one setter; integer codes (`set_domain_bc(type=)`, `set_advection_scheme`,
`set_csf_mode`, `add_scalar(scheme=)`) become enums/strings like `set_pressure_bottom` already is;
call-order requirements ("call BEFORE set_solid", 11 docstrings) enforced by state checks.
dem: `debug_coloring_conflicts`, `get_rest_*_stats`, `set_velocity_use_gs`, stabilization modes
`'escalate'`/`'ordered'`, `wall_sdf_at`, `get_profiling_info` → diagnostics; `set_stabilization(bool)`
+ `set_stabilization_mode(str)` → one; `initialize_shape(shape_type:int)` → enum; triples as
tuples everywhere (today `std::tuple`, `std::array`, three scalars and `(N,3)` arrays coexist);
grids passed as a 3-D array, not `(grid, nx, ny, nz, …)`; `set_positions` bounds-checked against
`capacity`; `step()` requires `dt`. voro: string modes → enums; `redistribute_pore_mesh` and
`sphere_union_scene` (245 lines of algorithm) out of `__init__.py`; bind
`DistributedMovingTessellation` or document `VoronoiHalo` as the whole MPI story; `minimize_interface`
stops returning energy through `maxVolErr`.

**Review 2026-09-10 (before executing F in the remaining repos) — decisions taken against the code:**
*Enum convention*: "integer/bool modes → enums" means VALIDATED STRINGS with the accepted set in the error
message (`set_pressure_bottom`, dem's shapes and modes); no C++ enums cross the Python boundary.
*voro*: the parked `wip/package-f-tiering` (e3e5ebb) fast-forwards onto main and its design stands
(four `diagnostics` views over an owner pointer, `InterfaceResult{iters, energy, energyRatio,
converged}` — the `maxVolErr` item is done there, `OptimizeResult` objects, `parseWallMode`/`parseMethod`,
and a `DistributedTessellation` binding over `DistributedMovingTessellation` — DECIDED: bind it, keep
`VoronoiHalo` as the primitive; the halo-only story hands the user the global skin-trip reduction that
already deadlocked at np≥4). But it is import-broken: the lazily imported `peclet.voro.pore_mesh` and
`.scenes` were never written/committed and CMake stages only `voro_init.py`; it also deleted
`FlowSolver(amg=)` silently and dropped `set_tolerance`'s default — both reversed (evidence or a
diagnostics setter; a numeric default is not a mode). `_union_sdf` (used by the gallery) becomes
`scenes.sphere_union_sdf`.
*flow*: 278 unique members, not 266. The plan's "3–7 are ablations" is contradicted by
`flow_ibm.hpp:855-860`: 5/6/7 are the Basilisk embed port and must stay reachable. DECIDED: one public
`set_collocated_scheme('ghost'|'gauge-exact'|'plain'|'embed')` (embed = mode 7); the intermediate rungs
only as `diagnostics.set_face_interp(5|6)`; modes 1, 2, 3, 4, 10, 11, 12, 13, `gauge-2a` and
`set_fv_relax` deleted with the kernels only they reach (most of `mac_approx_projection.hpp`; no
registered ctest calls `set_face_interp`). Faces become strings too (`'-x'…'+z'`), types
`'periodic'|'wall'|'inflow'|'outflow'|'slip'`. Eleven "call BEFORE" docstrings have ZERO state checks;
each becomes a check only where the late call is silently wrong (verified in the C++), else the
docstring is corrected. Pressure-driver selection, `set_decomposition`, `set_backflow_stabilization`,
the VoF block container, `hydro_force_torque(_reaction)`, the copying field registry and
`unit_scales` stay public (coupling and the documented usage need them); `field_view`,
`exchange_field*`, `rebalance_by_weights`, `bcast_from_root` are diagnostics — coupling follows.
*pnm*: no `diagnostics` object (nothing to put in it); `mpi_rank`/`mpi_size` deleted (zero callers);
`mpi_block`'s integer voxel offset renamed `origin_zyx` → `offset_zyx` (it collided with the physical
`origin_zyx` every other call takes); and the defect the plan missed — `segment_volume` /
`extract_pore_network` returned the segmentation as a Python `list[int]` (millions of boxed ints on
packing_ring) and `extract_topology` converted it back element-wise → ndarrays in and out
(`int32 (Nz,Ny,Nx)`, connections `(M,2)`), byte-identical values. `Pore.x/y/z` stay (self-named
scalars carry no axis-order ambiguity; NAMING §1.7 records the exception).
*core*: mpi/geom have nothing diagnostic; `peclet.amr.Flow` gets a `diagnostics` for its iteration
counters. Every hash-gate script is COMMITTED under `tests/` this time (dem's SHA gate and pnm's
54-file comparison were ad hoc and are lost).

**core DONE 2026-09-10 — as `peclet.amr` F** (amr `eeeac1e`): `Flow.diagnostics` (ten instruments, listed in
NAMING §2); mpi/geom had nothing to tier. Executed inside G.2 (§3.G.2).

**voro DONE 2026-09-10** (`16363b5`, `9e87eee` on top of the parked `e3e5ebb`, fast-forwarded; the wip
branch deleted): four `diagnostics` views; `pore_mesh` and `scenes` written as lazily imported
submodules and staged/installed by CMake (the parked branch had neither file); `OptimizeResult` /
`InterfaceResult` / `RedistributeResult`; `FlowSolver(amg=)` deleted with evidence (zero callers);
`set_tolerance` default restored; `DistributedTessellation` bound (np=2 vs a single-rank cold rebuild:
max |dV|/V̄ = 8.8e-14). Gate: 24/24 + 18/18 mpi before and after; `python/state_hash.py` COMMITTED
(17 paths identical + the new distributed path); Quality/Doxygen/MPI green. Gallery hits (five pages +
`src/peclet_examples/pore_mesh.py`) and voro's CLAUDE.md (the brief wrongly said none exists) in the
agent's report; coupling: none.

**pnm DONE 2026-09-10** (`6ee6399`, `b07ad75`): public surface 12 names, no `diagnostics` object; ndarray
returns (`segment_volume` int32 `(Nz,Ny,Nx)`, connections/throats `(M,2) int32`, network-flow scalars
float64 — the whole dict, not only `connections`), `extract_topology` reads the 3-D array in place,
`mpi_block` → `(offset_zyx, shape_zyx)`, `mpi_rank`/`mpi_size` deleted (zero callers). Gate: 9/9 before
and after; `tests/regression/state_hash.py` COMMITTED (61 hashes: lattice + packing_ring, staged +
fused, network flow ± openness, np=2) — all identical to the pristine build; CI green. Gallery:
`pore-network-extraction/index.qmd:94` keeps a now-redundant `reshape` (valid); coupling: no callers.

**dem DONE 2026-09-08** (`2213849`): public surface ≈ 90 members in eight groups (shapes, domain,
physics, walls, state, stepping, read-out, policy, MPI); `sim.diagnostics` holds 13 developer members;
deletions: `set_sphere_shape` (alias), `set_stabilization(bool)`, the flat `[3N]` `set_positions`
fallback — no kernel was an unreached ablation. Gate: 47/47 before and after, SHA-256 of final
positions identical on XPBD / Hertz / `step_mpi` np=1,2. Findings: `get_sdf_grid` returned x-fastest
data with C strides (transposed on non-cubic grids — fixed, Fortran order); `set_velocities` read
`(N,4)` input as `(N,3)` and mis-indexed (three dem tests did exactly that); `step()` had a silent
`dt = 1e-3` default and `step()` with no argument was a dt=0 relaxation (now `relax(n)`); NAMING §2's
dem row said counts stay methods — §1.2 wins, row fixed. Callers to update: coupling (`resolved.py`,
`driver.py`, six tests, `examples/fluidized_bed.py`) and 52 gallery files (both in flight).

### G. Structure (L, mostly not breaking)

1. **`flow/src/flow_ibm.hpp` (11 802 lines, one class, 483 member functions, 221 data members)**
   split by physics domain: single-phase core / scene + moving geometry / VoF / phase change /
   porous + closures / MPI state, as CRTP or mixin headers; `project()` (522 lines) and
   `setSolidDevice` (540) cut below ~150; the nine self-labelled "sibling" functions
   (`buildRhs`×5, `hydroForceTorque`×2, `addCsfRhs`×2, `fillVelGhostsTo`×2) merged behind parameters.
2. **`core/amr/` → a new `peclet-amr` package (D6).** *Decided 2026-09-10; supersedes the earlier
   "move the solver into flow". The audit behind it is below — re-read it before deviating.*

   **The move.** The whole `amr/` tree goes, solver and octree together, with its git history, into
   a new repo `peclet-amr` → Python `peclet.amr`, a submodule like every other package (own CMake,
   CI, CLAUDE.md, wheel, Doxygen, Zenodo DOI). It depends on `peclet-core` (`find_package(peclet-core
   CONFIG)`) and on nothing else in the suite. `core/python/amr_bindings.cpp` goes with it, so
   `peclet.core.amr.{Octree,DistributedOctree,Poisson,Flow}` becomes `peclet.amr.*` — breaking,
   hence before the 1.0.0 tag. `barnes_hut.hpp` is not AMR: it moves elsewhere in core or goes.

   **Why the whole tree, not just the solver.** Nothing outside `amr/` consumes it. `flow` includes
   no AMR header at all; `dem`, `pnm` and `coupling` none; the only includer of `block_octree.hpp` /
   `distributed_octree.hpp` outside `amr/` is core's own `amr_bindings.cpp`; and the Lagrangian
   rebalance path lives in `halo/particle_rebalance.hpp`, not in the octree. `voro` reaches into
   `amr/momentum.hpp` for exactly one function, `greedyColoring` → move it to `core/solver/coloring.hpp`
   (otherwise voro would acquire a dependency on the AMR package). Folding 10.6 k lines of a second,
   unrelated solver stack into `flow` — whose own `flow_ibm.hpp` is being split under G.1 *because*
   it is too big — trades one oversized package for another.

   | part of `amr/` | lines |
   |---|---|
   | solver (flow, oracle, Poisson, momentum, MG, PCG, cut cell, ghost projection, coarse-fine, scalar transport, distributed variants) | 10595 |
   | infrastructure (block/distributed octree, adapt, refine, indicators, leaf field + halo, distributed view/fv, VTU I/O, CSR) | 4167 |

   **Why `peclet-amr` does NOT depend on `peclet-flow`.** The two solvers have different data models,
   so the discretization does not transfer as code: flow computes with fixed-offset stencils on
   structured `(x,y,z)` Kokkos views, while the AMR path assembles a per-cell diagonal plus a general
   face CSR and applies it with weighted Jacobi + BiCGStab because the operator is non-symmetric.
   Hanging nodes are why `cf_scheme.hpp` exists and has no flow counterpart. Packaging says the same:
   `core` installs an exported CMake package, `flow` installs only its Python extension, so a C++
   dependency on flow would first require making flow a consumable header package, then pinning three
   repos together — a heavy price for a few hundred lines of scalar mathematics.

   **What IS shared, and where it goes.** The cut-cell closure polynomials are duplicated today,
   written independently in `flow/src/cut_cell_ibm.hpp` (`float`, `KOKKOS_INLINE_FUNCTION`) and
   `amr/cut_cell.hpp` (`double`, `MORTON_HD`), and the AMR ghost projection cites flow's campaign
   notes as its authority for the method it implements. That layer is pure functions of local
   geometry with no data layout in them: lift `poly_D` / `poly_Nc` / `poly_N_nb` and their siblings
   into **core**, templated on the scalar type (which also serves G.6), and have both packages call
   the one copy. Python-level composition stays available and costs nothing: `peclet.amr` may import
   `peclet.flow` for a uniform-grid reference solution or shared I/O without any C++ coupling.

   **Prerequisites and traps.** Three infrastructure headers reach back into solver headers and must
   be cut first: `distributed_view.hpp` → `multigrid.hpp`, `distributed_poisson.hpp`, and
   `distributed_fv.hpp` → `distributed_poisson.hpp`. `core/python/build*/` hold stale artefacts naming
   the retired `tpx_amr` target — do not carry them across. Move the ~30 AMR ctests and the AMR docs
   with the code; core's `tests/oracle/morton_octree.hpp` stays in core (it is BlockOctree's test
   oracle). Update the umbrella `CLAUDE.md` table, `ARCHITECTURE.md`, `mkdocs.yml`, `docs/python/`,
   `tools/release/`, `RELEASE.md`'s package list and `PecletDeps.cmake` for an eighth package.

   **Corrections from the 2026-09-10 re-audit (verified against the tree; they supersede the text
   above where they differ).** (1) voro uses MORE than `greedyColoring`: `ot_optimizer.hpp:95,228` uses
   `MomentumSolver<21>` / `MomentumOp` (the Jacobi-preconditioned BiCGStab over a face CSR), so the
   lift into `core/solver/` is the colouring AND the CSR operator + BiCGStab solver (verbatim; the AMR
   package keeps `using` aliases; `MomentumMG` stays in amr). (2) `barnes_hut.hpp` includes
   `block_octree.hpp` + `leaf_field.hpp` and is already inside the 4167-line infrastructure count: it
   is an octree consumer and moves with the tree. (3) Four AMR headers include `morton/morton.hpp`:
   `peclet-amr` depends on core AND morton — nothing else in the suite. (4) `tests/oracle/
   morton_octree.hpp` has one includer, `test_block_octree.cpp` (AMR): it moves. (5) The movable
   ctest set is 47 (plain) / 52 (host+MPI) / 92 (Kokkos) per core tree plus `python_amr{,_np2}`, not
   ~30. (6) No consumer uses `find_package(peclet-core CONFIG)`; every package vendors core through
   its own `cmake/PecletDeps.cmake` sibling include with a `PECLET_CORE_TAG` pin, and there is no
   umbrella `PecletDeps.cmake` — `peclet-amr` uses the same mechanism. (7) The back-edges
   (`distributed_view.hpp`/`distributed_fv.hpp` → solver headers) are genuine symbol uses but do not
   block the split, since nothing that stays in core depends on `amr/`; they are internal hygiene for
   the new package. (8) E for amr: `PECLET_CORE_GPS_RHO/MAXN` change numerics → `Flow.set_ghost_sampled(
   rho=, max_samples=)` setters, defaults inert; `PECLET_CORE_PROFILE_*` are prints (renamed
   `PECLET_AMR_*`); core's `grid_halo.hpp` variables are transport/logging and stay. (9) core's
   CLAUDE.md advertises 104/158 ctests; no current tree reproduces those counts — fixed with the strip.

   **DONE 2026-09-10.** core `d93c323` (B: the face-CSR operator layer lifted to `core/solver/` —
   `face_csr.hpp`, `csr_operator.hpp` (`MomentumOp`), `csr_bicgstab.hpp` (`MomentumSolver`, vestigial
   `Bits` dropped), `coloring.hpp`, `vector_ops.hpp`; new ctest `csr_solver`), `ae1affe` (D: the strip),
   `5810ab5` (toolchain-aware byte gate). New repo `peclet-amr` = 174 filtered commits (`include/peclet/
   core/amr/` and its `tpx/amr/` ancestry → `include/peclet/amr/`, the 51 AMR test sources, the study
   drivers, `bench_amr_flow`, the AMR docs and archive notes, `tests/oracle/morton_octree.hpp`) + scaffold
   `2533f16`, E `0c1de95`, F `eeeac1e`, G.5 `8e74940`, a format-only `48f1801`, CI `cfe5a50`; submodule
   `amr` in the umbrella. Counts: core 109/164/7 → 53/68/6 (+`csr_solver`); amr 100 ctests (79 + 16 np8 +
   5 bench) + 3 Python. Hashes: core mpi/geom 15 keys identical pristine → B → D; amr 13 keys identical
   across the relocation (same toolchain; the gate records per toolchain and SKIPs elsewhere — `-O0`
   and `-O3` differ). Findings: core's single-rank halo stub is not Kokkos-clean, so amr REQUIRES MPI;
   `-mfma` must stay module-only (host-vs-device bit-exact tests drift with it); filter-repo carried
   core's release tags into the new history — deleted locally, never pushed; `PECLET_CORE_TAG` pins in
   the consumers lag core `d93c323` (release session).

   **Not in scope, and not implied.** If the long-term goal is one solver serving both uniform and
   adaptive meshes, the mechanism is templating the discretization on a mesh policy — the pattern
   G.3 proved in pnm (`GridGeo` / `BlockGeo`) — not a package dependency. That is a deliberate
   project to decide on its own merits, never a side effect of this split.
3. **pnm — DONE 2026-09-08** (pnm `5ad3898`, `0e0c2cd`): `src/pore_kernels.hpp` holds every stage kernel
   once, templated on a geometry policy (`GridGeo` single-rank, `BlockGeo` MPI); the two pipeline
   files keep orchestration only (2873 → 2458 lines, `parallel_for` 66 → 37, no stage body twice).
   Gates: 9/9 ctests host and CUDA, packing_ring 7199/53020 unchanged, and a 54-file byte comparison
   of pores/segmentation/connections/network-flow (single-rank staged+fused, np=2 per rank, open and
   cut-cell) against the pre-refactor build: 0 differ.
4. **dem — DONE 2026-09-10** (`ee34cfe` gate, `4839ccf` split, `9dad55d`, `9fa890c` dedups, `93eec07`
   fix; CI green). `sim.hpp` 1917 → 1047: free drivers → `src/step_solve.hpp` + `step_solve_mpi.hpp`,
   the shape registry → `src/shape_registry.hpp` as a protected base `ShapeRegistry` (bodies verbatim;
   `addAnalyticWall` stayed with the walls); the world-radius fill was written FOUR times (not three)
   → one `fillWorldRadiiKokkos`; the gid-keyed search THREE times (not two) → `pairKeyFromGids` +
   `lowerBoundKey`. Gate: `tests/regression/state_hash.py` (COMMITTED; nine fixed-seed cases at one
   thread incl. `step_mpi`/`step_hertz_mpi` np=1,2) identical after every structural commit; 47/47.
   The numerics fix is its own commit: single-rank periodic wrap contacts were one-sided because the
   partner beyond one `maxRad` of the face had no image (the survey had the sides swapped: the far,
   un-imaged partner moved, by half the de-penetration); band = `2·maxRad + margin`, ghost capacity
   follows; `tests/python/test_periodic_wrap_symmetry.py` RED before / GREEN after, and
   `test_validate_periodic.py`'s straddlers are now asymmetric (np=2 error 0). Hashes changed only
   for the four single-rank periodic cases; Hertz and every MPI case identical.
5. **core Python — DONE 2026-09-10 in peclet-amr** (`8e74940`): the shared members (16, not 14) are bound
   once through `bindOctreeCommon<T>`; attribute sets identical before/after.
6. **Precision as a typed policy:** flow's `MReal = float` unless a raw `-DPECLET_FLOW_MREAL_DOUBLE`
   (no CMake option; three "hard `(float)` casts that survived the templating") is
   SCALING_ISSUES #1; make it `option(PECLET_FLOW_OPERATOR_DOUBLE)`, grep-test that no `(float)`
   touches an operator view, and document core's float closure storage
   (`ghost_projection.hpp:71-76`, `scheme/ghost_closure.hpp`) in CONVENTIONS §3 as the same exposure.
7. **voro — DONE 2026-09-10** (`5ffb0ea`, `76eed19`, `2407c58`, `d58373b`, `aee039b`, `c3d3416`,
   `4653c0b`, `4ab848e`; CI green). `include/peclet/voro/params.hpp` is the one home of the engine
   defaults (every template default, default argument and bench fixture names them; the bindings'
   `defaults` re-exports them) — the only capacity that changed is `ConvexCell`'s template default
   64/96 → 64/112, used by one unit test. `PECLET_VORO_PROFILE` (the library's last `getenv`) is gone:
   `diagnostics.set_profile(on)` on `Tessellation`/`Simulation`/`DistributedTessellation`, and the
   silent over-buffer rebuild is counted (`build_report()['over_buffer_rebuilds']`). The pore-space
   export runs on the device (`pore_cells.hpp`: the tessellator's own gather, count → scan → fill in
   seed order, no atomics), gated by `test_pore_cells` (invariants + device vs a certified host
   oracle: 805/805 cells, volumes 1e-12, vertex sets 1e-9 L; CUDA RTX 5080 6e-11, run-to-run
   identical). THE GATE FOUND: the old host reconstruction's fixed 80-nearest gather missed planes on
   8/805 cells (volumes off by up to 2.5e-3) — so the two pore hashes changed because the VALUES
   were wrong before (`edbc5056…` → `ca5485fc…`, `f498cf1b…` → `aac38ed6…`; the other 16 identical);
   `buildTessellation` judged `kIncomplete` against a window the grid clamps (fixed `c3d3416`). OPEN
   CUDA DEFECT: at 128/256 the device SDF clip is wrong on CUDA (every wall cell off up to 22 %,
   deterministic; 64/112 correct; 128/256 exact on OpenMP) — the device pore path runs at 64/112 with
   overflow counted; investigate `clipCellAgainstSdf` at 128/256 under nvcc. Warnings 25 → 0 (all
   in `tests/`). `aee039b` switched `mesh_optimizer.hpp`/`ot_optimizer.hpp`/`bench_mesh_optimizer.cpp`
   to `peclet::core::solver` (G.2's B4).

### H. Docs describe the code (S–M, not breaking) — D7

1. Umbrella — **DONE 2026-09-08** except the two items at the end: CONVENTIONS.md §4 states the
   *measured* precision policy (double state, float operator storage), :92's array-shape sentence and
   :79's `tpx/` path fixed; STYLE.md §Namespaces and §CI say what ships; INTERFACES.md carries its
   "design sketch, not realised" status banner; ROADMAP :77-84's `.cuh` file names marked historical and
   the header points at this file as the active work list; ARCHITECTURE :63 `block_decomposer` phrased
   as history; the phantom `DOC_CI_WORK_NOTES.md` `not_in_nav` entry removed; the 13 plan notes are in
   `docs/archive/` (AMR, AMR_GEOMETRY_SETUP_REQUIREMENTS, ANALYTIC_SDF_GEOMETRY, COMMUNICATION_SCALING,
   DEFECT_CORRECTION_PLAN+PROMPT, DEVICE_RESIDENCY_PLAN, MG_TELESCOPING_PLAN, MULTIPHYSICS_PLAN,
   VOF_PLAN, VOF_NEXT_SESSION, VORONOI_METHODS_PLAN, peclet_cuda_wheel_prototype) behind an
   `archive/README.md` index and a collapsed "Archive" nav section, 24 links re-based, `mkdocs build
   --strict` clean (umbrella `afda9d4`); PHYSICAL_UNITS_PLAN stays until Phases 3–4 land. **Open:** the
   D7 decision on INTERFACES.md (implement `concepts.hpp` + `static_assert`s, or rewrite as the written
   contract), and the RELEASE_PREP re-cut for 1.0.0 on release day. The submodule follow-up is
   done except flow: coupling (`2672318`) and core (`b39ffe4`, which also cited
   `AMR_GEOMETRY_SETUP_REQUIREMENTS.md`) now name the `archive/` paths; the two in
   `flow/src/flow_bindings.cpp` (`DEFECT_CORRECTION_PLAN.md`, `MG_TELESCOPING_PLAN.md`) wait for the
   package-E agent to finish in that file.
2. flow — **DONE 2026-09-08** (`628d3da` doc content, `ef25feb`, `013d3b3`): CLAUDE.md 178 KB / 2110
   lines → 20 KB / 292 lines, the old file archived verbatim as `doc/history/claude_md_2026-09-08.md`;
   `doc/` split into reference (17 live design docs) and `doc/history/` (the five `vof_workorders*`,
   eight collocated campaign notes, `colocated_study/`, ghost-hardening, advective cut-wall, the two
   packing reports) behind two dated indexes; 79 relative links checked, 0 broken; ctest counts
   corrected to 156 registered / 154 with `-LE bench`; `AGENTS.md` reduced to a true pointer and
   `GEMINI.md` deleted (it held another tool's generic workflow memory, nothing about this repo).
   **The plan's item 3 was wrong on all four counts** — `CFD_BUILD_MPI`, the `SolverColocated`
   "ghost" default, `pyproject`'s "single-rank" and the pybind11 mention were already fixed by A/B/C
   and D. Left for later, as core did: ~10 `doc/…` citations inside `src/` and `tests/*.cpp` gain the
   `history/` prefix when those files are next edited.
3. dem — **DONE 2026-09-08** (`f680c3d`, `acb0fd5`): README quick-start written and RUN against the
   1.0.0 API, folder listing and venv paragraph corrected, `docs/solver_details.md` rewritten for the
   Kokkos stack (it narrated the retired `src/cuda/*.cu`), CLAUDE.md carries the E/F traps and the
   right ctest counts, two campaign notes → `docs/archive/` with an index, zero broken links; the
   `max_overlap` docstring and `examples/pack.py` follow the moved path.
4. voro — **DONE 2026-09-08** (`23c088f`): CLAUDE.md written by D + H (5 KB, one-tree recipe, `docs/`
   vs `docs/archive/` rule); Lees–Edwards and the half-edge oracle dropped from README/CITATION.cff
   (zero occurrences in `include/`); 23 campaign notes (not 17) → `docs/archive/` with an index;
   `docs/` keeps `architecture.dox`, `distributed_voronoi.md`, `performance_report.md`.
5. core — **DONE 2026-09-08** (`c52989f`): last `tpx`/`transport_core`/`block_decomposer` prose gone;
   `-LE bench` counts corrected to 104/158 (totals 109/164/7 include the `bench` label); six campaign
   notes → `docs/archive/` with an index, four AMR reference docs stay (nothing deleted);
   `amr_advection_session_prompt.md` was already gone. CLAUDE.md 18.7 KB. Left: ~25 code comments cite
   the old `docs/<name>.md` paths (prefix `archive/` when those files are next edited).
6. pnm — **DONE 2026-09-08** (already in `978f340`; re-swept in `329eae2`): guard + `@brief` say pnm,
   no `cout`/`cerr`/`fprintf` left in `src/`, every failure path throws (the MPI ones after a collective
   `MPI_Allreduce` of the condition so no rank hangs); `docs/Doxyfile` was the last self-as-flow line.
   Left for G: global-namespace `SDFData` in `sdf_reader.h`.
7. morton — **DONE 2026-09-08** (verified against the tree, not just the plan): the README H1 is
   `peclet-morton`, no `mortonarith` or "python 3.8+" claim survives (`requires-python = ">=3.9"`),
   `docs/ROADMAP.md` carries no "v0.3", `bindings/morton_c.h` is installed beside the headers so the
   C ABI is documented, and `octree/` is gone (item 5; the std::map octree lives on as core's test
   oracle). Package C and item 5 had already done the work the plan still listed as open.

**Package H is complete in all eight repositories.**

## 4. Order and gates

| step | packages | gate |
|---|---|---|
| 1 | A + B + C + H1 (umbrella docs) | every repo's existing battery green on host-openmp; `check_release_state.sh` clean; gallery pages grep clean of removed names |
| 2 | D | a red test in CI is a real failure; MPI suites run in CI |
| 3 | E + F + G.2 (the breaking parts) | env vars retired; diagnostics tier; `core/amr` out of `peclet.core` into `peclet-amr` (D6) — every removal in the CHANGELOG |
| 4 | **tag 1.0.0** ("physical domains", the clean-break release) | RELEASE.md phases A–I; CUDA + MPI matrices |
| 5 | G (rest) + H2–7 | `flow_ibm.hpp` split, dem `sim.hpp` split, precision policy, doc diets — 1.x, non-breaking |

*Order corrected 2026-09-08 (was: tag after D, E + F in 1.x "breaking → 2.0"): F is breaking by
definition (D2) and G.2 moves public Python names out of `peclet.core`; under D9 (strict semver from
1.0.0) they belong BEFORE the tag, not in a 2.0 weeks later. E is launched per repo as its D pass
lands; F and G.2 follow in the same repo.*

## 5. Log

- **2026-09-08** — audit; this file; decisions D1–D9 taken (maintainer: "quality is the prime
  objective … be API breaking if needed"; "if the version should be major, do so"; "AMR is being
  developed, do not throw it away"). **Executed the same day, all pushed:** packages A, B, C and the
  per-repo stale-line fixes of H — flow `14f3388`→`64adc17`, dem `ae88d3e`→`885f85f`, voro
  `9e7b1b0`→`ef99da9`, pnm `978f340`→`6167f23`, core `8d9f3c2`→`6604ed0`, morton `8614353`/`b502598`,
  coupling `8603faa`→`34ad637`; umbrella `e263459`…; CHANGELOG `[Unreleased] — 1.0.0`. Batteries on
  host-openmp after the changes: flow `tests/kokkos` 44/44 + regression PASS + verify Poiseuille (vof
  subset re-run 16/16 after the second flow pass), dem `tests/kokkos` 8/8 + verify_packing + three
  test scripts, voro 24/24, pnm 6/6 MPI + 7199 pores, core 104/104 + 158/158 + Python np=1,2,4,
  morton all four configurations + pytest 9 + wheel, coupling pytest 4 passed / 1 skipped. **Not
  re-run:** the CUDA and MPI matrices of flow/dem/voro (RELEASE.md §3 on the day).
  Corrections the execution surfaced: flow `get_ox/oy/oz` are openness fields (table fixed); flow has
  44 kernel tests and core 158 Kokkos ctests (docs fixed); dem's `set_positions` must precede
  `set_shape_ids` (docstring fixed); voro's `volumes()` was not the getter model (§1.2 restated);
  morton's PDEP/PEXT grep test did not exist (now does); pnm's `release.yml` was already consistent.
  New observations for the open packages: voro's blanket `-Wno-*` removal exposes 622 warnings (fix
  under G.7); coupling's `test_fixed_bed_ergun_porous` passes but flow's `CutcellMG::solvePCG` prints
  "preconditioner produced non-finite z" on it (flow-side, check under D/G.6); voro's GitHub repo has
  a PR-required branch rule that direct pushes bypass; the `pre-legacy-removal` tag keeps morton's
  history reachable.
- **2026-09-08, package D** — pnm `ec646c8`…`72cf6f4` (0→9 ctests, CI 39 s + 74 s) and G.3
  `5ad3898`/`0e0c2cd` (one kernel set, 2873→2458 lines, 54-file output byte-identical, 9/9 host +
  CUDA); dem `5bb9bfd`…`8124d57` (47 ctests in one tree, scripts sorted, CI 2 m 47 s + 3 m 17 s).
  Details under §3.D / §3.G.3. core `69d6b0f`…`6bd091d` (109/164/7 ctests, six CI jobs, longest 17 min); voro `1cbf005`/`a487777`
  (42 ctests one tree, MPI launcher trap closed, 622 → 145 warnings; `test_sdf_curved` honestly RED,
  then root-caused the same day: order-dependent silent overflow caps, `9ce81c8`/`ce698c1`); morton
  `5f35316` (headers `-Wpedantic`-clean, voro's 120 remaining warnings gone).
- **2026-09-08, packages E/F/H and the voro engine fix** — E: dem `c7a89ec`/`54ca44c` (bit-exact),
  core's folded into G.2. F: dem `2213849` (public + `sim.diagnostics`), callers followed in coupling
  `f98e6d6` and the gallery (local `6a749f8`, not pushed — the site is re-rendered only on 1.0.0
  wheels). H: pnm `329eae2`, core `c52989f`, voro `23c088f`. voro `9ce81c8`/`ce698c1` closed the
  `test_sdf_curved` blocker; morton `5f35316` made its headers `-Wpedantic`-clean for consumers.
  **Package D is now done in all six repos with tests.**
  **Interrupted, resume here:** voro's package F was cut off mid-flight and left UNCOMMITTED edits in
  the voro working tree (`src/voro_bindings.cpp`, `include/peclet/voro/mesh_optimizer.hpp`,
  `packaging/voro_init.py`, `tests/kokkos/test_mesh_optimizer.cpp`) — inspect with `git -C voro diff`
  before starting anything there; dem's G.4 (sim.hpp split + the periodic-wrap one-sidedness) never
  started.
- **2026-09-08, after the model switch** — dem H.3 landed (`f680c3d`, `acb0fd5`, CI green) and
  `docs/python/dem.md` was regenerated from the tiered module; `tools/gen_python_api.py` now emits
  `Diagnostics` beside `Simulation`, so the developer tier is documented rather than hidden behind a
  property. The other generated pages are untouched (their modules did not change).
- **2026-09-08, package E complete** — flow `ad917b1` (25 variables, the process-global statics, and a
  real cross-solver leak closed), dem `54ca44c`, core's folded into G.2. Nine gallery files and one
  Snellius batch script still name retired `PECLET_FLOW_*` variables (list in §3.E); `coupling` has
  none. flow `486cdb3` finished H.1's citation follow-up, hand-wrapped because `flow_bindings.cpp`
  sits on quality.yml's temporary vof-w4 exclude list and must not meet clang-format until W4 merges.
- **2026-09-08, gallery callers** — `peclet-examples` `6a749f8` (dem's 1.0.0 API across 50 files; int
  shape codes were 1/2/3, not 0-based, and three latent bugs surfaced: an `(N,4)` `set_velocities`
  call that dem used to mis-index, a six-scalar `add_plane`, and a C-order `get_sdf_grid` read) and
  `ff21290` (flow's retired `PECLET_FLOW_*`). Local commits, NOT pushed, NOT re-rendered — that waits
  on the 1.0.0 wheels. Dated records in `ISSUES.md`/`PROGRESS.md` keep their historical commands with
  a bracketed note naming the replacement setter.
- **2026-09-08, a coordination lesson worth keeping** — flow `628d3da` carries BOTH a `predict_hierarchy`
  fix and the H.2 doc-diet agent's in-progress files: two agents were committing in the same checkout
  and a bare `git commit` takes the whole shared index, not just the paths you staged. With concurrent
  agents in one repo, always commit with a pathspec (`git commit <paths> -m ...`). The agent preambles
  now say so.
- **2026-09-08, a package-E regression caught by the gallery pass** — removing the process-global
  decomposition state left `CutcellMG::predict` calling `decomposition()` with the defaults, so
  `flow.predict_hierarchy` silently predicted the ALIGNED hierarchy for a coarse-first job while its
  docstring claimed otherwise. Fixed in `628d3da`: the depth and imbalance tolerance are parameters
  (`decomposition_levels=`, `max_imbalance=`). On 160^3/np=6 and 144^3/np=12 the prediction now differs
  from the default, as it must; 48/48 non-MPI green. **Lesson for F and G: when a process-global goes
  away, every pure/preflight function that used to read it needs the value passed in.**
- **2026-09-08, H.2 and its fallout** — flow's doc diet also flagged that
  `scripts/check_decomposition.py --predict` printed IDENTICAL hierarchies for `--mode 0,4` under
  headings naming different depths, and silently overwrote `--decomp-levels`; fixed in `013d3b3`
  (aligned 80x48x160 vs coarse-first(4) 80x52x160 on 160^3/np=6). Umbrella links re-pointed at
  `flow/doc/history/…` in eight files, `docs/archive/AMR.md` cited `flow/doc/sdflow_colocated_plan.md`
  which never existed (it is `flow_colocated_plan.md`), and `docs/python/flow.md` was regenerated from
  the MPI build so it no longer documents the retired `PECLET_FLOW_MG_ASPECT`.

- **2026-09-10, F/G review and launch** — the remaining packages were reviewed against the code before
  cutting (five read-only surveys: voro's parked branch, flow's 278 members, core's AMR dependency
  graph, pnm's surface, dem's `sim.hpp`). Findings and decisions are recorded in place: §3.F ("Review
  2026-09-10") and §3.G.2 ("Corrections from the 2026-09-10 re-audit"). Plan errors found: voro's AMR
  use is the CSR BiCGStab solver, not one function; `barnes_hut.hpp` is an octree consumer; peclet-amr
  needs morton; flow's face-interp 5/6/7 are the embed port, not ablations; pnm returned the
  segmentation as a list of boxed ints; dem's ledger carry is written three times, not two; the G.3 and
  dem SHA gates were never committed. `.gitmodules` still names `transport-core`/`sdflow`/`vorflow` (a
  D8 leftover, renamed when the eighth submodule is added). `preamble_G.md` written (byte-comparison
  gate mandatory, hash scripts committed). The empty repo `peclet-amr` was created. Execution order:
  wave 1 in parallel — voro F, flow F, pnm F, dem G.4 — plus core F + G.2 + G.5 as one pass; then the
  voro include switch, the shared `poly_*` lift, G.1, G.6, G.7; then callers, CHANGELOG/NAMING, this
  file, pointers. No version bump, no tag.

## 6. Handoff — starting packages F and G

Written 2026-09-08 at the end of the day A–E+H were executed, for whoever picks up F and G. Read
§1 (decisions), §3.F/§3.G, `docs/NAMING.md` §1, and the repo's own `CLAUDE.md` before touching code.

### Where the work stands

**Done in every repo:** A (one spelling per concept), B (dead code and artefacts out), C (one version
source, old identifiers gone), D (CI that is honest), E (no env var changes a result), H (docs
describe the code). Every submodule pointer is bumped and pushed; CI is green in all eight repos;
`tools/release/check_release_state.sh` flags only the deliberate "bump at tag time" versions.

**Done in part:** F in dem only (`2213849`). G.3 in pnm only (`0e0c2cd`).

**Remaining, and the order §4 wants:** F in voro, flow, pnm, core → G.2 (+G.5) → then the rest of G
(G.1, G.4, G.6, G.7) → tag 1.0.0. F and G.2 are breaking, so they precede the tag; the rest of G is
not breaking and could follow it, but doing it first keeps one release instead of two.

### Start here, per repo

- **voro F — half written, parked on a branch.** The agent was cut off before it built anything. Its
  work is committed on `wip/package-f-tiering` (pushed): public/`diagnostics` split in
  `src/voro_bindings.cpp`, `pore_mesh` and `scenes` lifted out of `packaging/voro_init.py` into lazily
  imported submodules, plus touches to `mesh_optimizer.hpp` and `test_mesh_optimizer.cpp`. It is
  UNBUILT and UNTESTED — read it critically against the current bindings, do not assume it is right.
  Still open from §3.F: string modes → enums, `minimize_interface` returning energy through
  `maxVolErr`, and the `DistributedMovingTessellation`-versus-`VoronoiHalo` decision.
- **flow F** is the big one (~180 of 266 members to `diagnostics`, retired `set_face_interp` modes
  deleted with their kernels). Do it before G.1, so the split moves a smaller surface.
- **pnm F / core F** are small. core's F is entangled with G.2 and G.5 — all three touch
  `python/amr_bindings.cpp`, so do them as one pass, not three.
- **G.2** moves the WHOLE `core/amr/` tree into a new eighth package `peclet-amr` depending on core
  alone (D6, decided 2026-09-10 — read G.2 in full, it carries the dependency audit; relocated with
  its history, never deleted, AMR is under active development). G.5 (`Octree`/`DistributedOctree`
  sharing 14 verbatim members) is the same file and rides along, as does core's F.
- **G.4** (dem `sim.hpp` split) carries a real numerics fix: single-rank periodic wrap contacts whose
  far partner sits more than one radius beyond the face are resolved ONE-SIDEDLY (`ghostBand = maxRad`);
  the MPI step is symmetric. Keep the structural commits bit-exact and isolate the fix in its own
  commit with a test. Also unexplained: dem's XPBD path is not run-to-run deterministic at 4 threads.

### Two lessons this work produced — they will bite F and G

1. **When a process-global disappears, every pure or pre-flight function that read it needs the value
   passed in.** E removed flow's decomposition statics; `CutcellMG::predict` kept calling
   `decomposition()` with the defaults, so `flow.predict_hierarchy` silently predicted the *aligned*
   hierarchy for coarse-first jobs while its docstring claimed otherwise (`628d3da`), and
   `check_decomposition.py --predict` printed identical ladders under headings naming different depths
   (`013d3b3`). F moves members and G moves whole files: grep for every reader before you move state.
2. **With concurrent agents in one checkout, commit with a pathspec** — `git commit <paths> -m …`.
   A bare `git commit` takes the whole shared index: flow `628d3da` swept another agent's staged docs
   into an unrelated commit.

### How the packages were run

Agent briefs live in `.claude/preambles/` (gitignored): `preamble.md` is the shared git/build/report
contract, `preamble_F.md` adds F's tiering rules and gates. There is no `preamble_G.md` — write one
from §3.G, and require of every structural change what G.3 delivered: **a byte-comparison of the
outputs against the pre-refactor build**, not just a green battery.

Gates that caught real defects and should stay: a SHA-256 of the final state from a fixed-seed run per
public entry path, before and after; the full registered battery on host-openmp (`OMP_NUM_THREADS=4
OMP_PROC_BIND=false`, MPI at one thread); `gh run watch` green before reporting.

### Callers to update after each breaking pass

`suite/coupling` and the gallery at `~/Codes/peclet-examples`. The gallery has local commits (dem
`6a749f8`, flow `ff21290`) that are deliberately NOT pushed and NOT re-rendered — that waits for the
1.0.0 wheels. Dated records there (`ISSUES.md`, `PROGRESS.md`) keep their historical commands with a
bracketed note naming the replacement; live instructions get updated.
