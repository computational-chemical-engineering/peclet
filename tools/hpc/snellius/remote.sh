# shellcheck shell=bash
# Remote helpers of `sn` (tools/hpc/sn), run ON Snellius: sn sends this file's text ahead of the
# command over ssh. They only read squeue and job scripts, except snr_cancel (scancel + .stop files).
# selftest.sh runs them locally against stub squeue/scancel. Job names (lib.sh): run jobs
# sn-<campaign>.<tag> (a campaign has no "."), build jobs sn-build.<tree>.<target>.

# One line per job of mine: uniqueid|id|arrayjobid|arraytaskid|name|dependency
snr_jobs() { squeue --me -h -o '%A|%i|%F|%K|%j|%E' 2>/dev/null; }

# exit 0 when a job of that exact name is queued or running
snr_name_queued() { snr_jobs | awk -F'|' -v n="$1" '$5 == n {f = 1} END {exit !f}'; }

# The names of my queued/running sn run jobs whose job script runs on build dir <B>.
snr_jobs_using_build() {  # <proj> <build dir>
  local P="$1" B="$2" j c t
  for j in $(snr_jobs | awk -F'|' '$5 ~ /^sn-[^.]+\./ && $5 !~ /^sn-build\./ {print $5}' | sort -u); do
    c="${j#sn-}"; c="${c%%.*}"; t="${j#sn-"$c".}"
    grep -qxF "SN_BUILD=$B" "$P/runs/$c/$t/job.sh" 2>/dev/null && echo "$j"
  done
  return 0
}

# Cancel a job (id, array task A_i, or a whole array A) or every job of a campaign, together with
# every job that depends on one of them (a chain successor is queued with afterany:<id> and would
# otherwise run), transitively. Before the scancel, a .stop file goes into the run directory of each
# (runs/<c>/<t>/<idx>/.stop for one job, runs/<c>/<t>/.stop for a whole array or a campaign), which
# injob.sh honours: a successor queued after this squeue snapshot stops at its start.
snr_cancel() {  # <proj> <jobid|campaign>
  local P="$1" w="$2" L sel isid=0
  L=$(snr_jobs)
  [[ "$w" =~ ^[0-9]+(_[0-9]+)?$ ]] && isid=1
  if [ "$isid" = 1 ]; then
    sel=$(awk -F'|' -v w="$w" '$1 == w || $2 == w || $3 == w {print $1}' <<< "$L")
  else
    sel=$(awk -F'|' -v r="sn-$w." -v b="^sn-build[.]$w-[0-9a-f]{8}[.]" \
            'index($5, r) == 1 || $5 ~ b {print $1}' <<< "$L")
  fi
  # dependents, to a fixed point: a job whose dependency field names a selected id
  local n=-1 m
  while :; do
    m=$(wc -w <<< "$sel")
    [ "$m" = "$n" ] && break; n=$m
    sel=$(awk -F'|' -v s="$sel" '
      BEGIN {k = split(s, a, /[ \n]+/); for (i = 1; i <= k; i++) if (a[i] != "") want[a[i]] = 1}
      {if ($1 in want) {print $1; next}
       d = $6; while (match(d, /[0-9]+/)) {x = substr(d, RSTART, RLENGTH); d = substr(d, RSTART + RLENGTH)
         if (x in want) {print $1; next}}}' <<< "$L" | sort -u)
  done
  if [ -z "$sel" ]; then
    if [ "$isid" = 1 ]; then scancel "$w" && echo "sn cancel: $w (not in squeue --me)"; else echo "sn cancel: no jobs of campaign $w"; fi
    return 0
  fi
  local ids="" stops="" u i k nm c t d
  while IFS='|' read -r u i _ k nm _; do
    grep -qxF "$u" <<< "$sel" || continue
    ids="$ids $i"
    case "$nm" in sn-build.*|"") continue ;; sn-*.*) ;; *) continue ;; esac
    c="${nm#sn-}"; c="${c%%.*}"; t="${nm#sn-"$c".}"
    d="$P/runs/$c/$t"; [ -d "$d" ] || continue
    if [ "$isid" = 1 ] && [[ "$k" =~ ^[0-9]+$ ]]; then d="$d/$k"
    elif [ "$isid" = 1 ] && [[ "$i" != *_* ]]; then d="$d/0"; fi
    mkdir -p "$d" && touch "$d/.stop" && stops="$stops ${d#"$P/runs/"}/.stop"
  done <<< "$L"
  # shellcheck disable=SC2086  # a list of job ids
  scancel $ids && echo "sn cancel:$ids${stops:+ (stop files:$stops)}"
}
