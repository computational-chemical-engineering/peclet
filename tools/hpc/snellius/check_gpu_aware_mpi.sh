#!/bin/bash
# ==========================================================================================
# Discover + validate CUDA-aware (GPU-aware) MPI on Snellius, so the halo can pass device
# pointers straight to MPI (drops the host-staging copies).
#
# Copied from peclet-examples/examples/wall-bounded-turbulence/check_gpu_aware_mpi.sh for the sn
# toolkit: `sn check-gpu-aware <tree> <target>` runs it as the driver of a 2-GPU gpu-mpi job
# (--no-srun) with positional <tree> <env.sh>; the #SBATCH lines below are then inert (sn's job
# header carries the resources). It only TESTS the transport: PECLET_CORE_GPU_AWARE_MPI=0 (host-
# staged halos) stays the default in snellius_env.sh (anomaly G5, SNELLIUS.md). Last line: CERT.
#
#   sbatch check_gpu_aware_mpi.sh          # runs as a batch job -> gpuaware-check-<jobid>.out
#   # or interactively:
#   srun -p gpu_h100 --gpus=2 --ntasks=2 --cpus-per-task=16 -t0:30:00 --account=tes24005 --pty bash
#   ./check_gpu_aware_mpi.sh
#
# It loads the same OpenMPI the solver was built against, adds the UCX-CUDA transports, and runs
# the suite's device-pointer MPI check. If it prints "CUDA-aware MPI works", we enable it in the
# run scripts. Paste the whole output (or the .out file) back.
# ==========================================================================================
#SBATCH --job-name=gpuaware-check
#SBATCH --partition=gpu_h100
#SBATCH --nodes=1
#SBATCH --gpus-per-node=2         # 2 GPUs on ONE node -> exercises cuda_ipc/cuda_copy
#SBATCH --ntasks=2               # one rank per GPU
#SBATCH --cpus-per-task=16
#SBATCH --time=00:15:00
#SBATCH --output=gpuaware-check-%j.out
#SBATCH --account=tes24005
set -uo pipefail
SUITE="${1:?usage: check_gpu_aware_mpi.sh <tree> <env.sh>}"; ENVSH="${2:?}"
TMPDIR_SN=$(mktemp -d)
CHECK="$SUITE/core/tools/cuda_aware_mpi_check.cpp"

echo "############ 1-2. load the GPU-aware toolchain (snellius_env.sh) ############"
source "$ENVSH"   # the build's copy of snellius_env.sh (2024a: gompi + CUDA 12.6 + UCX-CUDA 1.16)
echo "  loaded modules -- UCX-CUDA MUST appear here:"
module -t list 2>&1 | grep -iE "ucx|openmpi|cuda" | sed 's/^/    /'
echo
echo "############ 3. does UCX now expose CUDA transports? ############"
command -v ucx_info >/dev/null && ucx_info -d 2>&1 | grep -iE "Transport:.*cuda|cuda_copy|cuda_ipc|gdr" | sed 's/^/  /' \
  || echo "  (no cuda transports found)"
echo
echo "############ 4. build the device-pointer MPI check ############"
export OMPI_MCA_pml=ucx           # force the UCX pml (carries cuda_copy/cuda_ipc); the key setting
export UCX_MEMTYPE_CACHE=n        # recommended with CUDA (avoids a known UCX memtype bug)
# export UCX_TLS=self,sm,cuda_copy,cuda_ipc,rc,gdr_copy   # uncomment if auto-selection misses cuda
mpic++ "$CHECK" -I"${CUDA_HOME:-$EBROOTCUDA}/include" -L"${CUDA_HOME:-$EBROOTCUDA}/lib64" -lcudart -o "$TMPDIR_SN/cudampicheck" \
  && echo "  built $TMPDIR_SN/cudampicheck" || { echo "  BUILD FAILED"; exit 1; }
echo
echo "############ 5. run it on 2 ranks / 2 GPUs (DEVICE pointers) ############"
mpirun -np 2 "$TMPDIR_SN/cudampicheck" 2>&1 | tee "$TMPDIR_SN/out.txt" | sed 's/^/  /'
echo
echo "############ verdict ############"
echo "  If you saw 'device recv CORRECT -- CUDA-aware MPI works' above, GPU-aware MPI is functional."
echo "  Then the run scripts can set PECLET_CORE_GPU_AWARE_MPI=1 + these module/env lines."
if grep -q "CUDA-aware MPI works" "$TMPDIR_SN/out.txt"; then works=yes; else works=no; fi
rm -rf "$TMPDIR_SN"
echo "CERT gpu-aware works=$works"
