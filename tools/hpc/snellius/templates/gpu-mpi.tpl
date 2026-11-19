# shellcheck shell=bash
# gpu-mpi -- N GPUs, one MPI rank per GPU (--gpus N, default 4). Target h100 | a100.
# N <= 4: one node with N GPUs. N > 4: N/4 full nodes, `--nodes=N/4 --gpus-per-node=4`, never a
# total --gpus=K>4 (OpenMPI hangs in srun, SNELLIUS.md). N > 4 must be a multiple of 4: a multi-node
# job with < 4 GPUs per node needs --exclusive and is billed for all 4 GPUs of every node.
case "$SN_TARGET" in
  h100) T_PART=gpu_h100; _cpg=16 ;;
  a100) T_PART=gpu_a100; _cpg=18 ;;
  *) echo "sn: template gpu-mpi needs target h100 or a100, not '$SN_TARGET'" >&2; return 1 ;;
esac
_n=${L_GPUS:-4}
[[ "$_n" =~ ^[1-9][0-9]*$ ]] || { echo "sn: gpu-mpi: --gpus must be a positive integer" >&2; return 1; }
if [ "$_n" -le 4 ]; then _nodes=1; _gpn=$_n
elif [ $((_n % 4)) -eq 0 ]; then _nodes=$((_n / 4)); _gpn=4
else echo "sn: gpu-mpi: --gpus $_n > 4 must be a multiple of 4 (billed per full node otherwise)" >&2; return 1; fi
T_SBATCH=(--partition="$T_PART" --nodes="$_nodes" --gpus-per-node="$_gpn" --ntasks-per-node="$_gpn" --cpus-per-task="$_cpg")
T_LAUNCH=(srun --mpi=pmix --ntasks="$_n" --cpus-per-task="$_cpg" --gpus-per-task=1 --gpu-bind=per_task:1)
T_ENV=(OMP_NUM_THREADS="$_cpg" OMP_PROC_BIND=false)
T_ALLOC=$_n
