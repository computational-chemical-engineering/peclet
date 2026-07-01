#!/bin/bash
# Snellius (SURF) — multi-GPU (NVIDIA A100 / H100) distributed CFD with the peclet CUDA container.
# Adjust the account, partition, node/GPU counts, module versions and the .sif path/arch to your setup.
#
#   apptainer pull oras://ghcr.io/computational-chemical-engineering/peclet-cuda:0.1.0-sm80   # A100
#   sbatch containers/submit/snellius.slurm
#
#SBATCH --job-name=peclet-cfd
#SBATCH --partition=gpu               # Snellius GPU partition (A100). Use the H100 partition + sm90 image for Hopper.
#SBATCH --nodes=2
#SBATCH --gpus-per-node=4             # 4x A100 per node
#SBATCH --ntasks-per-node=4          # one MPI rank per GPU
#SBATCH --cpus-per-task=16
#SBATCH --time=00:30:00
##SBATCH --account=your_project       # uncomment + set your accounting project
set -euo pipefail

# Host CUDA-aware OpenMPI — match the 4.1.x series the container was built against (cuda.def OMPI_VER).
module load 2023 OpenMPI/4.1.5-GCC-12.3.0 CUDA/12.4.0

SIF="${SIF:-$HOME/peclet-cuda_0.1.0-sm80.sif}"     # sm90 image on the H100 partition
SCRIPT="${SCRIPT:-benchmarks/profile_mpi_flow.py}"

# One container per GPU; --mpi=pmix lets the host PMIx launch the container's OpenMPI ranks.
srun --mpi=pmix containers/snellius-run.sh "$SIF" "$SCRIPT" \
     --L "${L:-128}" --steps "${STEPS:-200}" --csv "snellius_${SLURM_JOB_ID}.csv"
