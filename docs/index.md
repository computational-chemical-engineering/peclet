# Peclet

[![PyPI version](https://img.shields.io/pypi/v/peclet.svg)](https://pypi.org/project/peclet/)
[![Python versions](https://img.shields.io/pypi/pyversions/peclet.svg)](https://pypi.org/project/peclet/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/computational-chemical-engineering/peclet/blob/main/LICENSE)
[![Docs build](https://github.com/computational-chemical-engineering/peclet/actions/workflows/site.yml/badge.svg)](https://github.com/computational-chemical-engineering/peclet/actions/workflows/site.yml)

**A suite of GPU-accelerated and parallel codes for the simulation of transport phenomena** —
Eulerian (CFD / Navier–Stokes), Lagrangian (DEM / particle packing) and mixed (Voronoi) methods,
sharing one MPI **block domain decomposition** with asynchronous **ghost-layer exchange**,
**SDF**-described solids, a common **immersed-boundary** methodology, **GPU** support (Kokkos:
CUDA / HIP / OpenMP), and **Python bindings** everywhere.

The name nods to the [Péclet number](https://en.wikipedia.org/wiki/P%C3%A9clet_number) — the ratio of
advective to diffusive transport, the dimensionless heart of transport phenomena.

## Quick start (Python)

The codes are driven from **Python** — one `peclet.*` namespace, installable from PyPI. The multicore-CPU
(OpenMP) build ships as a self-contained wheel, so this just works:

```bash
pip install peclet            # the CPU family: peclet-morton + peclet-flow + peclet-dem + peclet-voro
# or an individual package, e.g.  pip install peclet-flow
```

```python
import peclet.flow as flow
s = flow.Solver(32, 32, 32)
s.set_rho(1.0); s.set_mu(0.01); s.set_dt(60.0)
s.set_solid(sdf)                      # SDF geometry (<0 inside solid)
for _ in range(100):
    s.step()
u, p = s.get_u(), s.get_p()           # numpy arrays [x,y,z]
print(flow.execution_space)           # -> OpenMP / Cuda / HIP / Serial
```

→ **[Python API reference](python/index.md)** · **[Install & run](DEPLOYMENT.md)** (GPU / MPI / HPC containers).

## The codes

| Code | PyPI · import | Role |
|------|---------------|------|
| [**core**](https://github.com/computational-chemical-engineering/peclet-core) | `peclet-core` · `peclet.core` | Shared infrastructure: ORB block decomposition, async grid/particle halo, SDF geometry, VTI I/O, AMR octree |
| [**flow**](https://github.com/computational-chemical-engineering/peclet-flow) | `peclet-flow` · `peclet.flow` | Incompressible Navier–Stokes for porous media (staggered MAC + cut-cell IBM + multigrid); `pnm` pore extraction |
| [**dem**](https://github.com/computational-chemical-engineering/peclet-dem) | `peclet-dem` · `peclet.dem` | Discrete Element Method (XPBD) + SDF point-shell collision for dense packing |
| [**voro**](https://github.com/computational-chemical-engineering/peclet-voro) | `peclet-voro` · `peclet.voro` | Dynamic 3D Voronoi tessellation of moving particles (periodic & Lees–Edwards) + mesh generation |
| [**morton**](https://github.com/computational-chemical-engineering/peclet-morton) | `peclet-morton` · `peclet.morton` | Morton/Z-order codes with arithmetic *in Morton space* — the spatial-index primitive |

The GPU codes are **Kokkos**-based: the same source runs on CUDA, HIP (AMD/LUMI) and OpenMP, chosen at
build time by the install prefix (or the container).

## Documentation

- **[Python API reference](python/index.md)** — the classes and methods you call from Python (the primary interface).
- **[Install & run](DEPLOYMENT.md)** — the backend × MPI matrix and `pip install` recipes (CPU / Snellius CUDA / LUMI HIP).
- **[Containers (HPC)](containers.md)** — pull the pre-built Apptainer images from GHCR (or build your own) and run on a laptop, Snellius, or LUMI.
- **[Architecture](ARCHITECTURE.md)** · **[Conventions](CONVENTIONS.md)** · **[Interfaces](INTERFACES.md)** · **[Roadmap](ROADMAP.md)** — the cross-cutting design contract.
- **C++ API (Doxygen)** — the full C++ API per code:
  [core](https://computational-chemical-engineering.github.io/peclet-core/) ·
  [morton](https://computational-chemical-engineering.github.io/peclet-morton/) ·
  [flow](https://computational-chemical-engineering.github.io/peclet-flow/) ·
  [dem](https://computational-chemical-engineering.github.io/peclet-dem/) ·
  [voro](https://computational-chemical-engineering.github.io/peclet-voro/)
