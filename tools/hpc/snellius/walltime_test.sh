#!/bin/bash
# The real walltime test of the sn chain (one billed shakedown item, ~3 SBU): proves on Snellius that
# --signal=B:TERM@120 reaches the batch shell, that injob.sh forwards it through srun to the driver
# and waits for its checkpoint, and that a walltime end keeps the chain (no .failed, successor runs).
#   walltime_test.sh <tree> --test-only | --print-action | --card <id> --desk <dir>    submit
#   walltime_test.sh check <campaign>/<tag>                                              verdict
# The tree needs a cpu build (`sn build <tree> cpu morton` is the cheapest). The job: genoa-mpi
# --ranks 1 (one core of a shared node, charged in 24-core units), --time 0:03:00, --chain 2.
# Expected verdict, one line:
#   walltime_test: PASS job1 TERM after ~60 s (checkpoint 5 s) -> job2 resumed, .done; no .failed
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SN="$KIT/../sn"
if [ "${1:-}" != check ]; then
  [ $# -ge 1 ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
  exec "$SN" walltime-test "$@"
fi
ct="${2:?usage: walltime_test.sh check <campaign>/<tag>}"
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
"$SN" pull "$ct" "$d" --only 'summary.tsv,.done,.failed,ckpt,driver-*.log' >/dev/null || { echo "walltime_test: FAIL (pull)"; exit 1; }
s="$d/summary.tsv"
[ -f "$s" ] || { echo "walltime_test: FAIL no summary.tsv (still running? sn status)"; exit 1; }
why=""
[ "$(wc -l < "$s")" = 2 ] || why="$why; $(wc -l < "$s") summary lines, want 2"
r1=$(sed -n 1p "$s" | cut -f5); c1=$(sed -n 1p "$s" | cut -f7)
r2=$(sed -n 2p "$s" | cut -f5); c2=$(sed -n 2p "$s" | cut -f7)
[ "$r1" = TERM ] || why="$why; job1 rc '$r1', want TERM"
[[ "$c1" == "CERT walltime_test checkpoint=1 "* ]] || why="$why; job1 did not checkpoint ('$c1')"
[ "$r2" = 0 ] || why="$why; job2 rc '$r2', want 0"
[[ "$c2" == "CERT walltime_test resumed=1 "* ]] || why="$why; job2 did not resume ('$c2')"
[ -f "$d/0/.done" ] || why="$why; no .done"
[ ! -e "$d/0/.failed" ] || why="$why; .failed: $(cat "$d/0/.failed")"
at=$(grep -oE 'term_after_s=[0-9]+' <<< "$c1" | cut -d= -f2)
if [ -z "$why" ]; then
  echo "walltime_test: PASS job1 TERM after ${at} s (checkpoint 5 s) -> job2 resumed, .done; no .failed"
else
  echo "walltime_test: FAIL${why}"; exit 1
fi
