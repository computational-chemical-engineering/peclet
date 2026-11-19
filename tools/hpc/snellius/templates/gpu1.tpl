# shellcheck shell=bash
# gpu1 -- one GPU, one rank, billed for ONE GPU (not the node's four). Target h100 | a100.
# Sourced by sn with SN_TARGET and L_GPUS/L_RANKS/L_NODES/L_THREADS/L_EXCLUSIVE set; sets T_PART,
# T_SBATCH, T_LAUNCH, T_ENV, T_ALLOC, T_ACCEPTS. sn adds --signal=B:TERM@120 --no-requeue to every job.
case "$SN_TARGET" in
  h100) T_PART=gpu_h100; _cpg=16 ;;      # 64 cores / 4 GPUs
  a100) T_PART=gpu_a100; _cpg=18 ;;      # 72 cores / 4 GPUs
  *) echo "sn: template gpu1 needs target h100 or a100, not '$SN_TARGET'" >&2; return 1 ;;
esac
T_SBATCH=(--partition="$T_PART" --nodes=1 --gpus-per-node=1 --ntasks-per-node=1 --cpus-per-task="$_cpg")
T_LAUNCH=(srun --mpi=pmix --ntasks=1 --cpus-per-task="$_cpg" --gpus-per-task=1 --gpu-bind=per_task:1)
# Bounded host pool (the CUDA prefix carries an OpenMP host backend); no pinning beyond srun's.
T_ENV=(OMP_NUM_THREADS="$_cpg" OMP_PROC_BIND=false)
T_ALLOC=1
T_ACCEPTS=()   # the resource flags this template reads; sn refuses any other (it would sit on the card without effect)
