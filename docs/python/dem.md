# peclet.dem — Lagrangian DEM (XPBD + Hertz–Mindlin)

Discrete-element simulation with SDF point-shell collision, analytic SDF walls (static and moving), scene particles, and the distributed (MPI) step. The MPI methods are present only in an MPI-enabled build.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.dem`

peclet.dem — Lagrangian Discrete Element Method (XPBD) particle packing.

A Kokkos + ArborX XPBD solver with SDF point-shell collision for dense particle packing. The compiled
backend (Serial / OpenMP / CUDA / HIP) is chosen at build time — ``peclet.dem.execution_space`` reports
which one this build has. The distributed (MPI) step is exposed only in an MPI-enabled build
(``pip install . --config-settings=cmake.define.PECLET_DEM_MPI=ON``).

* :class:`peclet.dem.Simulation` — the packing simulation (initialize_shape, set_positions, step, ...).
* :func:`peclet.dem.build_particle` — build a general particle (grid SDF + surface point shell + mass
  properties) from an implicit-solid SDF, ready for ``Simulation.set_sdf_shape``.

``peclet`` is an implicit (PEP 420) namespace shared with the other ``peclet-*`` packages, so it has no
top-level ``__init__.py``.

### `Simulation`

| Method / property | Description |
|---|---|
| `add_analytic_wall` | add_analytic_wall(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float32, order='C'], root: int, invert: bool, restitution: float = 0.0, friction: float = 0.0) -> int  Add an ANALYTIC wall from a core shape tree in the flat node encoding (3 ints + 16 reals per node). Exact at every scale, with no voxel grid to replicate per rank. invert=False for a stirrer/obstacle (grains outside the solid); invert=True for a container, built from a SOLID body (a solid cylinder for a drum). The wall is positioned by the node TRANSFORM -- an identity transform sits at the origin. |
| `add_plane` | add_plane(self, point: tuple[float, float, float], normal: tuple[float, float, float]) -> None  Add an infinite boundary wall plane through `point`, with `normal` pointing into the half-space the grains occupy (both 3-sequences). |
| `add_scene_shape` | add_scene_shape(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float32, order='C'], root: int, shell: ndarray[dtype=float32, order='C'], inv_inertia: tuple[float, float, float], bounding_radius: float) -> int  Register a COMPOSED analytic particle shape from core's flat node encoding (the arrays peclet.core.geom.SceneBuilder.encode() returns; CSG of the full leaf vocabulary): the collision field is the exact tree, evaluated in canonical body space. shell: (M,3) surface probe points (bake the tree and run the shell path -- the point-shell model still needs probes). inv_inertia: unit-mass principal diagonal inverse inertia; bounding_radius: canonical enclosing radius. THE CANONICAL FRAME MUST BE THE PRINCIPAL INERTIA FRAME (SceneBuilder.principal_frame emits exactly that); a non-principal tree runs the diagonal-inertia rotational update on the wrong frame, silently. Returns the shape id for set_shape_ids. |
| `add_sdf_shape` | add_sdf_shape(self, grid: ndarray[dtype=float32, order='C'], nx: int, ny: int, nz: int, origin: tuple[float, float, float], spacing: tuple[float, float, float], shell: ndarray[dtype=float32, order='C'], inv_inertia: tuple[float, float, float], bounding_radius: float) -> int  Append a grid-SDF shape (the general non-spherical particle) and return its index. set_sdf_shape stays the single-shape entry point (it RESETS the registry). Pass an EMPTY shell to have one generated from the field itself (core surfacePoints). |
| `add_sdf_wall` | add_sdf_wall(self, grid: ndarray[dtype=float32, order='C'], nx: int, ny: int, nz: int, origin: tuple[float, float, float], spacing: tuple[float, float, float], restitution: float = 0.0, friction: float = 0.0) -> int  Add a static world-space SDF wall/container: flat grid SDF (nx*ny*nz, x-fastest, positive in the void), world origin/spacing, and the binary particle–wall restitution & friction. Returns the wall index. |
| `add_shape` | add_shape(self, shape_type: int, radius: float, height: float = 0.0, thickness: float = 0.0) -> int  Append an analytic shape to the registry and return its index, for a simulation with a MIXTURE of shapes. initialize_shape stays the single-shape entry point (it RESETS the registry to one shape). Assign the returned index with set_shape_ids. |
| `clear_external_forces` | clear_external_forces(self) -> None  Zero all per-particle external forces. |
| `clear_external_torques` | clear_external_torques(self) -> None  Zero all per-particle external torques (and re-enable island sleeping). |
| `compute_overlaps` | compute_overlaps(self) -> float  Measure and return the maximum pair interpenetration of the current committed state. |
| `debug_coloring_conflicts` | debug_coloring_conflicts(self) -> tuple[int, int]  TEST-ONLY: (velocity, position) colouring-invariant violations in the last substep; a valid colouring returns (0, 0). |
| `enable_mpi_step` | enable_mpi_step(self, rcut: float, sync_every: int = 1, forward_rotation: bool = True, rebalance_every: int = 0, verlet_skin: float = 0.0) -> None  Enable the distributed step: ghost cutoff rcut, sync cadence, rotation forwarding, the load-rebalance interval in steps (0 = fixed decomposition), and the Verlet ghost-reuse skin (0 = rebuild the halo topology every substep; >0 = reuse it until a particle moves > skin). |
| `export_lammps` | export_lammps(self, filename: str, step: int) -> None  Export particle state to a LAMMPS dump file. |
| `export_sdf` | export_sdf(self, filename: str, resolution: tuple[int, int, int]) -> None  Reconstruct and write the packed-bed SDF on a (rx,ry,rz) grid to a VTI file. |
| `extent` | The domain's SIZE (Lx, Ly, Lz) — read-only, and note it is a size and not the far corner, which is `origin + extent` (suite/docs/NAMING.md 1.1). |
| `get_angular_velocities` | get_angular_velocities(self) -> numpy.ndarray[dtype=float32]  Return particle angular velocities (body frame) as an (N,3) numpy array. |
| `get_external_forces_view` | get_external_forces_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of the per-particle external force (NumPy view on host, DLPack/CuPy on GPU) — write fluid drag here directly to avoid a host round-trip. |
| `get_growth_factor` | get_growth_factor(self) -> float  Return the current particle growth factor. |
| `get_growth_rate` | get_growth_rate(self) -> float  Return the particle growth rate. |
| `get_inv_inertia` | get_inv_inertia(self) -> numpy.ndarray[dtype=float32]  Return the per-particle principal-frame diagonal inverse inertia as an (N,3) array. |
| `get_inv_mass_view` | get_inv_mass_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,) device array of per-particle inverse mass (NumPy view on host, DLPack/CuPy on GPU) — read-only use; needed for stiff-safe drag integration. |
| `get_masses` | get_masses(self) -> numpy.ndarray[dtype=float32]  Return per-particle masses (1 / inverse mass; 0 for fixed bodies) as an (N,) array. |
| `get_positions` | get_positions(self) -> numpy.ndarray[dtype=float32]  Return particle positions as an (N,3) numpy array. |
| `get_positions_view` | get_positions_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of positions (NumPy view on host, DLPack/CuPy on GPU). |
| `get_profiling_info` | get_profiling_info(self) -> dict  Return a dict of particle/contact/manifold counts and the max overlap. |
| `get_quaternions` | get_quaternions(self) -> numpy.ndarray[dtype=float32]  Return particle orientation quaternions as an (N,4) numpy array. |
| `get_rest_bank_stats` | get_rest_bank_stats(self) -> tuple[float, float, int]  Poisson-restitution diagnostics: (sum, max, n_pairs>0) of the per-pair owed separation impulse committed last substep (physical impulse units). |
| `get_rest_orphan_stats` | get_rest_orphan_stats(self) -> tuple[float, float, int]  Poisson-restitution diagnostics: (sum, max, n_bodies>0) of the per-body orphaned event budget (physical impulse units). |
| `get_scales` | get_scales(self) -> numpy.ndarray[dtype=float32]  Return per-particle scales as a numpy array. |
| `get_sdf_grid` | get_sdf_grid(self, resolution: tuple[int, int, int]) -> numpy.ndarray[dtype=float32]  Reconstruct a packed-bed SDF on a (rx,ry,rz) grid (the get_sdf_grid pipeline for CFD). |
| `get_velocities` | get_velocities(self) -> numpy.ndarray[dtype=float32]  Return particle velocities as an (N,3) numpy array. |
| `get_velocities_view` | get_velocities_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of velocities (NumPy view on host, DLPack/CuPy on GPU). |
| `init_mpi` | init_mpi(self, origin: tuple[float, float, float], size: tuple[float, float, float], gsize: tuple[int, int, int], periodic: tuple[bool, bool, bool]) -> None  Set up the ORB block decomposition + transport-core particle halo for the distributed step. |
| `initialize_shape` | initialize_shape(self, shape_type: int, radius: float, height: float = 0.0, thickness: float = 0.0) -> None  Select the single particle shape and its dimensions: shape_type 1 = sphere (radius), 2 = hollow cylinder (radius, height, thickness), 3 = box (half-extent = radius); any other value is treated as a sphere. RESETS the shape registry to this one shape (use add_shape for a mixture) and records the unit-mass inverse inertia that set_positions applies to every particle -- so call it BEFORE set_positions. `radius` has no default: the retired `initialize` alias defaulted it to 0.5 (and height to 2.0). |
| `max_overlap` | max_overlap(self) -> float  Maximum pair interpenetration recorded by the position solver in the last step (its last-iteration residual, so it under-reports the committed overlap -- see docs/packing_investigation.md). compute_overlaps() measures the committed state. |
| `migrate_to_weights` | migrate_to_weights(self, weights: collections.abc.Sequence[float]) -> int  Co-rebalance: migrate ownership onto the weighted ORB of per-cell weights (global x-fastest, matching the ORB grid) -- the SAME partition the coupled flow solver redistributes onto from the same weight field. Returns this rank's new owned count. |
| `mpi_gathers` | mpi_gathers(self) -> int  Cumulative ghost gather() count across distributed steps. |
| `mpi_rebuilds` | mpi_rebuilds(self) -> int  Cumulative halo topology-rebuild count (Verlet-skin path); pair with mpi_gathers() for the ghost-reuse ratio. |
| `num_asleep` | num_asleep(self) -> int  Number of currently-sleeping real bodies. |
| `num_contacts` | num_contacts(self) -> int  Number of broad-phase candidate pairs found in the last step (ArborX BVH query). |
| `num_ghost` | num_ghost(self) -> int  Return the number of ghost particles on this rank. |
| `num_manifolds` | num_manifolds(self) -> int  Number of narrow-phase contact manifolds (touching pairs) resolved in the last step. |
| `num_particles` | num_particles(self) -> int  Return the number of particles. |
| `num_shapes` | num_shapes(self) -> int  Number of registered shapes. |
| `origin` | The domain's lower corner (x, y, z) — read-only; set it with `set_domain`. |
| `periodic` | Per-axis periodicity (x, y, z) — read-only; set it with `set_periodic`. |
| `rank` | rank(self) -> int  Return this rank's MPI index. |
| `rebalance` | rebalance(self) -> int  Re-decompose by particle count and migrate ownership now; returns this rank's new owned count. |
| `set_angular_velocities` | set_angular_velocities(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle angular velocities from an (N,3) array. |
| `set_domain` | set_domain(self, min: tuple[float, float, float], max: tuple[float, float, float]) -> None set_domain(self, extent: collections.abc.Sequence[float], origin: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], periodic: collections.abc.Sequence[bool] = [True, True, False]) -> None  Overloaded function.  1. ``set_domain(self, min: tuple[float, float, float], max: tuple[float, float, float]) -> None``  Set the domain by (min, max) corner tuples (arbitrary origin); keeps current periodicity.  2. ``set_domain(self, extent: collections.abc.Sequence[float], origin: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], periodic: collections.abc.Sequence[bool] = [True, True, False]) -> None``  Set the domain the suite-canonical way: `extent` is the box SIZE (not the far corner), `origin` the lower corner, `periodic` the per-axis flags. Equivalent to `set_domain(min=origin, max=origin+extent)` plus `set_periodic(*periodic)`. Either form resets the broad-phase skin to 0.1 x the global scale (as set_global_scale does). |
| `set_dt` | set_dt(self, arg: float, /) -> None  Set the time step dt. |
| `set_external_forces` | set_external_forces(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set the per-particle external FORCE (e.g. fluid drag) from an (N,3) array. Applied each step as dv = F*invMass*dt; persists until re-set or cleared. |
| `set_external_torques` | set_external_torques(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set the per-particle external TORQUE in the WORLD frame from an (N,3) array (the resolved-CFD-DEM hydrodynamic torque, a magnetic couple, ...). Applied each step in the angular predictor as Euler's equation in the body frame, dw = invI*(tau_body - w x I w)*dt, alongside the gyroscopic term that is already there; persists until re-set or cleared. Only bodies with a finite inertia respond -- a torque on a body whose invInertia is zero is inert, exactly as the gyroscopic term is. Sleeping is disabled while a torque is set, as it is for external forces. |
| `set_global_scale` | set_global_scale(self, arg: float, /) -> None  Set a global length scale applied to all particles. |
| `set_gravity` | set_gravity(self, arg0: float, arg1: float, arg2: float, /) -> None  Set the gravitational acceleration vector (gx, gy, gz). |
| `set_growth_params` | set_growth_params(self, rate: float, new_factor: float = -1.0) -> None  Set the particle growth rate and target size factor. |
| `set_hertz_material` | set_hertz_material(self, mat: int, youngs: float, poisson: float) -> None  Per-material Young's modulus and Poisson ratio for the soft-sphere Hertz-Mindlin engine (material ids as in set_material_ids). |
| `set_inv_inertia` | set_inv_inertia(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set per-particle inverse inertia from an (N,3) array. |
| `set_inv_mass` | set_inv_mass(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set per-particle inverse mass (0 => fixed/immovable). |
| `set_material_ids` | set_material_ids(self, ids: collections.abc.Sequence[int]) -> None  Per-particle material ids (0..7). Pair (e, mu) values come from set_pair_material; without any set_pair_material call the global material applies everywhere. |
| `set_material_params` | set_material_params(self, restitution_normal: float, restitution_tangent: float = 0.0, friction: float = 0.0) -> None  Set the BODY-BODY normal/tangential restitution and Coulomb friction coefficient. The default friction is ZERO, and add_analytic_wall / add_sdf_wall set the particle-WALL material only -- so a bed more than a few layers deep run with the defaults behaves like a liquid: it transmits full hydrostatic pressure to the container and the position solve squeezes grains through the boundary. That failure is silent and looks like a solver-convergence bug (raising the position iterations and halving dt do not move it). Set a non-zero friction for any deep bed. |
| `set_pair_material` | set_pair_material(self, a: int, b: int, restitution: float, friction: float) -> None  Symmetric pair material (restitution, friction) for material ids (a, b). The first call seeds every pair from the current global material. |
| `set_periodic` | set_periodic(self, x: bool, y: bool, z: bool) -> None  Set periodic boundaries per axis (x, y, z); read back with the `periodic` property (suite/docs/NAMING.md 1.4). |
| `set_positions` | set_positions(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle positions from an (N,3) array, or (N,4) where column 3 is inverse mass. |
| `set_quaternions` | set_quaternions(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle orientation quaternions from an (N,4) array. |
| `set_restitution_model` | set_restitution_model(self, model: str) -> None  Restitution model of the PGS velocity solve: 'newton' (default; per-substep restitution on the pre-solve approach) or 'poisson' (event-level: each pair banks its kinetic compression impulse and releases e x the bank as a budget-capped separation-velocity target during unloading -- restores the multi-substep-impact rebound per-substep Newton cannot return). PECLET_DEM_REST_MODEL overrides. |
| `set_scales` | set_scales(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set per-particle scales from an array. |
| `set_scales_uniform` | set_scales_uniform(self, arg: float, /) -> None  Set a single uniform scale for all particles. |
| `set_sdf_shape` | set_sdf_shape(self, grid: ndarray[dtype=float32, order='C'], nx: int, ny: int, nz: int, origin: tuple[float, float, float], spacing: tuple[float, float, float], shell: ndarray[dtype=float32, order='C'], inv_inertia: tuple[float, float, float], bounding_radius: float) -> None  Import a general particle: grid SDF (flat nx*ny*nz, x-fastest), surface point shell (M,3), unit-mass principal diagonal inverse inertia, and canonical bounding radius. An EMPTY shell means: generate one by sampling the field's own zero level set. |
| `set_shape_ids` | set_shape_ids(self, ids: ndarray[dtype=int32, order='C']) -> None  Per-particle shape index (one int per particle, each < num_shapes()). Refreshes each particle's inverse inertia from its new shape. Call it AFTER set_positions: set_positions resets every particle to shape 0 (and sizes the particle set this call is checked against). |
| `set_sleeping` | set_sleeping(self, enabled: bool, threshold_scale: float = 2.0, consecutive: int = 64, wake_scale: float = 40.0) -> None  Enable island sleeping (single-GPU statics, default OFF): freeze grounded bodies whose motion stays below threshold_scale x the resting floor for `consecutive` substeps; wake only above wake_scale x that floor (hysteresis vs residual jitter). |
| `set_solver_iterations` | set_solver_iterations(self, pos: int, vel: int) -> None  Set the XPBD position- and velocity-solve iteration counts. |
| `set_sphere_shape` | set_sphere_shape(self, radius: float) -> None  Use a uniform sphere of the given radius for all particles. |
| `set_stabilization` | set_stabilization(self, enabled: bool) -> None  Enable/disable the stabilization pass of the staged velocity solve (default True). Boolean form of set_stabilization_mode: True = 'onesided', False = 'off'. |
| `set_stabilization_mode` | set_stabilization_mode(self, mode: str) -> None  Select the stabilization pass of the staged velocity solve: 'off' (pure symmetric PGS), 'onesided' (default: held-lower-side grounded impulses -- arrests any collapse but is a momentum sink), 'multilevel' (GraphMG contact-graph aggregation: coarse inelastic solves at super-body masses -- momentum-conserving transport acceleration), 'escalate' (extra symmetric sweeps up to 256; diagnostic/fallback), 'ordered' (level-ordered symmetric sweeps; measurement mode). |
| `set_thermostat` | set_thermostat(self, temperature: float, tau: float, kB: float = 1.0) -> None  Enable a Berendsen-style velocity thermostat (target temperature, coupling time tau). |
| `set_velocities` | set_velocities(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle velocities from an (N,3) array. |
| `set_velocity_use_gs` | set_velocity_use_gs(self, use_gs: bool) -> None  Select the single-GPU restitution solve: True (default) = colored Gauss–Seidel (correct multi-contact dissipation), False = count-averaged Jacobi (legacy). |
| `set_verlet_skin` | set_verlet_skin(self, skin_frac: float) -> None  Enable the Verlet-cached impulse broadphase (single-GPU, non-periodic, default OFF): skip the ArborX rebuild while nothing moved more than skin/2 (skin = skin_frac x max grain radius). |
| `set_wall_material_id` | set_wall_material_id(self, wid: int, mat: int) -> None  Give an SDF wall a material id so particle-wall (e, mu) resolves via the pair table instead of the wall's binary material. |
| `set_wall_transform` | set_wall_transform(self, wall_index: int, translation: tuple[float, float, float] = (0.0, 0.0, 0.0), quat: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 1.0)) -> None  Place an ANALYTIC wall (add_analytic_wall) rigidly in the world: quat (x,y,z,w) then translation, composed onto the AUTHORED root transform, so calls are absolute and never compound. This moves the GEOMETRY -- a stirrer blade sweeps -- where set_wall_velocity only gives the static surface a velocity field (enough for an axisymmetric drum). Drive both together each step: integrate ang_vel into the quaternion here and pass the same ang_vel to set_wall_velocity. Grid-SDF walls have no tree and are refused. |
| `set_wall_velocity` | set_wall_velocity(self, wall_index: int, lin_vel: tuple[float, float, float] = (0.0, 0.0, 0.0), ang_vel: tuple[float, float, float] = (0.0, 0.0, 0.0), center: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> None  Set a wall's rigid-body surface velocity v(x) = lin_vel + ang_vel × (x − center) (felt by grains in contact even though the geometry is static). Cheap; call every step for a vibrating wall. |
| `step` | step(self, dt: float = 0.0) -> None  Advance the simulation one step of length dt. dt is used AS GIVEN -- the default 0.0 does NOT fall back to the time step set by set_dt; it runs a dynamics-free RELAXATION step (overlap removal only), so step() with no argument advances nothing and a driver calling it runs happily with frozen particles. Always pass dt explicitly. |
| `step_hertz` | step_hertz(self, dt: float, substeps: int = 1, skin_frac: float = 0.30000001192092896) -> None  Advance explicit soft-sphere Hertz-Mindlin steps (spheres, SDF walls, non-periodic): viscoelastic Hertz normal force + Mindlin shear-history spring, Coulomb-clamped; (e, mu) from the pair-material tables, stiffness from set_hertz_material. |
| `step_hertz_mpi` | step_hertz_mpi(self, dt: float, substeps: int = 1, skin_frac: float = 0.30000001192092896) -> None  Advance `substeps` distributed explicit Hertz-Mindlin (force-based) steps of size dt — the MPI counterpart of step_hertz on the init_mpi/enable_mpi_step decomposition. rebalance_every counts CALLS of this method; migration carries the Mindlin history. |
| `step_mpi` | step_mpi(self, nsteps: int = 1) -> None  Advance the distributed (MPI) simulation by nsteps with halo exchange. |
| `wall_sdf_at` | wall_sdf_at(self, wall_index: int, points: ndarray[dtype=float32, order='C']) -> list[float]  Diagnostic: the wall's signed distance at world points, an (M,3) array in -> length-M list out. POSITIVE in the void where the grains live -- exactly what the narrow phase reads, so it is the honest check of a set_wall_transform placement and the way to draw a stirrer. |
| `write_vtp` | write_vtp(self, filename: str) -> None  Write particle state to a VTP file (ParaView/Ovito). |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `execution_space` | `'OpenMP'` |

### `build_particle`
```
Build a :class:`ParticleShape` from a signed-distance function.

Parameters
----------
f : callable
    ``f(points) -> distances``: ``points`` is ``(N, 3)``, returns ``(N,)`` signed distances,
    **negative inside** the solid. Any implicit-modeling front-end that can evaluate on point
    arrays works (hand-written NumPy CSG, `fogleman/sdf`, ...).
bounds : ((xlo, ylo, zlo), (xhi, yhi, zhi))
    Axis-aligned box enclosing the solid, with a little slack so the zero level set is interior.
resolution : int or (nx, ny, nz)
    Lattice resolution. 48–96 is a good range; higher = smoother shell/SDF but larger on-device
    grid.
density : float
    Material density; scales ``mass`` and ``inertia`` (not ``inv_inertia_unit``).
shell : {"vertices", "centroids"}
    Place surface points at marching-cubes vertices or triangle centroids, then thin them to a
    controlled density (see ``target_shell_points``).
target_shell_points : int
    Approximate number of surface points to keep. The dense marching-cubes cloud is voxel-thinned
    to about this many — a few hundred is a good collision-shell size (comparable to the analytic
    shapes). Ignored if ``shell_spacing`` is given.
shell_spacing : float or None
    Explicit thinning cell size (canonical units); overrides ``target_shell_points``. ``None``
    derives it from the surface area and the target count.
align_principal : bool
    Recentre on the COM and rotate onto the principal axes so the stored diagonal inertia is
    exact. Strongly recommended (the solver inertia is diagonal). Requires ``f`` callable.
margin : float
    Extra half-width (as a fraction of the box size) added around ``bounds`` when re-sampling in
    the principal frame, so the rotated shape still fits.

Returns
-------
ParticleShape
```

### `build_wall_sdf`
```
Sample a static container/wall SDF onto a regular world-space lattice.

Give it ``f(points) -> distance`` (``points`` is ``(N, 3)`` world coordinates) that is **positive
in the void where the grains live and negative inside the solid wall**, over an axis-aligned box
``bounds`` that spans the whole simulation domain (the grid must cover wherever a grain can reach).
Returns a :class:`WallSDF` ready for :meth:`WallSDF.add_to`.

Parameters
----------
f : callable
    ``f(points) -> distances``; positive in the void, negative in the wall.
bounds : ((xlo, ylo, zlo), (xhi, yhi, zhi))
    Axis-aligned box covering the domain (typically the full ``set_domain`` box).
resolution : int or (nx, ny, nz)
    Lattice resolution. 64–128 resolves a smooth curved wall well.
```

### `export_lammps`
```
export_lammps(filename: str, step: int, pos: ndarray[dtype=float32, order='C'], vel: ndarray[dtype=float32, order='C'], quats: ndarray[dtype=float32, order='C'], radii: ndarray[dtype=float32, order='C'], box_min: tuple[float, float, float] | None = None, box_max: tuple[float, float, float] | None = None, periodic: bool = False) -> None

Module-level LAMMPS dump writer from raw arrays (filename, step, pos, vel, quats, radii, box corners, periodic flag).
```

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

