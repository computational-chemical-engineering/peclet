# shellcheck shell=bash
# quiet1 -- one EXCLUSIVE genoa node for timing gates (wall-clock gates TRS2 load leaves
# inconclusive). Target cpu. Default one process x 24 threads on cores 0-23 (one NUMA domain, NPS4);
# --ranks R --threads T for a distributed layout (T in 1, 2, 4, 8, 24). Billed for the whole node.
# genoa node-set variability is real (3.2 vs 8.0 s/step): report best-of or the spread.
[ "$SN_TARGET" = cpu ] || { echo "sn: template quiet1 needs target cpu, not '$SN_TARGET'" >&2; return 1; }
T_PART=genoa
_n=${L_RANKS:-1}; _t=${L_THREADS:-24}
case "$_t" in 1|2|4|8|24) ;; *) echo "sn: quiet1: --threads must be 1, 2, 4, 8 or 24" >&2; return 1 ;; esac
[ $((_n * _t)) -le 192 ] || { echo "sn: quiet1: $_n ranks x $_t threads exceed one node" >&2; return 1; }
T_SBATCH=(--partition=genoa --nodes=1 --exclusive --mem=0 --ntasks-per-node="$_n" --cpus-per-task="$_t")
T_LAUNCH=(srun --mpi=pmix --ntasks="$_n" --cpus-per-task="$_t" --distribution=block:block --cpu-bind=cores)
T_ENV=(OMP_NUM_THREADS="$_t" OMP_PLACES=cores OMP_PROC_BIND=close)
T_ALLOC=192
T_ACCEPTS=(ranks threads exclusive)   # the resource flags this template reads; sn refuses any other (it would sit on the card without effect)
