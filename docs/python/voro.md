# peclet.voro — dynamic Voronoi tessellation + Voronoi-mesh flow

Moving-cell Voronoi tessellation, moving-cell dynamics, the unstructured-mesh generator that feeds `peclet.flow`, the covolume / collocated Navier–Stokes solver on a Voronoi mesh (`FlowSolver`) and the distributed moving tessellation (`DistributedTessellation`, over the `VoronoiHalo` primitive). Developer instruments live on each object's `diagnostics`; the pore-mesh algorithms are `peclet.voro.pore_mesh`, the scene helpers `peclet.voro.scenes`.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.voro`

peclet.voro — dynamic 3D Voronoi tessellation of moving particles.

A device-native (Kokkos) moving-cell Voronoi engine: periodic boxes, incremental cell repair, and
compressible Euler / Navier–Stokes / multiphase dynamics on the moving cells. Also serves as
an unstructured-mesh generator that can feed an Eulerian solve in :mod:`peclet.flow`. The compiled
backend (Serial / OpenMP / CUDA / HIP) is chosen at build time — ``peclet.voro.execution_space`` reports
which one this build has.

The public surface (suite/docs/QUALITY_PLAN.md D2 — everything else is on each object's
``diagnostics``):

* :class:`Tessellation` — cold build + incremental repair of a moving point set, volumes, neighbour
  and wall counts, the energy layer (``energy_forces``).
* :class:`FlowSolver` — the static collocated / covolume Navier–Stokes solvers on the face mesh.
* :class:`Simulation` — the moving-cell compressible-Euler / Navier–Stokes fluid.
* :func:`optimize_volume_mesh`, :func:`minimize_interface` — mesh optimisers on a periodic box.
* :mod:`peclet.voro.pore_mesh` (imported on first use) — the SDF-walled pore-space family:
  ``optimize_pore_mesh``, ``redistribute_pore_mesh``, ``sdf_voronoi_cells``, ``sdf_voronoi_section``.
* :mod:`peclet.voro.scenes` (imported on first use) — scene helpers: ``sphere_union_scene``,
  ``sphere_union_sdf``.
* :class:`VoronoiHalo`, :class:`DistributedTessellation` — the MPI path (builds with
  ``PECLET_VORO_MPI=ON`` only).
* ``defaults`` — the named defaults the engine is driven with; ``execution_space``; ``finalize``.

``peclet`` is an implicit (PEP 420) namespace shared with the other ``peclet-*`` packages, so it has no
top-level ``__init__.py``.

### `Tessellation`
Moving-particle (power-)Voronoi tessellator on the device path, optionally clipped by an
SDF solid.

Build a tessellation once (`build`) then advance it cheaply as the points move (`step`) —
the incremental two-pass repair is several times faster than rebuilding for the small
per-step displacements typical of CFD/DEM, and falls back to a full rebuild (via an
adaptive gate) when displacements are large, so it is never much slower than a cold
build. Periodic box anchored at the origin. Single domain (one process); see
DistributedTessellation for the MPI driver. Instruments: `diagnostics`.

| Method / property | Description |
|---|---|
| `build` | build(self, positions: ndarray[dtype=float64, order='C'], strict: bool = False) -> None  Cold-build the (power-)Voronoi tessellation of `positions` (N,3) from scratch and make it resident, clipped by the geometry from `set_geometry` if any. Sets the particle count N for subsequent `step` calls. Warns (raises if strict=True) when the result is not a guaranteed-exact partition: buried power cells (a seed outside its own cell — never for w = r² of non-overlapping spheres), a search reach beyond half the box, or overflowed cells; see `diagnostics.build_report()`. |
| `clear_geometry` | clear_geometry(self) -> None  Drop the SDF geometry (takes effect at the next `build`). |
| `clear_weights` | clear_weights(self) -> None  Back to the unweighted Voronoi diagram (next `build`). |
| `diagnostics` | The diagnostics tier: build_report(), set_local_certificate(), set_gate(), set_profile(). |
| `energy_forces` | energy_forces(self, types: ndarray[dtype=int32, order='C'], tension: ndarray[dtype=float64, order='C'], sigma_wall: ndarray[dtype=float64, order='C'] | None = None, dEdV: ndarray[dtype=float64, order='C'] | None = None, lloyd: float = 0.0, facet_tension: float = 0.0) -> dict  Energies and their exact gradients on the RESIDENT cells (after build/step), no rebuild:   interfacial  E = Σ σ(t_i,t_j) A_ij over facets between different `types` (N,) int32,                with the symmetric `tension` table (nTypes, nTypes) float64;   wetting      E = Σ σ_wall(t_i) A_wall,i over SDF wall facets, if `sigma_wall` (nTypes,)                is given (a uniform wall tension is a constant — only the species                difference does work, which is what sets the contact angle);   volume       Σ e_i(V_i) for a caller-supplied e'(V_i) = `dEdV` (N,) (e.g. 2(V/Vref−1)/Vref);   centroidal   `lloyd` · Σ ∫_cell |y − x_i|² (Lloyd/CVT; gradient 2V(x−c) drives seeds to                their centroids — the skewness the grid solver's two-point operators need gone);   roundness    `facet_tension` · Σ A_f over all interior faces. Returns {'interface_energy', 'wall_energy', 'lloyd_energy', 'tension_energy', 'force' (N,3) = dE/dx, 'force_w' (N,) = dE/dw when weights are set}. Descend along −force to minimise. |
| `extent` | The box size (Lx, Ly, Lz) — read-only; set it with `set_domain`. |
| `get_neighbor_counts` | get_neighbor_counts(self) -> numpy.ndarray[dtype=int32]  Per-particle Voronoi neighbour count (N,) int32 (a copy) — the number of faces of each cell (wall facets included). |
| `get_volumes` | get_volumes(self) -> numpy.ndarray[dtype=float64]  Per-particle Voronoi cell volume (N,) float64 (a copy). Sums to the box volume (space-filling). |
| `get_wall_counts` | get_wall_counts(self) -> numpy.ndarray[dtype=int32]  Per-particle number of resident SDF wall planes (N,) int32 (a copy); all zero without geometry. |
| `num_particles` | Particle count N set by the last `build` (0 before it). |
| `set_domain` | set_domain(self, extent: collections.abc.Sequence[float], origin: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], periodic: collections.abc.Sequence[bool] = [True, True, True]) -> None  Set the periodic box before `build`: `extent` is the box SIZE (Lx, Ly, Lz). The suite-wide spelling (suite/docs/NAMING.md 1.1), the same call `dem.Simulation.set_domain` takes. `origin` must be (0, 0, 0) and `periodic` (True, True, True) — this engine's box is anchored at the origin and periodic on every axis; both are checked rather than ignored, so a caller who writes the suite-wide form gets an error naming the limitation. |
| `set_geometry` | set_geometry(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float64, order='C'], root: int = 0, grad_h: float = 1e-05) -> None  Clip the cells by an SDF solid given as a core shape scene in the flat node encoding (node_ints int32 (3 per node), node_reals float64 (16 per node)) — exactly what peclet.core.geom.Scene.encode() returns and dem.add_analytic_wall takes; `root` is the tree root to evaluate. Suite sign convention: sdf < 0 inside the solid. Seeds inside the solid get no cell (volume 0); cells reaching into it gain wall facets. Applies to the next `build` and is carried through every `step` (wall planes are resident; a boundary watch re-clips cells at the wall). `grad_h` (default 1e-05) is the central-difference step for the SDF gradient. Analytic vocabulary only (no sampled grids through this path yet). |
| `set_tolerance` | set_tolerance(self, frac: float = 0.0001) -> None  Certificate tolerance of the repair as a fraction of the mean inter-particle spacing (default 0.0001 = peclet.voro.defaults['certificate_tolerance']). A vertex poking past a stored plane by more than this flags the cell for repair; smaller is stricter (closer to machine-exact) at marginally higher cost. Takes effect at the next build(). |
| `set_wall_mode` | set_wall_mode(self, mode: str, skin_frac: float = 0.0) -> None  Wall re-gather policy for `step`. mode: one of 'exact', 'skin'. 'exact' (the default) re-clips every wall-clipped cell that moved, so the incremental result equals a cold rebuild; 'skin' keeps a cell's stale tangent planes until it moved more than skin_frac x the mean spacing (default 0; cheaper, not exact by construction). Takes effect at the next build(). |
| `set_weights` | set_weights(self, weights: ndarray[dtype=float64, order='C']) -> None  Per-seed POWER (Laguerre) weights (N,) float64: the cells become the power diagram (radical planes) instead of the Voronoi diagram. Takes effect at the next `build`; call again before a `step` to update the weights alongside the positions. Exact in the small-weight regime (see the docs). |
| `step` | step(self, positions: ndarray[dtype=float64, order='C']) -> dict  Incrementally repair the resident tessellation to new `positions` (N,3, same N as `build`; raises before `build`). Returns a dict of per-step work stats: 'flagged' (cells the certificate flagged), 'pass1' and 'pass2' (cells re-gathered in each pass), 'extra' (cells gathered across verify extra-passes), 'surgical' (Pass-1 cells repaired surgically), 'verify_passes' (verify iterations run), 'rebuilt' (True if the gate routed this step to a full rebuild), 'fell_back' (True if the verify failed and a cold rebuild was forced), 'wall_flagged' (cells the SDF boundary watch re-clipped). |

### `Simulation`
Device-native compressible-Euler / Navier-Stokes Voronoi fluid simulation.

Velocity-Verlet dynamics of a moving-particle Voronoi fluid: pressure forces from an
EOS plus an optional per-particle viscous (Navier-Stokes) term, with the tessellation
repaired each step on the device. Set the particle state, `init`, `set_dt`, then `step`;
the state setters raise after `init` (the state is then resident on the device).
Instruments: `diagnostics`.

| Method / property | Description |
|---|---|
| `clear_geometry` | clear_geometry(self) -> None  Drop the SDF geometry (before init()). |
| `diagnostics` | The diagnostics tier: set_repair(), set_profile(). |
| `dt` | The stored time step (0 until `set_dt`). |
| `extent` | The box size (Lx, Ly, Lz) — read-only; set it with `set_domain`. |
| `get_forces` | get_forces(self) -> numpy.ndarray[dtype=float64]  Current per-particle force (N,3) float64 — the pressure (EOS) force plus the optional viscous Navier-Stokes term, as used by the last velocity-Verlet kick. Useful for force-field analysis, equilibrium/convergence checks, and coupling. |
| `get_neighbor_counts` | get_neighbor_counts(self) -> numpy.ndarray[dtype=int32]  Per-particle Voronoi neighbour (facet) count (N,) int32 (a copy). |
| `get_positions` | get_positions(self) -> numpy.ndarray[dtype=float64]  Current particle positions (N,3) float64. |
| `get_velocities` | get_velocities(self) -> numpy.ndarray[dtype=float64]  Current particle velocities (N,3) float64. |
| `get_volumes` | get_volumes(self) -> numpy.ndarray[dtype=float64]  Per-particle Voronoi cell volume (N,) float64 (a copy). |
| `init` | init(self) -> None  Build the first tessellation and forces from the particle state set above (checks that every per-particle array has the N of set_masses). |
| `internal_energy` | internal_energy(self) -> float  Total internal (EOS) energy (scalar). |
| `kinetic_energy` | kinetic_energy(self) -> float  Total kinetic energy ½ Σ m_i |v_i|² (a device reduction). |
| `num_particles` | Particle count N. |
| `set_bulk_viscosities` | set_bulk_viscosities(self, viscosities: ndarray[dtype=float64, order='C']) -> None  Per-particle bulk viscosity (N,) float64 (defaults to zero if unset; before init). |
| `set_domain` | set_domain(self, extent: collections.abc.Sequence[float], origin: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], periodic: collections.abc.Sequence[bool] = [True, True, True]) -> None  Set the periodic box before `init`: `extent` is the box SIZE (Lx, Ly, Lz). The suite-wide spelling (suite/docs/NAMING.md 1.1), the same call `dem.Simulation.set_domain` takes. `origin` must be (0, 0, 0) and `periodic` (True, True, True) — this engine's box is anchored at the origin and periodic on every axis; both are checked rather than ignored, so a caller who writes the suite-wide form gets an error naming the limitation. |
| `set_dt` | set_dt(self, dt: float) -> None  Set the time step. The suite-wide way to configure a stepper (suite/docs/NAMING.md 1.5) — `flow.Solver`, `dem.Simulation` and `peclet.core.amr.Flow` all take `set_dt`. |
| `set_geometry` | set_geometry(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float64, order='C'], root: int = 0, grad_h: float = 1e-05) -> None  SDF solid walls for the fluid (same flat node encoding as Tessellation.set_geometry). The cells are clipped by the solid; the EOS pressure acts on the wall facets (the wall pushes back). Before init(). |
| `set_masses` | set_masses(self, masses: ndarray[dtype=float64, order='C']) -> None  Particle masses (N,) float64, all > 0 (before init; sets N). |
| `set_positions` | set_positions(self, positions: ndarray[dtype=float64, order='C']) -> None  Initial particle positions (N,3) float64 (before init). |
| `set_pressure` | set_pressure(self, pressure: float) -> None  Equation-of-state pressure constant (the stiffness of the barotropic EOS; before init). |
| `set_velocities` | set_velocities(self, velocities: ndarray[dtype=float64, order='C']) -> None  Initial particle velocities (N,3) float64 (before init; at rest if not set). |
| `set_viscosities` | set_viscosities(self, viscosities: ndarray[dtype=float64, order='C']) -> None  Per-particle shear viscosity (N,) — enables the viscous Navier-Stokes term (before init). |
| `step` | step(self, num_steps: int) -> None  Advance the velocity-Verlet dynamics by `num_steps` steps of the stored time step (`set_dt`); raises before init() and if no dt was set. |
| `time` | Current simulation time. |

### `FlowSolver`
Static Navier–Stokes solver on the face mesh of a resident (built) Tessellation (Voronoi methods plan, track C). layout='collocated' (default): peclet.flow's approximate projection with the skew-corrected adjoint constraint pair — second order on unstructured Voronoi meshes; layout='covolume': the staggered covolume scheme (exact energy conservation, first order on unstructured meshes). Walls come from the tessellation's SDF geometry (no-slip unless set_wall_velocity). SSP-RK3 with a projection per stage; GraphAMG-PCG pressure solve. The mesh is frozen at construction — build a new FlowSolver after moving the seeds. Instruments: `diagnostics`.

| Method / property | Description |
|---|---|
| `diagnostics` | The diagnostics tier: set_skew_corrected(), set_wall_gradient_quadratic(). |
| `dt` | The stored time step (0 until `set_dt`). |
| `get_pressure` | get_pressure(self) -> numpy.ndarray[dtype=float64]  Cell pressure (num_cells,) float64 (a copy). |
| `get_velocities` | get_velocities(self) -> numpy.ndarray[dtype=float64]  Cell velocity (num_cells, 3) float64 (a copy; the covolume layout reconstructs it from the face fluxes). |
| `get_volumes` | get_volumes(self) -> numpy.ndarray[dtype=float64]  Cell volume (num_cells,) float64 (a copy) — the face mesh's, i.e. the tessellation's. |
| `kinetic_energy` | kinetic_energy(self) -> float  Total kinetic energy ½ Σ V_i |U_i|² over the cells (a device reduction). |
| `layout` | The solver layout this instance was built with: 'collocated' or 'covolume'. |
| `max_divergence` | max_divergence(self) -> float  Max over the cells of the discrete divergence of the transporting face flux — round-off after a projection. |
| `num_cells` | Number of cells of the face mesh (= the tessellation's particle count). |
| `num_faces` | Number of faces of the face mesh: interior faces first, then the wall faces. |
| `num_wall_faces` | Number of SDF wall faces (the trailing block of the faces); 0 without geometry. |
| `pressure_iterations` | PCG iteration count of the last pressure solve. |
| `set_body_force` | set_body_force(self, force: collections.abc.Sequence[float]) -> None  Uniform body force per unit mass (fx, fy, fz) applied to every cell (a pressure gradient drive, gravity). |
| `set_dt` | set_dt(self, dt: float) -> None  Set the time step (suite/docs/NAMING.md 1.5); `step` uses it. |
| `set_implicit_diffusion` | set_implicit_diffusion(self, on: bool) -> None  Collocated only (raises on covolume): flow's semi-implicit step (explicit convection, backward-Euler viscous solve, approximate projection) — no diffusive dt limit, first order in time. |
| `set_pressure_tolerance` | set_pressure_tolerance(self, tol: float) -> None  Relative residual at which the pressure PCG stops (default set by the solver). |
| `set_stokes` | set_stokes(self, on: bool) -> None  Drop the convective term (creeping flow). |
| `set_velocity` | set_velocity(self, U: ndarray[dtype=float64, order='C']) -> None  Initial cell velocity (num_cells, 3); projected once. |
| `set_wall_velocity` | set_wall_velocity(self, U: ndarray[dtype=float64, order='C']) -> None  Prescribed velocity on the wall faces, (num_wall_faces, 3). |
| `step` | step(self, num_steps: int) -> None  Advance `num_steps` steps of the stored time step (`set_dt`); raises if none was set. |

### `VoronoiHalo`
Distributed (MPI) ghost-gather for the multi-rank Voronoi tessellation.

ORB block-decomposes a periodic box across MPI ranks and gathers, for each rank, every seed
within a cutoff `rcut` of its owned block (periodic images included). The recipe: select this
rank's owned seeds with `owned_mask`, `gather(...)` the owned+ghost set, tessellate it with the
single-rank `Tessellation` building only the first `n_owned` cells, and keep those cells — they
are bit-identical to a serial full-box tessellation (each owned cell has all its neighbours
present). `rcut` must exceed the largest owned-cell interaction distance (a few mean spacings).
For moving points use DistributedTessellation (the repair driver over this halo).
Auto-initialises MPI (MPI_COMM_WORLD). Drive it from mpi4py.

| Method / property | Description |
|---|---|
| `gather` | gather(self, positions: ndarray[dtype=float64, order='C'], gids: ndarray[dtype=int64, order='C'], rcut: float, weights: ndarray[dtype=float64, order='C'] | None = None) -> tuple  Gather ghost seeds within `rcut` of this rank's owned seeds. Inputs: the owned positions (N,3) float64, their global ids (N,) int64, the cutoff, and optional power weights (N,) float64 (zeros if None). Returns a tuple (pos (M,3) float64, gid (M,) int64, weight (M,) float64, n_owned): rows [0,n_owned) are the owned seeds, [n_owned,M) the gathered ghosts (with their owners' global ids/weights). |
| `num_ranks` | Number of MPI ranks. |
| `owned_mask` | owned_mask(self, positions: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=int32]  Mask (N,) int32 over the given positions (N,3): 1 where this rank owns the point, else 0. |
| `owner_of` | owner_of(self, point: collections.abc.Sequence[float]) -> int  Owning rank of a single point (x, y, z). |
| `rank` | This rank's MPI index. |
| `refresh_positions` | refresh_positions(self, positions: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  Position-only halo refresh (Verlet fast path): re-forward the current owned positions (N,3) onto the topology of the last `gather`, returning the combined owned+ghost positions (M,3) in the same order as that gather (no re-decomposition / ghost re-selection). |

### `DistributedTessellation`
Distributed (MPI) moving-point Voronoi tessellation: VoronoiHalo's ORB decomposition + ghost
gather composed with the device incremental repair under the distributed Verlet-skin
invariant (peclet::voro::mpi::DistributedMovingTessellation, gated by tests/kokkos_mpi at
np = 1, 2, 4). Each rank owns the seeds `owned_mask` selects; `establish` gathers the ghosts
within rcut and cold-builds; every `step` refreshes the ghost positions on the established
topology and repairs locally — until any rank's owned displacement since the last gather
exceeds skin/2, when ALL ranks re-gather and rebuild (a collective decision). The owned
cells [0, num_owned) equal a cold rebuild of the same combined positions to the certificate
tolerance. rcut, skin and tolerance are fractions of the mean spacing cbrt(V/N_global)
(defaults 3.5, 0.25, 0.0001). Collective calls: establish, step. Auto-initialises MPI
(MPI_COMM_WORLD). Instruments: `diagnostics`.

| Method / property | Description |
|---|---|
| `clear_geometry` | clear_geometry(self) -> None  Drop the SDF geometry (before establish()). |
| `diagnostics` | The diagnostics tier: num_regathers, set_profile(). |
| `establish` | establish(self, positions: ndarray[dtype=float64, order='C'], gids: ndarray[dtype=int64, order='C'], weights: ndarray[dtype=float64, order='C'] | None = None) -> None  Collective: gather the ghosts of this rank's owned seeds (positions (N,3), global ids (N,) int64, optional weights (N,)) and cold-build the combined tessellation. Call once, and again whenever ownership changes. |
| `get_combined_gids` | get_combined_gids(self) -> numpy.ndarray[dtype=int64]  Global ids (num_combined,) int64 of the owned + ghost seeds after the last gather (owned first, in establish() order). |
| `get_neighbor_counts` | get_neighbor_counts(self) -> numpy.ndarray[dtype=int32]  Owned-cell neighbour counts (num_owned,) int32 (a copy). |
| `get_volumes` | get_volumes(self) -> numpy.ndarray[dtype=float64]  Owned-cell volumes (num_owned,) float64 (a copy), in establish() order. |
| `get_wall_counts` | get_wall_counts(self) -> numpy.ndarray[dtype=int32]  Owned-cell resident SDF wall plane counts (num_owned,) int32 (a copy). |
| `num_combined` | Owned + ghost seed count of this rank's tessellation after the last gather. |
| `num_owned` | This rank's owned cell count. |
| `num_ranks` | Number of MPI ranks. |
| `owned_mask` | owned_mask(self, positions: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=int32]  Mask (N,) int32 over the given positions (N,3): 1 where this rank owns the point. |
| `rank` | This rank's MPI index. |
| `set_geometry` | set_geometry(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float64, order='C'], root: int = 0, grad_h: float = 1e-05) -> None  Replicated SDF solid (every rank passes the same scene), as Tessellation.set_geometry. Before establish(). |
| `set_wall_mode` | set_wall_mode(self, mode: str, skin_frac: float = 0.0) -> None  Wall re-gather policy, as Tessellation.set_wall_mode: mode one of 'exact', 'skin'. Before establish(). |
| `step` | step(self, positions: ndarray[dtype=float64, order='C']) -> dict  Collective: advance to the new owned positions (N,3, same N and ownership as establish). Returns the Tessellation.step stats dict plus 'regathered' (True when this step took the re-gather + cold-rebuild path; the repair stats are then zero). |

### `OptimizeResult`
Result of optimize_volume_mesh / pore_mesh.optimize_pore_mesh.

| Method / property | Description |
|---|---|
| `converged` | True if the gradient fell below tol. |
| `iters` | Gauss-Newton / descent iterations run. |
| `max_vol_err` | max_i |V_i / V_ref,i - 1| at the returned seeds. |
| `mean_vol_err` | mean_i |V_i / V_ref,i - 1| at the returned seeds. |
| `num_empty` | Seeds whose cell is empty at the returned seeds (0 for a valid mesh). |
| `positions` | The optimised seeds (N,3) float64. |
| `weights` | The optimised power weights (N,) float64, or None when use_weights=False. |

### `InterfaceResult`
Result of minimize_interface.

| Method / property | Description |
|---|---|
| `converged` | True if the gradient fell below tol. |
| `energy` | Final interfacial energy E = sum sigma A_ij over faces between different types. |
| `energy_ratio` | energy / the energy of the input seeds. |
| `iters` | Descent iterations run. |
| `positions` | The minimised seeds (N,3) float64. |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `execution_space` | `'OpenMP'` |

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

### `minimize_interface`
```
minimize_interface(positions: ndarray[dtype=float64, order='C'], types: ndarray[dtype=int32, order='C'], extent: collections.abc.Sequence[float], *, sigma: float = 1.0, search_window: int = 5, max_iter: int = 60, tol: float = 1e-09) -> peclet.voro._voro.InterfaceResult

Surface-Evolver-style interfacial-tension minimiser: move seeds (N,3) on the periodic box
`extent` to minimise the total area of faces between cells of different integer type (N,),
E = sum sigma A_ij (sigma default 1). Steepest descent with a trust-region line search on
the (non-smooth) interfacial energy; search_window / max_iter / tol default to 5 / 60 / 1e-09.
Returns an InterfaceResult (positions, energy, energy_ratio = final/initial, iters, converged).
```

### `optimize_volume_mesh`
```
optimize_volume_mesh(positions: ndarray[dtype=float64, order='C'], target_volumes: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], *, search_window: int = 5, max_iter: int = 60, tol: float = 1e-09, cg_iters: int = 300, use_weights: bool = False, method: str = 'jacobi') -> peclet.voro._voro.OptimizeResult

Move seeds (N,3) — and optionally the power weights — to minimise sum (V_i / V_ref,i - 1)^2 by
damped Gauss-Newton (Newton-Raphson + CG) on the periodic box `extent` (Lx, Ly, Lz).
target_volumes (N,) are the per-cell reference volumes V_ref (renormalised to the box
volume). method: the CG preconditioner, one of 'jacobi', 'colored_gs', 'graphamg', 'steepest' (default 'jacobi'; 'graphamg'
is the O(N) choice at large N, 'steepest' is plain descent). search_window (default 5), max_iter (60), tol (1e-09)
and cg_iters (300) are peclet.voro.defaults. Returns an OptimizeResult (positions, weights, iters,
max_vol_err, mean_vol_err, converged, num_empty). Pure Voronoi (use_weights=False)
reaches equal/graded volumes well; weights add fuller volume control but are limited by
the periodic tessellation's ~1% min-image floor.
```

## `peclet.voro._voro`

peclet.voro (device/Kokkos): moving-particle Voronoi tessellation and dynamics.

Classes: Tessellation (cold build + incremental repair, volumes, neighbour counts, energy
forces), FlowSolver (static Navier-Stokes on the face mesh), Simulation (moving-cell
compressible-Euler / Navier-Stokes fluid); functions optimize_volume_mesh, minimize_interface;
the pore-space family under peclet.voro.pore_mesh; VoronoiHalo and DistributedTessellation
when built with MPI. Every instrument lives on the object's `diagnostics`. Arrays are NumPy:
positions/velocities (N,3) float64, scalars (N,). The backend (Serial/OpenMP/CUDA/HIP) is
fixed at build time; see peclet.voro.execution_space. peclet.voro.defaults lists the named
defaults the engine is driven with.

### `TessellationDiagnostics`
Instruments and ablation switches of a Tessellation (reached as `t.diagnostics`).

| Method / property | Description |
|---|---|
| `build_report` | build_report(self) -> dict  Validity counts of the last build: {'buried', 'reach_exceeded', 'empty', 'overflow', 'incomplete'} — all zero for a guaranteed-exact partition (build() already warns, or raises with strict=True, when they are not) — and 'over_buffer_rebuilds', the number of times the build's facet/edge over-buffer estimate was exceeded and the build pass re-run at the exact demand (0 normally; each one doubles that build's cost). |
| `set_gate` | set_gate(self, on: bool) -> None  Ablation: the adaptive gate (default True) that routes high-churn steps straight to a full rebuild — the 'never much slower than a cold build' guard. Takes effect at the next build(). |
| `set_local_certificate` | set_local_certificate(self, on: bool) -> None  Ablation: the cheap O(nt) Lawson local certificate (default True) vs the brute O(nt*np) form for detecting which cells changed. Both are complete; local is faster. Takes effect at the next build(). |
| `set_profile` | set_profile(self, on: bool = True) -> None  Print the cold build's timing (grid / build / CSR), the worklist size, the over-buffer rebuilds and the max facets per cell on stderr (default off). Takes effect at the next build(). |

### `SimulationDiagnostics`
Performance-path switches of a Simulation (reached as `s.diagnostics`).

| Method / property | Description |
|---|---|
| `set_profile` | set_profile(self, on: bool = True) -> None  Print each cold build's timing and over-buffer report on stderr (default off). |
| `set_repair` | set_repair(self, on: bool = True) -> None  Opt-in (default off): use the incremental moving-point repair + reeval-published force geometry each step instead of a full rebuild. Before init(). |

### `FlowSolverDiagnostics`
Ablation switches of a FlowSolver (reached as `f.diagnostics`): the measured-worse alternatives kept for comparison.

| Method / property | Description |
|---|---|
| `set_skew_corrected` | set_skew_corrected(self, on: bool) -> None  Collocated only: the centroid-consistent constraint pair (default True; the plain pair drops to first order on skewed meshes — README, rung C2b). |
| `set_wall_gradient_quadratic` | set_wall_gradient_quadratic(self, on: bool) -> None  Wall viscous flux from the wall-anchored least-squares quadratic (default True; exact for Poiseuille) instead of the two-point (U_i - U_wall)/h_A (-13 % on the sphere drag). |

### `DistributedTessellationDiagnostics`
Instruments of a DistributedTessellation (reached as `d.diagnostics`).

| Method / property | Description |
|---|---|
| `num_regathers` | Number of collective re-gather + cold-rebuild events since construction (establish counts as one). |
| `set_profile` | set_profile(self, on: bool = True) -> None  Print each rank's cold-build timing and over-buffer report on stderr (default off). |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `execution_space` | `'OpenMP'` |

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

### `minimize_interface`
```
minimize_interface(positions: ndarray[dtype=float64, order='C'], types: ndarray[dtype=int32, order='C'], extent: collections.abc.Sequence[float], *, sigma: float = 1.0, search_window: int = 5, max_iter: int = 60, tol: float = 1e-09) -> peclet.voro._voro.InterfaceResult

Surface-Evolver-style interfacial-tension minimiser: move seeds (N,3) on the periodic box
`extent` to minimise the total area of faces between cells of different integer type (N,),
E = sum sigma A_ij (sigma default 1). Steepest descent with a trust-region line search on
the (non-smooth) interfacial energy; search_window / max_iter / tol default to 5 / 60 / 1e-09.
Returns an InterfaceResult (positions, energy, energy_ratio = final/initial, iters, converged).
```

### `optimize_pore_mesh`
```
optimize_pore_mesh(positions: ndarray[dtype=float64, order='C'], target_volumes: ndarray[dtype=float64, order='C'], sphere_centers: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], *, search_window: int = 6, max_iter: int = 80, tol: float = 1e-09, cg_iters: int = 400, method: str = 'graphamg', mu_barrier: float = 0.0, free_energy: bool = False) -> peclet.voro._voro.OptimizeResult

Relax interstitial seeds (N,3) so their SDF-clipped Voronoi cell volumes approach the per-cell
target_volumes (N,), with the sphere packing (sphere_centers (M,3), sphere_radii (M,)) as
periodic walls in the cubic box `extent` (Lx == Ly == Lz). method: one of 'jacobi', 'colored_gs', 'graphamg', 'steepest' (default
'graphamg'; 'steepest' is plain descent). free_energy=True uses E = -sum V_ref log V (pressure
V_ref/V, resists collapse); mu_barrier > 0 adds a log-barrier that decays by 0.7 per iteration.
search_window / max_iter / tol / cg_iters default to 6 / 80 / 1e-09 / 400. Returns an
OptimizeResult. Experimental (pore-space meshing; see the pore-mesh-voronoi example).
```

### `optimize_volume_mesh`
```
optimize_volume_mesh(positions: ndarray[dtype=float64, order='C'], target_volumes: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], *, search_window: int = 5, max_iter: int = 60, tol: float = 1e-09, cg_iters: int = 300, use_weights: bool = False, method: str = 'jacobi') -> peclet.voro._voro.OptimizeResult

Move seeds (N,3) — and optionally the power weights — to minimise sum (V_i / V_ref,i - 1)^2 by
damped Gauss-Newton (Newton-Raphson + CG) on the periodic box `extent` (Lx, Ly, Lz).
target_volumes (N,) are the per-cell reference volumes V_ref (renormalised to the box
volume). method: the CG preconditioner, one of 'jacobi', 'colored_gs', 'graphamg', 'steepest' (default 'jacobi'; 'graphamg'
is the O(N) choice at large N, 'steepest' is plain descent). search_window (default 5), max_iter (60), tol (1e-09)
and cg_iters (300) are peclet.voro.defaults. Returns an OptimizeResult (positions, weights, iters,
max_vol_err, mean_vol_err, converged, num_empty). Pure Voronoi (use_weights=False)
reaches equal/graded volumes well; weights add fuller volume control but are limited by
the periodic tessellation's ~1% min-image floor.
```

### `sdf_voronoi_cells`
```
sdf_voronoi_cells(positions: ndarray[dtype=float64, order='C'], sphere_centers: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], *, search_window: int = 6) -> dict

Reconstruct the SDF-clipped interstitial Voronoi cells (cubic periodic box `extent`, the
spheres as walls) on the device — the tessellator's own gather, one thread per cell — and
return their polyhedra as flat arrays (VTK_POLYHEDRON layout) in seed order: 'points' (Np,3),
'faces' + 'face_offsets' (per-cell face lists, global point ids, each face CCW about its
outward normal), 'volume' (Nc,), 'boundary' (Nc, 1 where the cell touches a sphere wall),
'seed' (Nc,). Seeds inside a sphere have no cell; 'num_overflow' counts cells skipped for
exceeding the cell capacity (peclet.voro.defaults max_planes / max_triangles) and 'num_incomplete' the cells whose
gather window (search_window grid blocks per axis, default 6) did not close — raise
search_window if it is not 0.
```

### `sdf_voronoi_section`
```
sdf_voronoi_section(positions: ndarray[dtype=float64, order='C'], sphere_centers: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], point: collections.abc.Sequence[float], normal: collections.abc.Sequence[float], *, search_window: int = 6) -> dict

Cross-section of the SDF-clipped interstitial Voronoi mesh (cubic periodic box `extent`) by
the plane through `point` with `normal`, on the device: every cell cut directly
(ConvexCell::sectionPolygon, from the dual edges, so it tiles the plane exactly where a
face-by-face slice drops facets). Returns 'verts' (Nv,3, world coords, all on the plane, CCW
about the normal) + 'offsets' (Npoly+1, per-polygon vertex ranges) + 'volume' (Npoly, the 3-D
cell volume) + 'seed' (Npoly, the seed index), in seed order, plus 'num_overflow' /
'num_incomplete' as in sdf_voronoi_cells (search_window default 6). For a z=z0 slice pass
point=(0,0,z0), normal=(0,0,1) and plot verts[:, :2].
```

## `peclet.voro.pore_mesh`

peclet.voro.pore_mesh — the SDF-walled pore-space (interstitial Voronoi) family.

The wall geometry is a periodic packing of spheres (``sphere_centers`` (M,3), ``sphere_radii`` (M,))
in a CUBIC box ``extent`` = (L, L, L); every function takes the suite-wide ``extent`` triple and
checks it is cubic. Bound in ``_voro`` and re-exported here: :func:`optimize_pore_mesh` (the
position-only Gauss–Newton relaxation toward per-cell target volumes), :func:`sdf_voronoi_cells`
(the clipped polyhedra) and :func:`sdf_voronoi_section` (a plane cross-section). Implemented here:
:func:`redistribute_pore_mesh`, the topological split / merge / relax loop that drives a seeding to
a graded target (rung B2 of the Voronoi methods plan).

### `RedistributeResult`
Result of :func:`redistribute_pore_mesh`.
### `optimize_pore_mesh`
```
optimize_pore_mesh(positions: ndarray[dtype=float64, order='C'], target_volumes: ndarray[dtype=float64, order='C'], sphere_centers: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], *, search_window: int = 6, max_iter: int = 80, tol: float = 1e-09, cg_iters: int = 400, method: str = 'graphamg', mu_barrier: float = 0.0, free_energy: bool = False) -> peclet.voro._voro.OptimizeResult

Relax interstitial seeds (N,3) so their SDF-clipped Voronoi cell volumes approach the per-cell
target_volumes (N,), with the sphere packing (sphere_centers (M,3), sphere_radii (M,)) as
periodic walls in the cubic box `extent` (Lx == Ly == Lz). method: one of 'jacobi', 'colored_gs', 'graphamg', 'steepest' (default
'graphamg'; 'steepest' is plain descent). free_energy=True uses E = -sum V_ref log V (pressure
V_ref/V, resists collapse); mu_barrier > 0 adds a log-barrier that decays by 0.7 per iteration.
search_window / max_iter / tol / cg_iters default to 6 / 80 / 1e-09 / 400. Returns an
OptimizeResult. Experimental (pore-space meshing; see the pore-mesh-voronoi example).
```

### `redistribute_pore_mesh`
```
Global redistribution of pore-space seeds toward the graded target volume
V_ref = s(φ)³, s(φ) = clip(φ, s_lo, s_hi) (φ = distance to the nearest sphere wall), by
TOPOLOGICAL moves the position-only optimiser cannot make (it cannot move seeds between
pores — rung B2 of the Voronoi methods plan):

  * split: a cell with V > β V_ref gets a second seed (offset from its centroid by ~s(φ)),
  * merge: a seed whose cell has V < V_ref/β, or no cell at all (dead / empty / buried), is
    removed — its neighbours absorb the volume,
  * relax: `lloyd_steps` Lloyd sweeps (seed → clipped-cell centroid, kept off the wall),

repeated until max |V/V_ref − 1| < tol (V_ref renormalised so Σ V_ref = the fluid volume) or
`max_rounds`; `max_change` caps the fraction of seeds changed per round. With `polish` the
position-only optimiser (:func:`optimize_pore_mesh`, GraphAMG Gauss–Newton) finishes from the
now-feasible start. Returns a :class:`RedistributeResult`.

The sphere packing is the periodic wall geometry (sphere_centers (M,3), sphere_radii (M,)) in
the cubic box `extent` = (L, L, L).
```

### `sdf_voronoi_cells`
```
sdf_voronoi_cells(positions: ndarray[dtype=float64, order='C'], sphere_centers: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], *, search_window: int = 6) -> dict

Reconstruct the SDF-clipped interstitial Voronoi cells (cubic periodic box `extent`, the
spheres as walls) on the device — the tessellator's own gather, one thread per cell — and
return their polyhedra as flat arrays (VTK_POLYHEDRON layout) in seed order: 'points' (Np,3),
'faces' + 'face_offsets' (per-cell face lists, global point ids, each face CCW about its
outward normal), 'volume' (Nc,), 'boundary' (Nc, 1 where the cell touches a sphere wall),
'seed' (Nc,). Seeds inside a sphere have no cell; 'num_overflow' counts cells skipped for
exceeding the cell capacity (peclet.voro.defaults max_planes / max_triangles) and 'num_incomplete' the cells whose
gather window (search_window grid blocks per axis, default 6) did not close — raise
search_window if it is not 0.
```

### `sdf_voronoi_section`
```
sdf_voronoi_section(positions: ndarray[dtype=float64, order='C'], sphere_centers: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], extent: collections.abc.Sequence[float], point: collections.abc.Sequence[float], normal: collections.abc.Sequence[float], *, search_window: int = 6) -> dict

Cross-section of the SDF-clipped interstitial Voronoi mesh (cubic periodic box `extent`) by
the plane through `point` with `normal`, on the device: every cell cut directly
(ConvexCell::sectionPolygon, from the dual edges, so it tiles the plane exactly where a
face-by-face slice drops facets). Returns 'verts' (Nv,3, world coords, all on the plane, CCW
about the normal) + 'offsets' (Npoly+1, per-polygon vertex ranges) + 'volume' (Npoly, the 3-D
cell volume) + 'seed' (Npoly, the seed index), in seed order, plus 'num_overflow' /
'num_incomplete' as in sdf_voronoi_cells (search_window default 6). For a z=z0 slice pass
point=(0,0,z0), normal=(0,0,1) and plot verts[:, :2].
```

### `sphere_union_scene`
```
Flat scene encoding ``(node_ints (n,3) int32, node_reals (n,16) float64, root)`` of the CSG
union of solid spheres — pass it to :meth:`Tessellation.set_geometry` as
``t.set_geometry(*sphere_union_scene(centers, radii))``. ``centers`` (M,3), ``radii`` (M,).
```

### `sphere_union_sdf`
```
Signed distance of ``points`` (N,3) to the periodic union of spheres (``centers`` (M,3),
``radii`` (M,)) in the box ``extent`` (Lx, Ly, Lz): ``min_i(|x - c_i|_minimage - r_i)``, < 0
inside a sphere, > 0 in the fluid. The numpy twin of the scene from
:func:`sphere_union_scene`.
```

## `peclet.voro.scenes`

peclet.voro.scenes — small SDF scene helpers for the tessellator's ``set_geometry``.

The tessellator takes a core shape scene in the flat node encoding (``node_ints`` (n,3) int32,
``node_reals`` (n,16) float64, a root index) — what :meth:`peclet.core.geom.SceneBuilder.encode`
returns. These helpers build the two encodings the pore-space examples need without importing
``peclet.core``: the CSG union of solid spheres (a packed bed as walls) and its numpy evaluation.

### `sphere_union_scene`
```
Flat scene encoding ``(node_ints (n,3) int32, node_reals (n,16) float64, root)`` of the CSG
union of solid spheres — pass it to :meth:`Tessellation.set_geometry` as
``t.set_geometry(*sphere_union_scene(centers, radii))``. ``centers`` (M,3), ``radii`` (M,).
```

### `sphere_union_sdf`
```
Signed distance of ``points`` (N,3) to the periodic union of spheres (``centers`` (M,3),
``radii`` (M,)) in the box ``extent`` (Lx, Ly, Lz): ``min_i(|x - c_i|_minimage - r_i)``, < 0
inside a sphere, > 0 in the fluid. The numpy twin of the scene from
:func:`sphere_union_scene`.
```

