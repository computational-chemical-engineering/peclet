# peclet.amr — block-octree AMR and its collocated cut-cell Navier–Stokes solver

The block-local-Morton AMR octree (`Octree`, distributed `DistributedOctree`), the AMR Poisson solve and the collocated cut-cell Navier–Stokes solver on it (`Flow`; developer instruments on `Flow.diagnostics`). Depends on peclet-core and peclet-morton; requires a Kokkos backend and MPI.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.amr`

peclet.amr — the block-local-Morton AMR octree and the collocated-projection Navier–Stokes solver.

Relocated out of ``peclet.core.amr`` on 2026-09-10 (suite/docs/QUALITY_PLAN.md D6 / G.2): the
same classes, the same names, one package up. Everything is Kokkos (CUDA / HIP / OpenMP;
``execution_space`` says which) over MPI (``import mpi4py.MPI`` first):

- ``Octree(cells, *, lmax, origin, spacing | extent)`` — the serial single-block octree: refine to a
  sphere / SDF / graded target, 2:1 balance, Löhner-driven ``adapt``, leaf geometry as numpy, VTU.
- ``DistributedOctree(cells, *, lmax, origin, spacing | extent, periodic)`` — one ORB block per
  rank over ``MPI_COMM_WORLD``: the same refinement surface, cross-block balance, weighted-ORB
  ``rebalance``, ``face_neighbor_gather``, distributed ``adapt``.
- ``Poisson(octree, periodic)`` — the geometric-multigrid FV Poisson solver on an octree.
- ``Flow(octree | distributed_octree, density, viscosity, dt)`` — the device cut-cell IBM
  collocated Stokes / Navier–Stokes step (ghost projection by default; the mixed-level sampled cut
  band via ``set_ghost_sampled``). Developer instruments live under ``Flow.diagnostics``.
- ``spacing_from_extent`` / ``spacings_from_extent`` — the one place an AMR spacing is computed.
- ``finalize()`` releases the Kokkos state (also registered at exit).

Conventions: per-leaf arrays are in the octree's Z-order slot order, length ``num_leaves``; the
domain quartet ``origin`` / ``extent`` / ``cells`` / ``spacing`` follows suite/docs/NAMING.md §1.1
(``cells`` is the FINEST grid; the root brick is ``cells / 2**lmax``); SDF sign is negative inside
the solid.

### `Octree`
Serial single-block adaptive octree with a world placement (origin + finest spacing per axis). Leaves are addressed in Z-order slot order; every per-leaf array is indexed by that slot.

| Method / property | Description |
|---|---|
| `adapt` | adapt(self, field: ndarray[dtype=float64, order='C'], refine_thresh: float, coarsen_thresh: float, finest_level: int = 0, eps: float = 0.01, linear: bool = True) -> numpy.ndarray[dtype=float64]  Solution-adaptive step (Löhner-driven): refine where the indicator > refine_thresh (to finest_level), coarsen sibling groups all < coarsen_thresh, 2:1-balance, and conservatively remap `field`. MUTATES the octree in place; returns the remapped field (M,). `linear` uses minmod-limited prolongation (else piecewise-constant). On a DistributedOctree: per block, cross-block balance, ORB ownership kept, bit-identical across rank counts (collective). |
| `balance` | balance(self) -> int  Enforce 2:1 graded balance to a fixpoint (cross-block and collective on a DistributedOctree); returns (this rank's) refinements performed. |
| `cells` | Finest-level cell counts per axis (root*2**lmax; the GLOBAL grid on a DistributedOctree). |
| `centers` | centers(self) -> numpy.ndarray[dtype=float64]  Leaf world centres, (num_leaves, 3) float64 (global coordinates). |
| `codes` | codes(self) -> numpy.ndarray[dtype=uint64]  Leaf block-local Morton origin codes, (num_leaves,) uint64. |
| `extent` | Box side lengths in world units (cells*spacing). |
| `find` | find(self, x: collections.abc.Sequence[float]) -> int  Index of the leaf containing world point x=(x,y,z), or -1 if outside the block. |
| `is_balanced` | is_balanced(self) -> bool  True iff every face-adjacent leaf pair differs by at most one level (2:1). |
| `levels` | levels(self) -> numpy.ndarray[dtype=int32]  Leaf refinement levels, (num_leaves,) int32 (0 = finest). |
| `lmax` | Root-cell level (max refinement depth). |
| `lohner_indicator` | lohner_indicator(self, field: ndarray[dtype=float64, order='C'], eps: float = 0.01) -> numpy.ndarray[dtype=float64]  Löhner normalized-second-difference feature indicator E in [0,1] per leaf from a scalar field (num_leaves,); large E = steep feature (refine), small = smooth (coarsen). On a DistributedOctree it is evaluated across the owner-based halo (collective). |
| `num_leaves` | Number of leaves (Z-order slots; this rank's on a DistributedOctree). |
| `origin` | Lower corner in world coordinates. |
| `refine_leaf` | refine_leaf(self, i: int) -> bool  Split leaf `i` into its 8 children; returns True if it was split (level>0). |
| `refine_to_gap_floor` | refine_to_gap_floor(self, sdf: collections.abc.Callable[[float, float, float], float], gap: collections.abc.Callable[[float, float, float], float], coarsest_level: int, n: float = 4.0, band: float = 2.0, balance: bool = True) -> int  refine_to_sdf_graded driven by the plan's GAP-WIDTH FLOOR (§7 criterion 1): the target level at a point is the coarsest L with n*h_L <= gap(x), clamped to [0, coarsest_level]. `gap` is the local fluid-gap proxy f(x,y,z)->width — for a sphere packing the two-closest-surfaces sum d1+d2; a medial-axis or peclet.pnm throat-radius field substitutes verbatim. n=4 per the M1/M2 measurements. This is the AMReX multi-valued-cell rule inverted: coarsening never merges or disconnects fluid. |
| `refine_to_sdf` | refine_to_sdf(self, sdf: collections.abc.Callable[[float, float, float], float], target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine toward an arbitrary signed-distance field given as a callable f(x,y,z)->distance (suite sign: <0 inside solid), down to target_level — rings / packed beds / any non-sphere geometry. Collective when balance=True on a DistributedOctree. Returns refinements performed. |
| `refine_to_sdf_graded` | refine_to_sdf_graded(self, sdf: collections.abc.Callable[[float, float, float], float], target_level: collections.abc.Callable[[float, float, float], int], band: float = 2.0, balance: bool = True) -> int  GRADED surface refinement (the mixed-level cut band, docs/amr_mixed_level_cut_band_plan.md §7): `target_level` is a callable f(x,y,z)->level giving the COARSEST acceptable level at a world point (0 = finest), so cut cells end up at SEVERAL levels — fine in throats/contacts, coarse on smooth caps. The band margin is measured in cells of the level being created (not in the finest spacing as in refine_to_sdf). Requires Flow.set_ghost_sampled(True) — the classic overlay contracts a uniform finest band and raises on these level jumps. Returns refinements performed. |
| `refine_to_sphere` | refine_to_sphere(self, center: collections.abc.Sequence[float], radius: float, target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine leaves the sphere surface passes through (plus `band` cells) down to target_level; optionally restore 2:1 balance (cross-block, collective, on a DistributedOctree). Returns the (local) number of refinements performed. |
| `sizes` | sizes(self, axis: int = 0) -> numpy.ndarray[dtype=float64]  Leaf world widths along `axis`: spacing[axis]*2**level, (num_leaves,) float64. A leaf is a BOX, so `axis` selects which of the three widths (0 by default, which is THE width on a cubic octree). |
| `spacing` | Finest cell size (dx, dy, dz), per axis. Equal on a cubic octree. |
| `write_vtu` | write_vtu(self, path: str, name: str, field: ndarray[dtype=float64, order='C']) -> None  Write the octree (this rank's block on a DistributedOctree — one file per rank, combine in ParaView) + a per-leaf scalar field (num_leaves,) as a VTK UnstructuredGrid (.vtu, ASCII, one cell per leaf). |

### `DistributedOctree`
MPI octree: an ORB block decomposition of a global root grid (one BlockOctree per rank, over MPI_COMM_WORLD). Construct it collectively; refine/balance/rebalance/face_neighbor_gather are collective. Per-leaf arrays describe THIS rank's local block in global world coordinates.

| Method / property | Description |
|---|---|
| `adapt` | adapt(self, field: ndarray[dtype=float64, order='C'], refine_thresh: float, coarsen_thresh: float, finest_level: int = 0, eps: float = 0.01, linear: bool = True) -> numpy.ndarray[dtype=float64]  Solution-adaptive step (Löhner-driven): refine where the indicator > refine_thresh (to finest_level), coarsen sibling groups all < coarsen_thresh, 2:1-balance, and conservatively remap `field`. MUTATES the octree in place; returns the remapped field (M,). `linear` uses minmod-limited prolongation (else piecewise-constant). On a DistributedOctree: per block, cross-block balance, ORB ownership kept, bit-identical across rank counts (collective). |
| `balance` | balance(self) -> int  Enforce 2:1 graded balance to a fixpoint (cross-block and collective on a DistributedOctree); returns (this rank's) refinements performed. |
| `block_brick` | This rank's block size in root cells per axis. |
| `block_origin_root` | This rank's block lower corner, in global root-cell coordinates. |
| `cells` | Finest-level cell counts per axis (root*2**lmax; the GLOBAL grid on a DistributedOctree). |
| `centers` | centers(self) -> numpy.ndarray[dtype=float64]  Leaf world centres, (num_leaves, 3) float64 (global coordinates). |
| `codes` | codes(self) -> numpy.ndarray[dtype=uint64]  Leaf block-local Morton origin codes, (num_leaves,) uint64. |
| `extent` | Box side lengths in world units (cells*spacing). |
| `face_neighbor_gather` | face_neighbor_gather(self, field: ndarray[dtype=float64, order='C'], sentinel: float = 0.0) -> numpy.ndarray[dtype=float64]  For each local leaf, the field value across each of its 6 faces, gathered over the owner-based halo. `field` is (num_leaves,); returns (num_leaves, 6) laid out [+x,-x,+y,-y,+z,-z]; domain boundaries carry `sentinel` (collective). |
| `global_root_size` | Global grid size in root cells per axis. |
| `levels` | levels(self) -> numpy.ndarray[dtype=int32]  Leaf refinement levels, (num_leaves,) int32 (0 = finest). |
| `lmax` | Root-cell level (max refinement depth). |
| `lohner_indicator` | lohner_indicator(self, field: ndarray[dtype=float64, order='C'], eps: float = 0.01) -> numpy.ndarray[dtype=float64]  Löhner normalized-second-difference feature indicator E in [0,1] per leaf from a scalar field (num_leaves,); large E = steep feature (refine), small = smooth (coarsen). On a DistributedOctree it is evaluated across the owner-based halo (collective). |
| `num_leaves` | Number of leaves (Z-order slots; this rank's on a DistributedOctree). |
| `origin` | Lower corner in world coordinates. |
| `rank` | This process's MPI rank. |
| `rebalance` | rebalance(self, fields: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  Re-decompose by leaf count (weighted ORB) and migrate leaves + their fields. `fields` is (num_leaves, K) float64; returns this rank's (M, K) columns after migration. Pure redistribution; the partition is updated in place (collective). |
| `refine_to_sdf` | refine_to_sdf(self, sdf: collections.abc.Callable[[float, float, float], float], target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine toward an arbitrary signed-distance field given as a callable f(x,y,z)->distance (suite sign: <0 inside solid), down to target_level — rings / packed beds / any non-sphere geometry. Collective when balance=True on a DistributedOctree. Returns refinements performed. |
| `refine_to_sphere` | refine_to_sphere(self, center: collections.abc.Sequence[float], radius: float, target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine leaves the sphere surface passes through (plus `band` cells) down to target_level; optionally restore 2:1 balance (cross-block, collective, on a DistributedOctree). Returns the (local) number of refinements performed. |
| `size` | Number of ranks (blocks). |
| `sizes` | sizes(self, axis: int = 0) -> numpy.ndarray[dtype=float64]  Leaf world widths along `axis`: spacing[axis]*2**level, (num_leaves,) float64. A leaf is a BOX, so `axis` selects which of the three widths (0 by default, which is THE width on a cubic octree). |
| `spacing` | Finest cell size (dx, dy, dz), per axis. Equal on a cubic octree. |
| `write_vtu` | write_vtu(self, path: str, name: str, field: ndarray[dtype=float64, order='C']) -> None  Write the octree (this rank's block on a DistributedOctree — one file per rank, combine in ParaView) + a per-leaf scalar field (num_leaves,) as a VTK UnstructuredGrid (.vtu, ASCII, one cell per leaf). |

### `Poisson`
Cell-centered finite-volume Poisson solver (L u = rhs) on an Octree, by a geometric-multigrid V-cycle. L is the conservative two-point FV Laplacian (suite sign). The hierarchy snapshots the octree at construction; per-leaf arrays are (num_leaves,) float64 in Z-order slots.

| Method / property | Description |
|---|---|
| `apply` | apply(self, u: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  L applied to u (the FV Laplacian); use b = apply(u_exact) to manufacture a RHS. (num_leaves,) -> (num_leaves,). |
| `num_leaves` | Leaves on the finest level. |
| `num_levels` | Number of multigrid levels. |
| `residual` | residual(self, u: ndarray[dtype=float64, order='C'], rhs: ndarray[dtype=float64, order='C']) -> float  Volume-weighted L2 residual norm sqrt(sum V*(rhs - L u)^2). |
| `solve` | solve(self, rhs: ndarray[dtype=float64, order='C'], x0: ndarray[dtype=float64, order='C'] | None = None, cycles: int = 20, pre: int = 2, post: int = 2, tol: float = 0.0) -> tuple  Solve L u = rhs with up to `cycles` V-cycles (pre/post Gauss-Seidel sweeps), from x0 or 0, stopping once residual <= tol (tol<=0 disables). Returns (u (num_leaves,), final_residual, cycles_done). |

### `Flow`
Collocated incompressible Stokes/Navier-Stokes step on an Octree with a cut-cell immersed boundary (no-slip on an SDF solid). step() = implicit viscous momentum predictor + Almgren-Bell-Colella rotational projection. Drive with a body force and iterate to steady state; velocities are per-leaf (num_leaves,) in Z-order slots.

| Method / property | Description |
|---|---|
| `begin_adapt` | begin_adapt(self) -> None  Snapshot the octree topology + (u, p) ahead of an external mesh mutation (adapt / refine_to_sphere / refine_to_sdf / balance on the SAME Octree object). Pair with finish_adapt. |
| `diagnostics` | The developer tier: iteration counts of the last step, the face-field divergence, and the solver-internals / ablation switches (FlowDiagnostics). A view onto this Flow. |
| `divergence_norm` | divergence_norm(self) -> float  Volume-weighted L2 norm of the residual cell divergence (projection-quality diagnostic). |
| `face_field` | face_field(self) -> numpy.ndarray[dtype=float64]  ABC divergence-free FACE velocity, one value per CSR (sub)face (conservative flux / streamline post-processing). |
| `finish_adapt` | finish_adapt(self, sdf: collections.abc.Callable[[float, float, float], float]) -> None  Rebuild the solver on the mutated octree and conservatively transfer the snapshotted u and p onto it (minmod-limited linear remap). `sdf` is re-sampled on the new leaves (pass the same geometry callable as set_solid); keep the cut band at the finest level on the new mesh (re-run refine_to_sdf on the geometry band after a solution-driven adapt). The advecting face field restarts from the cell average for one step. |
| `is_fluid` | is_fluid(self) -> numpy.ndarray[dtype=bool]  Per-leaf fluid mask (False in the solid), (num_leaves,) bool. |
| `num_leaves` | Number of leaves. |
| `pressure` | pressure(self) -> numpy.ndarray[dtype=float64]  Per-leaf pressure (incremental-rotational p), (num_leaves,) float64. |
| `project` | project(self, pres_iters: int = 60) -> None  Pressure projection only (no momentum solve) — project an externally-set velocity field to divergence-free. Returns nothing; read the result via velocity()/velocities(). |
| `rebalance_mpi` | rebalance_mpi(self, sdf: collections.abc.Callable[[float, float, float], float]) -> None  DISTRIBUTED: weighted-ORB load rebalance — migrates the leaves WITH the state (u, p) to the new owners and rebuilds every solver structure (collective). num_leaves is refreshed. |
| `set_advection` | set_advection(self, on: bool) -> None  Enable explicit momentum advection (Navier-Stokes); off = Stokes. |
| `set_advection_scheme` | set_advection_scheme(self, scheme: int) -> None  High-order advection flux: 0 = second-order upwind (default), 1 = Koren TVD. |
| `set_body_force` | set_body_force(self, fx: float, fy: float, fz: float) -> None  Set the per-volume body force (e.g. a pressure gradient) driving the flow. |
| `set_cf_scheme` | set_cf_scheme(self, scheme: int) -> None  Coarse/fine (2:1) interface scheme: 0 = standard two-point flux (default, 1st-order at level boundaries), 1 = Martin-Cartwright tangential quadratic (2nd-order; applied to the momentum diffusion, the divergence constraint, and the pressure gradients — the pressure matrix/MG stays standard, which does not move the steady solution). Works with both the aperture and the ghost projection. Call before set_solid. |
| `set_dt` | set_dt(self, dt: float) -> None  Change the time step. dt is BAKED INTO the momentum operator at build time (idiag = rho/dt), so a set_dt must be followed by set_solid or the operator stays stale. set_solid reallocates and zeroes u and p, so a dt SWITCH mid-march is: read velocity()/pressure() -> set_dt -> set_solid -> set_velocity()/set_pressure(). That sequence is the dt-cycling protocol of the attractor-family batteries. |
| `set_ghost_projection` | set_ghost_projection(self, on: bool, matrix_order: int = 2, rhs_order: int = 2) -> None  DEFAULT since 2026-08-25 (AUTO: ghost, with an aperture fallback + stderr notice when the finest band is too thin): the fluid-only constraint scheme — family-free, unconditionally stable, protocol-independent (flow's attractor-campaign verdicts; == flow's set_collocated_scheme('ghost')). FULL directional ghost-cell projection (the AMR port): binary-openness pressure operator + wall-anchored closure overlay on the finest-band rows, MG-preconditioned BiCGStab, ghost-closed divergence constraint; implies set_ghost_gradient. (matrix_order, rhs_order) closure orders: (2, 2) default and the only pair cleared for production — the (1, 2) mixed form is march-UNSTABLE above ~2000 spheres (flow hardening Phase A), kept callable for parity records only. Raises if the finest band is too thin (a closure would cross a 2:1 boundary). Call before set_solid. |
| `set_ghost_sampled` | set_ghost_sampled(self, on: bool, rho: float = 2.2, max_samples: int = 0) -> None  MIXED-LEVEL CUT BAND (docs/amr_mixed_level_cut_band_plan.md): allow cut cells at MULTIPLE octree levels — the finest-band contract is dropped. Chain entries that cross a 2:1 boundary become degree-2 LS virtual samples at the uniform closure positions (identity weights at same level, so a uniform finest band is BIT-IDENTICAL to set_ghost_sampled(False)); face classification uses the level-aware canonical openness; the momentum xi-row seam correction and the wall-aware C/F tangential fallback ride along. Implies the ghost projection (engages when the resolved scheme is ghost — the AUTO default or an explicit set_ghost_projection(True)). Distributed since 2026-08-30 (the clouds are a deterministic probe set through the leaf halo). `rho` is the least-squares cloud radius factor (rho = factor * max(h, H); 2.2 = the shipped behaviour) and `max_samples` the nearest-N candidate cap (0 = uncapped) — the M2a cloud-economy knobs, inert at their defaults; do not change them in production without the M2a table. Call before set_solid. |
| `set_implicit_advection` | set_implicit_advection(self, on: bool) -> None  Implicit first-order-upwind deferred-correction advection (default on): unconditionally stable. Off = fully explicit high-order advection. |
| `set_outer_iterations` | set_outer_iterations(self, n: int, tol: float = 1e-06) -> None  Picard outer iterations over the lagged advection per step (default 1). |
| `set_pressure` | set_pressure(self, values: ndarray[dtype=float64, order='C']) -> None  Write the accumulated rotational pressure from a (num_leaves,) array — restart, or re-accumulation policies after finish_adapt (at steady-state dt the transferred p is the load-bearing state; zeroing it after a coarsening adapt lets it re-accumulate cleanly). |
| `set_solid` | set_solid(self, sdf: collections.abc.Callable[[float, float, float], float]) -> None  Build the cut-cell operators from a signed-distance callable f(x,y,z) (>0 fluid, <0 solid) and zero the fields. Call before stepping; re-call to change the geometry. |
| `set_solid_spheres` | set_solid_spheres(self, centers: ndarray[dtype=float64, order='C', writable=False], radii: ndarray[dtype=float64, order='C', writable=False], periodic: bool = True) -> None  set_solid for a UNION OF SPHERES, evaluated natively instead of through a Python callback — the porous-media geometry. `centers` is (M,3), `radii` is (M,) or (1,); `periodic` uses the minimum-image convention over the octree's own box extent. Prefer this to set_solid at bed scale: set_solid samples the SDF tens of times per leaf (operator build, overlay classification at virtual positions, the openness probe), so a Python callback dominates everything else — measured >1h43m of pure numpy on an 11.35M-leaf 180-sphere bed before the GPU ran a single kernel. |
| `set_velocity` | set_velocity(self, component: int, values: ndarray[dtype=float64, order='C']) -> None  Write velocity component c (0=x,1=y,2=z) from a (num_leaves,) array — initial conditions, restart, or warm-start. Call before step()/project(). |
| `step` | step(self, mom_iters: int = 100, pres_iters: int = 60) -> None  Advance one collocated projection step on device: `mom_iters` momentum solver iterations (BiCGStab/MG), `pres_iters` pressure MG-PCG iterations. |
| `velocities` | velocities(self) -> numpy.ndarray[dtype=float64]  All three velocity components, (num_leaves, 3) float64. |
| `velocity` | velocity(self, component: int) -> numpy.ndarray[dtype=float64]  Per-leaf velocity component (0=x,1=y,2=z), (num_leaves,) float64. |

### `FlowDiagnostics`
Developer instruments and ablation switches of a Flow, reached as `flow.diagnostics` (suite/docs/QUALITY_PLAN.md D2: the public Flow surface is what a user needs to set up, run and read out a simulation; this is what a developer uses to inspect or ablate it).

| Method / property | Description |
|---|---|
| `divergence_norm_face` | divergence_norm_face(self) -> float  L2 norm of the divergence of the ABC divergence-free FACE field (≈ pressure-solve residual, far below divergence_norm — including across 2:1 interfaces). |
| `last_mom_iters` | last_mom_iters(self) -> int  Total momentum BiCGStab iterations (summed over the 3 components) of the last step. |
| `last_outer_iters` | last_outer_iters(self) -> int  Picard outer iterations actually run in the last step (1 unless set_outer_iterations(>1)). |
| `last_pres_iters` | last_pres_iters(self) -> int  Pressure PCG iterations of the last step. |
| `set_aperture_order` | set_aperture_order(self, order: int) -> None  Aperture estimator for the (fallback) aperture projection: 2 = analytic marching-squares (DEFAULT since 2026-08-26), 1 = legacy one-sample model. Call before set_solid. |
| `set_ghost_gradient` | set_ghost_gradient(self, on: bool) -> None  Directional ghost cell-gradient on cut cells for the pressure predictor and the projection's cell correction (2nd-order one-sided, never reads decoupled solid pressure — removes the gauge-dependent O(1/h) cut-cell gradient error of the plain ABC gradient). The ghost projection (the default) implies it; this switch matters for the aperture fallback only. Call before set_solid. |
| `set_momentum_gs` | set_momentum_gs(self, on: bool) -> None  Use the symmetric multicolour Gauss-Seidel smoother in the momentum multigrid (default off = weighted Jacobi). Call before set_solid. |
| `set_momentum_mg` | set_momentum_mg(self, on: bool) -> None  Use the Galerkin velocity multigrid as the momentum solve preconditioner (default on; makes the momentum solve scale with resolution). Call before set_solid. |
| `set_momentum_mg_solver` | set_momentum_mg_solver(self, on: bool) -> None  Solve the momentum predictor with the velocity-MG as the solver (no Krylov), mirroring flow's velocity solve (default off = BiCgStab with the MG as preconditioner). |
| `set_velocity_mg_staircase` | set_velocity_mg_staircase(self, on: bool) -> None  Use the rediscretised staircase velocity-MG instead of Galerkin (default off). |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `build_toolchain` | `'GNU 14.2.0 Release x86_64 Kokkos 5.1.1'` |
| `execution_space` | `'OpenMP'` |

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

### `spacing_from_extent`
```
spacing_from_extent(extent: collections.abc.Sequence[float], root_cells: collections.abc.Sequence[int], lmax: int) -> float

The finest cell width h0 = extent / (root_cells * 2**lmax) of a PHYSICAL domain — the one place an AMR spacing is computed, so no caller writes one (see suite/docs/PHYSICAL_UNITS_PLAN.md). Returns ONE number, so it raises when the extent does not give cubic cells — use `spacings_from_extent` for a box mesh.
```

### `spacings_from_extent`
```
spacings_from_extent(extent: collections.abc.Sequence[float], root_cells: collections.abc.Sequence[int], lmax: int) -> list[float]

The finest cell size (dx, dy, dz) = extent / (root_cells * 2**lmax), PER AXIS. The anisotropic form of `spacing_from_extent`: it accepts any positive extent, because the octree's cells are boxes (core/docs/amr_anisotropic.md).
```

