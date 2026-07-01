# peclet.flow — Eulerian Navier–Stokes solver

The incompressible cut-cell IBM Navier–Stokes solver on a staggered MAC grid. `execution_space` reports the compiled-in Kokkos backend.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.flow`

peclet.flow — the Eulerian incompressible Navier–Stokes solver.

A Kokkos cut-cell Immersed-Boundary-Method solver on a staggered MAC grid (grid-agnostic by design:
Cartesian cut-cell today, able to consume an unstructured Voronoi grid from `peclet.voro`). The
compiled backend (Serial / OpenMP / CUDA / HIP) is chosen at build time — `peclet.flow.execution_space`
reports which one this build has.

* `peclet.flow.Solver` — the staggered MAC solver.
* `peclet.flow.SolverColocated` — the collocated/cell-centered variant.
* `peclet.flow.pnm` — pore-network extraction from SDF pore geometry.

`peclet` is an implicit (PEP 420) namespace shared with the other `peclet-*` packages, so it has no
top-level `__init__.py`.

### `Solver`

| Method / property | Description |
|---|---|
| `bcast_from_root` | bcast_from_root(self, value: object) -> object  Broadcast a value from rank 0 (identity in the single-rank module; mirrors the MPI API). |
| `get_p` | get_p(self) -> numpy.ndarray[dtype=float64]  Return the physical pressure as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_resolution` | get_resolution(self) -> list[int]  Return the grid resolution [nx, ny, nz]. |
| `get_spacing` | get_spacing(self) -> list[float]  Return the grid spacing [dx, dy, dz] (always unit on this grid). |
| `get_u` | get_u(self) -> numpy.ndarray[dtype=float64]  Return the x-velocity component as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_uf` | get_uf(self) -> numpy.ndarray[dtype=float64]  Return the divergence-free FACE x-velocity (collocated: projected MAC field; staggered: == get_u). |
| `get_v` | get_v(self) -> numpy.ndarray[dtype=float64]  Return the y-velocity component as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_vf` | get_vf(self) -> numpy.ndarray[dtype=float64]  Return the divergence-free FACE y-velocity (collocated: projected MAC field; staggered: == get_v). |
| `get_w` | get_w(self) -> numpy.ndarray[dtype=float64]  Return the z-velocity component as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_wf` | get_wf(self) -> numpy.ndarray[dtype=float64]  Return the divergence-free FACE z-velocity (collocated: projected MAC field; staggered: == get_w). |
| `last_outer_iterations` | last_outer_iterations(self) -> int  Return the outer-iteration count from the last step(). |
| `last_pressure_iterations` | last_pressure_iterations(self) -> int  Return the pressure-solver iteration count from the last step(). |
| `max_open_divergence` | max_open_divergence(self) -> float  Return the max cut-cell flux divergence (the incompressibility residual; ~0 when converged). |
| `rank` | rank(self) -> int  MPI rank (always 0 in the single-rank Python module; the multi-rank path is the tests/kokkos_mpi suite). |
| `set_advection` | set_advection(self, on: bool) -> None  Enable/disable explicit high-order momentum advection (default scheme SOU). Off ⇒ Stokes. |
| `set_advection_scheme` | set_advection_scheme(self, scheme: int) -> None  High-order advection scheme: 0 = second-order upwind (SOU, default), 1 = Koren TVD. |
| `set_body_force` | set_body_force(self, fx: float, fy: float, fz: float) -> None  Set the body force per unit volume (fx, fy, fz) — e.g. a mean pressure gradient. |
| `set_domain_bc` | set_domain_bc(self, face: int, type: int, vx: float = 0.0, vy: float = 0.0, vz: float = 0.0) -> None  Set a per-face domain BC (face 0..5 = -x,+x,-y,+y,-z,+z; type 0 periodic/1 wall/2 inflow/3 outflow). |
| `set_domain_bc_profile` | set_domain_bc_profile(self, face: int, profile: ndarray[dtype=float64, order='C']) -> None  Prescribe a per-position inlet velocity profile (Nb,Nc,3) over a face (sets it to inflow). |
| `set_dt` | set_dt(self, dt: float) -> None  Set the time step dt; the momentum solve is scaled by 1/dt (well-conditioned at large dt). |
| `set_implicit_advection` | set_implicit_advection(self, on: bool) -> None  Use implicit-FOU advection with deferred-correction TVD. |
| `set_incremental_pressure` | set_incremental_pressure(self, on: bool) -> None  Toggle the rotational incremental-pressure projection. |
| `set_mu` | set_mu(self, mu: float) -> None  Set dynamic viscosity mu (physical units). |
| `set_outer_iterations` | set_outer_iterations(self, n: int) -> None  Set the number of Picard/outer iterations per step. |
| `set_outer_tolerance` | set_outer_tolerance(self, tol: float) -> None  Set the outer (Picard) convergence tolerance. |
| `set_pressure_chebyshev` | set_pressure_chebyshev(self, on: bool, max_iter: int = 120, rtol: float = 1e-09) -> None  Use the communication-light Chebyshev pressure accelerator (exclusive with PCG). |
| `set_pressure_geometry` | set_pressure_geometry(self, sdf: ndarray[dtype=float64, order='F']) -> None  Set an all-fluid SDF for the cut-cell pressure operator without an immersed solid. |
| `set_pressure_multigrid` | set_pressure_multigrid(self, on: bool, levels: int = 4) -> None  Set the pressure multigrid depth (levels=1 => pure RB-GS, no coarse grid). |
| `set_pressure_pcg` | set_pressure_pcg(self, on: bool, max_iter: int = 200, rtol: float = 1e-08) -> None  Use the MG-PCG pressure accelerator (single-GPU default; exclusive with Chebyshev). |
| `set_pressure_solver_params` | set_pressure_solver_params(self, iters: int) -> None  Set the pressure smoother iteration count. |
| `set_pressure_warmstart` | set_pressure_warmstart(self, on: bool) -> None  Seed each pressure solve from the previous step's phi (default off). |
| `set_rho` | set_rho(self, rho: float) -> None  Set fluid density rho (physical units). Set before geometry/first step. |
| `set_solid` | set_solid(self, sdf: ndarray[dtype=float64, order='F'], cutcell_pressure: bool = False, pressure_coarse: str = 'const') -> None  Set the solid SDF as a Fortran-order (nx,ny,nz) float64 array (negative inside the solid, positive in fluid); optionally enable the cut-cell pressure operator. |
| `set_state` | set_state(self, u: ndarray[dtype=float64, order='F'], v: ndarray[dtype=float64, order='F'], w: ndarray[dtype=float64, order='F']) -> None  Upload an initial velocity field (u,v,w each a Fortran-order (nx,ny,nz) float64 array). |
| `set_velocity_multigrid` | set_velocity_multigrid(self, on: bool, levels: int = 4, vcycles: int = 8) -> None  Enable velocity (momentum) multigrid for the implicit diffusion solve. |
| `set_velocity_solver_params` | set_velocity_solver_params(self, iters: int) -> None  Set the velocity (diffusion) smoother iteration count. |
| `set_velocity_streams` | set_velocity_streams(self, on: bool) -> None  Toggle overlapped per-component velocity solves. |
| `size` | size(self) -> int  MPI size (1 in the single-rank Python module). |
| `step` | step(self) -> None  Advance the solver one time step (semi-implicit: diffusion + projection). |

### `SolverColocated`

| Method / property | Description |
|---|---|
| `bcast_from_root` | bcast_from_root(self, value: object) -> object  Broadcast a value from rank 0 (identity in the single-rank module; mirrors the MPI API). |
| `get_p` | get_p(self) -> numpy.ndarray[dtype=float64]  Return the physical pressure as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_resolution` | get_resolution(self) -> list[int]  Return the grid resolution [nx, ny, nz]. |
| `get_spacing` | get_spacing(self) -> list[float]  Return the grid spacing [dx, dy, dz] (always unit on this grid). |
| `get_u` | get_u(self) -> numpy.ndarray[dtype=float64]  Return the x-velocity component as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_uf` | get_uf(self) -> numpy.ndarray[dtype=float64]  Return the divergence-free FACE x-velocity (collocated: projected MAC field; staggered: == get_u). |
| `get_v` | get_v(self) -> numpy.ndarray[dtype=float64]  Return the y-velocity component as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_vf` | get_vf(self) -> numpy.ndarray[dtype=float64]  Return the divergence-free FACE y-velocity (collocated: projected MAC field; staggered: == get_v). |
| `get_w` | get_w(self) -> numpy.ndarray[dtype=float64]  Return the z-velocity component as a Fortran-order (nx,ny,nz) float64 array (index [x,y,z]). |
| `get_wf` | get_wf(self) -> numpy.ndarray[dtype=float64]  Return the divergence-free FACE z-velocity (collocated: projected MAC field; staggered: == get_w). |
| `last_outer_iterations` | last_outer_iterations(self) -> int  Return the outer-iteration count from the last step(). |
| `last_pressure_iterations` | last_pressure_iterations(self) -> int  Return the pressure-solver iteration count from the last step(). |
| `max_open_divergence` | max_open_divergence(self) -> float  Return the max cut-cell flux divergence (the incompressibility residual; ~0 when converged). |
| `rank` | rank(self) -> int  MPI rank (always 0 in the single-rank Python module; the multi-rank path is the tests/kokkos_mpi suite). |
| `set_advection` | set_advection(self, on: bool) -> None  Enable/disable explicit high-order momentum advection (default scheme SOU). Off ⇒ Stokes. |
| `set_advection_scheme` | set_advection_scheme(self, scheme: int) -> None  High-order advection scheme: 0 = second-order upwind (SOU, default), 1 = Koren TVD. |
| `set_body_force` | set_body_force(self, fx: float, fy: float, fz: float) -> None  Set the body force per unit volume (fx, fy, fz) — e.g. a mean pressure gradient. |
| `set_domain_bc` | set_domain_bc(self, face: int, type: int, vx: float = 0.0, vy: float = 0.0, vz: float = 0.0) -> None  Set a per-face domain BC (face 0..5 = -x,+x,-y,+y,-z,+z; type 0 periodic/1 wall/2 inflow/3 outflow). |
| `set_domain_bc_profile` | set_domain_bc_profile(self, face: int, profile: ndarray[dtype=float64, order='C']) -> None  Prescribe a per-position inlet velocity profile (Nb,Nc,3) over a face (sets it to inflow). |
| `set_dt` | set_dt(self, dt: float) -> None  Set the time step dt; the momentum solve is scaled by 1/dt (well-conditioned at large dt). |
| `set_implicit_advection` | set_implicit_advection(self, on: bool) -> None  Use implicit-FOU advection with deferred-correction TVD. |
| `set_incremental_pressure` | set_incremental_pressure(self, on: bool) -> None  Toggle the rotational incremental-pressure projection. |
| `set_mu` | set_mu(self, mu: float) -> None  Set dynamic viscosity mu (physical units). |
| `set_outer_iterations` | set_outer_iterations(self, n: int) -> None  Set the number of Picard/outer iterations per step. |
| `set_outer_tolerance` | set_outer_tolerance(self, tol: float) -> None  Set the outer (Picard) convergence tolerance. |
| `set_pressure_chebyshev` | set_pressure_chebyshev(self, on: bool, max_iter: int = 120, rtol: float = 1e-09) -> None  Use the communication-light Chebyshev pressure accelerator (exclusive with PCG). |
| `set_pressure_geometry` | set_pressure_geometry(self, sdf: ndarray[dtype=float64, order='F']) -> None  Set an all-fluid SDF for the cut-cell pressure operator without an immersed solid. |
| `set_pressure_multigrid` | set_pressure_multigrid(self, on: bool, levels: int = 4) -> None  Set the pressure multigrid depth (levels=1 => pure RB-GS, no coarse grid). |
| `set_pressure_pcg` | set_pressure_pcg(self, on: bool, max_iter: int = 200, rtol: float = 1e-08) -> None  Use the MG-PCG pressure accelerator (single-GPU default; exclusive with Chebyshev). |
| `set_pressure_solver_params` | set_pressure_solver_params(self, iters: int) -> None  Set the pressure smoother iteration count. |
| `set_pressure_warmstart` | set_pressure_warmstart(self, on: bool) -> None  Seed each pressure solve from the previous step's phi (default off). |
| `set_rho` | set_rho(self, rho: float) -> None  Set fluid density rho (physical units). Set before geometry/first step. |
| `set_solid` | set_solid(self, sdf: ndarray[dtype=float64, order='F'], cutcell_pressure: bool = False, pressure_coarse: str = 'const') -> None  Set the solid SDF as a Fortran-order (nx,ny,nz) float64 array (negative inside the solid, positive in fluid); optionally enable the cut-cell pressure operator. |
| `set_state` | set_state(self, u: ndarray[dtype=float64, order='F'], v: ndarray[dtype=float64, order='F'], w: ndarray[dtype=float64, order='F']) -> None  Upload an initial velocity field (u,v,w each a Fortran-order (nx,ny,nz) float64 array). |
| `set_velocity_multigrid` | set_velocity_multigrid(self, on: bool, levels: int = 4, vcycles: int = 8) -> None  Enable velocity (momentum) multigrid for the implicit diffusion solve. |
| `set_velocity_solver_params` | set_velocity_solver_params(self, iters: int) -> None  Set the velocity (diffusion) smoother iteration count. |
| `set_velocity_streams` | set_velocity_streams(self, on: bool) -> None  Toggle overlapped per-component velocity solves. |
| `size` | size(self) -> int  MPI size (1 in the single-rank Python module). |
| `step` | step(self) -> None  Advance the solver one time step (semi-implicit: diffusion + projection). |

## `peclet.flow.pnm`

peclet.flow.pnm — pore-network extraction from SDF pore geometry.

`SDFReader`, `extract_pores`, `segment_volume`, `extract_topology_gpu` — the "pnm_from_sdf"
feature, distinct from the CFD solve in `peclet.flow`.

### `SDFReader`

| Method / property | Description |
|---|---|
| `read_vti` | read_vti(arg: str, /) -> tuple  Reads VTI; returns (sdf_3d[nz,ny,nx], origin_zyx, spacing_zyx) |

### `Pore`

| Method / property | Description |
|---|---|
| `radius` | (self) -> float |
| `x` | (self) -> float |
| `y` | (self) -> float |
| `z` | (self) -> float |

