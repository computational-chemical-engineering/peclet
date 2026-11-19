# shellcheck shell=bash
# genoa-hybrid -- MPI x OpenMP on genoa, one rank per CCD x 8 threads (--nodes N, default 1;
# 24 ranks per node). Target cpu. Exclusive whole nodes, --mem=0. --threads T (1, 2, 4 or 8; it
# must divide the 8 cores of a CCD) gives 192/T ranks per node; never 8 x 3 (a rank straddles a
# CCD: +18 % step time). `--ranks R` with R < the full count under-fills (3 x 8 on cores 0-23 is the
# measured best one-NUMA layout, SNELLIUS.md).
[ "$SN_TARGET" = cpu ] || { echo "sn: template genoa-hybrid needs target cpu, not '$SN_TARGET'" >&2; return 1; }
T_PART=genoa
_nodes=${L_NODES:-1}; _t=${L_THREADS:-8}
case "$_t" in 1|2|4|8) ;; *) echo "sn: genoa-hybrid: --threads must be 1, 2, 4 or 8 (divide a CCD)" >&2; return 1 ;; esac
[[ "$_nodes" =~ ^[1-9][0-9]*$ ]] || { echo "sn: genoa-hybrid: --nodes must be a positive integer" >&2; return 1; }
_full=$(( _nodes * 192 / _t )); _n=${L_RANKS:-$_full}
[ "$_n" -le "$_full" ] || { echo "sn: genoa-hybrid: --ranks $_n x $_t threads exceeds $_nodes node(s)" >&2; return 1; }
_rpn="$(( (_n + _nodes - 1) / _nodes ))"
T_SBATCH=(--partition=genoa --nodes="$_nodes" --ntasks-per-node="$_rpn" --cpus-per-task="$_t" --exclusive --mem=0)
T_LAUNCH=(srun --mpi=pmix --ntasks="$_n" --ntasks-per-node="$_rpn" --cpus-per-task="$_t" --distribution=block:block --cpu-bind=cores)
T_ENV=(OMP_NUM_THREADS="$_t" OMP_PLACES=cores OMP_PROC_BIND=close)
T_ALLOC="$((_nodes * 192))"
T_ACCEPTS=(nodes threads ranks exclusive)   # the resource flags this template reads; sn refuses any other (it would sit on the card without effect)
