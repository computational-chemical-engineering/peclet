# Deployment & environments

How to get the suite's Python packages running on a laptop, a multicore CPU node, an NVIDIA GPU
(Snellius), or an AMD GPU (LUMI) — and how the single "different environments" question actually
decomposes.

## The mental model

There are **two orthogonal choices**, both made at *build* time, not at `pip install`-from-PyPI time:

1. **Compute backend** — *where the kernels run.* The GPU codes (`sdflow`, `dem`) are
   [Kokkos](https://kokkos.org); the backend (Serial / OpenMP / CUDA / HIP) is **compiled in**. You do
   not pick it at runtime; you build (or pull a container) for your hardware.
2. **MPI** — *how many processes.* Orthogonal to the backend: any backend can run single-process or
   multi-process. It is a build option (`DEM_MPI` for dem; the sdflow Python module is single-rank, its
   multi-rank solver lives in the C++ `tests/kokkos_mpi` suite).

So "1 MPI process / multicore / GPU" is really **backend × MPI**:

| You want | Backend | MPI | Prefix (built by `tools/bootstrap_deps.sh`) |
|----------|---------|-----|---------------------------------------------|
| 1 process, 1 core | Serial (in OpenMP build) | off | `extern/install/host-openmp` |
| 1 process, multicore | OpenMP (`OMP_NUM_THREADS`) | off | `extern/install/host-openmp` |
| many processes, CPU | OpenMP/Serial | on | `extern/install/host-openmp` |
| NVIDIA GPU | CUDA | off/on | `extern/install/nvidia-cuda` |
| AMD GPU (LUMI) | HIP | off/on | `extern/install/lumi-hip` |

**Why not just PyPI wheels?** A GPU wheel is pinned to a GPU arch (sm_80 vs sm_90 vs gfx90a), a CUDA/ROCm
version, *and* an MPI ABI. There is no single portable GPU wheel. The realistic models are (a) **build
from source** against your site's toolchain, or (b) **a container** for your hardware. `mortonarith` is
the exception — it is pure CPU with runtime ISA dispatch, so it ships normal PyPI wheels.

## One-time dependency bootstrap

`sdflow` and `dem` need a Kokkos (+ ArborX for dem) install. Build it **once per backend** into a local
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

## Installing the Python packages

Point `pip` at the prefix you bootstrapped (CMake reads `CMAKE_PREFIX_PATH` from the environment); the
backend is whatever that prefix targets:

```bash
# CPU / multicore:
PREFIX=$PWD/extern/install/host-openmp
CMAKE_PREFIX_PATH=$PREFIX pip install ./sdflow
CMAKE_PREFIX_PATH=$PREFIX pip install --config-settings=cmake.define.DEM_MPI=ON ./dem
pip install ./morton          # pure-CPU, no prefix needed

# NVIDIA GPU (Snellius):
PREFIX=$PWD/extern/install/nvidia-cuda
PATH=/usr/local/cuda/bin:$PATH CMAKE_PREFIX_PATH=$PREFIX pip install ./sdflow ./dem
```

`pip install` builds the same CMake targets the developer build does; the install rule is gated on
`SKBUILD`, so a plain `cmake --build build` is unchanged. Use a virtualenv/conda env per backend if you
need more than one on the same machine.

### Running

```bash
# multicore, one process:
OMP_NUM_THREADS=16 python my_run.py

# distributed (dem): one process per rank
mpirun -np 4 python my_distributed_run.py

# GPU: just import — the device backend is compiled in
python -c "import sdflow; print(sdflow.execution_space)"   # -> Cuda / HIP / OpenMP / Serial
```

`execution_space` (exposed by both `sdflow` and `dem`) reports the compiled-in Kokkos backend — the
quickest way to confirm you imported the build you meant to.

## Containers (Snellius, LUMI, other HPC)

For HPC, prefer **Apptainer** (both Snellius and LUMI use it; Docker is barred on compute nodes). The
[`containers/`](https://github.com/computational-chemical-engineering/peclet/tree/main/containers)
directory has definition files that bake the toolchain + Kokkos prefix
and pip-install the packages:

- `containers/cpu.def`  — OpenMP + OpenMPI (laptops, CI, CPU partitions)
- `containers/cuda.def` — CUDA, defaults to Snellius A100 (`sm_80`)
- `containers/hip.def`  — HIP, LUMI MI250X (`gfx90a`)

```bash
git submodule update --init --recursive
apptainer build peclet-cpu.sif containers/cpu.def
srun apptainer exec --nv peclet-cuda.sif python3 my_run.py      # Snellius
# LUMI: Cray-MPICH is injected at runtime by the launcher wrapper —
module load LUMI partition/G cray-mpich rocm
srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip.sif my_run.py   # LUMI
```

For LUMI the container is built against vanilla MPICH and the host **Cray-MPICH** + Slingshot stack is
bound over it at runtime (`containers/lumi-run.sh`) — the MPICH-ABI hybrid model. See
[`containers/README.md`](https://github.com/computational-chemical-engineering/peclet/blob/main/containers/README.md#lumi--cray-mpich-the-hipdef-mpi-model).

See [`containers/README.md`](https://github.com/computational-chemical-engineering/peclet/blob/main/containers/README.md)
for MPI-ABI, GPU-aware-MPI, and arch details.

## Python API surface (what `import` gives you)

| Package | Import | Key API |
|---------|--------|---------|
| `sdflow` | `import sdflow` | `sdflow.Solver(nx,ny,nz)` — set_rho/mu/dt, set_solid, set_domain_bc, step, get_u/v/w/p; `sdflow.execution_space` |
| `pnm` (in sdflow) | `import pnm` | `SDFReader`, `extract_pores`, `segment_volume`, `extract_topology_gpu` |
| `dem` | `import dem` | `dem.Simulation(capacity)` — initialize_shape, set_domain, set_material_params, set_positions, step, get_positions, get_sdf_grid; gated MPI: init_mpi/enable_mpi_step/step_mpi |
| `mortonarith` | `from mortonarith import encode, decode, shift, box_zorder` | vectorised NumPy Morton ops |

Every binding method carries a one-line docstring (`help(sdflow.Solver.step)`); the full C++/Python API
is published as Doxygen on each repo's GitHub Pages.

## Status / caveats

- The `pip install` path is verified for the **OpenMP** backend (both modules install at the wheel root
  and import). The CUDA/HIP paths use the identical mechanism but were not built in this environment (no
  GPU); validate on first use on the target cluster.
- The container `.def` files are **not** CI-built (no GPU runners) — a tested starting point, not a
  guaranteed image. The MPI-ABI / GPU-aware-MPI binding is site-specific (notes in `containers/README.md`).
- Exact Snellius/LUMI module names and ROCm/CUDA versions drift; the recipes pin the *suite* deps
  (Kokkos 5.1.1, ArborX v2.1) and leave the site toolchain to `module load` / the container base image.
