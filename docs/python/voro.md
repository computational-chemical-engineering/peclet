# peclet.voro — dynamic Voronoi tessellation

Moving-cell Voronoi tessellation + moving-cell dynamics, and an unstructured-mesh generator that can feed `peclet.flow`.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.voro`

peclet.voro — dynamic 3D Voronoi tessellation of moving particles.

A device-native (Kokkos) moving-cell Voronoi engine: periodic & Lees–Edwards boxes, incremental cell
repair, and compressible Euler / Navier–Stokes / multiphase dynamics on the moving cells. Also serves as
an unstructured-mesh generator that can feed an Eulerian solve in `peclet.flow`. The compiled
backend (Serial / OpenMP / CUDA / HIP) is chosen at build time — `peclet.voro.execution_space` reports
which one this build has.

* `peclet.voro.Tessellation`, `peclet.voro.Simulation`.

`peclet` is an implicit (PEP 420) namespace shared with the other `peclet-*` packages, so it has no
top-level `__init__.py`.

### `Tessellation`
Moving-particle Voronoi tessellator on the device path.

Build a tessellation once (`build`) then advance it cheaply as the points move
(`step`) — the incremental two-pass repair is several times faster than rebuilding
for the small per-step displacements typical of CFD/DEM, and falls back to a full
rebuild (via an adaptive gate) when displacements are large, so it is never much
slower than a cold build. Periodic cubic box. Single domain (one process).

| Method / property | Description |
|---|---|
| `build` | build(self, positions: ndarray[dtype=float64, order='C']) -> None  Cold-build the Voronoi tessellation of `positions` (N,3) from scratch and make it resident. Sets the particle count N for subsequent `step` calls. |
| `neighbor_counts` | neighbor_counts(self) -> numpy.ndarray[dtype=int32]  Per-particle Voronoi neighbour count (N,) int32 — the number of faces of each cell. |
| `num_particles` | Particle count N set by the last `build`. |
| `set_box` | set_box(self, L: collections.abc.Sequence[float]) -> None  Set the periodic box edge lengths (Lx, Ly, Lz). Call before `build`. |
| `set_gate` | set_gate(self, on: bool = True) -> None  Enable the adaptive gate (default True) that routes high-churn steps straight to a full rebuild — the 'never much slower than a cold build' guard. |
| `set_local_certificate` | set_local_certificate(self, on: bool = True) -> None  Use the cheap O(nt) Lawson local certificate (default True) instead of the brute O(nt*np) form for detecting which cells changed. Both are complete; local is faster. |
| `set_tolerance` | set_tolerance(self, frac: float = 0.0001) -> None  Certificate tolerance as a fraction of the mean inter-particle spacing (default 1e-4). A vertex poking past a stored plane by more than this flags the cell for repair; smaller is stricter (closer to machine-exact) at marginally higher cost. |
| `step` | step(self, positions: ndarray[dtype=float64, order='C']) -> dict  Incrementally repair the resident tessellation to new `positions` (N,3, same N as `build`). Returns a dict of per-step work stats: 'flagged' (cells the certificate flagged), 'pass1' and 'pass2' (cells re-gathered in each pass), 'extra' (cells gathered across verify extra-passes), 'surgical' (Pass-1 cells repaired surgically), 'verify_passes' (verify iterations run), 'rebuilt' (True if the gate routed this step to a full rebuild), 'fell_back' (True if the verify failed and a cold rebuild was forced). |
| `volumes` | volumes(self) -> numpy.ndarray[dtype=float64]  Per-particle Voronoi cell volume (N,) float64. Sums to the box volume (space-filling). |

### `Simulation`
Device-native compressible-Euler / Navier-Stokes Voronoi fluid simulation.

Velocity-Verlet dynamics of a moving-particle Voronoi fluid: pressure forces from an
EOS plus an optional per-particle viscous (Navier-Stokes) term, with the tessellation
repaired each step on the device. Set the particle state, `init`, then `step`.

| Method / property | Description |
|---|---|
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
| `set_masses` | set_masses(self, masses: ndarray[dtype=float64, order='C']) -> None  Particle masses (N,) float64. |
| `set_positions` | set_positions(self, positions: ndarray[dtype=float64, order='C']) -> None  Initial particle positions (N,3) float64. |
| `set_pressure` | set_pressure(self, pressure: float) -> None  Equation-of-state pressure constant (the stiffness of the barotropic EOS). |
| `set_repair` | set_repair(self, on: bool = True) -> None  Opt-in (default off): use the incremental moving-point repair + reeval-published force geometry each step instead of a full rebuild. Call before init(). |
| `set_velocities` | set_velocities(self, velocities: ndarray[dtype=float64, order='C']) -> None  Initial particle velocities (N,3) float64. |
| `set_viscosities` | set_viscosities(self, viscosities: ndarray[dtype=float64, order='C']) -> None  Per-particle shear viscosity (N,) — enables the viscous Navier-Stokes term. |
| `step` | step(self, num_steps: int, dt: float) -> None  Advance the velocity-Verlet dynamics by `num_steps` steps of size `dt`. |

