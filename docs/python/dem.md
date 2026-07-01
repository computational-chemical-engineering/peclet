# peclet.dem — Lagrangian DEM/XPBD packing

XPBD discrete-element packing with SDF point-shell collision. The distributed (MPI) methods are present only in an MPI-enabled build.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.dem`

peclet.dem — Lagrangian Discrete Element Method (XPBD) particle packing.

A Kokkos + ArborX XPBD solver with SDF point-shell collision for dense particle packing. The compiled
backend (Serial / OpenMP / CUDA / HIP) is chosen at build time — `peclet.dem.execution_space` reports
which one this build has. The distributed (MPI) step is exposed only in an MPI-enabled build
(`pip install . --config-settings=cmake.define.PECLET_DEM_MPI=ON`).

* `peclet.dem.Simulation` — the packing simulation (initialize_shape, set_positions, step, ...).

`peclet` is an implicit (PEP 420) namespace shared with the other `peclet-*` packages, so it has no
top-level `__init__.py`.

### `Simulation`

| Method / property | Description |
|---|---|
| `add_plane` | add_plane(self, arg0: float, arg1: float, arg2: float, arg3: float, arg4: float, arg5: float, /) -> None add_plane(self, point: tuple[float, float, float], normal: tuple[float, float, float]) -> None  Overloaded function.  1. `add_plane(self, arg0: float, arg1: float, arg2: float, arg3: float, arg4: float, arg5: float, /) -> None`  Add a boundary wall plane (px,py,pz, nx,ny,nz).  2. `add_plane(self, point: tuple[float, float, float], normal: tuple[float, float, float]) -> None`  Add a boundary wall plane from a point and a normal (3-sequences). |
| `compute_overlaps` | compute_overlaps(self) -> float  Recompute particle overlaps. |
| `enable_periodicity` | enable_periodicity(self, x: bool, y: bool, z: bool) -> None  Enable periodic boundaries per axis (x, y, z). |
| `export_lammps` | export_lammps(self, filename: str, step: int) -> None  Export particle state to a LAMMPS dump file. |
| `export_sdf` | export_sdf(self, filename: str, resolution: tuple[int, int, int]) -> None  Reconstruct and write the packed-bed SDF on a (rx,ry,rz) grid to a VTI file. |
| `get_angular_velocities` | get_angular_velocities(self) -> numpy.ndarray[dtype=float32] |
| `get_domain_max` | get_domain_max(self) -> tuple[float, float, float]  Return the domain maximum corner (x, y, z). |
| `get_domain_min` | get_domain_min(self) -> tuple[float, float, float]  Return the domain minimum corner (x, y, z). |
| `get_growth_factor` | get_growth_factor(self) -> float  Return the current particle growth factor. |
| `get_growth_rate` | get_growth_rate(self) -> float  Return the particle growth rate. |
| `get_inv_inertia` | get_inv_inertia(self) -> numpy.ndarray[dtype=float32] |
| `get_masses` | get_masses(self) -> numpy.ndarray[dtype=float32] |
| `get_max_overlap` | get_max_overlap(self) -> float |
| `get_num_contacts` | get_num_contacts(self) -> int |
| `get_num_manifolds` | get_num_manifolds(self) -> int |
| `get_positions` | get_positions(self) -> numpy.ndarray[dtype=float32]  Return particle positions as an (N,3) numpy array. |
| `get_positions_view` | get_positions_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of positions (NumPy view on host, DLPack/CuPy on GPU). |
| `get_profiling_info` | get_profiling_info(self) -> dict  Return a dict of particle/contact/manifold counts and the max overlap. |
| `get_quaternions` | get_quaternions(self) -> numpy.ndarray[dtype=float32]  Return particle orientation quaternions as an (N,4) numpy array. |
| `get_scales` | get_scales(self) -> numpy.ndarray[dtype=float32]  Return per-particle scales as a numpy array. |
| `get_sdf_grid` | get_sdf_grid(self, resolution: tuple[int, int, int]) -> numpy.ndarray[dtype=float32]  Reconstruct a packed-bed SDF on a (rx,ry,rz) grid (the get_sdf_grid pipeline for CFD). |
| `get_velocities` | get_velocities(self) -> numpy.ndarray[dtype=float32]  Return particle velocities as an (N,3) numpy array. |
| `get_velocities_view` | get_velocities_view(self) -> numpy.ndarray[dtype=float32]  Zero-copy (N,3) device array of velocities (NumPy view on host, DLPack/CuPy on GPU). |
| `initialize` | initialize(self, shape_type: int, radius: float = 0.5, height: float = 2.0, thickness: float = 0.0) -> None  CUDA-API alias for initialize_shape. |
| `initialize_shape` | initialize_shape(self, shape_type: int, radius: float, height: float = 0.0, thickness: float = 0.0) -> None  Select the particle shape (sphere/cylinder/ring/...) and its dimensions. |
| `max_overlap` | max_overlap(self) -> float  Return the maximum particle-particle overlap. |
| `num_contacts` | num_contacts(self) -> int  Return the number of broad-phase contacts. |
| `num_manifolds` | num_manifolds(self) -> int  Return the number of contact manifolds. |
| `num_particles` | num_particles(self) -> int  Return the number of particles. |
| `set_angular_velocities` | set_angular_velocities(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle angular velocities from an (N,3) array. |
| `set_domain` | set_domain(self, lx: float, ly: float, lz: float, px: bool = True, py: bool = True, pz: bool = False) -> None set_domain(self, min: tuple[float, float, float], max: tuple[float, float, float]) -> None  Overloaded function.  1. `set_domain(self, lx: float, ly: float, lz: float, px: bool = True, py: bool = True, pz: bool = False) -> None`  Set the box size (lx,ly,lz) and per-axis periodicity.  2. `set_domain(self, min: tuple[float, float, float], max: tuple[float, float, float]) -> None`  Set the domain by (min, max) corner tuples (arbitrary origin); keeps current periodicity. |
| `set_dt` | set_dt(self, arg: float, /) -> None  Set the time step dt. |
| `set_global_scale` | set_global_scale(self, arg: float, /) -> None  Set a global length scale applied to all particles. |
| `set_gravity` | set_gravity(self, arg0: float, arg1: float, arg2: float, /) -> None  Set the gravitational acceleration vector (gx, gy, gz). |
| `set_growth_params` | set_growth_params(self, rate: float, new_factor: float = -1.0) -> None  Set the particle growth rate and target size factor. |
| `set_inv_inertia` | set_inv_inertia(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set per-particle inverse inertia from an (N,3) array. |
| `set_inv_mass` | set_inv_mass(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set per-particle inverse mass (0 => fixed/immovable). |
| `set_material_params` | set_material_params(self, restitution_normal: float, restitution_tangent: float = 0.0, friction: float = 0.0) -> None  Set normal/tangential restitution and the Coulomb friction coefficient. |
| `set_positions` | set_positions(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle positions from an (N,3) array, or (N,4) where column 3 is inverse mass. |
| `set_quaternions` | set_quaternions(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle orientation quaternions from an (N,4) array. |
| `set_scales` | set_scales(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set per-particle scales from an array. |
| `set_scales_uniform` | set_scales_uniform(self, arg: float, /) -> None  Set a single uniform scale for all particles. |
| `set_solver_iterations` | set_solver_iterations(self, pos: int, vel: int) -> None  Set the XPBD position- and velocity-solve iteration counts. |
| `set_sphere_shape` | set_sphere_shape(self, radius: float) -> None  Use a uniform sphere of the given radius for all particles. |
| `set_thermostat` | set_thermostat(self, temperature: float, tau: float, kB: float = 1.0) -> None  Enable a Berendsen-style velocity thermostat (target temperature, coupling time tau). |
| `set_velocities` | set_velocities(self, arg: ndarray[dtype=float32, order='C'], /) -> None  Set particle velocities from an (N,3) array. |
| `step` | step(self, dt: float = 0.0) -> None  Advance the simulation one step (dt=0 uses the configured time step). |
| `write_vtp` | write_vtp(self, filename: str) -> None  Write particle state to a VTP file (ParaView/Ovito). |

