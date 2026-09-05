# peclet.voro — dynamic Voronoi tessellation + Voronoi-mesh flow

Moving-cell Voronoi tessellation, moving-cell dynamics, the unstructured-mesh generator that feeds `peclet.flow`, the covolume / collocated Navier–Stokes solver on a Voronoi mesh (`FlowSolver`) and the distributed tessellation (`VoronoiHalo`).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.voro`

peclet.voro — dynamic 3D Voronoi tessellation of moving particles.

A device-native (Kokkos) moving-cell Voronoi engine: periodic & Lees–Edwards boxes, incremental cell
repair, and compressible Euler / Navier–Stokes / multiphase dynamics on the moving cells. Also serves as
an unstructured-mesh generator that can feed an Eulerian solve in :mod:`peclet.flow`. The compiled
backend (Serial / OpenMP / CUDA / HIP) is chosen at build time — ``peclet.voro.execution_space`` reports
which one this build has.

* :class:`peclet.voro.Tessellation`, :class:`peclet.voro.Simulation`.

``peclet`` is an implicit (PEP 420) namespace shared with the other ``peclet-*`` packages, so it has no
top-level ``__init__.py``.

### `Tessellation`
Moving-particle Voronoi tessellator on the device path.

Build a tessellation once (`build`) then advance it cheaply as the points move
(`step`) — the incremental two-pass repair is several times faster than rebuilding
for the small per-step displacements typical of CFD/DEM, and falls back to a full
rebuild (via an adaptive gate) when displacements are large, so it is never much
slower than a cold build. Periodic cubic box. Single domain (one process).

| Method / property | Description |
|---|---|
| `build` | build(self, positions: ndarray[dtype=float64, order='C'], strict: bool = False) -> None  Cold-build the (power-)Voronoi tessellation of `positions` (N,3) from scratch and make it resident, clipped by the geometry from `set_geometry` if any. Sets the particle count N for subsequent `step` calls. Warns (raises if strict=True) when the result is not a guaranteed-exact partition: buried power cells (a seed outside its own cell — never for w = r² of non-overlapping spheres), a search reach beyond half the box, or overflowed cells; see `build_report()`. |
| `build_report` | build_report(self) -> dict  Validity counts of the last build: {'buried', 'reach_exceeded', 'empty', 'overflow', 'incomplete'} — all zero for a guaranteed-exact partition. |
| `clear_geometry` | clear_geometry(self) -> None  Drop the SDF geometry (takes effect at the next `build`). |
| `clear_weights` | clear_weights(self) -> None  Back to the unweighted Voronoi diagram (next `build`). |
| `energy_forces` | energy_forces(self, types: ndarray[dtype=int32, order='C'], tension: ndarray[dtype=float64, order='C'], sigma_wall: ndarray[dtype=float64, order='C'] | None = None, dEdV: ndarray[dtype=float64, order='C'] | None = None, lloyd: float = 0.0, facet_tension: float = 0.0) -> dict  Energies and their exact gradients on the RESIDENT cells (after build/step), no rebuild:   interfacial  E = Σ σ(t_i,t_j) A_ij over facets between different `types` (N,) int32,                with the symmetric `tension` table (nTypes, nTypes) float64;   wetting      E = Σ σ_wall(t_i) A_wall,i over SDF wall facets, if `sigma_wall` (nTypes,)                is given (a uniform wall tension is a constant — only the species                difference does work, which is what sets the contact angle);   volume       Σ e_i(V_i) for a caller-supplied e'(V_i) = `dEdV` (N,) (e.g.   centroidal   `lloyd` · Σ ∫_cell |y − x_i|² (Lloyd/CVT; gradient 2V(x−c) drives seeds to                their centroids — the skewness the grid solver's two-point operators need gone);   roundness    `facet_tension` · Σ A_f over all interior faces. 2(V/Vref−1)/Vref). Returns {'interface_energy', 'wall_energy', 'force' (N,3) = dE/dx, 'force_w' (N,) = dE/dw when weights are set}. Descend along −force to minimise. |
| `neighbor_counts` | neighbor_counts(self) -> numpy.ndarray[dtype=int32]  Per-particle Voronoi neighbour count (N,) int32 — the number of faces of each cell (wall facets included). |
| `num_particles` | Particle count N set by the last `build`. |
| `set_box` | set_box(self, L: collections.abc.Sequence[float]) -> None  Set the periodic box edge lengths (Lx, Ly, Lz). Call before `build`. |
| `set_gate` | set_gate(self, on: bool = True) -> None  Enable the adaptive gate (default True) that routes high-churn steps straight to a full rebuild — the 'never much slower than a cold build' guard. |
| `set_geometry` | set_geometry(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float64, order='C'], root: int = 0, grad_h: float = 1e-05) -> None  Clip the cells by an SDF solid given as a core shape scene in the flat node encoding (node_ints int32 (3 per node), node_reals float64 (16 per node)) — exactly what peclet.core.geom.Scene.encode() returns and dem.add_analytic_wall takes; `root` is the tree root to evaluate. Suite sign convention: sdf < 0 inside the solid. Seeds inside the solid get no cell (volume 0); cells reaching into it gain wall facets. Applies to the next `build` and is carried through every `step` (wall planes are resident; a boundary watch re-clips cells at the wall). `grad_h` is the central-difference step for the SDF gradient. Analytic vocabulary only (no sampled grids through this path yet). |
| `set_local_certificate` | set_local_certificate(self, on: bool = True) -> None  Use the cheap O(nt) Lawson local certificate (default True) instead of the brute O(nt*np) form for detecting which cells changed. Both are complete; local is faster. |
| `set_tolerance` | set_tolerance(self, frac: float = 0.0001) -> None  Certificate tolerance as a fraction of the mean inter-particle spacing (default 1e-4). A vertex poking past a stored plane by more than this flags the cell for repair; smaller is stricter (closer to machine-exact) at marginally higher cost. |
| `set_wall_mode` | set_wall_mode(self, exact: bool = True, skin_frac: float = 0.0) -> None  Wall re-gather policy for `step` (default exact=True): re-clip every wall-clipped cell that moved, so the incremental result equals a cold rebuild. exact=False keeps a cell's stale tangent planes until it moved more than skin_frac × mean spacing (cheaper, not exact by construction). |
| `set_weights` | set_weights(self, weights: ndarray[dtype=float64, order='C']) -> None  Per-seed POWER (Laguerre) weights (N,) float64: the cells become the power diagram (radical planes) instead of the Voronoi diagram. Takes effect at the next `build`; call again before a `step` to update the weights alongside the positions. Exact in the small-weight regime (see the docs). |
| `step` | step(self, positions: ndarray[dtype=float64, order='C']) -> dict  Incrementally repair the resident tessellation to new `positions` (N,3, same N as `build`). Returns a dict of per-step work stats: 'flagged' (cells the certificate flagged), 'pass1' and 'pass2' (cells re-gathered in each pass), 'extra' (cells gathered across verify extra-passes), 'surgical' (Pass-1 cells repaired surgically), 'verify_passes' (verify iterations run), 'rebuilt' (True if the gate routed this step to a full rebuild), 'fell_back' (True if the verify failed and a cold rebuild was forced). |
| `volumes` | volumes(self) -> numpy.ndarray[dtype=float64]  Per-particle Voronoi cell volume (N,) float64. Sums to the box volume (space-filling). |
| `wall_counts` | wall_counts(self) -> numpy.ndarray[dtype=int32]  Per-particle number of resident SDF wall planes (N,) int32; all zero without geometry. |

### `Simulation`
Device-native compressible-Euler / Navier-Stokes Voronoi fluid simulation.

Velocity-Verlet dynamics of a moving-particle Voronoi fluid: pressure forces from an
EOS plus an optional per-particle viscous (Navier-Stokes) term, with the tessellation
repaired each step on the device. Set the particle state, `init`, then `step`.

| Method / property | Description |
|---|---|
| `clear_geometry` | clear_geometry(self) -> None  Drop the SDF geometry (before init()). |
| `get_forces` | get_forces(self) -> numpy.ndarray[dtype=float64]  Current per-particle force (N,3) float64 — the pressure (EOS) force plus the optional viscous Navier-Stokes term, as used by the last velocity-Verlet kick. Useful for force-field analysis, equilibrium/convergence checks, and coupling. |
| `get_internal_energy` | get_internal_energy(self) -> float  Total internal (EOS) energy (scalar). |
| `get_kinetic_energy` | get_kinetic_energy(self) -> float  Total kinetic energy (scalar). |
| `get_num_neighbors` | get_num_neighbors(self) -> numpy.ndarray[dtype=int32]  Per-particle Voronoi neighbour (facet) count (N,) int32. |
| `get_positions` | get_positions(self) -> numpy.ndarray[dtype=float64]  Current particle positions (N,3) float64. |
| `get_time` | get_time(self) -> float  Current simulation time (scalar). |
| `get_velocities` | get_velocities(self) -> numpy.ndarray[dtype=float64]  Current particle velocities (N,3) float64. |
| `get_volumes` | get_volumes(self) -> numpy.ndarray[dtype=float64]  Per-particle Voronoi cell volume (N,) float64. |
| `init` | init(self) -> None  Build the first tessellation and forces from the particle state set above. |
| `num_particles` | Particle count N. |
| `set_box` | set_box(self, L: collections.abc.Sequence[float]) -> None  Set the periodic box edge lengths (Lx, Ly, Lz). |
| `set_bulk_viscosities` | set_bulk_viscosities(self, viscosities: ndarray[dtype=float64, order='C']) -> None  Per-particle bulk viscosity (N,) float64 (defaults to zero if unset). |
| `set_geometry` | set_geometry(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float64, order='C'], root: int = 0, grad_h: float = 1e-05) -> None  SDF solid walls for the fluid (same flat node encoding as Tessellation.set_geometry). The cells are clipped by the solid; the EOS pressure acts on the wall facets (the wall pushes back). Call before init(). |
| `set_masses` | set_masses(self, masses: ndarray[dtype=float64, order='C']) -> None  Particle masses (N,) float64. |
| `set_positions` | set_positions(self, positions: ndarray[dtype=float64, order='C']) -> None  Initial particle positions (N,3) float64. |
| `set_pressure` | set_pressure(self, pressure: float) -> None  Equation-of-state pressure constant (the stiffness of the barotropic EOS). |
| `set_repair` | set_repair(self, on: bool = True) -> None  Opt-in (default off): use the incremental moving-point repair + reeval-published force geometry each step instead of a full rebuild. Call before init(). |
| `set_velocities` | set_velocities(self, velocities: ndarray[dtype=float64, order='C']) -> None  Initial particle velocities (N,3) float64. |
| `set_viscosities` | set_viscosities(self, viscosities: ndarray[dtype=float64, order='C']) -> None  Per-particle shear viscosity (N,) — enables the viscous Navier-Stokes term. |
| `step` | step(self, num_steps: int, dt: float) -> None  Advance the velocity-Verlet dynamics by `num_steps` steps of size `dt`. |

### `FlowSolver`
Static Navier–Stokes solver on the face mesh of a resident Tessellation (Voronoi methods plan, track C). layout='collocated' (default): peclet.flow's approximate projection with the skew-corrected adjoint constraint pair — second order on unstructured Voronoi meshes; layout='covolume': the staggered covolume scheme (exact energy conservation, first order on unstructured meshes). Walls come from the tessellation's SDF geometry (no-slip unless set_wall_velocity). SSP-RK3 with a projection per stage; GraphAMG-PCG pressure solve.

| Method / property | Description |
|---|---|
| `get_cell_volume` | get_cell_volume(self) -> numpy.ndarray[dtype=float64] |
| `get_pressure` | get_pressure(self) -> numpy.ndarray[dtype=float64] |
| `get_velocity` | get_velocity(self) -> numpy.ndarray[dtype=float64]  Cell velocity (num_cells, 3). |
| `kinetic_energy` | kinetic_energy(self) -> float |
| `layout` | layout(self) -> str |
| `max_divergence` | max_divergence(self) -> float |
| `num_cells` | num_cells(self) -> int |
| `num_faces` | num_faces(self) -> int |
| `num_wall_faces` | num_wall_faces(self) -> int |
| `pressure_iterations` | pressure_iterations(self) -> int |
| `set_body_force` | set_body_force(self, fx: float, fy: float, fz: float) -> None |
| `set_implicit_diffusion` | set_implicit_diffusion(self, on: bool) -> None  Collocated: flow's semi-implicit step (explicit convection, backward-Euler viscous solve, approximate projection) — no diffusive dt limit, first order in time. |
| `set_pressure_tolerance` | set_pressure_tolerance(self, tol: float) -> None |
| `set_skew_corrected` | set_skew_corrected(self, on: bool) -> None  Collocated only: the centroid-consistent constraint pair (default on). |
| `set_stokes` | set_stokes(self, on: bool) -> None  Drop the convective term (creeping flow). |
| `set_velocity` | set_velocity(self, U: ndarray[dtype=float64, order='C']) -> None  Initial cell velocity (num_cells, 3); projected once. |
| `set_wall_gradient_quadratic` | set_wall_gradient_quadratic(self, on: bool) -> None  Wall viscous flux from the wall-anchored least-squares quadratic (default on; exact for Poiseuille) instead of the two-point (U_i - U_wall)/h_A. |
| `set_wall_velocity` | set_wall_velocity(self, U: ndarray[dtype=float64, order='C']) -> None  Prescribed velocity on the wall faces, (num_wall_faces, 3). |
| `step` | step(self, num_steps: int, dt: float) -> None |

### `VoronoiHalo`
Distributed (MPI) ghost-gather for the multi-rank Voronoi tessellation.

ORB block-decomposes a periodic box across MPI ranks and gathers, for each rank, every seed
within a cutoff `rcut` of its owned block (periodic images included). The recipe: select this
rank's owned seeds with `owned_mask`, `gather(...)` the owned+ghost set, tessellate it with the
single-rank `Tessellation` building only the first `n_owned` cells, and keep those cells — they
are bit-identical to a serial full-box tessellation (each owned cell has all its neighbours
present). `rcut` must exceed the largest owned-cell interaction distance (a few mean spacings).
Auto-initialises MPI (MPI_COMM_WORLD). Drive it from mpi4py.

| Method / property | Description |
|---|---|
| `gather` | gather(self, owned_pos: ndarray[dtype=float64, order='C'], owned_gid: ndarray[dtype=int64, order='C'], owned_weight: ndarray[dtype=float64, order='C'], rcut: float) -> tuple  Gather ghost seeds within `rcut` of this rank's owned seeds. Inputs: owned_pos (N,3) float64, owned_gid (N,) int64, owned_weight (N,) float64. Returns a tuple (pos (M,3) float64, gid (M,) int64, weight (M,) float64, n_owned): rows [0,n_owned) are the owned seeds, [n_owned,M) the gathered ghosts (with their owners' global ids/weights). |
| `owned_mask` | owned_mask(self, positions: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=int32]  Mask (N,) int32 over the given positions (N,3): 1 where this rank owns the point, else 0. |
| `owner_of` | owner_of(self, x: float, y: float, z: float) -> int  Owning rank of a single point (x, y, z). |
| `rank` | rank(self) -> int  This rank's MPI index. |
| `refresh_positions` | refresh_positions(self, owned_pos: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  Position-only halo refresh (Verlet fast path): re-forward the current owned positions (N,3) onto the topology of the last `gather`, returning the combined owned+ghost positions (M,3) in the same order as that gather (no re-decomposition / ghost re-selection). |
| `size` | size(self) -> int  Number of MPI ranks. |

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
minimize_interface(positions: ndarray[dtype=float64, order='C'], types: ndarray[dtype=int32, order='C'], sigma: float = 1.0, L: float = 1.0, sw: int = 5, max_iter: int = 60, tol: float = 1e-09) -> dict

Surface-Evolver-style interfacial-tension minimiser: move seeds (N,3) to minimise the total
area of faces between cells of different integer type (N,), E = Σ σ A_ij. Steepest descent
with a trust-region line search on the (non-smooth) interfacial energy. Returns a dict with
the updated 'positions', final 'energy', 'energy_ratio' (final/initial), and iters.
```

### `optimize_pore_mesh`
```
optimize_pore_mesh(positions: ndarray[dtype=float64, order='C'], vref: ndarray[dtype=float64, order='C'], sphere_centres: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], L: float, sw: int = 6, max_iter: int = 80, tol: float = 1e-09, cg_iters: int = 400, method: str = 'graphamg', mu_barrier: float = 0.0, free_energy: bool = False) -> dict

Relax interstitial seeds (N,3) so their SDF-clipped Voronoi cell volumes approach the per-cell
targets vref (N,), with the sphere packing (sphere_centres (M,3), sphere_radii (M,)) as periodic
walls. method: 'graphamg'|'jacobi'|'colored_gs' (Gauss-Newton CG) or 'steepest' (descent).
free_energy=True uses E=-Σ V_ref·log V (pressure V_ref/V, resists collapse); mu_barrier>0 adds a
log-barrier. EXPERIMENTAL (pore-space meshing; see the pore-mesh-voronoi example).
```

### `optimize_volume_mesh`
```
optimize_volume_mesh(positions: ndarray[dtype=float64, order='C'], vset: ndarray[dtype=float64, order='C'], L: float = 1.0, sw: int = 5, max_newton: int = 60, tol: float = 1e-09, cg_iters: int = 300, use_weights: bool = False, colored_gs: bool = False) -> dict

Move seeds (N,3) — and optionally the power weights — to minimise Σ(V_i − vset_i)² by damped
Gauss-Newton (Newton–Raphson + CG with a Jacobi or colored-Gauss-Seidel preconditioner).
vset (N,) are the target cell volumes (renormalised to the box volume). Returns a dict with
the updated 'positions' (and 'weights' if use_weights), plus iters/max_vol_err/converged.
Pure Voronoi (use_weights=False) reaches equal/graded volumes well; weights add fuller volume
control but are limited by the periodic tessellation's ~1% min-image floor.
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
now-feasible start. Returns a dict: positions, volumes, vref, max_rel, rms_rel, rounds,
n_added, n_removed, n_dead, history (per-round (N, max_rel, rms_rel, n_dead)).

The sphere packing is the periodic wall geometry (centres (M,3), radii (M,), box L).
```

### `sdf_voronoi_cells`
```
sdf_voronoi_cells(positions: ndarray[dtype=float64, order='C'], sphere_centres: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], L: float) -> dict

Reconstruct the SDF-clipped interstitial Voronoi cells and return their polyhedra as flat
arrays (VTK_POLYHEDRON layout): 'points' (Np,3), 'faces' + 'face_offsets' (per-cell face lists,
global point ids), 'volume' (Nc,), 'boundary' (Nc, 1 where the cell touches a sphere wall).
```

### `sdf_voronoi_section`
```
sdf_voronoi_section(positions: ndarray[dtype=float64, order='C'], sphere_centres: ndarray[dtype=float64, order='C'], sphere_radii: ndarray[dtype=float64, order='C'], L: float, origin: collections.abc.Sequence[float], normal: collections.abc.Sequence[float]) -> dict

Cross-section of the SDF-clipped interstitial Voronoi mesh by the plane through `origin` with
`normal`: cut every cell directly (ConvexCell::sectionPolygon, robust — works from the dual
edges, so it tiles the plane exactly where a face-by-face slice drops facets). Returns 'verts'
(Nv,3, world coords, all on the plane) + 'offsets' (Npoly+1, per-polygon vertex ranges) +
'volume' (Npoly, the 3-D cell volume) + 'seed' (Npoly, the seed index). For a z=z0 slice pass
origin=(0,0,z0), normal=(0,0,1) and plot verts[:, :2].
```

### `sphere_union_scene`
```
Flat scene encoding (node_ints (n,3) int32, node_reals (n,16) float64, root) of the CSG union
of solid spheres — the geometry for :meth:`Tessellation.set_geometry`.
```

