#!/bin/bash
# LUMI-G — multi-GPU (AMD MI250X, gfx90a) distributed CFD with the peclet HIP container.
# Set your --account (project_46YXXXXXX). Each MI250X exposes 2 GCDs → 8 GCDs/node = 8 ranks/node.
#
#   apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-hip:0.1.0-gfx90a
#   sbatch containers/submit/lumi.slurm
#
#SBATCH --job-name=peclet-cfd
#SBATCH --partition=standard-g
#SBATCH --nodes=2
#SBATCH --gpus-per-node=8
#SBATCH --ntasks-per-node=8          # one MPI rank per GCD
#SBATCH --cpus-per-task=7
#SBATCH --time=00:30:00
#SBATCH --account=project_46YXXXXXX   # <-- set your LUMI project
set -euo pipefail

# Cray PE provides the Slingshot MPI stack that lumi-run.sh injects into the container.
module load LUMI partition/G cray-mpich rocm

SIF="${SIF:-$HOME/peclet-hip_0.1.0-gfx90a.sif}"
SCRIPT="${SCRIPT:-benchmarks/profile_mpi_flow.py}"

srun containers/lumi-run.sh "$SIF" "$SCRIPT" \
     --L "${L:-128}" --steps "${STEPS:-200}" --csv "lumi_${SLURM_JOB_ID}.csv"
