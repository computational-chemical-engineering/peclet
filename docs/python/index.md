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
