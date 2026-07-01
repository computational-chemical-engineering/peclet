# Containers

Apptainer (Singularity) definition files that bake the toolchain + a bootstrapped Kokkos/ArborX prefix
and pip-install the `peclet.flow`, `peclet.dem`, and `peclet.morton` Python packages. Apptainer is the de-facto
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
apptainer exec peclet-cpu.sif python3 -c "import peclet.flow, peclet.dem, peclet.morton"

# CPU, 4 MPI ranks (host mpirun launches one container per rank):
mpirun -np 4 apptainer exec peclet-cpu.sif python3 your_distributed_script.py

# NVIDIA GPU (Snellius) — --nv binds the host driver:
srun apptainer exec --nv peclet-cuda.sif python3 your_script.py

# AMD GPU (LUMI) — use the Cray-MPICH launcher wrapper (see below):
module load LUMI partition/G cray-mpich rocm
srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip.sif your_script.py
```

## LUMI / Cray-MPICH (the `hip.def` MPI model)

LUMI-G runs **Cray-MPICH** over the **Slingshot-11** interconnect (libfabric `cxi` provider), not
OpenMPI. `hip.def` therefore uses the **MPICH-ABI hybrid** model:

1. The container is **built against vanilla MPICH** (Ubuntu's MPICH 4.0 exports `libmpi.so.12`, the
   same SONAME Cray-MPICH provides), so `dem`'s distributed step links the MPICH ABI.
2. At **runtime**, [`lumi-run.sh`](lumi-run.sh) binds the host Cray-MPICH + libfabric + GPU-transport-
   layer (GTL) libraries over the container's MPICH, so the app actually talks Slingshot and does
   GPU-aware transfers. It injects `CRAY_LD_LIBRARY_PATH` (which the Cray PE sets once
   `cray-mpich`/`rocm` are loaded) into the container and sets `MPICH_GPU_SUPPORT_ENABLED=1`.

```bash
module load LUMI partition/G cray-mpich rocm          # populates CRAY_LD_LIBRARY_PATH
srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip.sif my_run.py
# override the host-library bind list if LUMI's layout differs:
PECLET_LUMI_BIND=/opt/cray,/var/spool/slurmd,/usr/lib64/libcxi.so.1 \
  srun ... containers/lumi-run.sh peclet-hip.sif my_run.py
```

Notes / gotchas:
- **ROCm version.** Pin the `hip.def` base (`rocm/dev-ubuntu-22.04:6.2.4`) to **≤** the LUMI driver's
  ROCm (`module show rocm`); a container ROCm newer than the host driver fails at load.
- **GTL vs hsa.** The GPU-transport-layer lib (`libmpi_gtl_hsa.so`) is built against the host ROCm; if
  you hit hsa-symbol errors, also bind the host `/opt/rocm` ahead of the container's in
  `PECLET_LUMI_BIND` / the injected `LD_LIBRARY_PATH`.
- **Simpler path.** If your project has LUMI's `singularity-bindings` (EasyBuild) module, load it
  instead — it sets the bind list + `LD_LIBRARY_PATH` for you, and `lumi-run.sh` will compose with it.

## Snellius / other HPC notes

- **MPI ABI.** Same hybrid model: `srun`/`mpirun` on the host, MPI inside the container. `cpu.def` and
  `cuda.def` ship OpenMPI; if your Snellius MPI module is OpenMPI this composes directly, otherwise bind
  the host MPI or rebuild against the matching ABI.
- **GPU-aware MPI (Snellius).** Use the CUDA-aware OpenMPI module + `--nv`. The codes host-stage the
  halo by default and opt into GPU-aware MPI explicitly — see `core/docs/cuda-aware-mpi.md`.
- **Arch.** `cuda.def` defaults to A100 (`sm_80`); pass `KOKKOS_ARCH=HOPPER90 CUDA_ARCH=90` for H100.
  `hip.def` targets MI250X (`gfx90a`).

These `.def` files have **not** been built/tested in CI (no GPU runners); treat them as a starting
point to build on the target cluster. Roadblocks/assumptions are noted in `../docs/DEPLOYMENT.md`.
