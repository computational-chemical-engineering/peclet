# Containers (HPC / Apptainer)

On HPC, the easiest way to run the suite is a container. **Apptainer** (formerly Singularity) is the
de-facto runtime on both **Snellius** and **LUMI** (Docker is not allowed on the compute nodes).

Pre-built images are published to the **GitHub Container Registry (GHCR)** on each release, and you can
also build your own from the [`containers/`](https://github.com/computational-chemical-engineering/peclet/tree/main/containers)
definition files. Every image bakes the Kokkos/ArborX toolchain and the full `peclet.*` family
(flow, dem, voro, core, morton).

## 1. Pull a pre-built image (recommended)

No toolchain, no build — just pull on the login node:

```bash
# CPU (laptops, CI, CPU partitions) — Kokkos OpenMP + Serial:
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cpu:0.1.0

# NVIDIA GPU (Snellius) — pick your arch:
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:0.1.0-sm80   # A100
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:0.1.0-sm90   # H100

# AMD GPU (LUMI-G, MI250X):
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-hip:0.1.0-gfx90a
```

Each image also carries a moving tag (`peclet-cpu:latest`, `peclet-cuda:sm80`, `peclet-hip:gfx90a`) that
tracks the newest release.

| Image | Backend | For |
|---|---|---|
| `peclet-cpu` | Kokkos OpenMP + Serial + OpenMPI | laptops, CI, CPU HPC partitions |
| `peclet-cuda:*-sm80` / `:*-sm90` | Kokkos CUDA | Snellius A100 (`sm_80`) / H100 (`sm_90`) |
| `peclet-hip:*-gfx90a` | Kokkos HIP | LUMI-G MI250X (`gfx90a`) |

## 2. Run

```bash
# --- Laptop / CPU node ---
apptainer exec peclet-cpu_0.1.0.sif python3 -c "import peclet.flow as f; print(f.execution_space)"  # -> OpenMP
OMP_NUM_THREADS=16 apptainer exec peclet-cpu_0.1.0.sif python3 my_run.py
mpirun -np 4 apptainer exec peclet-cpu_0.1.0.sif python3 my_distributed_run.py     # multi-rank (dem)

# --- Snellius (NVIDIA) --- request a GPU, then bind the host driver with --nv:
srun apptainer exec --nv peclet-cuda_0.1.0-sm80.sif python3 my_run.py

# --- LUMI-G (AMD) --- the launcher wrapper binds the host Cray-MPICH stack (see below):
module load LUMI partition/G cray-mpich rocm
srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip_0.1.0-gfx90a.sif my_run.py
```

`--nv` (NVIDIA) / `--rocm` (AMD) binds the host GPU driver into the container. `execution_space`
(`Cuda` / `HIP` / `OpenMP` / `Serial`) confirms which backend you're running.

### MPI on LUMI

The HIP image is built against vanilla **MPICH 4.0** (which exports the MPICH-ABI `libmpi.so.12`), and at
runtime [`containers/lumi-run.sh`](https://github.com/computational-chemical-engineering/peclet/blob/main/containers/lumi-run.sh)
binds the host **Cray-MPICH + libfabric + GPU-transport-layer** libraries over it — the MPICH-ABI hybrid
model, giving Slingshot + GPU-aware MPI without rebuilding. Pin the ROCm base tag `≤` the LUMI driver's
ROCm (`module show rocm`).

## 3. Build your own

If you need an arch that isn't published (or want to customise), build from the definition files
([details](https://github.com/computational-chemical-engineering/peclet/tree/main/containers)):

```bash
git submodule update --init --recursive              # the .def files copy the source tree
apptainer build peclet-cpu.sif  containers/cpu.def
KOKKOS_ARCH=HOPPER90 CUDA_ARCH=90 apptainer build peclet-cuda.sif containers/cuda.def   # e.g. H100
```

The images are produced in CI by [`.github/workflows/containers.yml`](https://github.com/computational-chemical-engineering/peclet/blob/main/.github/workflows/containers.yml),
which cross-compiles the GPU images on ordinary CPU runners (no GPU needed to *build* — only to *run*).
