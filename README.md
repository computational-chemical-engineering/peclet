# peclet

A suite of codes for **simulation of transport phenomena** — Eulerian (CFD/Navier–Stokes), Lagrangian
(DEM/particle packing) and mixed (Voronoi) methods — sharing one MPI **block domain decomposition**
with efficient **asynchronous ghost-layer exchange**, **SDF**-described solids, a common **immersed
boundary** methodology, **GPU** support, and **Python bindings**.

The name nods to the [Péclet number](https://en.wikipedia.org/wiki/P%C3%A9clet_number) — the ratio of
advective to diffusive transport, the dimensionless heart of transport phenomena.

This is an **umbrella repository**: each code is a git **submodule** (its own repo and history); this
repo pins compatible commits and holds the shared design docs.

## Clone

```bash
git clone --recursive git@github.com:computational-chemical-engineering/peclet.git
# or, after a plain clone:
git submodule update --init --recursive
```

## Layout

| Submodule | Role |
|-----------|------|
| `transport-core/` | **Shared infrastructure** (header-only C++20 + CUDA): block decomposition, async grid halo + Lagrangian particle migration/ghosts, SDF geometry, VTI I/O. Every method depends on it. |
| `cfd-gpu/` | Eulerian CUDA Navier–Stokes (porous media; MAC grid + IBM). Has a complete distributed NS solver on `transport-core` (branch `mpi-halo-integration`). |
| `packing-gpu/` | Lagrangian CUDA DEM/XPBD particle packing. MPI migration + ghost primitives validated (branch `mpi-integration`). |
| `voronoi_dynamics/` | Mixed Lagrangian/Eulerian dynamic Voronoi tessellation (header-only). |
| `morton_arithmetic/` | Morton/Z-order spatial-index primitive (arithmetic in Morton space). |
| `block_decomposer/` | Original MPI block-decomposition prototype (superseded by `transport-core`; kept for reference). |

## Shared design docs

`docs/` is the cross-code contract every method follows:
[ARCHITECTURE](docs/ARCHITECTURE.md) · [CONVENTIONS](docs/CONVENTIONS.md) · [STYLE](docs/STYLE.md) ·
[INTERFACES](docs/INTERFACES.md) · [ROADMAP](docs/ROADMAP.md). See `CLAUDE.md` for an agent-facing
overview, and `cfd-gpu/doc/mpi_parallelization_status.md` / `packing-gpu/mpi/README.md` for the MPI
integration status.

## Note on submodule pins

`cfd-gpu` and `packing-gpu` are currently pinned to **feature-branch** commits (`mpi-halo-integration`,
`mpi-integration`) carrying the in-progress MPI work; re-pin to `main` after those PRs merge with
`git submodule update --remote` + a commit here.
