# Changelog

All notable changes to the peclet suite are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-09-16 — the momentum solve, twice as fast

`peclet-flow` 1.1.0 · `peclet-core` / `peclet-dem` / `peclet-pnm` / `peclet-voro` 1.0.2 ·
`peclet-morton` 1.0.1 and `peclet-coupling` 1.0.1 unchanged (no commits since their tag) ·
`peclet-amr` 0.1.1 (still 0.x while under development).

### Changed

- **The implicit momentum solve now runs the velocity multigrid V-cycle by default, and it is
  roughly 2x faster.** Red-black Gauss–Seidel was the default and the V-cycle was selected only
  *below* 65536 cells per rank and only at `np > 1` — a rule whose premise had the sign of the
  effect backwards. Measured on the 1.0.0 scaling benchmark (384³ cut-cell bed, Snellius), the
  V-cycle is faster at every rung of both ladders and its margin is **largest at the biggest
  blocks**:

  | configuration | cells/rank | red-black | V-cycle | speed-up |
  |---|---|---|---|---|
  | Genoa, 24 cores | 2.36 M | 70890 ms | 36176 ms | 1.96x |
  | Genoa, 384 cores | 147 k | 8130 ms | 3646 ms | 2.23x |
  | Genoa, 768 cores | 74 k | 2904 ms | 1745 ms | 1.66x |
  | H100, 1 GPU | 56.6 M | 4025 ms | 1840 ms | 2.19x |
  | H100, 4 GPUs | 14.1 M | 1203 ms | 664 ms | 1.81x |

  Red-black was not merely slower: it ran at its sweep cap (200 per component) on every rung of
  both ladders, so it was **not converging**. The V-cycle takes 9.7 cycles, rank-independent.
  Accuracy is unchanged — that was checked rather than assumed.

  *If you benchmarked 1.0.x, note that the momentum default moved underneath you:* published
  1.0.0 scaling figures were taken at the 1.0.0 default, not this one.

- **The momentum solver is chosen by the operator's condition number, not by whether geometry is
  present.** The previous rule keyed on "a solid is present", so an IBM-sculpted body and a plain
  domain-BC box at the same `dt` got different solvers. The criterion is now
  `kappa = 1 + 4 dt mu (w_x + w_y + w_z) / rho` (`= 1 + 12 D` isotropic): V-cycle at `kappa >= 13`
  (`D >~ 1`), red-black below. The crossover was measured on a 64³/96³ channel with domain BCs and
  **no solid** — the case that had no evidence behind it before.

- The Chebyshev momentum solvers are bound on `solver.diagnostics`, not on the public `Solver`.
  Under [docs/RELEASE.md](docs/RELEASE.md) §4.1 and [docs/NAMING.md](docs/NAMING.md)'s alias ladder,
  removing public API later costs a major bump; ablation knobs belong on the diagnostics tier
  (QUALITY_PLAN D2), beside `set_velocity_multigrid_auto` and dem's existing
  `diagnostics.set_velocity_solver`.

### Added

- **One string selector per choice instead of a boolean per solver**, extensible without breaking
  the API:

  ```python
  solver.diagnostics.set_velocity_solver('auto' | 'gauss_seidel' | 'multigrid' | 'chebyshev')
  solver.diagnostics.set_velocity_mg_smoother('gauss_seidel' | 'chebyshev')
  solver.diagnostics.velocity_solver()          # readbacks
  solver.diagnostics.velocity_mg_smoother()
  ```

  Two axes, kept apart because they are orthogonal: which solver runs the momentum equation, and —
  only when that is `'multigrid'` — which smoother runs inside the V-cycle. `'auto'` is reachable as
  a value for the first time: it clears an explicit choice and re-decides at the next `step()`,
  where `dt` and `mu` are final. Spelled as `peclet.dem` already spells it (NAMING.md's whole
  point).

- **Chebyshev semi-iteration as an alternative momentum solver**
  (`diagnostics.set_velocity_chebyshev`). The implicit momentum solve is a screened Helmholtz whose
  condition number is a property of the diffusion number `D = mu dt / (rho h²)` and not of the mesh,
  so red-black needs `O(kappa)` sweeps where Chebyshev needs `O(sqrt(kappa))` — and one Chebyshev
  step costs one residual and one halo exchange against a red-black sweep's two of each, with every
  lane active instead of half. The spectral interval is Gershgorin arithmetic on the stored stencil,
  reduced over the communicator so every rank iterates with the same polynomial; a degenerate
  interval falls back to red-black rather than diverging. It delivers the predicted `sqrt(kappa)`
  factor (107 iterations/component against 147, predicted 111) but **loses to the V-cycle except at
  the smallest per-rank blocks**, and its docstring says so.

- **Chebyshev as the velocity multigrid's smoother**
  (`diagnostics.set_velocity_mg_chebyshev`), independent of the above. **Measured slower**, and the
  docstring says that too: at degree 4 / ratio 6 it is the stronger smoother per cycle (8.0 V-cycles
  against 9.3) and still loses on wall clock. Shipped because the measurement is worth keeping, not
  because it wins.

- **CPython 3.14 CUDA wheels.** `peclet-flow-cu13`, `peclet-pnm-cu13`, `peclet-dem-cu13` and
  `peclet-voro-cu13` now build one job per interpreter across cp310–cp314, matching the CPU wheels;
  cp314 users were falling through to a source build.

### Fixed

- **A solid cutting an inflow or outflow face no longer produces an unsolvable pressure system.**
  Three defects hid in the same gap — nothing anywhere had put an immersed solid *on* an open
  domain face — and none could be fixed alone, because each masked the next.

  The SDF ghost band outside a non-periodic face was filled by **periodic wrap**, so the geometry an
  inlet or outlet face saw was teleported from the opposite side of the domain. That decides the
  boundary-face aperture: a solid cell against the inlet (`sdf = -0.73`) was handed the far side's
  fluid and its inflow face came out fully **open**, so prescribed inflow was counted into a cell
  whose pressure row is entirely closed. `0*p = U` is an inconsistent row, and no Krylov driver and
  no multigrid depth solves an inconsistent system — which is precisely why the field evidence
  showed FCG capping, Chebyshev NaN-ing and divergence at `MGLEVELS <= 2`, and why the agglomerated
  bottom was (correctly) exonerated. The Dirichlet outlet row separately carried the literal
  openness `1.0` instead of the face aperture, i.e. mass leaving through solid.

  This closes [docs/SCALING_ISSUES.md](docs/SCALING_ISSUES.md) #3, and the **MPI-only** defect it
  surfaced as #8 — the halo wrapped a non-periodic face's *high* boundary plane. Both halves
  (openness and the outflow velocity plane) had to land together, since fixing either alone breaks
  `vof_bc_mpi`'s composed conservation budget.

  Gated by `test_openbc_solid{,_mpi}` — the first tests anywhere to combine `set_domain_bc` with
  `set_solid` — now run on **both** the staggered and collocated grids, plus a `colo-jet` case
  giving `SolverColocated` its first open-boundary conservation gate of any kind. The collocated
  path needed no code change: every part of the fix is in the geometry, and geometry is
  grid-independent. What was missing there was the gate, not the fix.

- **flow's height-function curvature is selected as often as it was before 1.0.0 again, and the
  droplet damping with it.** The cascade and the advector disagreed about what a PURE cell is.
  `enable_vof` runs Weymouth–Yue at `wispEps = 1e-8` (a cell that close to 0 or 1 is treated as a
  pure phase and fluxed algebraically, which is what stops a DRAINED open domain from taking the
  MYC normal of round-off residue and going to NaN in three steps). Such a cell is never
  reconstructed back onto exactly 1.0, so the colour field legitimately carries bulk liquid at
  `1 - O(1e-9)` — while the height-function column walk judged purity at its own hard-coded
  `1e-10`, two orders tighter, found no pure end to the column, and rejected it.

  The result degraded *progressively and silently*: a fallback is a valid answer, so nothing
  failed and no test went red — the curvature just got worse the longer a run went on. On the
  capillary-oscillations mode-2 droplet the HF tier fell from 790 interface cells to 134
  (37 % → 89 % PLIC fallback) over 2.5 periods, tracking 425 bulk cells drifting into the band
  between the two tolerances, and the fitted damping rate came out 1.029e-3 against 1.460e-3.

  Every VoF consumer is now TOLD what a pure cell is instead of deciding for itself — the same
  contract phase change was given in `633a144` when it hit this mechanism first. `core`'s
  `hfColumnHeight` takes a `pureEps`; `Solver::computeVofCurvature` sets it from the advector's
  `wispEps` at the point of use. With the fix the same run reads 784 HF cells / 37.0 % fallback
  and a damping rate of 1.407e-3, against 790 / 37.2 % / 1.460e-3 for the pre-regression
  configuration. `test_vof_curvature` gate H pins the contract: a bulk deficit inside the
  advector's tolerance must not cost the HF tier (it cost all of it — 1968 cells → 0 — before).

  Runs at `wispEps = 0` (the standalone advector's default, and `enable_phase_change`) are
  bit-identical. The drained-domain guard is untouched.

  *This entry was briefly filed under 1.0.1 by mistake.* Both halves of the fix (core `e6a612d`,
  flow `28d3224`) landed the day **after** the 1.0.1 tag, so 1.0.1 never carried them; it ships
  here.

### Tested

Measured on the release host (48-core Genoa + RTX 5080, sm120) on 2026-09-16, `OMP_NUM_THREADS`
bounded, every suite built fresh against `extern/install/{host-openmp,nvidia-cuda}`:

| suite | result |
|---|---|
| `core` plain (serial + MPI halo, migration, load balancing) | **54/54**, np 1–8 |
| `core` Kokkos (halo + AMR + solver layer), host and **CUDA** | **69/69** each |
| `core` Python bindings | **6/6**, np 1–8 |
| `flow` kernel units, host and **CUDA** | **46/46** each |
| `flow` distributed `tests/kokkos_mpi` | **109/109**, np 1, 2, 4 |
| `flow` accuracy/efficiency regression | **PASS** — `K_inf`, convergence order, pressure-iteration counts and step counts all `+0.00 %` against baseline on all three cases |
| `flow` analytic verifications | **5/5 PASS** — Poiseuille, periodic spheres, lid cavity, channel, backward-facing step |
| `dem` single-rank + MPI | **green on CI** at the release commit |

Two notes on what these numbers do and do not cover. `flow`'s 109 distributed tests are 106 plus the
three new `openbc_solid_mpi_np{1,2,4}` gates this release adds. And the **~2x momentum speed-up quoted
above was measured on Snellius** (Genoa and H100 ladders, recorded in flow `8acab7c`) — it was *not*
re-measured on the release host, whose timings were taken under deliberate contention and are not
comparable. What the release host establishes is that the change is **numerically inert**: same
answer, same iteration count, to every digit the regression prints.

### Known limitations in 1.1.0

Carried over from 1.0.0 except the first bullet of that list — *an immersed solid cutting an inflow
or outflow face* — which is **fixed** above.

- **Multigrid depth is capped by the factors of two in the grid.** An axis coarsens only while it
  stays even, so an odd dimension never coarsens at all, and under MPI only if every rank's block is
  even on it. Telescoping ships and is the default; the underlying requirement that intermediate
  levels coarsen in place is routed around, not solved, and it remains the top open item at scale
  ([docs/SCALING_ISSUES.md](docs/SCALING_ISSUES.md) #2).
- **Collocated solver:** the `(matrix_order=1, rhs_order=2)` ghost mode is march-unstable above about
  2000 spheres and is documented do-not-use. Collocated MPI is validated at np = 1, 2, 4; np >= 16 is
  unresolved. (New in 1.1.0: the collocated grid now has open-boundary gates — `test_openbc_solid`
  runs on both grids and `colo-jet` gives `SolverColocated` its first open-boundary conservation
  budget — but the np >= 16 question is untouched.)
- **VoF:** the staggered grid is the reference. The collocated path is all-fluid and rated to density
  ratio about 100 with motion; the per-bubble block container is all-fluid and staggered-only for its
  surface tension. **Colliding markers are outside the rating** — a contacting pair drives through the
  two-cell film at roughly 1.5 eddy turnovers, independent of the timestep.
- **voro on CUDA:** `clipCellAgainstSdf` is wrong by up to 22 % on device at 128 and 256 grids, while
  correct on the OpenMP backend. Unchanged in 1.0.2, which is a packaging-only release for `voro`.
- **peclet-amr's octree V-cycle is a preconditioner, not a solver, on anisotropic (box) cells** — it
  diverges at aspect ratio 2 and 4 even though the operators themselves are exact. See
  `amr/docs/amr_anisotropic.md`.
- **morton's AVX-512 batch kernels were not re-validated for this release either.** They need Intel
  SDE or AVX-512 hardware and the release host has neither. `peclet-morton` is unchanged at 1.0.1.
- **`core` has no automated test covering `vof/curvature.hpp`.** The height-function fix shipping
  here was verified inert at its default by inspection and a standalone compile, and the behaviour it
  restores is gated in `flow` (`test_vof_curvature` gate H) — but nothing in `core`'s own 198-test
  suite reaches that header. Recorded so the next change to it is not made on the assumption that
  core's gate would catch a mistake.
- **Unresolved and recorded:** whether the reported permeability `K` is interstitial or superficial.
  [docs/DECISIONS.md](docs/DECISIONS.md) carries the contradiction; it decides a (1−φ) factor. **No
  permeability number is published in these release notes for that reason.**

## [1.0.1] — 2026-09-14 — it installs, and it uses your cores

A patch release with no API change and no numerics change, prompted entirely by what two users hit on
their own machines the day after 1.0.0.

### Fixed

- **A container no longer collapses the first run.** Kokkos sized its host thread pool from the CPUs
  it could *see*; Colab, Binder, Docker and a Slurm cgroup show you the whole host while granting a
  fraction of it through a cgroup quota, which OpenMP cannot see, so the pool spin-waited itself to a
  standstill — measured, a 2.5-second quick start did not finish in **15 minutes** on 2 CPUs of quota
  with 48 visible. `peclet-core` now resolves the process's own cgroup, walks up the chain for the
  tightest quota, caps by the affinity mask, and passes the result to `Kokkos::initialize`. Inert on
  an unconstrained machine: same thread count, same schedule, same numbers.
- **`pip install peclet` on Windows no longer ends inside CMake.** There was no Windows wheel, so pip
  fell back to the sdist and the build died with "No CMAKE_CXX_COMPILER could be found" — a message
  about a compiler when the answer was "not this operating system". There are wheels now (below), and
  a platform that still has none gets a message that says so.

### Added

- **Wheels for four platforms, not one.** `manylinux x86-64` (unchanged), **`manylinux aarch64`**
  (Graviton, Raspberry Pi, an ARM Chromebook's Linux container), **`win_amd64`** and
  **`macosx_11_0_arm64`** — every one multi-threaded, and every one built and import-tested in CI.
  Linux uses the OpenMP host backend; Windows and macOS use Kokkos' C++ threads backend, because
  MSVC reports OpenMP 2.0 whatever runtime you select and AppleClang ships none. The backend changes
  nothing numerical — the quick start returns k = 1.2407e-01 in 14 steps on all three — and
  `execution_space` reports which you have.
- **CPython 3.14.** It was missing on every platform, Linux included: a user on a current Python was
  falling through to a source build exactly like the Windows user above.
- `OMP_NUM_THREADS` now works on every backend. Kokkos itself reads only `KOKKOS_NUM_THREADS`, so on
  a Threads or Serial build nothing had been reading it.

### Changed

- Five build-system assumptions that were invisible on Linux and fatal elsewhere: `/bigobj` for
  MSVC's COFF section limit, `--config Release` when installing vendored deps under a multi-config
  generator, GNU warning flags no longer handed to MSVC, `M_PI` (a POSIX extension) replaced by the
  same double, and the vendored Kokkos host backend chosen by `find_package(OpenMP 3.0)` rather than
  hard-coded.
- PyPI classifiers on every package, including `Operating System :: POSIX :: Linux` where that is
  still the truth, and `docs/DEPLOYMENT.md` gained an "Operating systems and wheels" section.
- **The quick start is 2.5 s instead of 25.6 s** (N = 48 → 32, and a three-step convergence window
  instead of a single-step one that the iteration could dip through). Both values sit within 0.2 % of
  what their own grid gives when iterated to convergence, and the page now prints its own wall clock.

## [1.0.0] — 2026-09-12 — the clean break

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
- **peclet.amr — NEW eighth package (G.2, D6), released as 0.1.0 and staying 0.x (under development;
  its API may break in a minor until it graduates on its own merits — QUALITY_PLAN D9 exception):** the whole `core/amr/` tree — the block-octree AMR
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

**One deliberate numerics change — flow's operator storage is now DOUBLE by default.**
`PECLET_FLOW_OPERATOR_DOUBLE` flips from OFF to ON (`SCALING_ISSUES.md` #1). Float storage of the
pressure hierarchy, the momentum stencil and the cut-cell overlay breaks the singular row-sum
identity `A·1 = 0` at high multigrid contrast, and it breaks it *silently*: on a dense bed the
residual floors and then rebounds, so the run is invalid rather than merely less accurate, and
nothing says so. The measured cost of being wrong (RCP bed, rtol 1e-8): float 24/33/CAPPED
iterations at `max|div|` 4.51e-06 against 14/14/28 and 9.51e-12 in double. A float build is still one
flag away and now emits a CMake warning naming what it costs. Documenting the limitation instead was
rejected, because documentation protects only a reader who already knows to look. The
double-*diagonal* fallback is a different mechanism and stays retired.
**What this means for your numbers:** results from the default build change in the last digits
wherever the operator is involved — nine of the ten fixed-seed entry paths in
`flow/tests/regression/state_hash.py` move, and the tenth (pure scalar transport, no cut cells and
no multigrid contrast) is byte-identical. The accuracy and efficiency baselines do **not** move:
`sdflow_regression.py` passes against its existing baseline with every gated metric at +0.00 % and
every pressure-iteration count identical, while `max|div|` improves by about two orders of
magnitude. Any dense-bed permeability produced by a float build should be re-checked.

**Build (no API or numerical effect).** `flow` compiles `Solver<Grid>` **once per grid** instead of
once per consumer: two explicit-instantiation translation units in a static library that the module
and all 45 test executables link, with `extern template` declarations in `flow_ibm.hpp` and the
twelve definition headers included only in those two units. A full flow rebuild fell from 44 to 12
CPU-minutes on the host backend and from 90 to 50 on CUDA; editing one of the twelve domain headers
now rebuilds **4** objects instead of 45, 41 CPU-minutes to 4. Proved bit-exact by the committed
state-hash gate, with step time unchanged. `ccache` is supported as an opt-in compiler launcher on
the host backends (`-DCMAKE_CXX_COMPILER_LAUNCHER=ccache`); it cannot work on a CUDA or HIP prefix,
where Kokkos already owns the compile rule's launcher, and the CMake now says so at configure time
instead of failing incomprehensibly ten minutes later. `peclet-coupling` gains the `CITATION.cff` it
was the only package to lack.

### Tested

Every package was re-verified on this release's own commits, on the host (Kokkos OpenMP) and, where
it has a GPU path, on CUDA 13.2 / RTX 5080. Counts are what the batteries actually reported, with
skips separated from passes.

| package | host | CUDA |
|---|---|---|
| core | 53 plain / 68 Kokkos / 6 Python, np 1–8, 0 skips | same, 0 skips |
| morton | default 1/1, non-BMI2 2/2 (incl. the PDEP/PEXT-free binary check), Kokkos 2/2, pytest 9/9 | Kokkos 2/2, device output bit-identical to the scalar reference on all four layouts |
| flow | **155/155** (49 single-rank + 106 distributed at np 1, 2, 4) + the accuracy/efficiency regression | 49/49 single-rank |
| pnm | 9/9, np 1/2/4 bit-exact to a single-rank oracle | 9/9; 7199 pores / 53020 connections on the 256³ ring packing, identical to host |
| dem | 47/47, np 1/2/4 | 47/47 |
| voro | 42/42 (24 single-rank + 18 distributed) | 42/42 |
| amr | 100/100, np 1–8 | 99/100, 1 self-diagnosing skip |
| coupling | 3/3 | — |

The Python API is fully documented: **955 public callables, 0 undocumented, 0 with a retired name.**

Not exercised: morton's AVX-512 batch kernels (the release host has no AVX-512F and Intel SDE could
not be obtained), and the LUMI/HIP path (no AMD hardware).

### Known limitations in 1.0.0

- **An immersed solid cutting an inflow or outflow face breaks the pressure solve** (iteration cap,
  `max|div|` ~4e-3). A bed clear of the open faces is fine. `flow/doc/cutcell_openbc_convergence.md`.
- **Multigrid depth is capped by the factors of two in the grid.** An axis coarsens only while it
  stays even, so an odd dimension never coarsens at all, and under MPI only if every rank's block is
  even on it. Telescoping ships and is the default; the underlying requirement that intermediate
  levels coarsen in place is routed around, not solved, and it is the top open item at scale.
- **Collocated solver:** the `(matrix_order=1, rhs_order=2)` ghost mode is march-unstable above about
  2000 spheres and is documented do-not-use. Collocated MPI is validated at np = 1, 2, 4; np >= 16 is
  unresolved.
- **VoF:** the staggered grid is the reference. The collocated path is all-fluid and rated to density
  ratio about 100 with motion; the per-bubble block container is all-fluid and staggered-only for its
  surface tension. **Colliding markers are outside the rating** — a contacting pair drives through the
  two-cell film at roughly 1.5 eddy turnovers, independent of the timestep.
- **voro on CUDA:** `clipCellAgainstSdf` is wrong by up to 22 % on device at 128 and 256 grids, while
  correct on the OpenMP backend.
- **peclet-amr's octree V-cycle is a preconditioner, not a solver, on anisotropic (box) cells** — it
  diverges at aspect ratio 2 and 4 even though the operators themselves are exact. See
  `amr/docs/amr_anisotropic.md`.
- **morton's AVX-512 batch kernels were not re-validated for this release.** They need Intel SDE or
  AVX-512 hardware, and the release host has neither. Every other morton configuration, including the
  contractual PDEP/PEXT-free non-BMI2 build, passed.
- **Unresolved and recorded:** whether the reported permeability `K` is interstitial or superficial.
  `DECISIONS.md` carries the contradiction; it decides a (1−φ) factor. **No permeability number is
  published in these release notes for that reason.**

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

- **flow: operator storage is now DOUBLE by default** (`PECLET_FLOW_OPERATOR_DOUBLE=ON`). This is a
  numerics-affecting default change, taken deliberately: float operator storage silently breaks
  `A·1 = 0` at high multigrid contrast, and the porous path's default MG-PCG was reporting a
  non-finite preconditioner on 2 of 5 steps, deterministically. Measured cost of being wrong (P1,
  RCP bed at rtol 1e-8): float 24/33/CAPPED iterations with `max|div|` 4.51e-06, versus 14/14/28 and
  9.51e-12 in double. The price is ~12% step time; a float build is still available with
  `-DPECLET_FLOW_OPERATOR_DOUBLE=OFF` and now emits a CMake warning. Dense-bed results from a float
  build should be regarded as untrustworthy. Regression state hashes and `perf_baseline.json` must be
  re-blessed for this change before the tag (RELEASE_PREP §1.2). The double-*diagonal* fallback is a different mechanism and remains
  retired (it converges to the float-face operator, 65× worse on divergence).
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
- (more at release time from the per-package logs — see [archive/RELEASE_PREP_0.7.x.md](docs/archive/RELEASE_PREP_0.7.x.md) §1.4 for the gallery-found defects)

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
