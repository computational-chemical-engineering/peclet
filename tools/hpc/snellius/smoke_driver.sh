#!/bin/bash
# `sn smoke` driver: the release smoke certification (tools/hpc/smoke_snellius.slurm, docs/RELEASE.md
# §7) on an sn build. Run by an sn job with --no-srun, so it launches its own steps with $SN_SRUN
# (the template's srun line, N ranks): imports of what was built, flow's distributed sphere-packing
# permeability at np=1 and np=N (k must agree to all digits), and the weak-scaling tile at N ranks.
# Last line: CERT smoke np1_k=<k> npN_k=<k> match=<yes|no> ms_step=<max per-step ms>.
set -uo pipefail
: "${SN_SRUN:?run me from an sn job (--no-srun)}" "${SN_TREE:?}" "${SN_BUILD:?}"
read -r -a SRUN <<< "$SN_SRUN"
N=${SLURM_NTASKS:-4}
ONE=(); for a in "${SRUN[@]}"; do case "$a" in --ntasks=*) ONE+=(--ntasks=1) ;; *) ONE+=("$a") ;; esac; done
PY="$SN_BUILD/.venv/bin/python"

echo "== 1. imports / backends (the built packages)"
mods=$(awk '$1=="package"{sub(/^peclet-/,"",$2); print ($2=="halo"||$2=="core") ? "peclet.halo" : "peclet."$2}' "$SN_BUILD/BUILD_INFO" | sort -u | tr '\n' ' ')
# shellcheck disable=SC2086
"${ONE[@]}" "$PY" -W "error:peclet.core:DeprecationWarning" - $mods <<'PY' || { echo "CERT smoke imports=FAIL"; exit 1; }
import importlib, sys
for m in sys.argv[1:]:
    mod = importlib.import_module(m)
    print(m, "space", getattr(mod, "execution_space", "-"), "has_mpi", getattr(mod, "has_mpi", "-"))
PY
grep -q '^package peclet-flow ' "$SN_BUILD/BUILD_INFO" || { echo "CERT smoke flow=absent imports=OK"; exit 0; }

echo "== 2. flow distributed solve: np=1 vs np=$N must print the same k"
(cd "$SN_TREE/flow" && "${ONE[@]}" "$PY" scripts/verify_mpi_spheres_sdflow.py) | tee np1.txt
(cd "$SN_TREE/flow" && "${SRUN[@]}" "$PY" scripts/verify_mpi_spheres_sdflow.py) | tee "np$N.txt"
k1=$(grep -m1 -oE 'k=[^ ]+' np1.txt | cut -d= -f2); kN=$(grep -m1 -oE 'k=[^ ]+' "np$N.txt" | cut -d= -f2)
match=no; [ -n "$k1" ] && [ "$k1" = "$kN" ] && match=yes

echo "== 3. weak-scaling tile, $N ranks (timing only)"
"${SRUN[@]}" "$PY" "$SN_TREE/benchmarks/profile_mpi_flow.py" --L 48 --steps 20 --warmup 5 --csv tile.csv | tee tile.txt
ms=$(grep -m1 -oE 'per-step: max +[0-9.]+' tile.txt | awk '{print $NF}')
echo "CERT smoke np1_k=${k1:-none} np${N}_k=${kN:-none} match=$match ms_step=${ms:-none}"
[ "$match" = yes ]
