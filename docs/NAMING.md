# Suite naming — one spelling per concept

`peclet` is seven repos and seven shipped Python packages (`peclet.flow`, `peclet.pnm`, `peclet.dem`,
`peclet.voro`, `peclet.coupling`, `peclet.morton`, `peclet.amr`, and `peclet.core`'s `mpi`/`geom` modules). They grew separately,
so the same idea acquired different spellings — `set_domain` in dem against `set_box` in voro,
`cell_centers` beside `cell_centres` in flow, `num_particles` against `scene_instance_count`. A user
who moves between two of them pays for that every time.

This file is the **canon**: one spelling per concept, the current divergences, and the rule for
changing a shipped name. [CONVENTIONS.md](CONVENTIONS.md) §6 governs the *mechanism* of the bindings
(nanobind, the array bridge, shapes and lifetimes); this file governs the *names*.

## 0. The rule for changing a shipped name

**Until 1.0.0: one spelling, clean break.** Decision D1 of [QUALITY_PLAN.md](QUALITY_PLAN.md)
(2026-09-08): the suite has no external users, so the release that follows 0.7.2 — **1.0.0**, because it
breaks every API — *removes* every non-canonical spelling and *renames* keyword arguments outright.
Nothing is aliased. The removals are listed with their replacements in the CHANGELOG and in
QUALITY_PLAN §2; §2 below records them as **removed 1.0.0**. Two spellings of one concept must never
ship again.

**From 1.0.0 on: additive, never breaking.** A rename lands as a NEW canonical name bound beside the old one, the
old one keeps working and keeps its docstring, and the divergence table below records the pair. One
release later the old spelling gains a `DeprecationWarning`; one release after that it may go. No
release removes a name it did not first warn on. This is the same ladder the physical-units plan
uses for `extent=None` ([PHYSICAL_UNITS_PLAN.md](PHYSICAL_UNITS_PLAN.md) D2), for the same reason:
every one of these APIs is on PyPI and someone's script imports it.

A canonical name is not permission to leave the old one undocumented. If both spellings exist, the
docstring of the old one says which is canonical.

### 0.1 What an alias cannot cover: keyword ARGUMENT names

Everything above works because a method can be bound twice. A keyword *argument* cannot: nanobind
resolves `f(sphere_centres=...)` against one spelling, and adding a second means either a wrapper
that accepts both (and has to decide what a caller passing both meant) or a break. So an argument
name that is merely spelled unusually — `sphere_centres`, `extract_topology(shape=...)` — is
**recorded here and changed at the next major version**, not aliased. 1.0.0 *is* that major
version: both are renamed there (§2).

The exception is an argument that is *added* rather than renamed: `set_domain(extent=..., ...)`
beside `set_domain(lx, ly, lz)` is a new overload, and overloads are resolvable. That is why the
domain quartet could land now and the spelling fixes could not.

## 1. The canon

### 1.1 The domain quartet

Four names, and they mean the same thing in every code:

| name | is | type |
|---|---|---|
| `origin` | the lower corner of the domain | 3-tuple, physical |
| `extent` | the SIZE of the domain (not the far corner) | 3-tuple, physical |
| `cells` | the number of cells per axis | 3-tuple of int |
| `spacing` | the derived per-axis cell size, `extent / cells` | 3-tuple, physical |

- **`extent` is a size, never a corner.** The far corner is `origin + extent`. A code that takes
  `(min, max)` corners keeps that overload but names its arguments `min`/`max` and does not call
  either of them an extent.
- **The setter is `set_domain(...)`**, taking `extent=`, `origin=` and (where the code has them)
  `periodic=` as KEYWORDS. Grid codes that fix the domain at construction take the same three as
  constructor keywords (`Solver(cells, extent=..., origin=...)`) and expose the quartet read-only.
- **`spacing` is derived and read-only.** No public API takes a cell size — that is decision D3 of
  the physical-units plan, and it is what makes a script survive a change of resolution.
- **Per axis, always.** All four are 3-tuples even where the code only supports cubic cells today;
  a scalar spelling (`spacing_from_extent`) may exist beside the vector one but never instead of it.

### 1.2 Accessors: no `get_` prefix on a property

A value the object simply *has* is a bare name: `extent`, `origin`, `spacing`, `cells`, `dt`,
`periodic`, `volumes`, `positions`. A `get_`/`set_` pair is for a value that is **converted,
copied or computed** on access — `get_u()`, `get_field(name)`, `set_positions(a)` — where the call
parentheses tell the reader a transfer happens. Concretely (the rule voro applied at 1.0.0 and
every module follows): a stored scalar or count is a **property** (`time`, `num_cells`, `layout`); a
scalar that is *computed* on call, e.g. a device reduction, is a bare-name **method**
(`kinetic_energy()`, `max_divergence()`); an **array copied out** carries `get_` (`get_volumes()`,
`get_velocities()`, `get_neighbor_counts()`). So `volumes()` without `get_` was wrong, not a model.

CONVENTIONS §6 previously wrote the lifecycle as "`step(dt)` → `get_*` accessors". That stays true
of the array getters, which do copy; it was never meant to make `get_spacing()` preferable to
`spacing`.

### 1.3 Counts are `num_<plural>`

`num_particles`, `num_cells`, `num_faces`, `num_shapes`, `num_contacts`, `num_leaves`,
`num_levels`, `num_scene_instances`. Not `<thing>_count`, not `n_<thing>`. (Dictionary KEYS
returned by a diagnostics call are exempt — they are data, and renaming them breaks plotting
scripts silently rather than loudly; `vof_diagnostics()['cut_cells']` stays.)

### 1.4 Periodicity is `periodic`

A 3-tuple of bool, per axis. Passed as `periodic=` to `set_domain` or the constructor, read back as
the `periodic` property, set on its own by `set_periodic(x, y, z)`. Not `enable_periodicity`, not
`pbc_enabled`, not three separate `px`/`py`/`pz` positionals. flow's per-face `set_domain_bc(face,
0)` is the richer boundary API and stays as it is — `periodic` is the shorthand for "all six faces
of this axis are periodic".

### 1.5 The time step is `set_dt(dt)` / `dt`

Every stepper takes its time step through `set_dt` and reports it as `dt`; `step()` advances one
step of it and `step(n)` advances `n`. No `step` takes a `dt` argument — that was a second way to
configure the same value (voro's `step(n, dt)` was removed at 1.0.0).

### 1.6 Spelling: American, and one of them

`center`, `color`, `neighbor`, `normalize`. The suite's C++ is already American throughout
(`centers`, `neighbor_counts`, `coarsenOpenAvg`); the British spellings that leaked into the Python
layer (`cell_centres`, `sphere_centres`, `colours`, `vof_block_colour`) are the outliers.
The `centre`-spelled names were removed at 1.0.0 (§2).

### 1.7 Axis order is x-fastest, and a name never has to say so

Suite tuples are `(x, y, z)` and suite grid arrays are `(nx, ny, nz)` Fortran-order
([CONVENTIONS.md](CONVENTIONS.md) §1, §6). Where a module's arrays are the C-contiguous `(nz, ny,
nx)` view of the same memory instead, the triples that describe them are stated in THAT order and
carry a `_zyx` suffix saying so. The suffix is a feature, not a defect: it is what stops a reader
guessing whether `spacing[0]` is dx or dz. `pnm` is the only module in this position, and the rule
is that a module never ships both spellings — one order per module, marked.

## 2. The divergence table

Status: **removed 1.0.0** = the non-canonical spelling was deleted in the clean-break release
(QUALITY_PLAN D1; the per-repo commits of 2026-09-08 carry the lists); **canon** = correct;
**open** = recorded, not yet done.

### peclet.flow

| former | canonical | status |
|---|---|---|
| `extent`, `origin`, `spacing`, `cells`, `global_cells` | — | **canon** (Phase 1 of the units plan) |
| `get_spacing()` | `spacing` (a list `[dx, dy, dz]`) | **removed 1.0.0** |
| `get_resolution()` / `global_resolution()` | `cells` / `global_cells` | **removed 1.0.0** |
| `get_ox()` / `get_oy()` / `get_oz()` | — | **canon** — NOT origin accessors: the per-face openness FIELDS of the cut-cell operator (an earlier draft of this table mislabelled them; corrected 2026-09-08 against the gallery's uses) |
| `cell_centres()` | `cell_centers()` | **removed 1.0.0** |
| `scene_instance_count()` | `num_scene_instances()` | **removed 1.0.0** |
| `vof_block_colour(id)`, `vof_filled_colour()`, `enable_vof_blocks_from_colours(colours=)` | `vof_block_color`, `vof_filled_color`, `enable_vof_blocks_from_colors(colors=)` | **removed 1.0.0** |
| `set_velocity_streams(on)` (a no-op) | — | **removed 1.0.0** |
| `set_solid(…, pressure_coarse=)` (accepted, ignored) | `set_solid(sdf, cutcell_pressure)` | **removed 1.0.0** |
| `set_domain_bc(face: int, type: int, …)`, `set_domain_bc_profile(face: int, …)`, `set_scalar_bc(name, face: int, type: int, v)`, `set_vof_inflow*(face: int, …)`, `set_vof_backflow(face: int, …)` | faces `'-x'|'+x'|'-y'|'+y'|'-z'|'+z'`, types `'periodic'|'wall'|'inflow'|'outflow'|'slip'` (scalars: `'periodic'|'neumann'|'dirichlet'`) — the per-face API stays; `periodic=` is not a substitute | **removed 1.0.0** (F, 2026-09-10) |
| `set_advection_scheme(0|1)`, `add_scalar(scheme=0|1|2)`, `set_csf_mode(0|1)`, `set_fluid_only_constraint(0|1|2)`, `set_phase_change_area(int)`, `set_contact_angle_pivot(int)`, `set_vof_block_assign(int, every)` | `'sou'|'koren'`; `'fou'|'koren'|'sou'`; `'face'|'cell'`; `'off'|'filter'|'star'`; `'plic'|'cascade-*'|'sheet-*'`; `'volume'|'centroid'|'projected-centroid'|'contact-line'`; `'round-robin'|'lpt'|'orb'` | **removed 1.0.0** (F) |
| `set_face_interp(mode)`, `set_collocated_scheme('gauge-2a')`, `set_ghost_projection(...)` as the way to pick a scheme; modes 1, 2, 3, 4, 10, 11, 12, 13; `set_fv_relax`, `set_aperture_floor` | ONE `set_collocated_scheme('ghost'|'gauge-exact'|'plain'|'embed')` (embed = the Basilisk embed port, former mode 7); the two intermediate embed rungs only as `diagnostics.set_face_interp(5|6)`; the rest deleted with their kernels | **removed 1.0.0** (F) |
| `set_contact_angle_dynamic(…)` + `_off()`, `set_phase_change_thermal(…)` + `_off()`, `set_phase_change_energy(…)` + `_off()`, `disable_vof_blocks()` | one setter with a leading `enabled`; `enable_vof_blocks(None)` | **removed 1.0.0** (F) |
| 125 developer members (`*_diagnostics/_stats/_census/_budget/_ledger/_probe/_timing`, `last_*`, solver tuning beyond selection, ablation switches, `field_view`, `exchange_field*`, `rebalance_by_weights`, `bcast_from_root`, …; the list is flow `853816f`) | `solver.diagnostics.<same>` (`SolverDiagnostics`) | **removed 1.0.0** (F) |
| call-order docstrings ("call BEFORE set_solid / init_mpi") | state checks: `set_domain_bc(_profile)`, `set_aperture_order`, `set_fluid_only_constraint`, `set_exact_crossings`, `set_openness_override`, `set_ghost_projection`/`'ghost'` RAISE after geometry; `set_decomposition`, `set_comm_avoiding` RAISE after `init_mpi`; late `set_rho`/`set_mu` now dirty the stencil (were silently wrong) | **canon** (F) |

### peclet.dem

| former | canonical | status |
|---|---|---|
| `initialize(shape_type, radius=0.5, height=2.0, …)` | `initialize_shape(shape_type, radius, height=0, thickness=0)` — `radius` mandatory | **removed 1.0.0** |
| `set_domain(lx, ly, lz, px, py, pz)` | `set_domain(extent=, origin=, periodic=)` | **removed 1.0.0** |
| `set_domain(min, max)` | — | **canon** (a corner overload, correctly named) |
| `get_domain_min()` / `get_domain_max()` | `origin` / `origin + extent` | **removed 1.0.0** |
| `enable_periodicity(x, y, z)`; `export_lammps(pbc_enabled=)` | `set_periodic(x, y, z)` + `periodic`; `export_lammps(periodic=)` | **removed 1.0.0** |
| `get_num_contacts()` / `get_num_manifolds()` / `get_max_overlap()`; `num_particles()`, `num_shapes()`, `num_asleep()`, `rank()`, `num_ghost()` | `num_contacts`, `num_manifolds`, `max_overlap`, `num_particles`, … — **properties** (§1.2: stored scalars) | **removed 1.0.0** |
| `step(dt)`; `step(0.0)`; `step_hertz(dt, …)` / `step_hertz_mpi(dt, …)`; `step_mpi(nsteps=)` | `set_dt(dt)` + `step(n=1)`; `relax(n=1)`; `step_hertz(substeps, skin_frac)`; `step_mpi(n=)` — a stepper before `set_dt` raises | **removed 1.0.0** |
| `initialize_shape(shape_type: int)`, `add_shape(int)`; `set_sphere_shape(r)` | `'sphere'` / `'hollow_cylinder'` / `'box'`; `initialize_shape('sphere', r)` | **removed 1.0.0** |
| `set_gravity(gx, gy, gz)`; `set_sdf_shape`/`add_sdf_shape`/`add_sdf_wall(grid, nx, ny, nz, …)` | `set_gravity((gx, gy, gz))` + `gravity`; one 3-D `grid[nx, ny, nz]` array | **removed 1.0.0** |
| `set_stabilization(bool)` + `set_stabilization_mode(str)` | `set_stabilization('off' \| 'onesided' \| 'multilevel')` + `stabilization`; `'escalate'`/`'ordered'` under `diagnostics` | **removed 1.0.0** |
| `set_velocity_use_gs`, `set_cuda_graphs`, `set_fused_sweeps`, `debug_coloring_conflicts`, `get_rest_*_stats`, `wall_sdf_at`, `get_profiling_info`, `mpi_rebuilds`, `mpi_gathers` | `sim.diagnostics.set_velocity_solver('gauss_seidel' \| 'jacobi')`, `.set_cuda_graphs`, `.set_fused_sweeps`, `.coloring_conflicts()`, `.rest_orphan_stats()`, `.rest_bank_stats()`, `.wall_sdf_at`, `.profiling_info()`, `.mpi_rebuilds`, `.mpi_gathers` | **moved 1.0.0** (D2 tier) |
| `get_growth_factor()` / `get_growth_rate()`; `init_mpi(size=, gsize=)` | `growth_factor` / `growth_rate`; `init_mpi(origin, extent, cells, periodic)` | **removed 1.0.0** |
| `add_plane(px, py, pz, nx, ny, nz)` | `add_plane(point, normal)` | **removed 1.0.0** |
| `num_particles`, `num_shapes`, … ; `get_positions()`, `get_velocities()`, … | — | **canon** |

### peclet.voro

| former | canonical | status |
|---|---|---|
| `set_box(L)` (`Tessellation`, `Simulation`) | `set_domain(extent=, origin=, periodic=)` — origin and periodic are CHECKED (origin-anchored, all-periodic engine) | **removed 1.0.0** |
| `Simulation.step(n, dt)`, `FlowSolver.step(n, dt)` | `set_dt(dt)` + `step(n)`; `step` raises if no dt was set | **removed 1.0.0** |
| `sphere_centres=`; `centres=` (`redistribute_pore_mesh`, `sphere_union_scene`) | `sphere_centers=`; `centers=` | **removed 1.0.0** |
| `Tessellation.volumes()` / `neighbor_counts()` / `wall_counts()`; `Simulation.get_num_neighbors()`; `FlowSolver.get_cell_volume()` / `get_velocity()` | `get_volumes()` / `get_neighbor_counts()` / `get_wall_counts()`; `get_neighbor_counts()`; `get_volumes()` / `get_velocities()` — array copies carry `get_` (§1.2) | **removed 1.0.0** |
| `Simulation.get_kinetic_energy()` / `get_internal_energy()` / `get_time()`; `FlowSolver.num_cells()` / `num_faces()` / `num_wall_faces()` / `layout()` / `pressure_iterations()` | `kinetic_energy()` / `internal_energy()` / `time`; the five as read-only properties | **removed 1.0.0** |
| `num_cells`, `num_faces`, `num_particles`, `num_wall_faces` | — | **canon** |
| `Tessellation.build_report()` / `set_local_certificate()` / `set_gate()`; `FlowSolver.set_skew_corrected()` / `set_wall_gradient_quadratic()`; `Simulation.set_repair()` | `<object>.diagnostics.<same>` (F, D2) | **removed 1.0.0** (F, 2026-09-10) |
| `Tessellation.set_wall_mode(exact: bool, skin_frac)` | `set_wall_mode(mode='exact'\|'skin', skin_frac)` | **removed 1.0.0** (F) |
| `FlowSolver(..., amg=True)` | — (the plain-CG ablation, unreached) | **removed 1.0.0** (F) |
| `FlowSolver.set_body_force(fx, fy, fz)` | `set_body_force((fx, fy, fz))` | **removed 1.0.0** (F) |
| `optimize_volume_mesh(positions, vset, L, sw, max_newton, …, colored_gs)` → dict | `optimize_volume_mesh(positions, target_volumes, extent, *, search_window, max_iter, tol, cg_iters, use_weights, method=)` → `OptimizeResult` (`n_empty` → `num_empty`) | **removed 1.0.0** (F) |
| `minimize_interface(positions, types, sigma, L, sw, max_iter, tol)` → dict (energy in `maxVolErr`) | `minimize_interface(positions, types, extent, *, sigma, search_window, max_iter, tol)` → `InterfaceResult{iters, energy, energy_ratio, converged}` | **removed 1.0.0** (F) |
| `optimize_pore_mesh(positions, vref, c, r, L, sw, …)`, `sdf_voronoi_cells(…, L)`, `sdf_voronoi_section(…, L, origin, normal)`, `redistribute_pore_mesh(…, L, …)` at the package root | `peclet.voro.pore_mesh.<same>(…, target_volumes, sphere_centers, sphere_radii, extent, *, search_window, …)`, `(…, extent)`, `(…, extent, point, normal)`, `→ RedistributeResult` (`n_added/n_removed/n_dead` → `num_*`) | **removed 1.0.0** (F) |
| `sphere_union_scene(…)`, `_union_sdf(pts, c, r, L)` at the package root | `peclet.voro.scenes.sphere_union_scene`, `scenes.sphere_union_sdf(points, centers, radii, extent)` | **removed 1.0.0** (F) |
| `VoronoiHalo(origin, size, gsize, periodic)`, `.rank()`, `.size()`, `owner_of(x, y, z)`, `gather(owned_pos, owned_gid, owned_weight, rcut)` | `VoronoiHalo(cells, *, extent, origin, periodic)`, `rank` / `num_ranks` properties, `owner_of(point)`, `gather(positions, gids, rcut, weights=None)` | **removed 1.0.0** (F) |
| — | `DistributedTessellation(cells, *, extent, origin, periodic, rcut, skin, tolerance)` — the distributed moving tessellation (`establish`, `step`, `num_owned`, `num_combined`, `get_combined_gids`); `VoronoiHalo` stays as the primitive | **new 1.0.0** (F) |

### peclet.pnm

| former | canonical | status |
|---|---|---|
| `origin_zyx`, `spacing_zyx`, `global_shape_zyx`, `grad_p_zyx` | — | **canon, as the documented exception of §1.7** |
| `extract_topology_gpu(segmentation, shape)` | `extract_topology(segmentation, shape_zyx)` | **removed 1.0.0** |
| `segment_volume()` → `list[int]`, `extract_topology()` → `list[tuple]`, `extract_network_flow()['throats'` / `'pore_pressure'` / …`]` → lists | `int32 (Nz,Ny,Nx)` ndarray, `(M,2) int32` ndarray, float64 ndarrays (same values, same order) | **removed 1.0.0** (F, 2026-09-10) |
| `mpi_block()` → `(origin_zyx, shape_zyx)` — an INTEGER voxel offset spelled like the physical origin | `(offset_zyx, shape_zyx)` | **removed 1.0.0** (F) |
| `mpi_rank()`, `mpi_size()` | — (mpi4py; zero callers) | **removed 1.0.0** (F) |
| `Pore.x`, `.y`, `.z` | — | **canon** — three self-named scalars carry no axis-order ambiguity, so they take no `_zyx` (the documented exception to §1.7 for this module) |

pnm is the one module whose Python arrays are C-contiguous `(nz, ny, nx)` rather than
Fortran-order `(nx, ny, nz)` — `SDFReader.read_vti` returns exactly that, because that is the
layout a VTI hands over — and its origin/spacing triples are stated in the SAME order as the array
they describe. The `_zyx` suffix is therefore load-bearing. **Keep the suffix wherever the triple is
in array order**, and never add a bare `origin`/`spacing` beside it in the other order.

### peclet.core (`peclet.core.mpi`, `peclet.core.geom`) and peclet.amr (`peclet.core.amr` until 2026-09-10)

| former | canonical | status |
|---|---|---|
| `Octree(brick, lmax, origin=, h0=, extent=)`; `DistributedOctree(global_root_size=, …)` | `Octree(cells, *, lmax=0, origin=, spacing=None, extent=None)` — `cells` is the FINEST grid (= brick·2^lmax, must divide); keyword-only after `cells` | **removed 1.0.0** |
| `.h0` | `.spacing` | **removed 1.0.0** |
| `spacing_from_extent` (scalar) / `spacings_from_extent(root_cells=)` | — | **canon** (a cubic helper that says so; `root_cells` is a different quantity from `cells`) |
| `mpi.Migrator`, `mpi.Halo`; ctor `(origin, size, gsize, periodic)` | `ParticleMigrator`, `ParticleHalo`; `(origin, extent, cells, periodic)` | **removed 1.0.0** |
| `ParticleHalo.num_ghost()` / `num_owned()` | read-only properties | **removed 1.0.0** |
| `num_leaves`, `num_levels`, `centers` | — | **canon** |
| `peclet.core.amr.{Octree, DistributedOctree, Poisson, Flow}` | `peclet.amr.{…}` — the whole AMR tree is the eighth package `peclet-amr` (QUALITY_PLAN G.2, D6) | **removed 1.0.0** (G.2, 2026-09-10) |
| `Flow.last_mom_iters` / `last_pres_iters` / `last_outer_iters` / `divergence_norm_face` / `set_momentum_mg` / `set_momentum_gs` / `set_velocity_mg_staircase` / `set_momentum_mg_solver` / `set_ghost_gradient` / `set_aperture_order` | `Flow.diagnostics.<same>` | **removed 1.0.0** (F, 2026-09-10) |
| env `PECLET_CORE_GPS_RHO` / `PECLET_CORE_GPS_MAXN` | `Flow.set_ghost_sampled(on, rho=2.2, max_samples=0)` | **removed 1.0.0** (E for amr) |

### peclet.coupling

| former | canonical | status |
|---|---|---|
| `CfdDem(smooth_width=)` (cells); `CfdDem(h=)` | `smooth_length=` (a physical length); the spacing comes from the flow solver | **removed 1.0.0** |
| `ResolvedCfdDem(rho_f=, periodic=<bool>, move=)` | `rho=`, `periodic=(bx, by, bz)`, `move_particles=` — the same words as `CfdDem` | **removed 1.0.0** |
| `drag="bvk"`, `"bvk2"` | `"beetstra"`, `"tang"` (the literature names) | **removed 1.0.0** |
| `CfdDem(..., periodic=)` | — | **canon** |

## 3. What this file does NOT rename

- **Diagnostics dictionary keys.** `vof_diagnostics()`, `phase_change_diagnostics()`,
  `contact_angle_diagnostics()`, `get_profiling_info()` and friends return dicts whose keys are
  measured quantities. Renaming a key breaks a plotting script with a `KeyError` at the end of a
  long run, and there is no alias mechanism for a dict. They stay.
- **Method-specific vocabulary.** `openness`, `aperture`, `wisp`, `Ja`, `theta`, `beta`, `kappa`,
  `mdot` mean what the literature means. Uniformity applies to the *shared* concepts, not to the
  physics.
- **`get_`/`set_` on array transfers.** `get_u()` copies a converted field; `set_positions(a)`
  uploads. The prefix is carrying information there.

## 4. History

- 2026-09-07 — file created. Canon fixed; `smooth_length` (coupling) is the first entry landed under
  it, together with flow's already-shipped `spacing`/`cells`/`extent`/`origin` quartet.
- 2026-09-08 (later) — **1.0.0 clean break** (QUALITY_PLAN D1): every *aliased* row above became
  *removed 1.0.0* in flow `b891b8e`, dem `4aff4db`, voro `9e7b1b0`, pnm `b2d4fce`, core `8d9f3c2`
  and the coupling/sweep commits of the same day; the alias ladder is binding from 1.0.0 on.
- 2026-09-08 — first alias pass (superseded the same day by the clean break). voro `set_domain`/`extent`/`set_dt`/`dt` (`Tessellation`,
  `Simulation`, `FlowSolver`); dem `set_domain(extent=, origin=, periodic=)`, `set_periodic`,
  `origin`/`extent`/`periodic`; flow `num_scene_instances`, `vof_block_color`, and the
  canonical-partner note on `get_spacing`/`cell_centres`. Every old spelling still works and every
  gate is green: voro ctest 24/24, dem tests/kokkos 8/8, flow `units_*` + the coupling battery.
  The pnm row was CORRECTED — its `_zyx` names are right, not an open item.
