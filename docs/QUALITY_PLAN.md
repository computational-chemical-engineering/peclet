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
reformat commit. flow/dem/voro/core in progress.

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
`PECLET_CORE_GPS_RHO/MAXN`. Each becomes a setter with a documented default, or is deleted with
the ablation it served. Keep `*_DEBUG`, `*_VERBOSE`, `*_PROFILE*`, `*_TIMEOUT`, `GPU_AWARE_MPI`.

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
5. **core Python:** `Octree` and `DistributedOctree` share 14 verbatim members with no base.
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
   contract), and the RELEASE_PREP re-cut for 1.0.0 on release day. Small follow-up in the submodules:
   docstrings in `flow/src/flow_bindings.cpp` (×2) and `coupling/python/peclet_coupling/resolved.py`
   cite `docs/DEFECT_CORRECTION_PLAN.md`, `docs/MG_TELESCOPING_PLAN.md`, `docs/ANALYTIC_SDF_GEOMETRY.md`
   as plain text — add the `archive/` prefix when those files are next touched.
2. flow: `CLAUDE.md` (174 KB, 2062 lines) → a < 20 KB reference; campaign history to
   `doc/history/`; `doc/` (31 files, five `vof_workorders*.md` = 853 KB) split reference/history;
   README `-DCFD_BUILD_MPI` → `PECLET_FLOW_MPI`, `SolverColocated` default "ghost"; `pyproject`
   "single-rank"; `ci.yml` "pybind11"; `AGENTS.md`/`GEMINI.md` either made true or deleted.
3. dem: write `dem/CLAUDE.md` (build matrix, three test projects, hidden call orders); README
   folder listing (12 of 22 headers), venv paragraph, `docs/solver_details.md` still narrating `src/cuda/*.cu`.
4. voro: write `voro/CLAUDE.md`; README drops Lees–Edwards (zero occurrences in `include/`),
   `PECLET_VORO_BUILD_BENCHMARKS` (does not exist), `mainpage.dox`, "two surfaces"; lists `fv/`;
   17 campaign notes to `docs/history/`.
5. core: `README`/`CLAUDE.md`/`pyproject` still say `tpx_amr`/`tpx_mpi`, "26 ctests" (157);
   `docs/` split reference (4) / campaigns (7); `amr_advection_session_prompt.md` deleted.
6. pnm: `pore_extraction.hpp` header guard `PECLET_FLOW_…` and `@brief flow —`; `sdf_reader.cpp:126`
   unconditional `std::cout`; `cerr` warnings and the four `fprintf(stderr)` non-convergence paths
   in the MPI file become exceptions.
7. morton: README H1 `morton-arithmetic`, `pyproject` comment (`mortonarith`), "python 3.8+" badge
   vs `>=3.9`, `docs/ROADMAP.md` "v0.3"; ship `bindings/morton_c.h` so the 26 C exports are a
   documented ABI; decide `octree/` (split out or delete — "being split out" since July).

## 4. Order and gates

| step | packages | gate |
|---|---|---|
| 1 | A + B + C + H1 (umbrella docs) | every repo's existing battery green on host-openmp; `check_release_state.sh` clean; gallery pages grep clean of removed names |
| 2 | D | a red test in CI is a real failure; MPI suites run in CI |
| 3 | **tag 1.0.0** ("physical domains", the clean-break release) | RELEASE.md phases A–I |
| 4 | E + F | 1.x: env vars retired, diagnostics tier (additive where possible; breaking → 2.0) |
| 5 | G + H2–7 | `flow_ibm.hpp` split, AMR flow relocated (D6), pnm dedupe |

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
