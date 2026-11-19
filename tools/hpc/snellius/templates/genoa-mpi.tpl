# shellcheck shell=bash
# genoa-mpi -- pure MPI on genoa, one rank per core (--ranks N, default 192; up to 1536 = 8 nodes).
# Target cpu. One node with N < 192: a shared node, billed per core (memory 1792 MiB per rank; pass
# --exclusive for the whole node). Several nodes, or --exclusive: whole nodes, and --mem=0 when the
# nodes are under-filled -- --exclusive does NOT give the node's memory, SLURM caps at ~1792 MiB x
# ntasks (OOM, job 26280702, SNELLIUS.md).
[ "$SN_TARGET" = cpu ] || { echo "sn: template genoa-mpi needs target cpu, not '$SN_TARGET'" >&2; return 1; }
T_PART=genoa
_n=${L_RANKS:-192}
[[ "$_n" =~ ^[1-9][0-9]*$ ]] || { echo "sn: genoa-mpi: --ranks must be a positive integer" >&2; return 1; }
_nodes=$(( (_n + 191) / 192 )); _rpn=$(( (_n + _nodes - 1) / _nodes ))
T_SBATCH=(--partition=genoa --nodes="$_nodes" --ntasks="$_n" --cpus-per-task=1)
if [ "$_nodes" -gt 1 ] || [ "${L_EXCLUSIVE:-0}" = 1 ]; then
  T_SBATCH+=(--exclusive); T_ALLOC="$((_nodes * 192))"
  [ "$_n" -lt $((_nodes * 192)) ] && T_SBATCH+=(--mem=0)
else
  T_ALLOC=$_n
fi
T_LAUNCH=(srun --mpi=pmix --ntasks="$_n" --ntasks-per-node="$_rpn" --cpus-per-task=1 --distribution=block:block --cpu-bind=cores)
T_ENV=(OMP_NUM_THREADS=1)
