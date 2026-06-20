# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`suite/` is the **`peclet`** umbrella repository for GPU-accelerated and parallel scientific computing — particle dynamics, CFD, and the spatial-indexing primitives they build on. It holds **five method/infrastructure projects as git submodules** (`sdflow`, `dem`, `transport-core`, `voronoi_dynamics`, `morton`), each its own self-contained repo with its own `CMakeLists.txt`, build system, and (in some cases) its own `CLAUDE.md`. There is no top-level build or test runner — work happens *inside* a submodule, not at this level.

**Consequence for any task:** `cd` into the relevant submodule before building, testing, or running git. A `git status` / commit / diff issued from `suite/` itself acts on the **umbrella** (submodule pointers + shared `docs/`), not on a method code — so commit code changes inside the submodule first, then bump the pointer in the umbrella.

## Direction of the suite (read before cross-cutting work)

The codes are being given a shared foundation while staying separate method codes: one MPI **block
decomposition** with efficient **asynchronous ghost-layer exchange**, common **SDF** solids and
**IBM**, **GPU** support, and **Python bindings** everywhere. The reusable parts of the old
`block_decomposer` (now **retired/archived**) were extracted into the shared **`transport-core/`**
library (header-only C++20, its own git repo + `CLAUDE.md`) that every method depends on.

**`transport-core/` status:** complete and tested (26 ctests, `mpirun -np 1..8`). Provides ORB block
decomposition; the async grid ghost-layer exchange (`tpx::halo::GridHalo` — topology/exchange split,
field-agnostic, NBX + persistent neighborhood-collective engines, overlap-capable, plus a GPU-resident
host-staged variant); the Lagrangian halo (`tpx::halo::ParticleMigrator` — particle migration +
`gatherGhosts`); and SDF geometry with scalar/vector VTI I/O. See `transport-core/CLAUDE.md`.

**Consumers:** both GPU codes are now **Kokkos**-based (CUDA retired — see
[docs/CUDA_RETIREMENT.md](docs/CUDA_RETIREMENT.md)). `sdflow` has a **complete, validated distributed
Navier–Stokes solver** (`sdflow`) on the core: the whole cut-cell IBM + MG-PCG step runs multi-rank,
bit-exact to single-rank (`tests/kokkos_mpi`, 18 ctests np=1,2,4, gated `CFD_MPI`). `sdflow` is **THE**
sdflow solver; `pnm` is its pore-network-extraction module. `dem`'s `dem` module runs the
full XPBD step (ArborX broad-phase) with a validated distributed `step_mpi` (transport-core particle
halo; `tests/kokkos_mpi` 6 ctests). The single-GPU codes are complete + faster than the retired CUDA at
scale; remaining work is at-scale multi-GPU tuning — see [docs/ROADMAP.md](docs/ROADMAP.md).

The design contract lives in `docs/`:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layering, dependency graph, Lagrangian/Eulerian/mixed taxonomy, how each code maps onto the core.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — SDF sign, x-fastest indexing, types, precision policy, periodic/Lees–Edwards, Python array shapes.
- [docs/STYLE.md](docs/STYLE.md) — C++20 host / C++17 device, clang-format/tidy (from voronoi), namespaces, CMake/CI.
- [docs/INTERFACES.md](docs/INTERFACES.md) — shared C++20 concepts: `Domain`, `Decomposition`, `Field`, `HaloExchange`, `SdfGeometry`, `ImmersedBoundary`, `Stepper`.
- [docs/ROADMAP.md](docs/ROADMAP.md) — phased plan; the near-term work is the decomposition + async halo engine.

## The projects

| Directory | Language / stack | What it does | Has own CLAUDE.md |
|-----------|------------------|--------------|-------------------|
| `transport-core/` | Header-only C++20 + MPI | **Shared infrastructure** (new): ORB block decomposition + asynchronous ghost-layer exchange (NBX + persistent engines) + particle migration. The layer every method code will depend on. Tested (13/13, np 1–8). | **Yes — read it** |
| `morton/` | Header-only C++17 (+ CUDA, Python) | Morton/Z-order codes with **arithmetic in Morton space** (neighbour-find, axis add, Z-order step without decode→re-encode). BMI2/AVX-512 + runtime dispatch; the foundational spatial-index library. | **Yes — read it** |
| `sdflow/` | **Kokkos** + C++20 + pybind11 (`sdflow`) | Incompressible Navier–Stokes solver for porous media: staggered MAC grid, Immersed Boundary Method over SDF geometry, pressure projection. `sdflow` is the solver; `pnm` is the pore-network-extraction module. **CUDA retired** (Kokkos: CUDA/HIP/OpenMP). | **Yes — read it** |
| `dem/` | **Kokkos + ArborX** + C++20 + pybind11 (`dem`) | Discrete Element Method (DEM): XPBD solver + SDF point-shell collision for dense particle packing. Optional MPI. **CUDA retired** (Kokkos: CUDA/HIP/OpenMP). README still calls it `dem-gpu`. | No |
| `voronoi_dynamics/` | Header-only C++17 (+ OpenMP, Boost, Voro++) | Dynamic 3D Voronoi tessellation of moving particles; periodic & Lees–Edwards boxes, incremental cell repair, Euler/NS/multiphase dynamics. | No |

Common threads worth knowing when moving between them: SDFs (signed distance fields) are the shared geometry representation across `sdflow` and `dem`; VTI/VTP files (ParaView/Ovito) are the shared I/O format; periodic boundary conditions appear everywhere; and the GPU codes (`sdflow`, `dem`, `transport-core`'s device halo) are now **Kokkos**-based — the backend (CUDA/HIP/OpenMP) and arch are chosen by the `extern/install/<backend>` prefix the build is pointed at, not hard-coded in the sources (`tools/bootstrap_deps.sh` + `CMakePresets.json`).

## Per-project quick reference

For `morton` and `sdflow`, **defer to their own `CLAUDE.md`** — the entries below are only an entry point.

### morton
```bash
cd morton
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
ctest --test-dir build --output-on-failure
./build/tests/morton_tests --test-case="<name>"     # single doctest case
```
The non-BMI2 build is contractually PDEP/PEXT-free (a test greps the binary). AVX-512 batch kernels have no local hardware — validate under Intel SDE (`sde64 -skx -- ./build/tests/morton_tests`). See its CLAUDE.md for the runtime-dispatch and wheel-build subtleties.

Both `sdflow` and `dem` now build via `find_package(Kokkos)` (+`ArborX` for packing) against the
bootstrapped prefix `extern/install/<backend>` (built once by `tools/bootstrap_deps.sh` — a **hard build
dependency**). Put `nvcc` on `PATH` for the CUDA backend (`export PATH=/usr/local/cuda-13.2/bin:$PATH`).

### sdflow
```bash
cd sdflow && source .venv/bin/activate
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda;$(python -m pybind11 --cmakedir)"
cmake --build build -j                          # -> build/sdflow.*.so (solver) + build/pnm.*.so
PYTHONPATH=$PWD/build python scripts/verify_poiseuille_sdflow.py        # analytical-solution check
PYTHONPATH=$PWD/build python scripts/verify_periodic_spheres_sdflow.py  # cut-cell Stokes through spheres
```

### dem
```bash
cd dem && python -m venv .venv && source .venv/bin/activate && pip install pybind11 numpy
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda;$(python -m pybind11 --cmakedir)"
cmake --build build -j$(nproc)                  # -> build/dem.cpython-*.so  (-DDEM_MPI=ON for the MPI step)
export PYTHONPATH=$PYTHONPATH:$(pwd)/build
python verify_packing_spheres.py                # verify_*.py are the test/demo entry points
```
The many root-level `verify_*.py` / `test_*.py` / `plan_*.md` / `build_log*.txt` files are this project's working scratch — verification scripts and design notes, not a packaged test suite.

### voronoi_dynamics
```bash
cd voronoi_dynamics
cmake -B build -DCMAKE_BUILD_TYPE=Release        # FetchContent pulls Voro++ automatically
cmake --build build --parallel
ctest --test-dir build -R "test_static_voronoi|test_voro_comparison" --output-on-failure
clang-format --dry-run --Werror include/voronoi_dynamics/*.hpp tests/*.cpp   # Google style, enforced
```
Header-only: consumers just add `include/`. Voronoi cells are stored as a half-edge mesh with a packed `makeLabel(facet,vertex,edge)` integer encoding (see README "Data structure overview").

## Conventions across the suite

- **Kokkos C++ projects** (`sdflow`, `dem`) put device kernels in header-only `.hpp` (compiled as C++; the Kokkos launch compiler routes them through `nvcc`/`hipcc` — never `.cu`) and expose the simulation as an importable Python module via a pybind11 binding TU; drive simulations from Python, not C++ mains.
- **Header-only C++ projects** (`morton`, `voronoi_dynamics`, `transport-core`) put the real logic in templates under `include/`; there is no library to link.
- Build artifacts (`build/`, `build_*/`, `.venv/`, `*.so`, `__pycache__/`) and large output assets (`*.vti`, `*.vtp`, `*.png`) are committed/present in several projects — don't treat their existence as something you created, and prefer the project's own out-of-source `build/` directory.
- Two projects carry `AGENTS.md`/`GEMINI.md` alongside `CLAUDE.md` (sdflow); when editing guidance, the CLAUDE.md is the one that governs Claude Code.
