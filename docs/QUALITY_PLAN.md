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
- **D6 — core is infrastructure; AMR is preserved.** AMR is under active development and
  nothing of it is deleted. The AMR Navier–Stokes solver (`core/include/peclet/core/amr/flow.hpp`
  and its 10 k lines of siblings, bindings and tests) is *relocated* with its history — either
  into `flow` as its octree backend, or onto a `dev/amr-flow` branch of core until it is ready
  to ship as a method — so that the released core is mesh infrastructure only (`BlockOctree`,
  `DistributedOctree`, leaf halo, CSR, refine/adapt, VTU I/O stay). The AMR plan notes and
  campaign logs move to `archive/`, not the bin. (Maintainer, 2026-09-08: "AMR is being
  developed. So, do not throw it away. You might move things to a development branch.")
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
2. **core → flow (D6):** `amr/{flow,flow_oracle,poisson,momentum*,multigrid,pcg,velocity_mg,
   ghost_projection*,cut_cell,cf_scheme,scalar_transport,distributed_flow_mg,distributed_poisson}.hpp`
   + `amr_bindings.cpp` `Flow`/`Poisson` + ~30 tests move; `greedyColoring` (voro's only reason to
   include `amr/momentum.hpp`) → `solver/coloring.hpp`; `barnes_hut.hpp` out of `amr/`. `AmrFlow`'s
   23 setters → a config struct; `fprintf(stderr)` ×13 → a logger hook.
3. **pnm — DONE 2026-09-08** (pnm `5ad3898`, `0e0c2cd`): `src/pore_kernels.hpp` holds every stage kernel
   once, templated on a geometry policy (`GridGeo` single-rank, `BlockGeo` MPI); the two pipeline
   files keep orchestration only (2873 → 2458 lines, `parallel_for` 66 → 37, no stage body twice).
   Gates: 9/9 ctests host and CUDA, packing_ring 7199/53020 unchanged, and a 54-file byte comparison
   of pores/segmentation/connections/network-flow (single-rank staged+fused, np=2 per rank, open and
   cut-cell) against the pre-refactor build: 0 differ.
4. **dem:** `sim.hpp` (1876) → step drivers / `Simulation` facade / shape registry; the world-radius
   fill written inline 3× beside `fillWorldRadiiKokkos`; the gid-keyed ledger carry written twice
   (`solve_driver_force.hpp:72-90`, `contact_preprocessing.hpp:119-170`).
5. **core Python:** `Octree` and `DistributedOctree` share 14 verbatim members with no base. Folded into G.2 (same file, `python/amr_bindings.cpp`, restructured once).
6. **Precision as a typed policy:** flow's `MReal = float` unless a raw `-DPECLET_FLOW_MREAL_DOUBLE`
   (no CMake option; three "hard `(float)` casts that survived the templating") is
   SCALING_ISSUES #1; make it `option(PECLET_FLOW_OPERATOR_DOUBLE)`, grep-test that no `(float)`
   touches an operator view, and document core's float closure storage
   (`ghost_projection.hpp:71-76`, `scheme/ghost_closure.hpp`) in CONVENTIONS §3 as the same exposure.
7. voro: named defaults (`TessellationParams`) for the literals scattered through the bindings
   (`MAXP/MAXT` 64/112 vs 64/96 vs 128/256, `0.25*spacing`, `0.7`); library `printf`s behind a
   verbosity flag; the serial host loops in `sdf_voronoi_cells`/`_section` on the resident device
   tessellation (device-first directive).

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
2. flow: `CLAUDE.md` (174 KB, 2062 lines) → a < 20 KB reference; campaign history to
   `doc/history/`; `doc/` (31 files, five `vof_workorders*.md` = 853 KB) split reference/history;
   README `-DCFD_BUILD_MPI` → `PECLET_FLOW_MPI`, `SolverColocated` default "ghost"; `pyproject`
   "single-rank"; `ci.yml` "pybind11"; `AGENTS.md`/`GEMINI.md` either made true or deleted.
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
7. morton: README H1 `morton-arithmetic`, `pyproject` comment (`mortonarith`), "python 3.8+" badge
   vs `>=3.9`, `docs/ROADMAP.md` "v0.3"; ship `bindings/morton_c.h` so the 26 C exports are a
   documented ABI; decide `octree/` (split out or delete — "being split out" since July).

## 4. Order and gates

| step | packages | gate |
|---|---|---|
| 1 | A + B + C + H1 (umbrella docs) | every repo's existing battery green on host-openmp; `check_release_state.sh` clean; gallery pages grep clean of removed names |
| 2 | D | a red test in CI is a real failure; MPI suites run in CI |
| 3 | E + F + G.2 (the breaking parts) | env vars retired; diagnostics tier; AMR flow out of `peclet.core` (D6) — every removal in the CHANGELOG |
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
