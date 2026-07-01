# Python API

The suite is driven from Python — everything lives under the single **`peclet`** namespace, installable
from PyPI (`pip install peclet` for the CPU family, or an individual `pip install peclet-<name>`).

| Package | Import | What you get |
|---|---|---|
| [**peclet.flow**](flow.md) | `import peclet.flow` | `Solver` / `SolverColocated` — the Eulerian Navier–Stokes solver; `peclet.flow.pnm` pore extraction |
| [**peclet.dem**](dem.md) | `import peclet.dem` | `Simulation` — Lagrangian DEM/XPBD packing |
| [**peclet.voro**](voro.md) | `import peclet.voro` | `Tessellation`, `Simulation` — moving-cell Voronoi + dynamics |
| [**peclet.core**](core.md) | `from peclet.core import mpi, amr` | particle halo (MPI) + Kokkos AMR octree |
| [**peclet.morton**](morton.md) | `import peclet.morton` | vectorised Morton/Z-order arithmetic |

Every Kokkos-backed module exposes `execution_space` (`OpenMP` / `Cuda` / `HIP` / `Serial`) so you can
confirm which build you imported. The pages here are generated from the modules' own docstrings; the full
**C++** API is on each code's Doxygen site (linked from the home page).

!!! tip "GPU & multi-rank"
    The wheels on PyPI are the multicore-CPU (OpenMP) build. For GPU (CUDA/HIP) or multi-rank MPI, build
    the package from source against a Kokkos prefix, or use a container — see [Install & run](../DEPLOYMENT.md).

## Distributed (MPI) API

Built with the MPI flags on (`PECLET_FLOW_MPI` / `PECLET_DEM_MPI` / `PECLET_VORO_MPI` — all on in the
[containers](../containers.md)), the compute modules gain a multi-rank surface driven from `mpi4py`.
These methods aren't in the auto-generated tables above (that snapshot is the single-rank CPU wheel):

| Module | Distributed entry points |
|---|---|
| `peclet.flow` | `Solver.init_mpi(gnx,gny,gnz)`, `peclet.flow.mpi_block(gnx,gny,gnz) → (origin, size)`, real `Solver.rank()/size()`, `peclet.flow.has_mpi` |
| `peclet.dem` | `Simulation.init_mpi(...)`, `enable_mpi_step(...)`, `step_mpi(nsteps)`, `rebalance()`, `rank()`, `num_ghost()` |
| `peclet.voro` | `VoronoiHalo(origin, size, gsize, periodic)` with `owned_mask`, `gather(...) → (pos, gid, weight, n_owned)`, `refresh_positions`, `rank()/size()` |
| `peclet.core` | `peclet.core.mpi.Migrator` / `Halo` (the shared particle halo the above build on) |

A distributed driver `import mpi4py` (which calls `MPI_Init`), then decomposes and steps. See the
worked example [`benchmarks/profile_mpi_flow.py`](https://github.com/computational-chemical-engineering/peclet/tree/main/benchmarks)
and the launch recipes in [Containers → Distributed MPI](../containers.md).
