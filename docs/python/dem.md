# peclet.dem — Lagrangian DEM (XPBD + Hertz–Mindlin)

Discrete-element simulation with SDF point-shell collision, analytic SDF walls (static and moving), scene particles, and the distributed (MPI) step. The MPI methods are present only in an MPI-enabled build. `Simulation` is the public tier; developer instruments, ablations and GPU execution policies live on `Simulation.diagnostics` (`Diagnostics` below).

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
One granular-dynamics simulation (XPBD impulse engine + explicit Hertz-Mindlin engine, the same particle set). Set up shapes -> domain -> positions -> materials, `set_dt`, then `step(n)`; read out with the `get_*` arrays. Developer instruments live on `.diagnostics`.

| Method / property | Description |
|---|---|
| `add_analytic_wall` | add_analytic_wall(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float32, order='C'], root: int, invert: bool, restitution: float = 0.0, friction: float = 0.0) -> int  Add an ANALYTIC wall from a core shape tree in the flat node encoding (3 ints + 16 reals per node). Exact at every scale, with no voxel grid to replicate per rank. invert=False for a stirrer/obstacle (grains outside the solid); invert=True for a container, built from a SOLID body (a solid cylinder for a drum). The wall is positioned by the node TRANSFORM -- an identity transform sits at the origin. Returns the wall index. |
| `add_plane` | add_plane(self, point: collections.abc.Sequence[float], normal: collections.abc.Sequence[float]) -> None  Add an infinite boundary wall plane through `point`, with `normal` pointing into the half-space the grains occupy (both 3-sequences). XPBD engine only; the Hertz engine takes SDF walls. |
| `add_scene_shape` | add_scene_shape(self, node_ints: ndarray[dtype=int32, order='C'], node_reals: ndarray[dtype=float32, order='C'], root: int, shell: ndarray[dtype=float32, order='C'], inv_inertia: collections.abc.Sequence[float], bounding_radius: float) -> int  Register a COMPOSED analytic particle shape from core's flat node encoding (the arrays peclet.core.geom.SceneBuilder.encode() returns; CSG of the full leaf vocabulary): the collision field is the exact tree, evaluated in canonical body space. shell: (M,3) surface probe points (bake the tree and run the shell path -- the point-shell model still needs probes). inv_inertia: unit-mass principal diagonal inverse inertia; bounding_radius: canonical enclosing radius. THE CANONICAL FRAME MUST BE THE PRINCIPAL INERTIA FRAME (SceneBuilder.principal_frame emits exactly that); a non-principal tree runs the diagonal-inertia rotational update on the wrong frame, silently. Returns the shape id for set_shape_ids. |
| `add_sdf_shape` | add_sdf_shape(self, grid: ndarray[dtype=float32, shape=(*, *, *), order='F'], origin: collections.abc.Sequence[float], spacing: collections.abc.Sequence[float], shell: ndarray[dtype=float32, order='C'], inv_inertia: collections.abc.Sequence[float], bounding_radius: float) -> int  Append a grid-SDF shape (arguments as set_sdf_shape) and return its index. set_sdf_shape stays the single-shape entry point (it RESETS the registry). |
| `add_sdf_wall` | add_sdf_wall(self, grid: ndarray[dtype=float32, shape=(*, *, *), order='F'], origin: collections.abc.Sequence[float], spacing: collections.abc.Sequence[float], restitution: float = 0.0, friction: float = 0.0) -> int  Add a static world-space SDF wall/container (drum barrel, hopper, vibrating tray): `grid` is the signed distance on an (nx, ny, nz) array indexed [x, y, z] at world nodes origin + (x, y, z) * spacing -- POSITIVE in the void where grains live, NEGATIVE in the solid wall; restitution / friction are the binary particle-wall material. Returns the wall index (for set_wall_velocity). See peclet.dem.build_wall_sdf for the SDF -> (grid, origin, spacing) helper. |
| `add_shape` | add_shape(self, shape: str, radius: float, height: float = 0.0, thickness: float = 0.0) -> int  Append an analytic shape ('sphere' | 'hollow_cylinder' | 'box', dimensions as initialize_shape) to the registry and return its index, for a simulation with a MIXTURE of shapes. initialize_shape stays the single-shape entry point (it RESETS the registry). Assign the returned index with set_shape_ids. |
| `capacity` | The particle capacity this was built with. |
| `clear_external_forces` | clear_external_forces(self) -> None  Zero all per-particle external forces. |
| `clear_external_torques` | clear_external_torques(self) -> None  Zero all per-particle external torques (and re-enable island sleeping). |
| `compute_overlaps` | compute_overlaps(self) -> float  Measure and return the maximum pair interpenetration of the current committed state. |
| `diagnostics` | The developer tier (Diagnostics) of this simulation. |
| `dt` | The time step set by set_dt. |
| `enable_mpi_step` | enable_mpi_step(self, rcut: float, sync_every: int = 1, forward_rotation: bool = True, rebalance_every: int = 0, verlet_skin: float = 0.0) -> None  Enable the distributed step: ghost cutoff rcut, sync cadence, rotation forwarding, the load-rebalance interval in steps (0 = fixed decomposition), and the Verlet ghost-reuse skin (0 = rebuild the halo topology every substep; >0 = reuse it until a particle moves > skin). |
| `export_lammps` | export_lammps(self, filename: str, step: int) -> None  Export particle state to a LAMMPS dump file. |
| `export_sdf` | export_sdf(self, filename: str, resolution: tuple[int, int, int]) -> None  Reconstruct and write the packed-bed SDF on an (rx, ry, rz) grid to a VTI file. |
| `extent` | The domain's SIZE (Lx, Ly, Lz) — read-only, and note it is a size and not the far corner, which is `origin + extent` (suite/docs/NAMING.md 1.1). |
| `get_angular_velocities` | get_angular_velocities(self) -> numpy.ndarray[dtype=float32]  Return particle angular velocities (body frame) as an (N, 3) numpy array. |
| `get_external_forces_view` | get_external_forces_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of the per-particle external force (NumPy view on host, DLPack/CuPy on GPU) — write fluid drag here directly to avoid a host round-trip. |
| `get_inv_inertia` | get_inv_inertia(self) -> numpy.ndarray[dtype=float32]  Return the per-particle principal-frame diagonal inverse inertia as an (N, 3) array. |
| `get_inv_mass_view` | get_inv_mass_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,) device array of per-particle inverse mass (NumPy view on host, DLPack/CuPy on GPU) — read-only use; needed for stiff-safe drag integration. |
| `get_masses` | get_masses(self) -> numpy.ndarray[dtype=float32]  Return per-particle masses (1 / inverse mass; 0 for fixed bodies) as an (N,) array. |
| `get_positions` | get_positions(self) -> numpy.ndarray[dtype=float32]  Return particle positions as an (N, 3) numpy array. |
| `get_positions_view` | get_positions_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of positions (NumPy view on host, DLPack/CuPy on GPU). |
| `get_quaternions` | get_quaternions(self) -> numpy.ndarray[dtype=float32]  Return particle orientation quaternions (x, y, z, w) as an (N, 4) numpy array. |
| `get_scales` | get_scales(self) -> numpy.ndarray[dtype=float32]  Return per-particle scales as an (N,) numpy array. |
| `get_sdf_grid` | get_sdf_grid(self, resolution: tuple[int, int, int]) -> numpy.ndarray[dtype=float32]  Reconstruct the packed-bed SDF (negative inside solid) over the domain on an (rx, ry, rz) grid; returns an (rx, ry, rz) array indexed [x, y, z]. |
| `get_velocities` | get_velocities(self) -> numpy.ndarray[dtype=float32]  Return particle velocities as an (N, 3) numpy array. |
| `get_velocities_view` | get_velocities_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of velocities (NumPy view on host, DLPack/CuPy on GPU). |
| `global_scale` | The global length scale. |
| `gravity` | The gravitational acceleration (gx, gy, gz). |
| `growth_factor` | The current particle growth factor (-1 = growth inactive). |
| `growth_rate` | The particle growth rate. |
| `incremental_coloring` | Whether incremental (warm-started) coloring is enabled. |
| `init_mpi` | init_mpi(self, origin: tuple[float, float, float], extent: tuple[float, float, float], cells: tuple[int, int, int], periodic: tuple[bool, bool, bool]) -> None  Set up the ORB block decomposition + core particle halo for the distributed step on the global domain (`origin` lower corner, `extent` SIZE, `cells` per axis for the ORB grid, `periodic` per axis -- the suite's domain quartet). |
| `initialize_shape` | initialize_shape(self, shape: str, radius: float, height: float = 0.0, thickness: float = 0.0) -> None  Select the single particle shape and its dimensions: 'sphere' (radius), 'hollow_cylinder' (radius, height, thickness) or 'box' (half-extent = radius). RESETS the shape registry to this one shape (use add_shape for a mixture) and records the unit-mass inverse inertia that set_positions applies to every particle -- so call it BEFORE set_positions. |
| `max_overlap` | Maximum pair interpenetration recorded by the position solver in the last step (its last-iteration residual, so it under-reports the committed overlap -- see docs/archive/packing_investigation.md). compute_overlaps() measures the committed state. |
| `migrate_to_weights` | migrate_to_weights(self, weights: collections.abc.Sequence[float]) -> int  Co-rebalance: migrate ownership onto the weighted ORB of per-cell weights (global x-fastest, matching the ORB grid) -- the SAME partition the coupled flow solver redistributes onto from the same weight field. Returns this rank's new owned count. |
| `num_asleep` | Number of currently-sleeping real bodies. |
| `num_contacts` | Broad-phase candidate pairs found in the last step (ArborX BVH query). |
| `num_ghost` | The number of ghost particles on this rank. |
| `num_manifolds` | Narrow-phase contact manifolds (touching pairs) resolved in the last step. |
| `num_particles` | The number of particles. |
| `num_shapes` | Number of registered shapes. |
| `origin` | The domain's lower corner (x, y, z) — read-only; set it with `set_domain`. |
| `periodic` | Per-axis periodicity (x, y, z) — read-only; set it with `set_periodic`. |
| `rank` | This rank's MPI index. |
| `rebalance` | rebalance(self) -> int  Re-decompose by particle count and migrate ownership now; returns this rank's new owned count. |
| `relax` | relax(self, n: int = 1) -> None  Run `n` dynamics-free RELAXATION substeps: overlap removal only, no gravity and no velocity update -- the growth-packing protocol's settle move (dt = 0 inside; the stored dt is untouched and set_dt is not required). |
| `restitution_model` | 'newton' or 'poisson'. |
| `set_angular_velocities` | set_angular_velocities(self, angular_velocities: ndarray[dtype=float32, order='C']) -> None  Set particle angular velocities (body frame) from an (N, 3) array. |
| `set_domain` | set_domain(self, min: collections.abc.Sequence[float], max: collections.abc.Sequence[float]) -> None set_domain(self, extent: collections.abc.Sequence[float], origin: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], periodic: collections.abc.Sequence[bool] = [True, True, False]) -> None  Overloaded function.  1. ``set_domain(self, min: collections.abc.Sequence[float], max: collections.abc.Sequence[float]) -> None``  Set the domain by (min, max) corner tuples (arbitrary origin); keeps current periodicity.  2. ``set_domain(self, extent: collections.abc.Sequence[float], origin: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], periodic: collections.abc.Sequence[bool] = [True, True, False]) -> None``  Set the domain the suite-canonical way: `extent` is the box SIZE (not the far corner), `origin` the lower corner, `periodic` the per-axis flags. Equivalent to `set_domain(min=origin, max=origin+extent)` plus `set_periodic(*periodic)`. Either form resets the broad-phase skin to 0.1 x the global scale (as set_global_scale does). |
| `set_dt` | set_dt(self, dt: float) -> None  Set the time step (> 0) every stepper uses: step, step_hertz, step_mpi, step_hertz_mpi. There is no default -- a step before set_dt raises. |
| `set_external_forces` | set_external_forces(self, forces: ndarray[dtype=float32, order='C']) -> None  Set the per-particle external FORCE (e.g. fluid drag) from an (N, 3) array. Applied each step as dv = F*invMass*dt; persists until re-set or cleared. |
| `set_external_torques` | set_external_torques(self, torques: ndarray[dtype=float32, order='C']) -> None  Set the per-particle external TORQUE in the WORLD frame from an (N, 3) array (the resolved-CFD-DEM hydrodynamic torque, a magnetic couple, ...). Applied each step in the angular predictor as Euler's equation in the body frame, dw = invI*(tau_body - w x I w)*dt, alongside the gyroscopic term that is already there; persists until re-set or cleared. Only bodies with a finite inertia respond -- a torque on a body whose invInertia is zero is inert, exactly as the gyroscopic term is. Sleeping is disabled while a torque is set, as it is for external forces. |
| `set_global_scale` | set_global_scale(self, scale: float) -> None  Set a global length scale applied to all particles (effective radius = scale x global_scale x base radius). Resets the broad-phase skin, as set_domain does -- call it BEFORE set_domain if you rely on the skin. |
| `set_gravity` | set_gravity(self, gravity: collections.abc.Sequence[float]) -> None  Set the gravitational acceleration (gx, gy, gz) -- any sequence of three floats. The default is ZERO. |
| `set_growth_params` | set_growth_params(self, rate: float, new_factor: float = -1.0) -> None  Set the particle growth rate (factor *= exp(rate*dt) per step, capped at 1) and, if new_factor > 0, the current growth factor (a negative value keeps it; 0.01 if growth was inactive). |
| `set_hertz_material` | set_hertz_material(self, mat: int, youngs: float, poisson: float) -> None  Per-material Young's modulus and Poisson ratio for the soft-sphere Hertz-Mindlin engine (material ids as in set_material_ids). |
| `set_incremental_coloring` | set_incremental_coloring(self, enabled: bool) -> None  Incremental (warm-started) graph coloring of the contact manifolds (default True): reuse last substep's colors and repair only the conflicts. This CHANGES RESULTS -- the coloring fixes the Gauss-Seidel sweep order -- so False reproduces the pre-incremental behaviour rather than merely running slower. |
| `set_inv_inertia` | set_inv_inertia(self, inv_inertia: ndarray[dtype=float32, order='C']) -> None  Set the per-particle principal-frame diagonal inverse inertia from an (N, 3) array. |
| `set_inv_mass` | set_inv_mass(self, inv_mass: ndarray[dtype=float32, order='C']) -> None  Set per-particle inverse mass, an (N,) array (0 = fixed body). |
| `set_material_ids` | set_material_ids(self, ids: collections.abc.Sequence[int]) -> None  Per-particle material ids (0..7). Pair (e, mu) values come from set_pair_material; without any set_pair_material call the global material applies everywhere. |
| `set_material_params` | set_material_params(self, restitution_normal: float, restitution_tangent: float = 0.0, friction: float = 0.0) -> None  Set the BODY-BODY normal/tangential restitution and Coulomb friction coefficient. The default friction is ZERO, and add_analytic_wall / add_sdf_wall set the particle-WALL material only -- so a bed more than a few layers deep run with the defaults behaves like a liquid: it transmits full hydrostatic pressure to the container and the position solve squeezes grains through the boundary. That failure is silent and looks like a solver-convergence bug (raising the position iterations and halving dt do not move it). Set a non-zero friction for any deep bed. |
| `set_pair_material` | set_pair_material(self, a: int, b: int, restitution: float, friction: float) -> None  Symmetric pair material (restitution, friction) for material ids (a, b). The first call seeds every pair from the current global material. |
| `set_periodic` | set_periodic(self, x: bool, y: bool, z: bool) -> None  Set periodic boundaries per axis (x, y, z); read back with the `periodic` property (suite/docs/NAMING.md 1.4). |
| `set_positions` | set_positions(self, positions: ndarray[dtype=float32, order='C']) -> None  Set particle positions from an (N, 3) array, or (N, 4) whose column 3 is the INVERSE mass (0 is remapped to 1; use set_inv_mass for a fixed body). N may not exceed `capacity`. This (re)sizes the particle set and RESETS every particle's quaternion, scale, inverse mass, shape id (to 0), velocities and gid -- so every other per-particle setter goes AFTER it. |
| `set_quaternions` | set_quaternions(self, quaternions: ndarray[dtype=float32, order='C']) -> None  Set particle orientation quaternions (x, y, z, w) from an (N, 4) array. |
| `set_restitution_model` | set_restitution_model(self, model: str) -> None  Restitution model of the PGS velocity solve: 'newton' (default; per-substep restitution on the pre-solve approach) or 'poisson' (event-level: each pair banks its kinetic compression impulse and releases e x the bank as a budget-capped separation-velocity target during unloading -- restores the multi-substep-impact rebound per-substep Newton cannot return). |
| `set_scales` | set_scales(self, scales: ndarray[dtype=float32, order='C']) -> None  Set per-particle scales from an (N,) array (the growth target). |
| `set_scales_uniform` | set_scales_uniform(self, scale: float) -> None  Set a single uniform scale for all particles. |
| `set_sdf_shape` | set_sdf_shape(self, grid: ndarray[dtype=float32, shape=(*, *, *), order='F'], origin: collections.abc.Sequence[float], spacing: collections.abc.Sequence[float], shell: ndarray[dtype=float32, order='C'], inv_inertia: collections.abc.Sequence[float], bounding_radius: float) -> None  Import a general particle: `grid` is the body-frame signed distance on an (nx, ny, nz) array indexed [x, y, z] (negative inside), sampled at nodes origin + (x, y, z) * spacing; `shell` the (M,3) surface point shell (EMPTY = sample the field's own zero level set); `inv_inertia` the unit-mass principal diagonal inverse inertia; `bounding_radius` the canonical enclosing radius. RESETS the registry to this one shape. See peclet.dem.build_particle for the SDF -> (grid, shell, inertia) helper. |
| `set_shape_ids` | set_shape_ids(self, ids: ndarray[dtype=int32, order='C']) -> None  Per-particle shape index (one int per particle, each < num_shapes). Refreshes each particle's inverse inertia from its new shape. Call it AFTER set_positions: set_positions resets every particle to shape 0 (and sizes the particle set this call is checked against). |
| `set_sleeping` | set_sleeping(self, enabled: bool, threshold_scale: float = 2.0, consecutive: int = 64, wake_scale: float = 40.0, wake_on_lost_contact: bool = False, immovable_frac: float = 0.009999999776482582) -> None  Island sleeping (single-GPU statics, default ON): freeze grounded bodies whose motion stays below threshold_scale x the resting floor for `consecutive` substeps; wake only above wake_scale x that floor (hysteresis vs residual jitter). wake_on_lost_contact additionally wakes a sleeper whose support disappeared; immovable_frac is a sleeper's effective inverse-mass fraction in the solve (0 = exactly immovable). Requires gravity and no external force; inert under MPI. |
| `set_solver_iterations` | set_solver_iterations(self, pos: int, vel: int) -> None  Set the XPBD position- and velocity-solve iteration counts. `vel` defaults to 0 (no velocity solve, hence no restitution). |
| `set_stabilization` | set_stabilization(self, mode: str) -> None  Stabilization pass of the staged velocity solve: 'off' (pure symmetric PGS -- exact ballistic response, but a deep static column mid-collapse cannot be arrested within the iteration budget), 'onesided' (default: held-lower-side grounded impulses -- arrests any collapse but is a momentum sink), 'multilevel' (GraphMG contact-graph aggregation: coarse inelastic solves at super-body masses -- momentum-conserving transport acceleration). |
| `set_thermostat` | set_thermostat(self, temperature: float, tau: float, kB: float = 1.0) -> None  Enable a Berendsen-style velocity thermostat (target temperature, coupling time tau; tau = 0 disables). |
| `set_velocities` | set_velocities(self, velocities: ndarray[dtype=float32, order='C']) -> None  Set particle velocities from an (N, 3) array. |
| `set_verlet_skin` | set_verlet_skin(self, skin_frac: float) -> None  Enable the Verlet-cached impulse broadphase (single-GPU, non-periodic, default OFF, i.e. skin_frac = 0): skip the ArborX rebuild while nothing moved more than skin/2 (skin = skin_frac x max grain radius). |
| `set_wall_material_id` | set_wall_material_id(self, wid: int, mat: int) -> None  Give an SDF wall a material id so particle-wall (e, mu) resolves via the pair table instead of the wall's binary material. |
| `set_wall_transform` | set_wall_transform(self, wall_index: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], quat: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0]) -> None  Place an ANALYTIC wall (add_analytic_wall) rigidly in the world: quat (x,y,z,w) then translation, composed onto the AUTHORED root transform, so calls are absolute and never compound. This moves the GEOMETRY -- a stirrer blade sweeps -- where set_wall_velocity only gives the static surface a velocity field (enough for an axisymmetric drum). Drive both together each step: integrate ang_vel into the quaternion here and pass the same ang_vel to set_wall_velocity. Grid-SDF walls have no tree and are refused. |
| `set_wall_velocity` | set_wall_velocity(self, wall_index: int, lin_vel: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], ang_vel: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], center: collections.abc.Sequence[float] = [0.0, 0.0, 0.0]) -> None  Set a wall's rigid-body surface velocity v(x) = lin_vel + ang_vel × (x − center) (felt by grains in contact even though the geometry is static). Cheap; call every step for a vibrating wall. |
| `sleeping` | Whether island sleeping is enabled. |
| `stabilization` | The stabilization mode: 'off', 'onesided', 'multilevel' (or a diagnostics mode). |
| `step` | step(self, n: int = 1) -> None  Advance `n` XPBD substeps of the time step set by set_dt (raises if set_dt was never called). |
| `step_hertz` | step_hertz(self, substeps: int = 1, skin_frac: float = 0.30000001192092896) -> None  Advance `substeps` explicit soft-sphere Hertz-Mindlin steps of the time step set by set_dt (spheres, SDF walls, non-periodic): viscoelastic Hertz normal force + Mindlin shear-history spring, Coulomb-clamped; (e, mu) from the pair-material tables, stiffness from set_hertz_material. skin_frac is the Verlet pair-list skin as a fraction of the radius. |
| `step_hertz_mpi` | step_hertz_mpi(self, substeps: int = 1, skin_frac: float = 0.30000001192092896) -> None  Advance `substeps` distributed explicit Hertz-Mindlin (force-based) steps of the time step set by set_dt — the MPI counterpart of step_hertz on the init_mpi/enable_mpi_step decomposition. rebalance_every counts CALLS of this method; migration carries the Mindlin history. |
| `step_mpi` | step_mpi(self, n: int = 1) -> None  Advance the distributed (MPI) simulation by `n` steps of the time step set by set_dt, with halo exchange. |
| `verlet_skin` | Broadphase-skin fraction of the max grain radius (0 = rebuild every step). |
| `write_vtp` | write_vtp(self, filename: str) -> None  Write particle state to a VTP file (ParaView/Ovito). |

### `Diagnostics`
Developer tier of a Simulation, reached as `sim.diagnostics`: instruments, ablations and execution-policy switches. Nothing here is needed to set up, run or read out a simulation; the setters that CHANGE RESULTS say so in their docstring.

| Method / property | Description |
|---|---|
| `coloring_conflicts` | coloring_conflicts(self) -> tuple[int, int]  (velocity, position) graph-coloring-invariant violations in the last substep; a valid coloring returns (0, 0). Test hook for the incremental warm-start path. |
| `cuda_graphs` | Whether CUDA-graph replay of the solver loops is enabled. |
| `fused_sweeps` | Fused-sweep policy: 'auto', 'on' or 'off'. |
| `mpi_gathers` | Cumulative ghost gather() count across distributed steps. |
| `mpi_rebuilds` | Cumulative halo topology-rebuild count (Verlet-skin path); with mpi_gathers this is the ghost-reuse ratio. |
| `profiling_info` | profiling_info(self) -> dict  Dict of the particle / broad-phase pair / manifold counts and the last-step max overlap (the same four values the Simulation properties carry). |
| `rest_bank_stats` | rest_bank_stats(self) -> tuple[float, float, int]  Poisson-restitution instrument: (sum, max, n_pairs>0) of the per-pair owed separation impulse committed last substep (physical impulse units). |
| `rest_orphan_stats` | rest_orphan_stats(self) -> tuple[float, float, int]  Poisson-restitution instrument: (sum, max, n_bodies>0) of the per-body orphaned event budget (physical impulse units). |
| `set_cuda_graphs` | set_cuda_graphs(self, enabled: bool) -> None  CUDA-graph replay of the solver's iteration loops (default True): capture collapses each iteration's launch storm into one replay. Results are bit-identical either way; inert on non-CUDA backends and on the distributed step. |
| `set_fused_sweeps` | set_fused_sweeps(self, mode: str) -> None  Fused color sweeps (CUDA): a whole sweep -- and where eligible the whole adaptive iteration loop -- as ONE kernel behind software grid barriers. 'auto' (default) uses them exactly where graph replay is unavailable (the distributed step, or set_cuda_graphs(False)); 'on'/'off' force. Bit-identical results either way. |
| `set_stabilization` | set_stabilization(self, mode: str) -> None  The full stabilization mode set: the three production modes of Simulation.set_stabilization plus the two measurement modes -- 'escalate' (extra symmetric sweeps up to 256; diagnostic/fallback) and 'ordered' (level-ordered symmetric sweeps; known insufficient for deep columns). |
| `set_velocity_solver` | set_velocity_solver(self, name: str) -> None  A/B switch of the single-GPU collision solves: 'gauss_seidel' (default; colored Gauss-Seidel, correct multi-contact dissipation) or 'jacobi' (count-averaged Jacobi, the exact-redundant legacy scheme). CHANGES RESULTS. |
| `velocity_solver` | 'gauss_seidel' or 'jacobi'. |
| `wall_sdf_at` | wall_sdf_at(self, wall_index: int, points: ndarray[dtype=float32, order='C']) -> numpy.ndarray[dtype=float32]  The wall's signed distance at world points: (M,3) in -> (M,) out, POSITIVE in the void where the grains live -- exactly what the narrow phase reads, so it is the honest check of a set_wall_transform placement and the way to draw a stirrer. |

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
export_lammps(filename: str, step: int, pos: ndarray[dtype=float32, order='C'], vel: ndarray[dtype=float32, order='C'], quats: ndarray[dtype=float32, order='C'], radii: ndarray[dtype=float32, order='C'], box_min: collections.abc.Sequence[float] | None = None, box_max: collections.abc.Sequence[float] | None = None, periodic: bool = False) -> None

Module-level LAMMPS dump writer from raw arrays (filename, step, pos, vel, quats, radii, box corners, periodic flag).
```

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

