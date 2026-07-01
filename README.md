# peclet

A suite of codes for **simulation of transport phenomena** — Eulerian (CFD/Navier–Stokes), Lagrangian
(DEM/particle packing) and mixed (Voronoi) methods — sharing one MPI **block domain decomposition**
with efficient **asynchronous ghost-layer exchange**, **SDF**-described solids, a common **immersed
boundary** methodology, **GPU** support, and **Python bindings**.

The name nods to the [Péclet number](https://en.wikipedia.org/wiki/P%C3%A9clet_number) — the ratio of
advective to diffusive transport, the dimensionless heart of transport phenomena.

📖 **Documentation site:** <https://computational-chemical-engineering.github.io/peclet/> — the suite's front
door (design docs + install/deployment guide + links to each code's Doxygen API). Built from `docs/`
via MkDocs ([mkdocs.yml](mkdocs.yml)).

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
| `core/` | **Shared infrastructure** (header-only C++20 + MPI, optional Kokkos): ORB block decomposition, async grid ghost-layer exchange + Lagrangian particle migration/ghosts, SDF geometry, VTI I/O. Every method depends on it. |
| `flow/` | Eulerian **Kokkos** incompressible Navier–Stokes (porous media; staggered MAC grid + cut-cell IBM). Complete, validated, MPI-optional distributed solver on `core`; `pnm` is its pore-network-extraction module. |
| `dem/` | Lagrangian **Kokkos + ArborX** DEM/XPBD particle packing. Full XPBD step with a validated distributed `step_mpi` (core particle halo). |
| `voro/` | Mixed Lagrangian/Eulerian dynamic 3D Voronoi tessellation (header-only C++17; periodic & Lees–Edwards). |
| `morton/` | Morton/Z-order spatial-index primitive — arithmetic directly in Morton space (header-only C++17 + BMI2/AVX-512, Python). |

Both GPU codes are **Kokkos**-based; the same source runs on CUDA, HIP (AMD/LUMI), and OpenMP backends,
chosen by the bootstrapped install prefix (`tools/bootstrap_deps.sh`). The reusable parts of the original
`block_decomposer` prototype were extracted into `core/`.

## Shared design docs

`docs/` is the cross-code contract every method follows:
[ARCHITECTURE](docs/ARCHITECTURE.md) · [CONVENTIONS](docs/CONVENTIONS.md) · [STYLE](docs/STYLE.md) ·
[INTERFACES](docs/INTERFACES.md) · [ROADMAP](docs/ROADMAP.md) ·
[PORTABILITY](docs/PORTABILITY.md). See `CLAUDE.md` for an agent-facing overview.

## Install & run (Python)

Everything ships under one **`peclet` namespace** — installable parts of one family:

| PyPI package | Import | Role |
|---|---|---|
| `peclet-morton` | `peclet.morton` | Morton/Z-order spatial index |
| `peclet-flow` | `peclet.flow` (+ `.pnm`) | Eulerian incompressible Navier–Stokes solver |
| `peclet-dem` | `peclet.dem` | Lagrangian DEM/XPBD particle packing |
| `peclet-voro` | `peclet.voro` | Dynamic Voronoi tessellation + mesh generator |
| `peclet-core` | `peclet.core` (`.mpi`, `.amr`) | Shared infra (particle halo, AMR) — sdist only |
| `peclet` | — | metapackage: `pip install peclet` pulls the CPU family |

**Multicore CPU (OpenMP):** the compute packages ship **self-contained wheels** — `pip install peclet`
(or an individual `pip install peclet-flow`) just works and runs multi-threaded (`OMP_NUM_THREADS`).

**GPU (CUDA/HIP) and multi-rank MPI:** a portable binary wheel is impossible (arch × CUDA/ROCm × MPI-ABI),
so you build the packages from source against a Kokkos prefix, or use a container. Because the backend
(Serial / OpenMP / CUDA / HIP) is compiled in, you build for your hardware —
[**docs/DEPLOYMENT.md**](docs/DEPLOYMENT.md) is the guide: the backend×MPI matrix, `pip install` recipes
per environment, and **Apptainer containers** for Snellius (CUDA) and LUMI (HIP) in [`containers/`](containers).

## Continuous integration & docs

Each submodule carries its own `.github/workflows/`: a **CI** workflow (build + test where feasible —
`core` and `morton` run full CPU/MPI suites; `flow` and `dem` build the Kokkos OpenMP host
backend) and a **Documentation** workflow that builds the Doxygen API docs and publishes them to that
repo's GitHub Pages. Enabling Pages once per repo (Settings → Pages → "Source: GitHub Actions") is the
only manual step.

## Note on submodule pins

This umbrella pins each submodule to a compatible commit on `main`. Update to the latest upstream with
`git submodule update --remote` followed by a commit here that bumps the pointers.
