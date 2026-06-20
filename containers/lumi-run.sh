#!/usr/bin/env bash
# Per-rank launcher for the peclet HIP container on LUMI-G, injecting the host
# Cray-MPICH + Slingshot (libfabric/cxi) + GPU-transport-layer over the container's
# MPICH-ABI libmpi.so.12. This is the runtime half of the "hybrid MPI" model used by
# containers/hip.def (which builds against vanilla MPICH).
#
# Usage — launch it WITH srun (one container per MPI rank):
#   module load LUMI partition/G cray-mpich rocm
#   srun -n8 --gpus-per-node=8 containers/lumi-run.sh peclet-hip.sif my_run.py [args...]
#
# The Cray PE populates CRAY_LD_LIBRARY_PATH (libfabric + cray-mpich + GTL lib dirs)
# when its modules are loaded; we inject that into the container so its MPICH resolves
# to the host Slingshot stack. Override the binds/paths below if LUMI's layout differs
# from this script's assumptions (see the LUMI "Running MPI in containers" docs, or load
# the site-provided `singularity-bindings` module which sets these for you).
set -euo pipefail

SIF="${1:?usage: lumi-run.sh <image.sif> <python-script> [args...]}"; shift

if [[ -z "${CRAY_LD_LIBRARY_PATH:-}" ]]; then
  echo "lumi-run.sh: CRAY_LD_LIBRARY_PATH is empty — 'module load cray-mpich rocm' first," >&2
  echo "             otherwise the container's MPICH will not bind the Slingshot stack." >&2
fi

# Host libraries the cxi (Slingshot) libfabric provider needs, plus the Cray PE tree.
# Adjust this list to your LUMI environment if a library is missing at runtime.
: "${PECLET_LUMI_BIND:=/opt/cray,/var/spool/slurmd,/usr/lib64/libcxi.so.1,/usr/lib64/libjansson.so.4}"

export MPICH_GPU_SUPPORT_ENABLED=1
# Both names so the script works under either `apptainer` or `singularity`.
export APPTAINER_BIND="${PECLET_LUMI_BIND}${APPTAINER_BIND:+,$APPTAINER_BIND}"
export SINGULARITY_BIND="${APPTAINER_BIND}"
# Prepend the host Cray libs; keep the container's own ROCm libs after them.
INJECT="${CRAY_LD_LIBRARY_PATH:-}:/opt/rocm/lib"
export APPTAINERENV_LD_LIBRARY_PATH="${INJECT}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export SINGULARITYENV_LD_LIBRARY_PATH="${APPTAINERENV_LD_LIBRARY_PATH}"

# --rocm binds the GPU devices (/dev/kfd, /dev/dri) and the host ROCm user stack.
exec apptainer exec --rocm "$SIF" python3 "$@"
