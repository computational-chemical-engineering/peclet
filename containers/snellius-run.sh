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

BIND=""
for d in "$OMPI" "$UCX" "$PMIX" /run/munge /var/run/munge /etc/slurm ${PECLET_HOST_BIND:+${PECLET_HOST_BIND//:/ }}; do
  [[ -n "$d" && -e "$d" ]] && BIND="${BIND:+$BIND,}$d"
done
export APPTAINER_BIND="${BIND}${APPTAINER_BIND:+,$APPTAINER_BIND}"
export SINGULARITY_BIND="${APPTAINER_BIND}"

# Prefer the host OpenMPI/UCX/PMIx libs inside the container; OPAL_PREFIX points OpenMPI at the host tree.
INJECT="${OMPI:+$OMPI/lib}${UCX:+:$UCX/lib}${PMIX:+:$PMIX/lib}:/opt/openmpi/lib:/usr/local/cuda/lib64"
export APPTAINERENV_LD_LIBRARY_PATH="${INJECT}"
export SINGULARITYENV_LD_LIBRARY_PATH="${INJECT}"
export APPTAINERENV_OPAL_PREFIX="${OMPI:-/opt/openmpi}"
export APPTAINERENV_PECLET_CORE_GPU_AWARE_MPI="${PECLET_CORE_GPU_AWARE_MPI:-0}"

# --nv binds the host NVIDIA driver + devices into the container.
exec apptainer exec --nv "$SIF" python3 "$@"
