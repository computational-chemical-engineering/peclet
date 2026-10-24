#!/usr/bin/env bash
# Per-rank launcher for the peclet CUDA container on Snellius (NVIDIA A100/H100), binding the host
# CUDA-aware OpenMPI + UCX + PMIx over the container's ABI-compatible OpenMPI (the Apptainer "hybrid"
# model — cuda.def builds OpenMPI 4.1.6 --with-cuda). This gives the real InfiniBand + GPUDirect
# transport without rebuilding on the node.
#
# Usage — launch it WITH srun (one container per rank/GPU):
#   module load 2023 OpenMPI/4.1.5-GCC-12.3.0 CUDA/12.4.0     # match cuda.def's OpenMPI 4.1.x series
#   srun --gpus-per-node=4 --ntasks-per-node=4 --mpi=pmix \
#        containers/snellius-run.sh peclet-cuda_0.1.0-sm80.sif benchmarks/profile_mpi_flow.py --L 128
#
# EasyBuild (Snellius) sets $EBROOT<PKG> to each loaded module's install root — we bind those in.
# If a library is missing at runtime, add its dir to PECLET_HOST_BIND. Set PECLET_CORE_GPU_AWARE_MPI=1
# to route GPU buffers straight through MPI (needs the bound host MPI to be CUDA-aware; default host-stages).
set -euo pipefail
SIF="${1:?usage: snellius-run.sh <image.sif> <python-script> [args...]}"; shift

OMPI="${EBROOTOPENMPI:-}"; UCX="${EBROOTUCX:-}"; PMIX="${EBROOTPMIX:-}"
if [[ -z "$OMPI" ]]; then
  echo "snellius-run.sh: no OpenMPI module loaded (\$EBROOTOPENMPI empty) —" >&2
  echo "                 'module load OpenMPI/4.1.x-GCC-...' so the host MPI can be bound." >&2
fi

# The host libmpi also needs the libraries of its own module dependencies (EasyBuild 2023 stack:
# hwloc, libevent, libpciaccess, libxml2, XZ, zlib; UCX's UCC/libfabric/numactl; binutils' libbfd for
# mca_pml_ucx). Without them the import dies on "libhwloc.so.15: cannot open shared object file", and
# without libbfd OpenMPI silently drops pml_ucx, the InfiniBand transport (both measured 2026-10-24).
DEPS=""
for v in EBROOTHWLOC EBROOTLIBEVENT EBROOTLIBPCIACCESS EBROOTLIBXML2 EBROOTXZ EBROOTZLIB \
         EBROOTUCC EBROOTLIBFABRIC EBROOTNUMACTL EBROOTBINUTILS; do
  [[ -n "${!v:-}" && -d "${!v}" ]] && DEPS="$DEPS ${!v}"
done

# The project space: /projects/0/<prj> is a symlink into /gpfs/work4, so bind both or a script under
# it is invisible in the container ("can't open file"). Extra dirs: PECLET_HOST_BIND (colon-separated).
BIND=""
for d in "$OMPI" "$UCX" "$PMIX" $DEPS /projects /gpfs/work4 /run/munge /var/run/munge /etc/slurm \
         ${PECLET_HOST_BIND:+${PECLET_HOST_BIND//:/ }}; do
  [[ -n "$d" && -e "$d" ]] && BIND="${BIND:+$BIND,}$d"
done
export APPTAINER_BIND="${BIND}${APPTAINER_BIND:+,$APPTAINER_BIND}"
export SINGULARITY_BIND="${APPTAINER_BIND}"

# Prefer the host OpenMPI/UCX/PMIx libs (and their dependencies) inside the container; OPAL_PREFIX
# points OpenMPI at the host tree.
INJECT="${OMPI:+$OMPI/lib}${UCX:+:$UCX/lib}${PMIX:+:$PMIX/lib}"
for d in $DEPS; do
  for l in "$d/lib64" "$d/lib"; do [[ -d "$l" ]] && INJECT="$INJECT:$l"; done
done
INJECT="$INJECT:/opt/openmpi/lib:/usr/local/cuda/lib64"
export APPTAINERENV_LD_LIBRARY_PATH="${INJECT}"
export SINGULARITYENV_LD_LIBRARY_PATH="${INJECT}"
export APPTAINERENV_OPAL_PREFIX="${OMPI:-/opt/openmpi}"
# The container's PMIx client trips "PMIX ERROR ... gds_ds12_lock_pthread.c" against the host server;
# the hash GDS component avoids the shared-memory store it fails on.
export APPTAINERENV_PMIX_MCA_gds="${PMIX_MCA_gds:-hash}"
export APPTAINERENV_PECLET_CORE_GPU_AWARE_MPI="${PECLET_CORE_GPU_AWARE_MPI:-0}"

# --nv binds the host NVIDIA driver + devices into the container.
exec apptainer exec --nv "$SIF" python3 "$@"
