# Python API

The suite is driven from Python — everything lives under the single **`peclet`** namespace, installable
from PyPI (`pip install peclet` for the CPU family, `pip install peclet-cu13` for the CUDA family, or an
individual `pip install peclet-<name>`). Worked, runnable examples for every module are on the
**[examples gallery](https://computational-chemical-engineering.github.io/peclet-examples/)**.

| Package | Import | What you get |
|---|---|---|
| [**peclet.flow**](flow.md) | `import peclet.flow` | `Solver` / `SolverColocated` — the Eulerian Navier–Stokes solver (cut-cell IBM, VoF two-phase, moving analytic scenes, scalars, CFD-DEM hooks) |
| [**peclet.pnm**](pnm.md) | `import peclet.pnm` | Pore-network extraction + per-throat flow rates / pore pressures from a flow DNS |
| [**peclet.dem**](dem.md) | `import peclet.dem` | `Simulation` — Lagrangian DEM (XPBD and Hertz–Mindlin), SDF-shaped particles, analytic walls |
| [**peclet.voro**](voro.md) | `import peclet.voro` | `Tessellation`, `Simulation`, `FlowSolver` — moving-cell Voronoi, dynamics, Navier–Stokes on a Voronoi mesh |
| [**peclet.coupling**](coupling.md) | `import peclet.coupling` | `CfdDem` / `ResolvedCfdDem` — two-way CFD-DEM over `flow` + `dem` |
| [**peclet.core**](core.md) | `from peclet.core import mpi, amr, geom` | particle halo (MPI), Kokkos AMR octree, analytic-SDF scene authoring (`SceneBuilder`) |
| [**peclet.morton**](morton.md) | `import peclet.morton` | vectorised Morton/Z-order arithmetic |

Every Kokkos-backed module exposes `execution_space` (`OpenMP` / `Cuda` / `HIP` / `Serial`) so you can
confirm which build you imported, and `finalize()` for a deterministic teardown (also run at interpreter
exit). The pages here are generated from the modules' own docstrings by `tools/gen_python_api.py` at each
release, from an MPI-enabled build, so the distributed entry points are included; the full **C++** API is
on each code's Doxygen site (linked from the home page).

!!! tip "GPU & multi-rank"
    `pip install peclet` gives the multicore-CPU (OpenMP) build and `pip install peclet-cu13` the
    single-GPU CUDA build. For AMD/HIP or multi-rank MPI, build the packages from source against a
    Kokkos prefix, or use a container — see [Install & run](../DEPLOYMENT.md).

## Distributed (MPI) API

Built with the MPI flags on (`PECLET_FLOW_MPI` / `PECLET_PNM_MPI` / `PECLET_DEM_MPI` / `PECLET_VORO_MPI`
— all on in the [containers](../containers.md) and the Snellius site install), the compute modules gain a
multi-rank surface driven from `mpi4py`. `peclet.flow.has_mpi` reports whether the build you imported
carries it (the PyPI wheels do not):

| Module | Distributed entry points |
|---|---|
| `peclet.flow` | `Solver.init_mpi(gnx,gny,gnz)`, `peclet.flow.mpi_block(gnx,gny,gnz) → (origin, size)`, `Solver.rebalance_by_weights(...)`, real `Solver.rank()/size()`, `exchange_field` / `exchange_field_add` across ranks |
| `peclet.pnm` | `peclet.pnm.mpi_block(...)`, `extract_pore_network_mpi(...)`, `extract_network_flow_mpi(...)` (bit-exact to the single-rank extraction), `mpi_rank()/mpi_size()` |
| `peclet.dem` | `Simulation.init_mpi(...)`, `enable_mpi_step(...)`, `step_mpi(nsteps)`, `step_hertz_mpi(nsteps)`, `rebalance()`, `rank()`, `num_ghost()` |
| `peclet.voro` | `VoronoiHalo(origin, size, gsize, periodic)` with `owned_mask`, `gather(...) → (pos, gid, weight, n_owned)`, `refresh_positions`, `rank()/size()` |
| `peclet.coupling` | the drivers run distributed when their `flow` and `dem` are (the deposition uses `exchange_field_add`) |
| `peclet.core` | `peclet.core.mpi.Migrator` / `Halo` (the shared particle halo the above build on); `peclet.core.amr.DistributedOctree` |

A distributed driver `import mpi4py` (which calls `MPI_Init`), then decomposes and steps. See the
worked example [`benchmarks/profile_mpi_flow.py`](https://github.com/computational-chemical-engineering/peclet/tree/main/benchmarks),
the launch recipes in [Containers → Distributed MPI](../containers.md), and the scaling studies on the
[gallery's benchmarks section](https://computational-chemical-engineering.github.io/peclet-examples/benchmarks/).
