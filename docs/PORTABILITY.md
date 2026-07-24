# Portability (Kokkos + ArborX)

Status: **Kokkos is canonical.** flow (`flow`), pnm (`peclet.pnm`, its own project since 2026-07), dem (`dem`), and core all build and run on Kokkos
([ArborX](https://github.com/arborx/ArborX) provides dem's broad-phase). This document is the contract for the suite's portability across NVIDIA
(Snellius) and AMD (LUMI/MI250X) GPUs and covers *how the toolchain is provisioned and built* — the
bootstrapped install prefix (`tools/bootstrap_deps.sh`) is now a **hard build dependency** of every
method code's main build (`cmake -S . -B build -DCMAKE_PREFIX_PATH=extern/install/<backend>;...`).

## Backend matrix

| Target | Where | Kokkos backend | Arch flag | Compiler |
|---|---|---|---|---|
| **NVIDIA (primary dev)** | local RTX 5080, CUDA 13.2 | `Kokkos_ENABLE_CUDA` | `Kokkos_ARCH_BLACKWELL120` (sm_120) | `nvcc` (host gcc 14) |
| **NVIDIA (cluster)** | Snellius A100/H100 | `Kokkos_ENABLE_CUDA` | `Kokkos_ARCH_AMPERE80` / `HOPPER90` | `nvcc` |
| **AMD (LUMI)** | MI250X — *no access yet* | `Kokkos_ENABLE_HIP` | `Kokkos_ARCH_AMD_GFX90A` | `hipcc` |
| **Host / CI** | any CPU | `Kokkos_ENABLE_OPENMP` (+`SERIAL`) | — | gcc/clang |

Development happens on NVIDIA first; the HIP path is kept in lockstep (preset +
CMake plumbing present) so the AMD build is a configuration change, not a port.
A piece of work is considered "ported" only when it passes on **both** a CUDA
build and a host (OpenMP) build; the HIP build is validated once LUMI access exists.

## Pinned versions

- **Kokkos `5.1.1`** — first clean CUDA 13 + Blackwell (`sm_120`) support landed in 5.0.
- **ArborX `v2.1`** — 2.x interface (`attach_indices`, `BoundingVolumeHierarchy::query`);
  requires Kokkos ≥ 4.5, so 5.1.1 satisfies it.

Both are set as cache variables (`SUITE_KOKKOS_VERSION`, `SUITE_ARBORX_VERSION`)
in `cmake/SuiteKokkos.cmake` / `cmake/SuiteArborX.cmake` — bump them in one place.

## Provisioning policy: find_package against a shared prefix

Each repo stays independently buildable (the suite is six sibling repos, not a
superbuild). Kokkos and ArborX are consumed via **`find_package(... CONFIG)`** —
one mechanism that composes correctly, because ArborX itself does
`find_package(Kokkos CONFIG)` and cannot consume an in-tree (FetchContent) Kokkos.
The package is provided by either:

1. a **cluster module** (`module load Kokkos` on Snellius/LUMI), or
2. a **local install prefix** built once by `tools/bootstrap_deps.sh <backend>`,
   which the matching CMake preset puts on `CMAKE_PREFIX_PATH`
   (`extern/install/<backend>`). This is the local-dev stand-in for a module.

The shared helpers `cmake/SuiteKokkos.cmake` / `cmake/SuiteArborX.cmake` expose
`suite_require_kokkos()` / `suite_require_arborx()` (find_package + a clear error
pointing at the bootstrap script). `suite_kokkos_device_sources()` is a documented
no-op: Kokkos 5.x compiles device code through its CXX path (an installed Kokkos
wires up the `kokkos_launch_compiler` / device flags for any target linking
`Kokkos::kokkos`), so **suite device sources are plain `.cpp` compiled as CXX, not
`.cu`** — a key migration convention.

## Building (Phase 0 smoke tests)

The top-level `CMakeLists.txt` is a **toolchain harness only** — it does not build
the method codes; it builds the smoke tests under `tools/` to validate provisioning.

```bash
# One-time: build+install the pinned deps for a backend (the heavy step)
tools/bootstrap_deps.sh nvidia-cuda     # RTX 5080 / CUDA 13.2 (a few minutes)

# Configure + build + run the smoke tests
cmake --preset nvidia-cuda
cmake --build --preset nvidia-cuda -j
./build/nvidia-cuda/tools/kokkos_smoke/kokkos_smoke
./build/nvidia-cuda/tools/arborx_smoke/arborx_smoke

# CPU (portable; no GPU needed) — good for CI and correctness checks
tools/bootstrap_deps.sh host-openmp
cmake --preset host-openmp && cmake --build --preset host-openmp -j

# LUMI / AMD (once access exists; run on a ROCm node)
tools/bootstrap_deps.sh lumi-hip
cmake --preset lumi-hip && cmake --build --preset lumi-hip -j
```

On a cluster, `module load` the deps instead of bootstrapping and drop the
`CMAKE_PREFIX_PATH` from the preset. `build/` and `extern/` are git-ignored.

## GPU-aware MPI (relevant from Phase 1 on)

core's halo exchange will offer two paths: host-staged (portable
fallback) and **GPU-aware MPI** (`Kokkos::View::data()` passed straight to
`MPI_Isend/Irecv`). GPU-aware transport is available on Snellius (OpenMPI+UCX) and
LUMI (cray-mpich); selectable at runtime so non-GPU-aware stacks still work.

## Notes / gotchas

- `tools/bootstrap_deps.sh` hardcodes `/usr/local/cuda/bin/nvcc` for the dev box;
  on a cluster, `module load` Kokkos/ArborX instead of bootstrapping.
- Kokkos 5.x requires **C++20** (the suite was C++20 host / C++17 device; the device
  side moves to C++20 under Kokkos). The presets set `CMAKE_CXX_STANDARD=20`.
- `morton` is already `__host__/__device__` + HIP-guarded and is *not* on
  the packing broad-phase path — it needs no Kokkos work.
- `voro` uses the **OpenMP backend** only for now (its half-edge mesh
  repair stays on the host).
