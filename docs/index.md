# peclet

**A suite of GPU-accelerated and parallel codes for the simulation of transport phenomena** —
Eulerian (CFD / Navier–Stokes), Lagrangian (DEM / particle packing) and mixed (Voronoi) methods,
sharing one MPI **block domain decomposition** with asynchronous **ghost-layer exchange**,
**SDF**-described solids, a common **immersed-boundary** methodology, **GPU** support (Kokkos:
CUDA / HIP / OpenMP), and **Python bindings**.

The name nods to the [Péclet number](https://en.wikipedia.org/wiki/P%C3%A9clet_number) — the ratio of
advective to diffusive transport, the dimensionless heart of transport phenomena.

This site is the front door to the suite: the cross-cutting **design contract**, the **install &
deployment** guide, and links to each code's **API reference** (Doxygen).

## The codes

| Code | Role | Stack |
|------|------|-------|
| [**core**](https://github.com/computational-chemical-engineering/core) | Shared infrastructure: ORB block decomposition, async grid/particle halo, SDF geometry, VTI I/O | header-only C++20 + MPI (optional Kokkos) |
| [**flow**](https://github.com/computational-chemical-engineering/flow) | Incompressible Navier–Stokes for porous media (staggered MAC + cut-cell IBM + multigrid); `pnm` pore extraction | Kokkos + nanobind |
| [**dem**](https://github.com/computational-chemical-engineering/dem) | Discrete Element Method (XPBD) + SDF point-shell collision for dense packing | Kokkos + ArborX + nanobind |
| [**voro**](https://github.com/computational-chemical-engineering/voro) | Dynamic 3D Voronoi tessellation of moving particles (periodic & Lees–Edwards) | header-only C++17 |
| [**morton**](https://github.com/computational-chemical-engineering/morton) | Morton/Z-order codes with arithmetic *in Morton space* — the spatial-index primitive | header-only C++17 + BMI2/AVX-512 + Python |

Both GPU codes are **Kokkos**-based (CUDA retired); the same source runs on CUDA, HIP (AMD/LUMI) and
OpenMP, selected at build time. See [CUDA retirement](CUDA_RETIREMENT.md).

## Start here

- **[Install & run](DEPLOYMENT.md)** — the backend × MPI matrix, `pip install` recipes per environment
  (CPU / Snellius CUDA / LUMI HIP), and Apptainer containers for HPC.
- **[Architecture](ARCHITECTURE.md)** — layering, dependency graph, and how each code maps onto the core.
- **[Conventions](CONVENTIONS.md)** — SDF sign, x-fastest indexing, types, precision, periodic/Lees–Edwards.
- **[Interfaces](INTERFACES.md)** — the shared C++20 concepts (`Domain`, `Field`, `HaloExchange`, …).
- **[Roadmap](ROADMAP.md)** — the phased plan.

## API reference (Doxygen)

Each code publishes its full C++/Python API as Doxygen on its own GitHub Pages site:

- [core API](https://cautious-barnacle-7p9p71w.pages.github.io/)
- [morton API](https://congenial-chainsaw-g414wov.pages.github.io/)
- [flow API](https://miniature-adventure-y7jzg8e.pages.github.io/)
- [dem API](https://expert-chainsaw-6qjq213.pages.github.io/)
