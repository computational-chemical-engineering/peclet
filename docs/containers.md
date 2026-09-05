# Containers (HPC / Apptainer)

On HPC, the easiest way to run the suite is a container. **Apptainer** (formerly Singularity) is the
de-facto runtime on both **Snellius** and **LUMI** (Docker is not allowed on the compute nodes).

Pre-built images are published to the **GitHub Container Registry (GHCR)** by CI on every release tag
([`containers.yml`](https://github.com/computational-chemical-engineering/peclet/blob/main/.github/workflows/containers.yml)),
and you can also build your own from the [`containers/`](https://github.com/computational-chemical-engineering/peclet/tree/main/containers)
definition files. Every image bakes the Kokkos/ArborX toolchain and the full `peclet.*` family
(flow, pnm, dem, voro, coupling, core, morton) with the distributed (MPI) API compiled in.

## 1. Pull a pre-built image (recommended)

Each image carries a **moving tag** that tracks the newest release — `peclet-cpu:latest`,
`peclet-cuda:sm80`, `peclet-cuda:sm90`, `peclet-hip:gfx90a` — and a **pinned tag** per family release,
`<version>` / `<version>-sm80` / `<version>-sm90` / `<version>-gfx90a` (the family version is the
`peclet` version on PyPI; see the [changelog](https://github.com/computational-chemical-engineering/peclet/blob/main/CHANGELOG.md)
and the GHCR package pages for the list). Use the pinned tag for anything you want to reproduce.

The images are **public** on GHCR — no login or token required. No toolchain, no build; just pull on the
login node:

```bash
# CPU (laptops, CI, CPU partitions) — Kokkos OpenMP + Serial:
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cpu:latest

# NVIDIA GPU (Snellius) — pick your arch:
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:sm80     # A100
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:sm90     # H100

# AMD GPU (LUMI-G, MI250X):
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-hip:gfx90a

# a pinned release, e.g. the family version X.Y.Z:
apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:X.Y.Z-sm90
```

!!! warning "LUMI / HIP image — untested on hardware"
    The `peclet-cpu` and `peclet-cuda` images are built, published and run in practice. The **HIP** image
    builds in CI with the whole family (since 2026-09-04; earlier releases had no HIP image at all because
    of a link error in the Python modules under `hipcc`) but has **not run on an AMD GPU** — there is no
    LUMI allocation yet. Treat it as a candidate, not a validated product; see [LUMI](LUMI.md).

| Image | Backend | For |
|---|---|---|
| `peclet-cpu` | Kokkos OpenMP + Serial + OpenMPI | laptops, CI, CPU HPC partitions |
| `peclet-cuda:*-sm80` / `:*-sm90` | Kokkos CUDA | Snellius A100 (`sm_80`) / H100 (`sm_90`) |
| `peclet-hip:*-gfx90a` | Kokkos HIP | LUMI-G MI250X (`gfx90a`) |

## 2. Run

```bash
# --- Laptop / CPU node ---
apptainer exec peclet-cpu_latest.sif python3 -c "import peclet.flow as f; print(f.execution_space, f.has_mpi)"  # -> OpenMP True
OMP_NUM_THREADS=16 apptainer exec peclet-cpu_latest.sif python3 my_run.py
mpirun -np 4 apptainer exec peclet-cpu_latest.sif python3 my_distributed_run.py   # single-node MPI

# --- Snellius (NVIDIA) --- request a GPU, then bind the host driver with --nv:
srun apptainer exec --nv peclet-cuda_sm90.sif python3 my_run.py

# --- LUMI-G (AMD) --- the launcher wrapper binds the host Cray-MPICH stack (see below):
module load LUMI partition/G cray-mpich rocm
srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip_gfx90a.sif my_run.py
```

`--nv` (NVIDIA) / `--rocm` (AMD) binds the host GPU driver into the container. `execution_space`
(`Cuda` / `HIP` / `OpenMP` / `Serial`) confirms which backend you're running. Any page of the
[examples gallery](https://computational-chemical-engineering.github.io/peclet-examples/) runs unchanged
inside the image (the bootstrap cell is a no-op when `peclet` is already importable).

## 3. Distributed MPI (multi-GPU / multi-node)

Every image compiles in the **distributed step of flow, pnm, dem and voro** (`PECLET_FLOW_MPI` /
`PECLET_PNM_MPI` / `PECLET_DEM_MPI` / `PECLET_VORO_MPI`; `coupling` follows) and ships **`mpi4py`**. A
distributed driver imports `mpi4py` (which calls `MPI_Init`) then uses the multi-rank API —
`Solver.init_mpi(...)` + `peclet.flow.mpi_block(...)` for the CFD, `Simulation.step_mpi(...)` for dem,
`peclet.voro.VoronoiHalo` for the tessellation, `extract_pore_network_mpi` for pnm — see
[Python API → Distributed](python/index.md#distributed-mpi-api).

**Single node** is trivial — the container's own MPI launches the ranks:

```bash
mpirun -np 4 apptainer exec peclet-cpu_latest.sif python3 my_run.py
```

**Multiple nodes / GPUs** use the Apptainer *bind* model: the container is built against a compatible MPI,
and at runtime the **host** MPI + interconnect libraries are bound in. Each system has a launcher wrapper
+ an example `sbatch` script under [`containers/`](https://github.com/computational-chemical-engineering/peclet/tree/main/containers):

| System | Target | Image | Wrapper | Submit script |
|---|---|---|---|---|
| **Snellius** | NVIDIA A100/H100 multi-GPU | `peclet-cuda:*-sm80` / `-sm90` | `snellius-run.sh` (binds host OpenMPI+UCX+PMIx, `--nv`) | `submit/snellius.slurm` |
| **LUMI-G** | AMD MI250X multi-GPU | `peclet-hip:*-gfx90a` | `lumi-run.sh` (binds host Cray-MPICH/Slingshot, `--rocm`) | `submit/lumi.slurm` |
| **TU/e SMM** | AMD Genoa multi-node CPU (hybrid MPI+OpenMP) | `peclet-cpu` | `tue-run.sh` (binds host OpenMPI, `OMP_NUM_THREADS`) | `submit/tue-smm.slurm` |

The wrapper is launched **by** `srun`, one container per rank:

```bash
# Snellius — 4 GPUs/node, one rank per GPU (load the site's OpenMPI 4.1.x + CUDA modules first;
# the wrapper binds whatever $EBROOTOPENMPI / $EBROOTUCX / $EBROOTPMIX point at):
srun --mpi=pmix containers/snellius-run.sh peclet-cuda_sm90.sif benchmarks/profile_mpi_flow.py --L 128

# TU/e SMM (chem.smm03.q) — hybrid 4 ranks × 8 threads/node:
export OMP_NUM_THREADS=8
srun --mpi=pmix containers/tue-run.sh peclet-cpu_latest.sif benchmarks/profile_mpi_flow.py --L 96
```

!!! warning "Match the OpenMPI version"
    The CUDA & CPU images ship **OpenMPI 4.1.x** (the `OMPI_VER` in `cuda.def`); the bind model needs the
    host `module load OpenMPI/4.1.x` to be the same series. If your site differs, rebuild the image with
    `OMPI_VER` set to your `module show OpenMPI` version. LUMI instead uses the **Cray-MPICH ABI**
    (`libmpi.so.12`) — no version pin, but keep the ROCm base tag `≤` the LUMI driver's ROCm.

A site-built install (no container) is the other multi-GPU route on Snellius:
`tools/hpc/install_snellius.sh` builds the family from a release tag against the module toolchain —
see [Snellius](SNELLIUS.md).

### Weak-scaling / communication-overhead benchmark

[`benchmarks/profile_mpi_flow.py`](https://github.com/computational-chemical-engineering/peclet/tree/main/benchmarks)
is a ready-made profiler: every rank runs an **identical** periodic sphere-packing CFD tile, glued
periodically, so per-rank work is constant and the per-step-time rise vs `np` is the pure MPI tax (halo
exchange + global pressure solve). The packing geometry is generated once and not timed. Launch it through
the wrappers above; see [`benchmarks/README.md`](https://github.com/computational-chemical-engineering/peclet/tree/main/benchmarks).
The published scaling studies (1→32 H100, up to 1536 CPU ranks) are on the
[gallery's benchmarks section](https://computational-chemical-engineering.github.io/peclet-examples/benchmarks/).

## 4. Build your own

If you need an arch that isn't published (or want to customise), build from the definition files
([details](https://github.com/computational-chemical-engineering/peclet/tree/main/containers)):

```bash
git submodule update --init --recursive              # the .def files copy the source tree
apptainer build peclet-cpu.sif  containers/cpu.def
KOKKOS_ARCH=HOPPER90 CUDA_ARCH=90 apptainer build peclet-cuda.sif containers/cuda.def   # e.g. H100
```

The images are produced in CI by [`.github/workflows/containers.yml`](https://github.com/computational-chemical-engineering/peclet/blob/main/.github/workflows/containers.yml),
which cross-compiles the GPU images on ordinary CPU runners (no GPU needed to *build* — only to *run*);
the same workflow can be dispatched by hand for one image group (`cpu` / `cuda` / `hip`) with or without
pushing.
