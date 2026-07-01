# peclet.core — shared infrastructure (MPI halo + AMR)

The Lagrangian particle halo (`peclet.core.mpi`) and the Kokkos AMR octree (`peclet.core.amr`, present when built with a Kokkos backend + morton).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.core.mpi`

core Lagrangian halo (block decomposition + particle migration/ghosts)

### `Migrator`

| Method / property | Description |
|---|---|
| `cell_of` | cell_of(self, x: collections.abc.Sequence[float]) -> list[int]  Global decomposition cell index (i,j,k) containing x (after wrap). |
| `gather_ghosts` | gather_ghosts(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C'], rcut: float) -> tuple  Copies of particles within rcut of this rank's block (periodic images handled); returns the (ghost positions (G,3), ghost payload (G,K)). |
| `last_received` | last_received(self) -> int  Particles absorbed by this rank in the last migrate(). |
| `last_sent` | last_sent(self) -> int  Particles shipped by this rank in the last migrate(). |
| `migrate` | migrate(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C']) -> tuple  Reassign every particle to the rank owning its (wrapped) position; returns this rank's (positions (M,3), payload (M,K)) after the exchange. |
| `owner_of` | owner_of(self, x: collections.abc.Sequence[float]) -> int  Rank that owns the block containing position x (after periodic wrap / boundary clamp). |
| `rank` | This process's MPI rank. |
| `rebalance` | rebalance(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C']) -> tuple  Re-decompose by particle count (weighted ORB) so each rank holds a near-equal share, then migrate. Pure redistribution (count/payload preserved); the partition is updated in place. Returns this rank's (positions (M,3), payload (M,K)). |
| `wrap_position` | wrap_position(self, x: collections.abc.Sequence[float]) -> list[float]  Periodic-wrapped / boundary-clamped position for x (the canonical image). |

### `Halo`

| Method / property | Description |
|---|---|
| `build` | build(self, positions: ndarray[dtype=float64, order='C'], rcut: float, include_periodic_self: bool = False) -> int  Establish the owner<->ghost correspondence over this rank's owned positions |
| `forward` | forward(self, owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  owned (N,3) -> ghost (G,3) verbatim (velocities, ...) |
| `forward_positions` | forward_positions(self, owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  owned (N,3) -> ghost (G,3) with the periodic image shift (positions) |
| `num_ghost` | num_ghost(self) -> int |
| `num_owned` | num_owned(self) -> int |
| `owner_of` | owner_of(self, x: collections.abc.Sequence[float]) -> int |
| `rank` | (self) -> int |
| `reverse` | reverse(self, ghost: ndarray[dtype=float64, order='C'], owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  ghost (G,3) summed onto owned (N,3); returns owned + reversed contributions |

## `peclet.core.amr`

core adaptive-mesh-refinement: per-block BlockOctree (serial) and DistributedOctree (MPI ORB) for the mesh, plus the device (Kokkos) AmrFlow cut-cell Stokes/Navier-Stokes solver. Build a graded octree, refine to an SDF surface, read leaf geometry + per-leaf fields as numpy, load-rebalance, gather face neighbours, export VTU, and run the flow step on device.

### `Octree`
Serial single-block adaptive octree with a world placement (origin + finest spacing h0). Leaves are addressed in Z-order slot order; every per-leaf array is indexed by that slot.

| Method / property | Description |
|---|---|
| `adapt` | adapt(self, field: ndarray[dtype=float64, order='C'], refine_thresh: float, coarsen_thresh: float, finest_level: int = 0, eps: float = 0.01, linear: bool = True) -> numpy.ndarray[dtype=float64]  Solution-adaptive step (Löhner-driven): refine where the indicator > refine_thresh (to finest_level), coarsen sibling groups all < coarsen_thresh, 2:1-balance, and conservatively remap `field`. MUTATES the octree in place; returns the remapped field (M,). `linear` uses minmod-limited prolongation (else piecewise-constant). |
| `balance` | balance(self) -> int  Enforce 2:1 graded balance to a fixpoint; returns refinements performed. |
| `centers` | centers(self) -> numpy.ndarray[dtype=float64]  Leaf world centres, (num_leaves, 3) float64. |
| `codes` | codes(self) -> numpy.ndarray[dtype=uint64]  Leaf block-local Morton origin codes, (num_leaves,) uint64. |
| `find` | find(self, x: collections.abc.Sequence[float]) -> int  Index of the leaf containing world point x=(x,y,z), or -1 if outside the block. |
| `h0` | Finest (level-0) cell width in world units. |
| `is_balanced` | is_balanced(self) -> bool  True iff every face-adjacent leaf pair differs by at most one level (2:1). |
| `levels` | levels(self) -> numpy.ndarray[dtype=int32]  Leaf refinement levels, (num_leaves,) int32 (0 = finest). |
| `lmax` | Root-cell level (max refinement depth). |
| `lohner_indicator` | lohner_indicator(self, field: ndarray[dtype=float64, order='C'], eps: float = 0.01) -> numpy.ndarray[dtype=float64]  Löhner normalized-second-difference feature indicator E in [0,1] per leaf from a scalar field (num_leaves,); large E = steep feature (refine), small = smooth (coarsen). |
| `num_leaves` | Number of leaves (Z-order slots). |
| `origin` | Block lower corner in world coordinates. |
| `refine_leaf` | refine_leaf(self, i: int) -> bool  Split leaf `i` into its 8 children; returns True if it was split (level>0). |
| `refine_to_sdf` | refine_to_sdf(self, sdf: collections.abc.Callable[[float, float, float], float], target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine toward an arbitrary signed-distance field given as a callable f(x,y,z)->distance (suite sign: <0 inside solid), down to target_level. Returns refinements performed. |
| `refine_to_sphere` | refine_to_sphere(self, center: collections.abc.Sequence[float], radius: float, target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine leaves the sphere surface passes through (plus `band`*h0) down to target_level; optionally restore 2:1 balance. Returns the number of refinements performed. |
| `sizes` | sizes(self) -> numpy.ndarray[dtype=float64]  Leaf world widths h0*2**level, (num_leaves,) float64. |
| `write_vtu` | write_vtu(self, path: str, name: str, field: ndarray[dtype=float64, order='C']) -> None  Write the octree + a per-leaf scalar field (num_leaves,) as a VTK UnstructuredGrid (.vtu, ASCII, one cell per leaf), openable in ParaView. |

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
| `divergence_norm` | divergence_norm(self) -> float  Volume-weighted L2 norm of the residual cell divergence (projection-quality diagnostic). |
| `divergence_norm_face` | divergence_norm_face(self) -> float  L2 norm of the divergence of the ABC divergence-free FACE field (≈ pressure-solve residual, far below divergence_norm — including across 2:1 interfaces). |
| `face_field` | face_field(self) -> numpy.ndarray[dtype=float64]  ABC divergence-free FACE velocity, one value per CSR (sub)face (conservative flux / streamline post-processing). |
| `is_fluid` | is_fluid(self) -> numpy.ndarray[dtype=bool]  Per-leaf fluid mask (False in the solid), (num_leaves,) bool. |
| `last_mom_iters` | last_mom_iters(self) -> int  Total momentum BiCGStab iterations (summed over the 3 components) of the last step. |
| `last_outer_iters` | last_outer_iters(self) -> int  Picard outer iterations actually run in the last step (1 unless set_outer_iterations(>1)). |
| `last_pres_iters` | last_pres_iters(self) -> int  Pressure PCG iterations of the last step. |
| `num_leaves` | Number of leaves. |
| `pressure` | pressure(self) -> numpy.ndarray[dtype=float64]  Per-leaf pressure (incremental-rotational p), (num_leaves,) float64. |
| `project` | project(self, pres_iters: int = 60) -> None  Pressure projection only (no momentum solve) — project an externally-set velocity field to divergence-free. Returns nothing; read the result via velocity()/velocities(). |
| `set_advection` | set_advection(self, on: bool) -> None  Enable explicit momentum advection (Navier-Stokes); off = Stokes. |
| `set_advection_scheme` | set_advection_scheme(self, scheme: int) -> None  High-order advection flux: 0 = second-order upwind (default), 1 = Koren TVD. |
| `set_body_force` | set_body_force(self, fx: float, fy: float, fz: float) -> None  Set the per-volume body force (e.g. a pressure gradient) driving the flow. |
| `set_implicit_advection` | set_implicit_advection(self, on: bool) -> None  Implicit first-order-upwind deferred-correction advection (default on): unconditionally stable. Off = fully explicit high-order advection. |
| `set_momentum_gs` | set_momentum_gs(self, on: bool) -> None  Use the symmetric multicolour Gauss-Seidel smoother in the momentum multigrid (default off = weighted Jacobi). Call before set_solid. |
| `set_momentum_mg` | set_momentum_mg(self, on: bool) -> None  Use the Galerkin velocity multigrid as the momentum solve preconditioner (default on; makes the momentum solve scale with resolution). Call before set_solid. |
| `set_momentum_mg_solver` | set_momentum_mg_solver(self, on: bool) -> None  Solve the momentum predictor with the velocity-MG as the solver (no Krylov), mirroring flow's velocity solve (default off = BiCgStab with the MG as preconditioner). |
| `set_outer_iterations` | set_outer_iterations(self, n: int, tol: float = 1e-06) -> None  Picard outer iterations over the lagged advection per step (default 1). |
| `set_solid` | set_solid(self, sdf: collections.abc.Callable[[float, float, float], float]) -> None  Build the cut-cell operators from a signed-distance callable f(x,y,z) (>0 fluid, <0 solid) and zero the fields. Call before stepping; re-call to change the geometry. |
| `set_velocity` | set_velocity(self, component: int, values: ndarray[dtype=float64, order='C']) -> None  Write velocity component c (0=x,1=y,2=z) from a (num_leaves,) array — initial conditions, restart, or warm-start. Call before step()/project(). |
| `set_velocity_mg_staircase` | set_velocity_mg_staircase(self, on: bool) -> None  Use the rediscretised staircase velocity-MG instead of Galerkin (default off). |
| `step` | step(self, mom_iters: int = 100, pres_iters: int = 60) -> None  Advance one collocated projection step on device: `mom_iters` momentum solver iterations (BiCGStab/MG), `pres_iters` pressure MG-PCG iterations. |
| `velocities` | velocities(self) -> numpy.ndarray[dtype=float64]  All three velocity components, (num_leaves, 3) float64. |
| `velocity` | velocity(self, component: int) -> numpy.ndarray[dtype=float64]  Per-leaf velocity component (0=x,1=y,2=z), (num_leaves,) float64. |

### `DistributedOctree`
MPI octree: an ORB block decomposition of a global root grid (one BlockOctree per rank, over MPI_COMM_WORLD). Construct it collectively; refine/balance/rebalance/face_neighbor_gather are collective. Per-leaf arrays describe THIS rank's local block in global world coordinates.

| Method / property | Description |
|---|---|
| `adapt` | adapt(self, field: ndarray[dtype=float64, order='C'], refine_thresh: float, coarsen_thresh: float, finest_level: int = 0, eps: float = 0.01, linear: bool = True) -> numpy.ndarray[dtype=float64]  Distributed solution-adaptive step (Löhner-driven): refine/coarsen each block, restore cross-block 2:1 balance, and conservatively remap `field` (num_leaves,) onto the new local mesh. MUTATES the octree in place (keeping ORB ownership); returns the remapped local field (M,). Bit-identical across rank counts (collective). |
| `balance` | balance(self) -> int  Restore cross-block 2:1 graded balance (collective). Returns this rank's refinements. |
| `block_brick` | This rank's block size in root cells per axis. |
| `block_origin_root` | This rank's block lower corner, in global root-cell coordinates. |
| `centers` | centers(self) -> numpy.ndarray[dtype=float64]  Local leaf world centres, (num_leaves, 3) float64 (global coordinates). |
| `codes` | codes(self) -> numpy.ndarray[dtype=uint64]  Local leaf block-local Morton origin codes, (num_leaves,) uint64. |
| `face_neighbor_gather` | face_neighbor_gather(self, field: ndarray[dtype=float64, order='C'], sentinel: float = 0.0) -> numpy.ndarray[dtype=float64]  For each local leaf, the field value across each of its 6 faces, gathered over the owner-based halo. `field` is (num_leaves,); returns (num_leaves, 6) laid out [+x,-x,+y,-y,+z,-z]; domain boundaries carry `sentinel` (collective). |
| `global_root_size` | Global grid size in root cells per axis. |
| `h0` | Finest cell width in world units. |
| `levels` | levels(self) -> numpy.ndarray[dtype=int32]  Local leaf levels, (num_leaves,) int32. |
| `lmax` | Root-cell level. |
| `lohner_indicator` | lohner_indicator(self, field: ndarray[dtype=float64, order='C'], eps: float = 0.01) -> numpy.ndarray[dtype=float64]  Löhner feature indicator per local leaf, evaluated across the owner-based halo so cross-block neighbours count exactly as in a whole-domain solve. `field` is (num_leaves,); returns (num_leaves,) (collective). |
| `num_leaves` | Leaves owned by this rank. |
| `rank` | This process's MPI rank. |
| `rebalance` | rebalance(self, fields: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  Re-decompose by leaf count (weighted ORB) and migrate leaves + their fields. `fields` is (num_leaves, K) float64; returns this rank's (M, K) columns after migration. Pure redistribution; the partition is updated in place (collective). |
| `refine_to_sdf` | refine_to_sdf(self, sdf: collections.abc.Callable[[float, float, float], float], target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine the local block toward an arbitrary GLOBAL surface given as a callable f(x,y,z)->distance (suite sign: <0 inside solid) — the distributed analogue of Octree.refine_to_sdf, for rings / packed beds / any non-sphere geometry. Collective when balance=True. |
| `refine_to_sphere` | refine_to_sphere(self, center: collections.abc.Sequence[float], radius: float, target_level: int = 0, band: float = 1.0, balance: bool = True) -> int  Refine the local block toward a GLOBAL sphere surface down to target_level, then (if balance) restore cross-block 2:1 balance collectively. Returns the local count. |
| `size` | Number of ranks (blocks). |
| `sizes` | sizes(self) -> numpy.ndarray[dtype=float64]  Local leaf world widths, (num_leaves,) float64. |
| `write_vtu` | write_vtu(self, path: str, name: str, field: ndarray[dtype=float64, order='C']) -> None  Write this rank's local octree + a per-leaf scalar (num_leaves,) as a .vtu (one file per rank; combine in ParaView). |

