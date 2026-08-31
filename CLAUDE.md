# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`suite/` is the **`peclet`** umbrella repository for GPU-accelerated and parallel scientific computing — particle dynamics, CFD, and the spatial-indexing primitives they build on. It holds **five method/infrastructure projects as git submodules** (`flow`, `dem`, `core`, `voro`, `morton`), each its own self-contained repo with its own `CMakeLists.txt`, build system, and (in some cases) its own `CLAUDE.md`. There is no top-level build or test runner — work happens *inside* a submodule, not at this level.

**Consequence for any task:** `cd` into the relevant submodule before building, testing, or running git. A `git status` / commit / diff issued from `suite/` itself acts on the **umbrella** (submodule pointers + shared `docs/`), not on a method code — so commit code changes inside the submodule first, then bump the pointer in the umbrella.

## Direction of the suite (read before cross-cutting work)

The codes are being given a shared foundation while staying separate method codes: one MPI **block
decomposition** with efficient **asynchronous ghost-layer exchange**, common **SDF** solids and
**IBM**, **GPU** support, and **Python bindings** everywhere. The reusable parts of the old
`block_decomposer` (now **retired/archived**) were extracted into the shared **`core/`**
library (header-only C++20, its own git repo + `CLAUDE.md`) that every method depends on.

**`core/` status:** complete and tested (26 ctests, `mpirun -np 1..8`). Provides ORB block
decomposition; the async grid ghost-layer exchange (`peclet::core::halo::GridHalo` — topology/exchange split,
field-agnostic, NBX + persistent neighborhood-collective engines, overlap-capable, plus a GPU-resident
host-staged variant); the Lagrangian halo (`peclet::core::halo::ParticleMigrator` — particle migration +
`gatherGhosts`); SDF geometry with scalar/vector VTI I/O; and **dynamic load balancing** (weighted ORB
`BlockDecomposer::init(…, weights)` + `DistributedOctree::rebalance` for AMR leaf/field migration and
`rebalanceByParticleCount` for the Lagrangian path). See `core/CLAUDE.md`.

**Consumers:** both GPU codes are now **Kokkos**-based (CUDA retired — see
[docs/CUDA_RETIREMENT.md](docs/CUDA_RETIREMENT.md)). `flow` has a **complete, validated distributed
Navier–Stokes solver** (`flow`) on the core: the whole cut-cell IBM + MG-PCG step runs multi-rank,
bit-exact to single-rank (`tests/kokkos_mpi`, 18 ctests np=1,2,4, gated `PECLET_FLOW_MPI`). `flow` is **THE**
flow solver; pore-network extraction is the separate `pnm/` project (`peclet.pnm`, split out of flow
2026-07). `dem`'s `dem` module runs the
full XPBD step (ArborX broad-phase) with a validated distributed `step_mpi` that drives the SAME
modern solver stack as the single-GPU step (shared `demSolveContacts` driver, processor-block
Gauss–Seidel: rank-local coloring + warm-started PGS with gid-keyed persistent contacts +
statics/stabilization), a distributed **force-based** engine (`step_hertz_mpi` — explicit
Hertz–Mindlin as the first law of the generalized `demStepForce` driver, domain-decomposed MD-style
with gid-keyed Mindlin history; `tests/kokkos_mpi` 24 ctests, host + CUDA) and periodic **load
rebalancing** (`enable_mpi_step(rebalance_every=…)` / `Sim.rebalance()` — SoA ownership migration on
the weighted ORB, both engines' contact ledgers carried). The single-GPU codes are complete +
faster than the retired CUDA at scale; remaining work is at-scale multi-GPU tuning — see
[docs/ROADMAP.md](docs/ROADMAP.md).

The design contract lives in `docs/`:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layering, dependency graph, Lagrangian/Eulerian/mixed taxonomy, how each code maps onto the core.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — SDF sign, x-fastest indexing, types, precision policy, periodic/Lees–Edwards, Python array shapes.
- [docs/STYLE.md](docs/STYLE.md) — C++20 host & Kokkos device (morton pins C++17), clang-format/tidy (from voronoi), namespaces, CMake/CI.
- [docs/INTERFACES.md](docs/INTERFACES.md) — shared C++20 concepts: `Domain`, `Decomposition`, `Field`, `HaloExchange`, `SdfGeometry`, `ImmersedBoundary`, `Stepper`.
- [docs/DECOMPOSITION_AND_MULTIGRID.md](docs/DECOMPOSITION_AND_MULTIGRID.md) — how the MPI decomposition and the pressure multigrid constrain each other: the per-axis coarsening rule, why grid dimensions' factors of two decide solver cost, aligned vs coarse-first partitions, the measured evidence, and the open problems. **Read before touching decomposition, load balancing or MG depth.**
- [docs/ROADMAP.md](docs/ROADMAP.md) — phased plan; the decomposition, async halo engine, and dynamic load balancing (Phase 7) are done — remaining work is at-scale multi-GPU tuning.

## The projects

| Directory | Language / stack | What it does | Has own CLAUDE.md |
|-----------|------------------|--------------|-------------------|
| `core/` | Header-only C++20 + MPI | **Shared infrastructure**: ORB block decomposition + asynchronous ghost-layer exchange (NBX + persistent engines) + particle migration + SDF geometry + dynamic load balancing + AMR octree. The layer every method code depends on. Tested (26 ctests, np 1–8). | **Yes — read it** |
| `morton/` | Header-only C++17 (+ **Kokkos**, Python) | Morton/Z-order codes with **arithmetic in Morton space** (neighbour-find, axis add, Z-order step without decode→re-encode). BMI2/AVX-512 + runtime dispatch; the foundational spatial-index library. Portable **Kokkos** GPU backend (`include/morton/kokkos.hpp`, CUDA/HIP/OpenMP) — raw CUDA retired. | **Yes — read it** |
| `flow/` | **Kokkos** + C++20 + nanobind (`flow`) | Incompressible Navier–Stokes solver for porous media: staggered MAC grid, Immersed Boundary Method over SDF geometry, pressure projection. **CUDA retired** (Kokkos: CUDA/HIP/OpenMP). | **Yes — read it** |
| `pnm/` | **Kokkos** + C++20 + nanobind (`peclet.pnm`) | Pore-network extraction from SDF geometry: pore detection, marker-controlled watershed segmentation, throat topology (`SDFReader`, `extract_pores`, `segment_volume`, `extract_topology_gpu`, fused `extract_pore_network`). **Distributed MPI extraction** on the core ORB (`extract_pore_network_mpi`, gated `PECLET_PNM_MPI`) — bit-exact to single-rank, `tests/kokkos_mpi` ctests np=1,2,4 host+CUDA. Split out of `flow` (2026-07) with its git history. | Yes (brief) |
| `dem/` | **Kokkos + ArborX** + C++20 + nanobind (`dem`) | Discrete Element Method (DEM): XPBD solver + SDF point-shell collision for dense particle packing. Optional MPI. **CUDA retired** (Kokkos: CUDA/HIP/OpenMP). README still calls it `peclet-dem`. | No |
| `voro/` | **Kokkos** + C++17/20 (+ core MPI, nanobind; Voro++ fetched as a benchmark reference) | Dynamic 3D Voronoi tessellation of moving particles; periodic & Lees–Edwards boxes, incremental cell repair, Euler/NS/multiphase dynamics. Kokkos (CUDA/HIP/OpenMP) + core MPI; the legacy half-edge CPU oracle has been **retired**. | No |

Common threads worth knowing when moving between them: SDFs (signed distance fields) are the shared geometry representation across `flow` and `dem`; VTI/VTP files (ParaView/Ovito) are the shared I/O format; periodic boundary conditions appear everywhere; and the GPU codes (`flow`, `dem`, `core`'s device halo) are now **Kokkos**-based — the backend (CUDA/HIP/OpenMP) and arch are chosen by the `extern/install/<backend>` prefix the build is pointed at, not hard-coded in the sources (`tools/bootstrap_deps.sh` + `CMakePresets.json`).

## Per-project quick reference

For `morton` and `flow`, **defer to their own `CLAUDE.md`** — the entries below are only an entry point.

### morton
```bash
cd morton
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
ctest --test-dir build --output-on-failure
./build/tests/morton_tests --test-case="<name>"     # single doctest case
```
The non-BMI2 build is contractually PDEP/PEXT-free (a test greps the binary). AVX-512 batch kernels have no local hardware — validate under Intel SDE (`sde64 -skx -- ./build/tests/morton_tests`). See its CLAUDE.md for the runtime-dispatch and wheel-build subtleties.

Both `flow` and `dem` now build via `find_package(Kokkos)` (+`ArborX` for packing) against the
bootstrapped prefix `extern/install/<backend>` (built once by `tools/bootstrap_deps.sh` — a **hard build
dependency**). Put `nvcc` on `PATH` for the CUDA backend (`export PATH=/usr/local/cuda-13.2/bin:$PATH`).

### flow
```bash
cd flow && source ../.venv/bin/activate       # THE suite venv (see "One venv" below); nanobind
                                              # is found via the active interpreter (SuiteNanobind)
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j                          # -> build/peclet/flow/_flow.*.so (the solver)
# (canonical install: CMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda" pip install .)
PYTHONPATH=$PWD/build python scripts/verify_poiseuille_flow.py        # analytical-solution check
PYTHONPATH=$PWD/build python scripts/verify_periodic_spheres_sdflow.py  # cut-cell Stokes through spheres
```

### pnm
```bash
cd pnm && source ../.venv/bin/activate        # same interpreter/nanobind as every other project
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j                          # -> build/peclet/pnm/_pnm.*.so (import peclet.pnm)
PYTHONPATH=$PWD/build python scripts/test_extraction.py ../flow/data/packing_ring.vti
PYTHONPATH=$PWD/build python scripts/verify_segmentation.py ../flow/data/packing_ring.vti
# Distributed extraction (-DPECLET_PNM_MPI=ON): mpi_block + extract_pore_network_mpi, bit-exact
# to single-rank; MPI ctests: cmake -S tests/kokkos_mpi -B build_kmpi -DMPIEXEC_EXECUTABLE=/usr/bin/mpirun ...
```

### dem
```bash
cd dem && source ../.venv/bin/activate        # the suite venv already has nanobind + numpy
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j$(nproc)                  # -> build/dem.cpython-*.so  (-DPECLET_DEM_MPI=ON for the MPI step)
export PYTHONPATH=$PYTHONPATH:$(pwd)/build
python verify_packing_spheres.py                # verify_*.py are the test/demo entry points
```
The many root-level `verify_*.py` / `test_*.py` / `plan_*.md` / `build_log*.txt` files are this project's working scratch — verification scripts and design notes, not a packaged test suite.

### voro
```bash
cd voro && source ../.venv/bin/activate
# The tests live in tests/kokkos and are registered ONLY by the Kokkos build — a plain
# `cmake -B build` configures zero tests ("No tests were found!!!"), which is not a failure signal.
cmake -B build_dev -DPECLET_VORO_KOKKOS=ON -DPECLET_VORO_BUILD_PYTHON=ON \
  -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"   # add -DPECLET_VORO_MPI=ON for the distributed path
cmake --build build_dev --parallel        # -> build_dev/peclet/voro/_voro.*.so (import peclet.voro)
OMP_PROC_BIND=false ctest --test-dir build_dev --output-on-failure    # 11 tests
CLANG_FORMAT_BIN=clang-format-18 bash tools/clang_format_check.sh     # what CI runs (see below)
```
`tools/clang_format_check.sh` is the canonical format command — it walks `include/` and `tests/`
itself, so don't hand-roll globs (the older `include/voro/**` path has not existed since the
`vorflow` → `voro` rename). Google style, but **informational, not enforced**: the CI job is named
"clang-format (informational)" and the tree currently carries ~570 pre-existing violations
(`repair.hpp`, `sdf.hpp`, `tessellator.hpp` + test files), mostly unicode-in-comment lines. Keep
*new* code clean; a repo-wide reformat is a separate deliberate change.
The legacy half-edge `voronoi.hpp` CPU oracle is **gone** — retired in voro `0d4f3b8`
("retire the legacy half-edge engine + rewrite the docs (device-only)"); `include/` now holds only
`peclet/voro/`. Voro++ survives solely as a FetchContent throughput reference for `bench_convexcell`.
The production device tessellator stores each Voronoi cell as a compact **dual-triangle ConvexCell**
(a vertex is a triple of plane indices) plus a `facetGeometry` CSR — not the old half-edge mesh
(see README).

### One venv for the whole suite

There is **one** development virtualenv, `suite/.venv` (gitignored), and every project uses it:

```bash
source /path/to/suite/.venv/bin/activate    # or ../.venv from inside a submodule
```

It carries nanobind, numpy/scipy/numba/h5py/pandas, matplotlib/pyvista/scikit-image, mpi4py,
cupy-cuda12x, scikit-build-core/hatchling/build, pytest, clang-format and the Jupyter stack — the
union of what the per-project venvs held.

**Why one.** `coupling` composes `flow` + `dem` in a single interpreter by design, and `pnm` already
borrowed flow's venv, so a shared interpreter was the de-facto requirement. The per-project venvs had
also drifted (three nanobind copies; numpy 2.3.5 vs 2.5.0; scipy 1.16.3 vs 1.17.0), and nanobind's
version wants to be consistent across extensions that interoperate.

**Do not `mv` or rename a venv.** A venv bakes absolute paths into `bin/activate*` and every console
script. The retired per-project venvs had been moved repeatedly (`~/Codes/dem-gpu` →
`suite/packing-gpu` → `suite/dem`, and `~/Codes/pnm_from_sdf` → `suite/cfd-gpu` → `suite/flow`), which
left `activate` exporting a dead `VIRTUAL_ENV` and prepending a non-existent `PATH` entry. The failure
is SILENT and nasty: `python` disappears, while `python3` and `pip` fall through to `/usr/bin` — so
everything after `activate` runs against system Python and a `pip install` targets the system
interpreter. If the suite directory ever moves, delete `.venv` and recreate it.

**Local dev imports** come from the build tree, not an install: `PYTHONPATH=<build-dir>`. The
`coupling` module additionally needs its three pure-Python files staged beside the extension
(`cp coupling/python/peclet_coupling/{__init__,driver,resolved}.py <build>/peclet/coupling/`), because the
importable package is `peclet.coupling` — the `python/peclet_coupling/` directory is only the source
location that the wheel install maps into place.

## Conventions across the suite

- **The `nvidia-cuda` prefix carries an OpenMP HOST backend since 2026-08-30**
  (`OPENMP;SERIAL;CUDA`; `core/docs/amr_setup_parallel_plan.md` D1′): host-side Kokkos
  `parallel_for`/`parallel_scan` (the AMR setup builders) run multithreaded. Consequences:
  **bound the pool** — `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` for test batteries (an unbounded
  pool on a 48-core host is a measured hour-long trap), and thread-count-pinned probes (e.g.
  `.sdf-campaign-probes/flow_probe.py` at 4 threads) must keep their pinned counts. Binaries
  built before the switch statically link the old Kokkos and are unaffected until rebuilt —
  but do NOT compose old- and new-prefix modules in one Python process (e.g. `coupling`
  importing flow + dem) until both are rebuilt against the same prefix.

- **Kokkos C++ projects** (`flow`, `dem`) put device kernels in header-only `.hpp` (compiled as C++; the Kokkos launch compiler routes them through `nvcc`/`hipcc` — never `.cu`) and expose the simulation as an importable Python module via a nanobind binding TU (built with scikit-build-core, on core's zero-copy View↔ndarray bridge); drive simulations from Python, not C++ mains.
- **Header-only C++ projects** (`morton`, `voro`, `core`) put the real logic in templates under `include/`; there is no library to link.
- Build artifacts (`build/`, `build_*/`, `.venv/`, `*.so`, `__pycache__/`) and large output assets (`*.vti`, `*.vtp`, `*.png`) are committed/present in several projects — don't treat their existence as something you created, and prefer the project's own out-of-source `build/` directory.
- Two projects carry `AGENTS.md`/`GEMINI.md` alongside `CLAUDE.md` (flow); when editing guidance, the CLAUDE.md is the one that governs Claude Code.
