#!/bin/bash
# TU/e Umbrella cluster — multi-node CPU MPI (hybrid MPI+OpenMP) on the SMM partition chem.smm03.q
# (AMD Genoa, 32 cores / node) with the peclet CPU container.
#
#   apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cpu:0.1.0
#   sbatch containers/submit/tue-smm.slurm
#
#SBATCH --job-name=peclet-cfd
#SBATCH --partition=chem.smm03.q
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4          # 4 MPI ranks/node ...
#SBATCH --cpus-per-task=8            # ... x 8 OpenMP threads = 32 cores/node (Genoa)
#SBATCH --time=01:00:00
set -euo pipefail

# Site OpenMPI (4.1.x) — bound over the container's OpenMPI by tue-run.sh for multi-node.
module load OpenMPI 2>/dev/null || true

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-8}"
SIF="${SIF:-$HOME/peclet-cpu_0.1.0.sif}"
SCRIPT="${SCRIPT:-benchmarks/profile_mpi_flow.py}"

# Hybrid MPI+OpenMP: one container per rank, OMP_NUM_THREADS threads each.
srun --mpi=pmix containers/tue-run.sh "$SIF" "$SCRIPT" \
     --L "${L:-96}" --steps "${STEPS:-200}" --csv "tue_${SLURM_JOB_ID}.csv"
