# Changelog

All notable changes to the peclet suite are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — 1.0.0, the clean break

**Every package goes to 1.0.0.** This release removes every non-canonical Python name instead of
aliasing it (the suite had no external users; [docs/QUALITY_PLAN.md](docs/QUALITY_PLAN.md) D1/D9 and
[docs/NAMING.md](docs/NAMING.md) §0). From 1.0.0 on a rename is additive and deprecated for two
releases before removal, and a break costs a major. The full old→new table is NAMING.md §2; in short:

- **peclet.flow**: `get_spacing()`→`spacing`, `get_resolution()`→`cells`, `global_resolution()`→
  `global_cells`, `cell_centres()`→`cell_centers()`, `scene_instance_count()`→`num_scene_instances()`,
  `vof_block_colour`/`vof_filled_colour`/`enable_vof_blocks_from_colours(colours=)`→`…color…`;
  `set_velocity_streams()` (a no-op) and the ignored `set_solid(pressure_coarse=)` keyword are gone.
  `get_ox/oy/oz` stay (they are the openness fields). **API tiering (F, 2026-09-10):** 125 developer
  members move to `solver.diagnostics` (instruments, timers, census/budget/ledger calls, solver tuning
  beyond driver selection, ablation switches, the zero-copy `field_view`/`exchange_field*`/
  `rebalance_by_weights`); ONE collocated scheme setter, `set_collocated_scheme('ghost'|'gauge-exact'|
  'plain'|'embed')` — `set_face_interp` modes 1, 2, 3, 4, 10, 11, 12, 13, `'gauge-2a'`, `set_fv_relax`
  and `set_aperture_floor` are deleted with their kernels (the two intermediate embed rungs survive as
  `diagnostics.set_face_interp(5|6)`); every integer code is a string (`set_domain_bc('-x', 'inflow',
  …)`, `set_advection_scheme('sou'|'koren')`, `add_scalar(scheme='koren')`, `set_scalar_bc(name, face,
  'dirichlet', v)`, `set_csf_mode('face'|'cell')`, …); the `_off` pairs and `disable_vof_blocks` collapse
  into their setters; and the "call BEFORE" docstrings became checks that raise (`set_domain_bc` after
  geometry, `set_decomposition` after `init_mpi`, …) — a late `set_rho`/`set_mu` used to leave a stale
  stencil silently and now rebuilds it; a VALUE update of a domain BC or inflow profile after geometry
  (a ramped jet or lid) stays allowed and now refreshes the tangential fold it used to leave stale.
  `set_body_force((fx, fy, fz))` and `set_domain_bc(face, type, velocity=(vx, vy, vz))` take one
  3-sequence like dem and voro. **Structure (G.1, partial):** `project()` and `setSolidDevice` are
  stage dispatchers (5 + 9 stage members), `fillVelGhostsKeepOutflow` folded into `fillVelGhostsTo`;
  the domain-header split of `flow_ibm.hpp` follows. **Precision (G.6):** `option(PECLET_FLOW_OPERATOR_DOUBLE)`
  replaces the raw `-DPECLET_FLOW_MREAL_DOUBLE` flag and now covers the cut-cell IBM overlay too (it was
  hard float even in a double build); the ctest `no_float_operator_casts` refuses a bare `(float)` on an
  operator view; the shared cut-cell closure polynomials live once in core (`scheme/cut_cell_closure.hpp`,
  templated on the scalar; flow float, amr double — byte-identical formulas).
- **peclet.dem**: `initialize()`→`initialize_shape(shape_type, radius, …)` (radius mandatory),
  `enable_periodicity()`→`set_periodic()`, `get_domain_min/max()`→`origin`/`extent`, positional
  `set_domain(lx,ly,lz,px,py,pz)`→`set_domain(extent=, origin=, periodic=)`, `get_num_contacts()`/
  `get_num_manifolds()`/`get_max_overlap()`→`num_contacts()`/`num_manifolds()`/`max_overlap()`,
  `add_plane(6 scalars)`→`add_plane(point, normal)`, `export_lammps(pbc_enabled=)`→`periodic=`.
  **API tiering (F):** `step(dt)`→`set_dt(dt)`+`step(n)` (a stepper before `set_dt` raises; the silent
  `dt = 1e-3` default is gone), `step(0.0)`→`relax(n)`, `step_hertz(dt, …)`→`step_hertz(substeps,
  skin_frac)`, `step_mpi(nsteps=)`→`step_mpi(n=)`; shape codes→`'sphere'|'hollow_cylinder'|'box'`,
  `set_sphere_shape(r)`→`initialize_shape('sphere', r)`; `set_gravity(gx,gy,gz)`→one triple + `gravity`;
  SDF grids→one 3-D array; `set_stabilization(bool)`+`set_stabilization_mode`→`set_stabilization(str)`;
  counts (`num_particles`, `num_contacts`, `num_manifolds`, `max_overlap`, `num_asleep`, `rank`,
  `num_ghost`, …), `growth_factor`, `growth_rate`→properties; `init_mpi(size=, gsize=)`→`(origin, extent,
  cells, periodic)`; developer members→`sim.diagnostics` (`set_velocity_solver`, `set_cuda_graphs`,
  `set_fused_sweeps`, `coloring_conflicts`, `rest_orphan_stats`, `rest_bank_stats`, `wall_sdf_at`,
  `profiling_info`, `mpi_rebuilds`, `mpi_gathers`, the `'escalate'`/`'ordered'` stabilization modes).
  New checks raise where the old code was silent: `set_positions` beyond `capacity`, per-particle
  setters with a wrong row count (`set_velocities` used to mis-index `(N,4)` input), `set_dt(≤0)`, bad
  mode/shape names. `get_sdf_grid` now returns a Fortran-ordered `(rx,ry,rz)` array (it returned
  x-fastest data with C strides, transposed on non-cubic grids).
- **peclet.voro**: `set_box(L)`→`set_domain(extent=)`, `step(n, dt)`→`set_dt(dt)`+`step(n)`,
  `sphere_centres=`/`centres=`→`sphere_centers=`/`centers=`; getters made uniform — arrays copied out
  carry `get_` (`get_volumes()`, `get_neighbor_counts()`, `get_wall_counts()`, `get_velocities()`),
  stored scalars are properties (`time`, `num_cells`, `num_faces`, `num_wall_faces`, `layout`,
  `pressure_iterations`), computed scalars are bare methods (`kinetic_energy()`, `internal_energy()`).
  **API tiering (F):** developer members move to `<object>.diagnostics` (`build_report`,
  `set_local_certificate`, `set_gate`, `set_skew_corrected`, `set_wall_gradient_quadratic`, `set_repair`);
  `set_wall_mode('exact'|'skin')`; `set_body_force((fx, fy, fz))`; the mesh optimizers take `extent`
  and keyword-only options and return `OptimizeResult` / `InterfaceResult` / `RedistributeResult`
  objects instead of dicts (`minimize_interface` no longer reports its energy through `maxVolErr`);
  the pore-mesh algorithms live in `peclet.voro.pore_mesh` and the scene helpers in
  `peclet.voro.scenes` (`_union_sdf` → `scenes.sphere_union_sdf`); `FlowSolver(amg=)` (an unreached
  plain-CG ablation) is gone; `VoronoiHalo(cells, *, extent, origin, periodic)` with `rank`/`num_ranks`
  properties; **new** `DistributedTessellation` binds the distributed moving tessellation (global
  skin-trip reduction included) so the MPI story no longer needs hand-driven halo gathers.
  **Structure (G.7):** `pore_mesh.sdf_voronoi_cells` / `sdf_voronoi_section` run on the device
  (`search_window=` keyword, `num_overflow`/`num_incomplete` in the result) — and their VALUES changed:
  the old host reconstruction's fixed 80-nearest gather missed planes on ~1 % of cells (volumes off by
  up to 2.5e-3); the new path is gated against a certified shell-walk oracle. `PECLET_VORO_PROFILE` is
  gone → `<object>.diagnostics.set_profile(on)`, and `build_report()` reports `over_buffer_rebuilds`.
  Engine defaults have one home, `include/peclet/voro/params.hpp` (`ConvexCell`'s template default
  is 64/112 like every consumer; it was 64/96).
- **peclet.pnm**: `extract_topology_gpu(shape=)`→`extract_topology(shape_zyx=)`; **API tiering (F):**
  the segmentation, the connections and the network-flow arrays are ndarrays in and out
  (`segment_volume` → `int32 (Nz,Ny,Nx)`, `extract_topology`/`connections`/`throats` → `(M,2) int32`,
  the five network-flow scalars → float64; they were Python lists of boxed ints/floats/tuples — same
  values, same order), `extract_topology` reads the 3-D array in place, `mpi_block` returns
  `(offset_zyx, shape_zyx)` (the integer voxel offset was spelled `origin_zyx`, colliding with the
  physical origin every other call takes), `mpi_rank()`/`mpi_size()` are gone (mpi4py has them);
  `Pore` gained
  constructors and `__repr__`; malformed VTI files and non-convergence now raise instead of printing.
- **peclet.amr — NEW eighth package (G.2, D6):** the whole `core/amr/` tree — the block-octree AMR
  infrastructure AND the collocated cut-cell Navier–Stokes solver on it — is relocated with its git
  history into `peclet-amr` (`import peclet.amr`; `peclet.core.amr.{Octree, DistributedOctree, Poisson,
  Flow}` → `peclet.amr.{…}`; C++ `peclet::core::amr` → `peclet::amr`, `peclet/core/amr/` → `peclet/amr/`,
  `PECLET_CORE_AMR_*` → `PECLET_AMR_*`). It depends on peclet-core and peclet-morton only, requires MPI and a
  Kokkos backend, and is sdist-only (`pip install peclet[amr]`). The face-CSR operator, the BiCGStab
  solver, the greedy graph colouring and the vector primitives it shared with voro were lifted into
  `peclet::core::solver` (`core/include/peclet/core/solver/{face_csr,csr_operator,csr_bicgstab,coloring,
  vector_ops}.hpp`, bodies verbatim; voro includes those now). **API tiering (F):** `Flow.diagnostics`
  holds the instruments (`last_mom_iters`, `last_pres_iters`, `last_outer_iters`, `divergence_norm_face`,
  `set_momentum_mg`, `set_momentum_gs`, `set_velocity_mg_staircase`, `set_momentum_mg_solver`,
  `set_ghost_gradient`, `set_aperture_order`). **Environment variables removed (E):** `PECLET_CORE_GPS_RHO` /
  `PECLET_CORE_GPS_MAXN` → `Flow.set_ghost_sampled(on, rho=2.2, max_samples=0)` (defaults bit-exact);
  `PECLET_CORE_PROFILE_*` (prints) → `PECLET_AMR_PROFILE_*`. `Octree` and `DistributedOctree` bind their 16
  shared members once (G.5). Byte gate across the relocation: `python/state_hash.py` in both repos.
- **peclet.core**: the AMR tree is gone (above); core is decomposition, halo, geometry, load balancing,
  the VoF kernel layer and the shared `solver/` layer. `mpi.Migrator`/`Halo`→`ParticleMigrator`/`ParticleHalo` with `(origin, extent,
  cells, periodic)`; `num_ghost`/`num_owned` are properties; `amr.Octree(brick, lmax, …)`→
  `Octree(cells, *, lmax=0, origin=, spacing=None, extent=None)` (`cells` is the finest grid),
  `.h0`→`.spacing`; `.pyi` stubs for `amr`/`mpi`/`geom` ship in the wheel; `find_package(peclet-core
  CONFIG)` works.
- **peclet.coupling**: `CfdDem(smooth_width=, h=)`→`smooth_length=` (spacing from the flow solver);
  `ResolvedCfdDem(rho_f=, periodic=bool, move=)`→`rho=`, `periodic=(…)`, `move_particles=`;
  drag names `bvk`/`bvk2`→`beetstra`/`tang`; one `eps_min` default.
- **peclet.morton**: C library `libmortonarith_c`→`libpeclet_morton_c` with a shipped `morton_c.h`;
  the `legacy/` tree removed (tag `pre-legacy-removal`).

- **peclet.dem — numerics fix (G.4, `93eec07`):** single-rank periodic wrap contacts are now resolved
  symmetrically. A wrap pair whose farther partner sat more than one maximum radius beyond the periodic
  face had no image on that side, so only the un-imaged partner moved, and by half the de-penetration;
  the ghost band is now `2·maxRad + margin` (ghost capacity follows). Results change only for periodic
  single-rank runs with such pairs; the MPI step was already symmetric and is unchanged. Structural:
  `src/sim.hpp` split into `step_solve.hpp` / `step_solve_mpi.hpp` / `shape_registry.hpp` (bit-exact,
  gated by the committed `tests/regression/state_hash.py`).

**Environment variables removed** (QUALITY_PLAN D3: no env var may change numerics; every knob is a
setter with a documented default, defaults bit-exact to the old unset behaviour):

- **peclet.flow**: all 25 `PECLET_FLOW_*` (and `PECLET_PC_DEPOSIT_FALLBACK`) reads that changed a
  result are gone. The process-global `CutcellMG::setDecompositionLevels` static and its siblings
  become per-solver state: `decomposition(levels=, max_imbalance=)`, `set_decomposition(...)`,
  `mpi_block(..., levels=, max_imbalance=)`; `PECLET_FLOW_CA`'s four states become
  `set_comm_avoiding('both'|'off'|'momentum'|'pressure')`; the rest became individual setters whose
  defaults reproduce the old unset behaviour bit-exactly. This closes a cross-solver leak: the
  exact-residual flag was process-wide, so enabling VoF on one solver silently changed a later
  single-phase solver's pressure solve. Only `*_DEBUG` variables remain, and a test enforces it.
- **peclet.dem**: `PECLET_DEM_REST_MODEL`→`set_restitution_model('newton'|'poisson')`;
  `PECLET_DEM_SLEEP`/`_SLEEP_SCALE`/`_SLEEP_K`/`_WAKE_SCALE`/`_SLEEP_WAKELOST`/`_SLEEP_INVMASS_FRAC`→
  `set_sleeping(enabled=True, threshold_scale=2.0, consecutive=64, wake_scale=40.0,
  wake_on_lost_contact=False, immovable_frac=0.01)`; `PECLET_DEM_VERLET_SKIN`→`set_verlet_skin(0.0)`;
  `PECLET_DEM_NO_GRAPH`→`set_cuda_graphs(True)`; `PECLET_DEM_FUSED`/`_NO_FUSED`→
  `set_fused_sweeps('auto'|'on'|'off')`; `PECLET_DEM_NO_INCR_COLOR`→`set_incremental_coloring(True)`;
  deleted with their code paths: `PECLET_DEM_FUSED_GRID` (tuning cap), `PECLET_DEM_ML_GATES`,
  `PECLET_DEM_REST_NEWTON_OFF`, `PECLET_DEM_REST_ONESIDED` (ablations). Read-only properties
  `sleeping`, `verlet_skin`, `cuda_graphs`, `fused_sweeps`, `incremental_coloring`; a test greps
  `src/` for `getenv`. Kept: `PECLET_DEM_HERTZ_PROFILE`. (`PECLET_DEM_SYMMETRIC_PGS`, used by the
  gallery's production scripts, was never read by any version — those runs were no-ops on it.)

Also: every repo's CMake `project(VERSION)` now reads `pyproject.toml`; the `transport_core`/`tpx_*`
CMake names became `peclet_core`/`peclet::core`, `PECLET_TPX_TAG`→`PECLET_CORE_TAG`, flow's target
`sdflow`→`peclet_flow`, voro's `vorflow` remnants gone; tracked artefacts removed (a third-party PDF,
logs, PNGs, dem's 2.5 MB run log, voro's retired-engine zip); dead test harnesses deleted; new
`dem/CLAUDE.md`, `voro/CLAUDE.md`; pnm and coupling gained CI/quality workflows.

## [0.7.2] — 2026-09-06

CUDA wheels only. `peclet-flow-cu13` 0.5.1, `peclet-pnm-cu13` 0.1.2, `peclet-dem-cu13` 0.5.1,
`peclet-voro-cu13` 0.5.1 (their CPU twins re-released at the same numbers with no code change) now embed
native machine code for Turing (sm_75), Ampere (sm_80), Hopper (sm_90) and Blackwell (sm_100, sm_120) plus
the Turing PTX, and are built with the oldest CUDA 13 toolkit so that PTX JIT-compiles on every 13.x
driver. The 0.4.0–0.5.0 wheels carried sm_75 code + PTX from CUDA 13.2 only: on a non-Turing GPU with a
driver older than 13.2 every import aborted with Kokkos "likely mismatch of architecture" (the driver
cannot JIT PTX newer than itself, and under minor-version compatibility the launch silently no-ops).
`peclet-cu13` / `peclet` 0.7.2 pin the new numbers; `peclet[mpi]` still pins peclet-core 0.6.1.

## [0.7.1] — 2026-09-06

Metapackage-only follow-up: `peclet[mpi]` / `peclet-cu13[mpi]` pin **peclet-core 0.6.1**, whose
standalone sdist builds again. `pip install peclet-core` (and therefore the `[mpi]` extra) had failed
since the nanobind port (0.1.0 through 0.6.0): the build included `SuiteNanobind.cmake` from the
umbrella checkout, which an sdist does not contain. The file is now vendored under `core/cmake/`
(searched after the umbrella's copy). Found by the 0.7.0 fresh-venv smoke test; no other member
changes. The docs site carries no version literals any more (PyPI badge + this file + the moving
container tags are the version surface); `CITATION.cff` carries the concept DOI only.

## [0.7.0] — 2026-09-05

Family: peclet-core 0.6.0, peclet-flow 0.5.0 (+ peclet-flow-cu13), **new** peclet-pnm-cu13 /
peclet-dem-cu13 / peclet-voro-cu13 and the `peclet-cu13` CUDA metapackage, peclet-pnm 0.1.1 (core
header repin), peclet-dem 0.5.0, peclet-voro 0.5.0, peclet-coupling 0.4.0, peclet-morton 0.2.1 (unchanged).

### Added
- **flow**: geometric VoF two-phase flow (Weymouth–Yue advection, CSF surface tension with curvature
  branches, contact angle, phase change), analytic-SDF **scenes with moving instances** (`set_scene`,
  `set_solid_from_scene`, `set_instance_motion/transform`, `hydro_force_torque_reaction`), momentum
  residual stop + velocity multigrid, telescoping pressure hierarchy, `rebalance_by_weights`, ghost MASK exchange.
- **core**: `peclet.core.geom.SceneBuilder` (analytic CSG scene authoring, mass properties), weighted
  rebalancing hooks, GPU-aware halo option; NBX inter-round tag-race fix.
- **dem**: analytic SDF walls with `set_wall_transform` / `wall_sdf_at`, `set_external_torques`, scene
  particles (`peclet.dem.scene_particle`), `set_shape_ids`; two out-of-bounds writes fixed.
- **voro**: `FlowSolver` (covolume + collocated Navier–Stokes on a Voronoi mesh), `redistribute_pore_mesh`,
  covolume MPI hooks, device-packed ghost exchange.
- **coupling**: `ResolvedCfdDem` (resolved cut-cell CFD-DEM), reaction torque opt-in.
- **flow**: free-slip / symmetry domain boundary (`set_domain_bc(face, 4)`, both grids, MPI; a half domain
  closed by a symmetry plane reproduces the full one pointwise) and the outflow-reversal census
  (`outflow_backflow()`, a one-time warning when an outlet reverses with the backflow stabilization off).
- **Packaging**: CUDA wheels for the whole family (`pip install peclet-cu13`); containers now include pnm
  and coupling; `__version__` derived from the installed metadata; release workflow documented in
  `docs/RELEASE.md` with pre-flight and audit tools under `tools/release/`; Snellius family install +
  smoke scripts under `tools/hpc/`; LUMI recipe (`docs/LUMI.md`, untested).

### Changed / Fixed
- **Clean interpreter teardown in every module** (was a `Kokkos::abort`, exit 134, whenever a solver or a
  zero-copy view outlived the atexit finalize — scripts, `python -c`, notebooks): shared
  `kokkos_teardown.hpp` registry, release-then-finalize; explicit `finalize()` per module.
- `__version__` reports the installed distribution's version (was a stale literal in every package).
- HIP (LUMI) link: default symbol visibility on the HIP path + AMR wrappers in a named namespace.
- **core.amr**: `Flow.step()`/`project()` before `set_solid` raise a named `RuntimeError` (was a segfault);
  `set_solid`/`finish_adapt`/`rebalance_mpi` with a Python callable no longer hang under the OpenMP host
  backend (the bindings release the GIL around the multithreaded operator build).
- **core**: NBX round tags live in a reserved range (fixes the np=8 particle-halo hang and the
  intermittent distributed-AMR ghost errors).
- **dem**: `add_scene_shape` sizes the contact buffers and every capacity-sized array follows the
  particle capacity (was a silent contact drop, then heap corruption); root-level scratch scripts are
  excluded from the sdist.
- (more at release time from the per-package logs — see RELEASE_PREP §1.4 for the gallery-found defects)

### Known limitations
- LUMI / HIP: the `peclet-hip` image builds and is published for the first time, but has not run on AMD
  hardware (no LUMI allocation yet) — see docs/LUMI.md.

## [0.6.0] — 2026-07-25

Family release: peclet-flow 0.4.0 (**BREAKING**: pore-network extraction split out of `peclet.flow.pnm`),
**new** peclet-pnm 0.1.0 (`peclet.pnm`: extraction + distributed MPI extraction + DNS network flow with
per-patch throats), peclet-dem 0.4.0, peclet-voro 0.4.0, peclet-morton 0.2.1 (cp38 wheels dropped),
peclet-core 0.5.0, peclet-coupling 0.3.0; peclet-flow-cu13 0.4.0. Zenodo DOIs minted per repo.

## [0.5.0] — 2026-07-06

peclet-coupling 0.2.0 joins the family as the `[cfd-dem]` extra (unresolved point-particle CFD-DEM
`CfdDem`: void fraction, drag laws, semi-implicit feedback); dem event-level restitution + multilevel
contact stabiliser; flow porous (ε-weighted) momentum for coupled runs.

## [0.4.4] / [0.4.3] / [0.4.2] / [0.4.1] — 2026-07-04

voro 0.3.1 → 0.3.3: SDF pore-mesh optimiser in the Python API (`optimize_pore_mesh`), O(N)
`sdf_voronoi_cells`, `ConvexCell::sectionPolygon` / `sdf_voronoi_section`; dem 0.3.1 `to_stl` mesh export.

## [0.4.0] — 2026-07-04

peclet-flow 0.3.0 (verify_bfs shear-layer stability, inflow/outflow + immersed solid fixed, deferred
correction), peclet-flow-cu13 first published (single-GPU CUDA wheel on `nvidia-cuda-runtime`),
dem 0.3.0, voro 0.3.0, core 0.3.0.

## [0.3.0] — 2026-07-03

voro graph-AMG mesh-optimiser preconditioner (host + device).

## [0.2.2] — 2026-07-03

peclet-flow 0.2.1: inflow/outflow domain BCs with immersed solids, `set_backflow_stabilization`,
`set_deferred_correction`.

## [0.2.1] — 2026-07-03

peclet-dem 0.2.1: periodic collision detection fix (unfilled ghost halo layers in the Kokkos port;
found through the gallery's random-packed-bed g(r)).

## [0.2.0] — 2026-07-02

Feature release: multi-rank Python API + HPC MPI containers.

### Added
- **Multi-rank (MPI) `flow` and `voro` exposed to Python**: `peclet.flow.Solver.init_mpi(gnx,gny,gnz)` +
  `peclet.flow.mpi_block(...)` for the distributed Navier–Stokes solve; `peclet.voro.VoronoiHalo` for the
  distributed tessellation (both validated bit-exact / Σvol-exact at np=1/2/4). Gated on
  `PECLET_FLOW_MPI` / `PECLET_VORO_MPI` (on in the containers).
- **MPI-enabled Apptainer containers** on GHCR (public): `peclet-cpu` and `peclet-cuda` (`-sm80`/`-sm90`),
  with `mpi4py` + distributed flow/dem/voro; the CUDA image bundles a from-source **CUDA-aware OpenMPI**.
- **Per-site launch**: MPI bind wrappers `snellius-run.sh` / `tue-run.sh` / `lumi-run.sh` + SLURM submit
  scripts for Snellius, TU/e SMM (`chem.smm03.q`), and LUMI.
- **Weak-scaling communication-overhead benchmark** `benchmarks/profile_mpi_flow.py`.
- Open-source hygiene: status badges, `CITATION.cff`, `CONTRIBUTING`/`CODE_OF_CONDUCT`/`SECURITY`,
  issue/PR templates, Dependabot, repo descriptions + topics.

### Fixed
- nvcc: an extended `__host__ __device__` lambda in a private dem method (`maxOwnedDisplacement`).
- Container builds on the Ubuntu-22.04 GPU bases: conditional `pip` upgrade for `--config-settings` /
  `--break-system-packages`.

### Changed
- Project display name capitalized to **Peclet** in the documentation (package/import/CLI names remain
  lowercase `peclet`).

### Known limitations
- The **LUMI / HIP** container still does not build (hipcc/lld undefined-vtable link error); needs on-GPU debugging.

## [0.1.0] — 2026-07-02

First public release.

### Added
- **`peclet.*` PEP-420 namespace family** on PyPI: `peclet-core`, `peclet-flow`, `peclet-dem`,
  `peclet-voro`, `peclet-morton`, and the `peclet` metapackage (`pip install peclet` for the CPU family).
- **Self-contained multicore-CPU (OpenMP) wheels** for the compute codes (vendored Kokkos/ArborX); GPU
  and MPI builds via source + containers.
- **`peclet.flow`** — incompressible cut-cell IBM Navier–Stokes on a staggered MAC grid with geometric
  multigrid pressure solve; `pnm` pore-network extraction. Multi-rank (MPI) solver exposed to Python
  (`Solver.init_mpi`, `mpi_block`).
- **`peclet.dem`** — XPBD discrete-element packing with SDF collision + distributed step.
- **`peclet.voro`** — dynamic Voronoi tessellation + distributed `VoronoiHalo`.
- **`peclet.core`** — shared ORB block decomposition, asynchronous grid/particle halo, SDF geometry,
  dynamic load balancing, AMR octree (MPI + Kokkos).
- **`peclet.morton`** — Morton/Z-order codes with arithmetic in Morton space.
- **Documentation site** (MkDocs Material, GitHub Pages) with a Python-forward API reference and per-code
  Doxygen; **HPC container** guide.
- **Apptainer containers** on GHCR: `peclet-cpu` and `peclet-cuda` (`-sm80`/`-sm90`), MPI-enabled
  (mpi4py + distributed flow/dem/voro), with per-site MPI bind wrappers (`snellius-run.sh`, `tue-run.sh`,
  `lumi-run.sh`) + SLURM submit scripts and a weak-scaling communication-overhead benchmark
  (`benchmarks/profile_mpi_flow.py`).
- MIT license across the suite; `CITATION.cff`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.

### Known limitations
- The **LUMI / HIP** container does not yet build (an `hipcc`/`lld` undefined-vtable link error involving
  nanobind hidden-visibility and the static Kokkos libraries); it needs on-GPU debugging. The CUDA image
  demonstrates the multi-GPU flow/voro code is correct.
- Multi-node / multi-GPU container runs on Snellius/LUMI/TU-e have not been validated on-cluster (match
  your site's exact OpenMPI module for the bind model).

[0.6.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.6.0
[0.5.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.5.0
[0.2.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.2.0
[0.1.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.1.0
