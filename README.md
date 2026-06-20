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
| `transport-core/` | **Shared infrastructure** (header-only C++20 + MPI, optional Kokkos): ORB block decomposition, async grid ghost-layer exchange + Lagrangian particle migration/ghosts, SDF geometry, VTI I/O. Every method depends on it. |
| `sdflow/` | Eulerian **Kokkos** incompressible Navier–Stokes (porous media; staggered MAC grid + cut-cell IBM). Complete, validated, MPI-optional distributed solver on `transport-core`; `pnm` is its pore-network-extraction module. |
| `dem/` | Lagrangian **Kokkos + ArborX** DEM/XPBD particle packing. Full XPBD step with a validated distributed `step_mpi` (transport-core particle halo). |
| `vorflow/` | Mixed Lagrangian/Eulerian dynamic 3D Voronoi tessellation (header-only C++17; periodic & Lees–Edwards). |
| `morton/` | Morton/Z-order spatial-index primitive — arithmetic directly in Morton space (header-only C++17 + BMI2/AVX-512, Python). |

Both GPU codes are now **Kokkos**-based (CUDA retired — see [docs/CUDA_RETIREMENT.md](docs/CUDA_RETIREMENT.md));
the same source runs on CUDA, HIP (AMD/LUMI), and OpenMP backends, chosen by the bootstrapped install
prefix (`tools/bootstrap_deps.sh`). The original `block_decomposer` prototype has been **retired**; its
reusable parts were extracted into `transport-core/`.

## Shared design docs

`docs/` is the cross-code contract every method follows:
[ARCHITECTURE](docs/ARCHITECTURE.md) · [CONVENTIONS](docs/CONVENTIONS.md) · [STYLE](docs/STYLE.md) ·
[INTERFACES](docs/INTERFACES.md) · [ROADMAP](docs/ROADMAP.md) · [CUDA_RETIREMENT](docs/CUDA_RETIREMENT.md) ·
[PORTABILITY](docs/PORTABILITY.md). See `CLAUDE.md` for an agent-facing overview.

## Install & run (Python)

The method codes expose Python APIs (`import sdflow`, `import dem`, `from mortonarith import encode`).
Because the GPU backend (Serial / OpenMP / CUDA / HIP) is compiled in, you build for your hardware —
[**docs/DEPLOYMENT.md**](docs/DEPLOYMENT.md) is the guide: the backend×MPI matrix, `pip install` recipes
per environment, and **Apptainer containers** for Snellius (CUDA) and LUMI (HIP) in [`containers/`](containers).

## Continuous integration & docs

Each submodule carries its own `.github/workflows/`: a **CI** workflow (build + test where feasible —
`transport-core` and `morton` run full CPU/MPI suites; `sdflow` and `dem` build the Kokkos OpenMP host
backend) and a **Documentation** workflow that builds the Doxygen API docs and publishes them to that
repo's GitHub Pages. Enabling Pages once per repo (Settings → Pages → "Source: GitHub Actions") is the
only manual step.

## Note on submodule pins

This umbrella pins each submodule to a compatible commit on `main`. Update to the latest upstream with
`git submodule update --remote` followed by a commit here that bumps the pointers.
