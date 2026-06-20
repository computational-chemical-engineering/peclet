# Containers

Apptainer (Singularity) definition files that bake the toolchain + a bootstrapped Kokkos/ArborX prefix
and pip-install the `sdflow`, `dem`, and `mortonarith` Python packages. Apptainer is the de-facto
container runtime on HPC (both **Snellius** and **LUMI** use it; Docker is not permitted on the compute
nodes).

| File | Backend | Target |
|------|---------|--------|
| `cpu.def` | Kokkos OpenMP + Serial | laptops, CI, CPU HPC partitions |
| `cuda.def` | Kokkos CUDA | **Snellius** (A100 `sm_80` default; H100 `sm_90` via env) |
| `hip.def` | Kokkos HIP | **LUMI-G** (MI250X `gfx90a`) |

## Build

Run from the **suite root** so the `%files . /opt/peclet` section copies the full source tree
(check out submodules first):

```bash
git submodule update --init --recursive
apptainer build peclet-cpu.sif  containers/cpu.def
# GPU images compile device code for a chosen arch (no GPU needed at build time):
KOKKOS_ARCH=AMPERE80 CUDA_ARCH=80 apptainer build peclet-cuda.sif containers/cuda.def   # A100
apptainer build peclet-hip.sif  containers/hip.def
```

The GPU images are large and slow to build (they compile Kokkos for the device arch); build them on a
build node, or pull/convert a prebuilt image. The arch is read from the build environment — see the
header comment in each `.def`.

## Run

```bash
# CPU, single process:
apptainer exec peclet-cpu.sif python3 -c "import sdflow, dem, mortonarith"

# CPU, 4 MPI ranks (host mpirun launches one container per rank):
mpirun -np 4 apptainer exec peclet-cpu.sif python3 your_distributed_script.py

# NVIDIA GPU (Snellius) — --nv binds the host driver:
srun apptainer exec --nv peclet-cuda.sif python3 your_script.py

# AMD GPU (LUMI) — --rocm binds the GPU devices:
srun apptainer exec --rocm peclet-hip.sif python3 your_script.py
```

## HPC notes

- **MPI ABI.** For multi-rank runs the container's MPI must be ABI-compatible with the host launcher
  (the *hybrid* model: `srun`/`mpirun` on the host, MPI inside the container). The images ship OpenMPI;
  on a Cray-MPICH site (LUMI) either bind the host MPI (`-B`) or rebuild the image against an
  MPICH-ABI MPI. See the Apptainer "MPI applications" docs and the site guides.
- **GPU-aware MPI.** Enable by binding the host libraries (`-B /opt/rocm`, libfabric/Cray-MPICH on
  LUMI; the CUDA-aware OpenMPI on Snellius) and setting the relevant env. The codes host-stage the
  halo by default and opt into GPU-aware MPI explicitly — see `transport-core/docs/cuda-aware-mpi.md`.
- **Arch.** `cuda.def` defaults to A100 (`sm_80`); pass `KOKKOS_ARCH=HOPPER90 CUDA_ARCH=90` for H100.
  `hip.def` targets MI250X (`gfx90a`).

These `.def` files have **not** been built/tested in CI (no GPU runners); treat them as a starting
point to build on the target cluster. Roadblocks/assumptions are noted in `../docs/DEPLOYMENT.md`.
