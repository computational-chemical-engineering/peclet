# Deployment & environments

How to get the suite's Python packages running on a laptop, a multicore CPU node, an NVIDIA GPU
(workstation or Snellius), or an AMD GPU (LUMI) — and how the single "different environments" question
actually decomposes. Runnable, validated examples for every route are on the
**[examples gallery](https://computational-chemical-engineering.github.io/peclet-examples/)**.

## The mental model

There are **two orthogonal choices**, both made at *build* time, not at run time:

1. **Compute backend** — *where the kernels run.* The compute codes (`flow`, `pnm`, `dem`, `voro`,
   `coupling`, `core.amr`) are [Kokkos](https://kokkos.org); the backend (Serial / OpenMP / CUDA / HIP)
   is **compiled in**. You do not pick it at runtime; you install the wheel flavour, build, or pull the
   container that matches your hardware.
2. **MPI** — *how many processes.* Orthogonal to the backend: any backend can run single-process or
   multi-process. It is a build option per code (`PECLET_FLOW_MPI`, `PECLET_PNM_MPI`, `PECLET_DEM_MPI`,
   `PECLET_VORO_MPI`; `coupling` follows `flow` + `dem`) that adds the distributed API
   (`init_mpi`, `mpi_block`, `step_mpi`, `VoronoiHalo`, …) to the same Python module. `has_mpi` on a
   module tells you whether the build you imported carries it.

So "1 MPI process / multicore / GPU" is really **backend × MPI**:

| You want | Backend | MPI | How you get it |
|----------|---------|-----|----------------|
| 1 process, multicore CPU | OpenMP (`OMP_NUM_THREADS`) | off | `pip install peclet` (PyPI wheels) |
| 1 process, 1 NVIDIA GPU | CUDA | off | `pip install peclet-cu13` (PyPI wheels) |
| many processes, CPU | OpenMP/Serial | on | source build against `extern/install/host-openmp`, or the `peclet-cpu` container |
| many GPUs (NVIDIA) | CUDA | on | source build against `extern/install/nvidia-cuda` (Snellius: `tools/hpc/install_snellius.sh`), or the `peclet-cuda` container |
| AMD GPU (LUMI) | HIP | off/on | source build against `extern/install/lumi-hip`, or the `peclet-hip` container (untested on hardware) |

**Why not PyPI wheels for everything?** A wheel cannot carry an MPI ABI, and a GPU wheel is pinned to a
toolkit generation. So the split is:

- **Multicore CPU (OpenMP):** `peclet-morton`, `peclet-flow`, `peclet-pnm`, `peclet-dem`, `peclet-voro` ship
  **self-contained PyPI wheels** — the compute ones vendor-build Kokkos (OpenMP + Serial) inside the wheel,
  so `pip install peclet` (the CPU-family metapackage) or any individual `pip install peclet-flow` runs
  multi-threaded with no prefix. `peclet-morton` is pure CPU with runtime ISA dispatch.
- **Single-GPU CUDA:** `pip install peclet-cu13` — the CUDA twin of the metapackage, pulling
  `peclet-flow-cu13`, `peclet-pnm-cu13`, `peclet-dem-cu13`, `peclet-voro-cu13` (+ `peclet-morton`). Each
  module embeds a static Kokkos-CUDA build with native machine code for Turing (sm_75), Ampere (sm_80),
  Hopper (sm_90) and Blackwell (sm_100, sm_120) plus Turing PTX for anything newer, built with the
  oldest CUDA 13 toolkit so the PTX JIT-compiles on any 13.x driver (a driver cannot JIT PTX newer than
  itself, and under minor-version compatibility such a launch silently does nothing — Kokkos then
  aborts at import with "likely mismatch of architecture"; if you ever see that, update the driver or
  build from source against the local toolkit: `CMAKE_PREFIX_PATH=<nvidia-cuda prefix> pip install .`)
  and gets `libcudart` from the `nvidia-cuda-runtime` dependency wheel via its rpath; only the NVIDIA
  driver (CUDA ≥ 13 capable) must be on the host — no system CUDA toolkit. The `-cu13` packages install
  the **same `peclet.*` imports** as the CPU ones and are therefore **mutually exclusive with `peclet`**
  in one environment (the CuPy `cupy` vs `cupy-cuda12x` model): one venv per backend. Single-rank only.
- **Source-only packages:** `peclet-core` (MPI particle halo, AMR octree, `core.geom` scene authoring)
  and `peclet-coupling` (CFD-DEM) are published as **sdists** — `pip install peclet[mpi]` /
  `pip install peclet[cfd-dem]` builds them against your MPI and Kokkos prefix.
- **AMD/HIP or multi-rank MPI:** **build from source** (`pip install` against a Kokkos prefix) or use a
  **container** — both routes below.

## One-time dependency bootstrap (source builds)

The compute codes need a Kokkos (+ ArborX for dem) install. Build it **once per backend** into a local
prefix — the local stand-in for a cluster `module load`:

```bash
tools/bootstrap_deps.sh host-openmp     # CPU (OpenMP + Serial)
tools/bootstrap_deps.sh nvidia-cuda     # NVIDIA GPU  (put nvcc on PATH)
tools/bootstrap_deps.sh lumi-hip        # AMD GPU
```

GPU arch defaults to the local dev box; override per target:

```bash
KOKKOS_ARCH=AMPERE80 CUDA_ARCH=80 tools/bootstrap_deps.sh nvidia-cuda   # Snellius A100
KOKKOS_ARCH=HOPPER90 CUDA_ARCH=90 tools/bootstrap_deps.sh nvidia-cuda   # Snellius H100
#                                       LUMI MI250X = gfx90a (the lumi-hip default)
```

The pinned versions (Kokkos, ArborX) live in `cmake/SuiteKokkos.cmake` / `cmake/SuiteArborX.cmake` — see
[Portability](PORTABILITY.md).

## Installing the Python packages

```bash
# CPU / multicore — the easy path: portable wheels straight from PyPI, no prefix:
pip install peclet                 # peclet-morton + peclet-flow + peclet-pnm + peclet-dem + peclet-voro
pip install peclet[cfd-dem]        # + peclet-coupling (builds from sdist; needs a Kokkos prefix on CMAKE_PREFIX_PATH)
pip install peclet[mpi]            # + peclet-core (builds from sdist; needs MPI)
pip install peclet-flow            # or any one on its own

# Single NVIDIA GPU — CUDA wheels straight from PyPI (needs only the driver; NOT alongside `peclet`):
pip install peclet-cu13            # peclet-morton + peclet-{flow,pnm,dem,voro}-cu13 (+ nvidia-cuda-runtime)
pip install peclet-flow-cu13       # or any one on its own

# From a source checkout against a bootstrapped prefix (dev, GPU + MPI, or to add MPI to a CPU build).
# CMake reads CMAKE_PREFIX_PATH from the environment; the backend is whatever that prefix targets:
PREFIX=$PWD/extern/install/host-openmp             # or nvidia-cuda (put nvcc on PATH) / lumi-hip
CMAKE_PREFIX_PATH=$PREFIX pip install ./core ./morton
CMAKE_PREFIX_PATH=$PREFIX pip install --config-settings=cmake.define.PECLET_FLOW_MPI=ON ./flow
CMAKE_PREFIX_PATH=$PREFIX pip install --config-settings=cmake.define.PECLET_PNM_MPI=ON  ./pnm
CMAKE_PREFIX_PATH=$PREFIX pip install --config-settings=cmake.define.PECLET_DEM_MPI=ON  ./dem
CMAKE_PREFIX_PATH=$PREFIX pip install --config-settings=cmake.define.PECLET_VORO_MPI=ON ./voro
CMAKE_PREFIX_PATH=$PREFIX pip install ./coupling   # after flow + dem
```

The dist names are `peclet-core` (repo `core`), `peclet-morton` (`morton`), `peclet-flow` (`flow`),
`peclet-pnm` (`pnm`), `peclet-dem` (`dem`), `peclet-voro` (`voro`), `peclet-coupling` (`coupling`); a
source `pip install ./<repo>` builds the matching one. Install in dependency order (core and morton
first, coupling last).

`pip install` builds the same CMake targets the developer build does; the install rule is gated on
`SKBUILD`, so a plain `cmake --build build` is unchanged. Use a virtualenv/conda env per backend if you
need more than one on the same machine.

On **Snellius** the release procedure installs the whole family from a tag with
`tools/hpc/install_snellius.sh <tag> h100|a100|cpu` (venv + site-specific wheelhouse, `PECLET_*_MPI=ON`)
and certifies it with `tools/hpc/smoke_snellius.slurm`; the toolchain and the traps are in
[Snellius](SNELLIUS.md). The LUMI counterpart (`tools/hpc/install_lumi.sh`, [LUMI](LUMI.md)) is written
but has not run on the machine yet.

### Running

```bash
# multicore, one process:
OMP_NUM_THREADS=16 python my_run.py

# distributed: one process per rank (flow / pnm / dem / voro / coupling built with the MPI flag)
mpirun -np 4 python my_distributed_run.py

# GPU: just import — the device backend is compiled in
python -c "import peclet.flow as f; print(f.execution_space, f.has_mpi)"   # -> Cuda True / OpenMP False / ...
```

`execution_space` (exposed by every Kokkos module) reports the compiled-in backend and `has_mpi` whether
the distributed API is present — the quickest way to confirm you imported the build you meant to.

## Containers (Snellius, LUMI, other HPC)

> **See the [Containers page](containers.md)** for pulling the pre-built GHCR images and full run recipes. This section is the short version.

For HPC, prefer **Apptainer** (both Snellius and LUMI use it; Docker is barred on compute nodes). The
[`containers/`](https://github.com/computational-chemical-engineering/peclet/tree/main/containers)
directory has definition files that bake the toolchain + Kokkos prefix and pip-install the whole family
with the MPI flags on; CI builds them on every release tag and publishes them to GHCR:

- `containers/cpu.def`  — OpenMP + OpenMPI (laptops, CI, CPU partitions) → `peclet-cpu`
- `containers/cuda.def` — CUDA, Snellius A100 (`sm_80`) and H100 (`sm_90`) → `peclet-cuda:*-sm80` / `-sm90`
- `containers/hip.def`  — HIP, LUMI MI250X (`gfx90a`) → `peclet-hip:*-gfx90a` (builds; not yet run on AMD hardware)

```bash
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:sm90    # moving tag = newest release
srun apptainer exec --nv peclet-cuda_sm90.sif python3 my_run.py                     # Snellius, one GPU
# LUMI: Cray-MPICH is injected at runtime by the launcher wrapper —
module load LUMI partition/G cray-mpich rocm
srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip_gfx90a.sif my_run.py
```

For LUMI the container is built against vanilla MPICH and the host **Cray-MPICH** + Slingshot stack is
bound over it at runtime (`containers/lumi-run.sh`) — the MPICH-ABI hybrid model. See
[`containers/README.md`](https://github.com/computational-chemical-engineering/peclet/blob/main/containers/README.md)
for MPI-ABI, GPU-aware-MPI, and arch details.

## Python API surface (what `import` gives you)

| Package | Import | Key API |
|---------|--------|---------|
| `peclet-flow` | `import peclet.flow` | `Solver(nx,ny,nz)` / `SolverColocated` — set_rho/mu/dt, set_solid, set_domain_bc, scalars, VoF, scenes, step, get_u/v/w/p; MPI: `init_mpi`, `mpi_block`, `rebalance_by_weights` |
| `peclet-pnm` | `import peclet.pnm` | `SDFReader`, `extract_pores`, `segment_volume`, `extract_topology`, `extract_pore_network`, network flow from a DNS; MPI: `mpi_block`, `extract_pore_network_mpi` |
| `peclet-dem` | `import peclet.dem` | `Simulation(capacity)` — initialize_shape, set_domain, set_material_params, set_positions, SDF walls, scene particles, step / step_hertz, get_positions, get_sdf_grid; MPI: `init_mpi`, `enable_mpi_step`, `step_mpi`, `step_hertz_mpi`, `rebalance` |
| `peclet-voro` | `import peclet.voro` | `Tessellation`, `Simulation` (moving-cell Voronoi + dynamics), `FlowSolver` (Navier–Stokes on the Voronoi mesh); MPI: `VoronoiHalo` |
| `peclet-coupling` | `import peclet.coupling` | `CfdDem` (unresolved, volume-averaged) and `ResolvedCfdDem` (cut-cell) two-way coupling drivers over `flow` + `dem` |
| `peclet-core` | `from peclet.core import mpi, amr, geom` | MPI particle halo (`mpi.Migrator`, `mpi.Halo`), Kokkos AMR octree (`amr.Flow`, `amr.DistributedOctree`), analytic-SDF scene authoring (`geom.SceneBuilder`) |
| `peclet-morton` | `from peclet.morton import encode, decode, shift, box_zorder` | vectorised NumPy Morton ops |

Every binding method carries a docstring (`help(peclet.flow.Solver.step)`); the
[Python API reference](python/index.md) is generated from them, and the full C++ API is published as
Doxygen on each repo's GitHub Pages.

## Status / caveats

- **Verified routes:** the CPU wheels (every gallery page runs from `pip install peclet`), the CUDA wheels
  (`peclet-cu13`, single GPU), source builds with MPI on the OpenMP and CUDA backends (the `tests/kokkos_mpi`
  suites of every code, np = 1, 2, 4, bit-exact to single-rank where claimed), the `peclet-cpu` and
  `peclet-cuda` containers, and the Snellius site install.
- **HIP / LUMI** is the one untested route: the code builds for HIP (the `peclet-hip` image is produced in
  CI) but has not run on an AMD GPU — see [LUMI](LUMI.md).
- Multi-node container runs depend on the site's MPI bind model (OpenMPI/UCX on Snellius, Cray-MPICH on
  LUMI); the wrappers under `containers/` encode it, and the OpenMPI series must match the image's.
- Cluster module names and CUDA/ROCm versions drift; the recipes pin the *suite* dependencies (Kokkos,
  ArborX) and leave the site toolchain to `module load` / the container base image.
