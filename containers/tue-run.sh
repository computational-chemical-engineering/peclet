#!/usr/bin/env bash
# Per-rank launcher for the peclet CPU container on the TU/e Umbrella cluster — targeting the SMM
# CPU-MPI partition (chem.smm03.q; AMD Genoa nodes). Binds the host EasyBuild OpenMPI + UCX + PMIx over
# the container's ABI-compatible OpenMPI (the CPU image ships OpenMPI 4.1.6) so multi-NODE MPI uses the
# host interconnect (RoCEv2 / UCX). Single-node needs no binding — just `mpirun -np N apptainer exec ...`.
#
# Usage — launch it WITH srun (one container per MPI rank; use OMP_NUM_THREADS for hybrid MPI+OpenMP):
#   module load OpenMPI                                  # the site's OpenMPI/4.1.x
#   export OMP_NUM_THREADS=8
#   srun -p chem.smm03.q --ntasks-per-node=4 --cpus-per-task=8 --mpi=pmix \
#        containers/tue-run.sh peclet-cpu_0.1.0.sif benchmarks/profile_mpi_flow.py --L 96
#
# If a host library is missing at runtime, add its directory to PECLET_HOST_BIND (colon-separated).
set -euo pipefail
SIF="${1:?usage: tue-run.sh <image.sif> <python-script> [args...]}"; shift

OMPI="${EBROOTOPENMPI:-}"; UCX="${EBROOTUCX:-}"; PMIX="${EBROOTPMIX:-}"
if [[ -z "$OMPI" ]]; then
  echo "tue-run.sh: no OpenMPI module loaded (\$EBROOTOPENMPI empty) — 'module load OpenMPI' first" >&2
  echo "            for multi-node runs, so the container OpenMPI binds the host interconnect." >&2
fi

BIND=""
for d in "$OMPI" "$UCX" "$PMIX" /run/munge /var/run/munge /etc/slurm ${PECLET_HOST_BIND:+${PECLET_HOST_BIND//:/ }}; do
  [[ -n "$d" && -e "$d" ]] && BIND="${BIND:+$BIND,}$d"
done
export APPTAINER_BIND="${BIND}${APPTAINER_BIND:+,$APPTAINER_BIND}"
export SINGULARITY_BIND="${APPTAINER_BIND}"

INJECT="${OMPI:+$OMPI/lib}${UCX:+:$UCX/lib}${PMIX:+:$PMIX/lib}:/usr/lib/x86_64-linux-gnu"
export APPTAINERENV_LD_LIBRARY_PATH="${INJECT}"
export SINGULARITYENV_LD_LIBRARY_PATH="${INJECT}"
export APPTAINERENV_OPAL_PREFIX="${OMPI:-/usr}"
# forward the OpenMP thread count into the container (hybrid MPI+OpenMP)
export APPTAINERENV_OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"

exec apptainer exec "$SIF" python3 "$@"
