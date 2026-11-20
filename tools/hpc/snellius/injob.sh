# shellcheck shell=bash
# In-job body of every `sn run` job. sn writes the job script as: #SBATCH header + the SN_* settings
# of this run + this file, verbatim, into runs/<campaign>/<tag>/job.sh -- the script is self-contained,
# so a chain successor resubmits the very same file. Arguments are positional because SURF's sbatch
# drops a leading VAR=x (SNELLIUS.md):
#   job.sh fresh  <build_info_sha>        the first submit (sn run)
#   job.sh resume <build_info_sha>        sn run --resume: the chain count starts again at 1
#   job.sh chain  <build_info_sha> <n>    a successor queued by job n-1 of the chain
# <build_info_sha> is sha256(BUILD_INFO)[:16] as sn read it at submit: a job refuses a build that was
# wiped or rebuilt since (sn build --rebuild), and one without BUILD_INFO (half built).
#
# Set by sn above this body:
#   SN_TREE SN_TREE_NAME SN_TARGET SN_BUILD SN_RUN SN_CAMPAIGN SN_TAG SN_CHAIN SN_NOSRUN SN_ARRAY
#   SN_LIMIT_S (the --time in s)  SN_GRACE (s the driver gets after a TERM)  SN_WALLTIME_WINDOW  SN_TOOLKIT
#   SN_LAUNCH=(srun ...)  SN_DRIVER=(driver args...)  SN_ENVS=(K=V ...)
#
# Per array index (0 without --array) the driver runs in SN_OUT = $SN_RUN/<idx>, which stays the same
# across a chain so a successor resumes from the driver's checkpoint. The driver ends the chain by
# creating $SN_DONE (= $SN_OUT/.done). Exported to the driver: SN_OUT SN_DONE SN_IDX SN_CASE
# SN_FRESH (1 only on the first submit) SN_TREE SN_BUILD SN_CMAKE_BUILD (= $SN_BUILD/cmake, the
# packages' CMake build dirs: test binaries of an `sn build --define`) SN_SRUN (the template's srun
# line, for --no-srun drivers that launch their own steps).
#
# Markers in SN_OUT: .done (driver: finished), .failed (a crash or a refusal: the chain stops; sn run
# --resume clears it), .stop (sn cancel; also $SN_RUN/.stop for the whole run), .chain_n.
#
# Walltime: every template asks for --signal=B:TERM@120, so 120 s before the limit Slurm sends TERM to
# THIS shell. The trap forwards it to the driver (srun forwards it to the tasks) and waits up to
# SN_GRACE s for it to checkpoint and exit. A walltime end is told apart from a failure by the flag the
# trap sets, never by the exit code: it keeps the successor and writes no .failed. A TERM long before
# the limit is a cancel (scancel by hand): it ends the chain, without .failed. Every TERM is logged as
# "[sn] TERM at <t> s since the job started, <left> s before the <limit> s limit" and, after a driver
# ran, as an 8th summary.tsv field "term_at_s=<t> left_s=<left>" (does Snellius add an OverTimeLimit?).
set -uo pipefail
SN_MODE="${1:-}"; SN_BIHASH="${2:-}"
SN_IDX="${SLURM_ARRAY_TASK_ID:-0}"
SN_OUT="$SN_RUN/$SN_IDX"
SN_DONE="$SN_OUT/.done"
SN_JOB="${SLURM_JOB_ID:-nojob}"
SN_CMAKE_BUILD="$SN_BUILD/cmake"
mkdir -p "$SN_OUT" || { echo "FATAL(sn): cannot create $SN_OUT" >&2; exit 1; }
_sn_log="$SN_OUT/driver-$SN_JOB.log"
_sn_next=""; _sn_keep_next=0

_sn_summary() {  # <rc> <wall_s> [<term>]: one line in summary.tsv (flock: array tasks append concurrently)
  local cert
  cert=$(grep -E '^CERT ' "$_sn_log" 2>/dev/null | tail -n 1)
  local line
  line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$SN_JOB" "$SN_IDX" "$SN_TREE_NAME" "$SN_TARGET" "$1" "$2" "$cert")
  [ -z "${3:-}" ] || line="$line"$'\t'"$3"
  echo "SUMMARY $line"
  if command -v flock >/dev/null 2>&1; then
    flock "$SN_RUN/summary.tsv.lock" bash -c 'printf "%s\n" "$1" >> "$2"' _ "$line" "$SN_RUN/summary.tsv"
  else
    printf '%s\n' "$line" >> "$SN_RUN/summary.tsv"
  fi
}
_sn_refuse() {  # <why>: stop this index -- no driver, no successor, .failed says why
  echo "FATAL(sn): $1" >&2
  echo "refused job $SN_JOB: $1" > "$SN_OUT/.failed"
  exit 1
}
# Any exit that does not explicitly keep the chain going cancels the successor queued below.
_sn_on_exit() {
  if [ -n "$_sn_next" ] && [ "$_sn_keep_next" != 1 ]; then
    scancel "$_sn_next" && echo "[sn chain] cancelled successor $_sn_next (${_sn_why:-early exit})"
  fi
}
trap _sn_on_exit EXIT

# --- 1. may this job run at all? -------------------------------------------------------------------
case "$SN_MODE" in
  fresh|resume) _sn_n=1 ;;
  chain) _sn_n="${3:-}"; [[ "$_sn_n" =~ ^[1-9][0-9]*$ ]] || _sn_refuse "chain successor without its count" ;;
  *) _sn_refuse "job.sh needs <fresh|resume|chain> <build_info_sha> [n], got '${*}'" ;;
esac
# A requeue (node failure) would rerun this script with the first submit's arguments: never.
[ "${SLURM_RESTART_COUNT:-0}" = 0 ] \
  || _sn_refuse "requeued (SLURM_RESTART_COUNT=$SLURM_RESTART_COUNT); sn run --resume restarts it"
if [ -f "$SN_DONE" ]; then
  echo "[sn chain] $SN_OUT complete ($(head -c 200 "$SN_DONE")); nothing to run."; exit 0
fi
if [ -f "$SN_RUN/.stop" ] || [ -f "$SN_OUT/.stop" ]; then
  echo "[sn chain] stopped by sn cancel (.stop); nothing to run."; exit 0
fi
if [ "$SN_MODE" = chain ] && [ -f "$SN_OUT/.failed" ]; then
  echo "[sn chain] an earlier job failed ($(head -c 200 "$SN_OUT/.failed")); nothing to run."; exit 0
fi
rm -f "$SN_OUT/.failed"          # fresh / resume from sn: a new attempt
echo "$_sn_n" > "$SN_OUT/.chain_n"

# --- 2. environment: the build's own env file and venv, so build and run cannot disagree ---------
[ -f "$SN_BUILD/BUILD_INFO" ] || _sn_refuse "$SN_BUILD has no BUILD_INFO (not built, or a rebuild is running)"
_sn_bi=$(sha256sum < "$SN_BUILD/BUILD_INFO" | cut -c1-16)
[ "$_sn_bi" = "$SN_BIHASH" ] || _sn_refuse "$SN_BUILD/BUILD_INFO is $_sn_bi, not $SN_BIHASH as at submit (rebuilt?)"
# shellcheck disable=SC1091
source "$SN_BUILD/env.sh" || _sn_refuse "$SN_BUILD/env.sh"
# shellcheck disable=SC1091
source "$SN_BUILD/.venv/bin/activate" || _sn_refuse "$SN_BUILD/.venv"
for _kv in "${SN_ENVS[@]}"; do export "${_kv?}"; done
grep -m1 '^MANIFEST ' "$SN_BUILD/BUILD_INFO" || _sn_refuse "no MANIFEST line in $SN_BUILD/BUILD_INFO"
# GPU target: every device module of the build must run on Cuda (a host-only "h100" build bills GPUs
# for nothing -- the dem fallback trap of SNELLIUS.md). The imports run in a 1-task srun step, never in
# this batch shell: a module that initializes MPI or Kokkos at import can hang or fail outside srun
# under pmix. Bounded by _sn_imp_timeout s (python -u: the output so far survives a hang). Only the
# first job of a chain (fresh or resume) checks: a successor runs the very same build (BUILD_INFO hash).
_sn_imp_timeout=120
if [ "$SN_TARGET" != cpu ]; then
  _sn_dev=$(sed -n 's/^device_modules //p' "$SN_BUILD/BUILD_INFO" | head -n 1)
  if [ -n "$_sn_dev" ] && [ "$SN_MODE" = chain ]; then
    echo "[sn] GPU import check: done by the first job of this chain (same BUILD_INFO); skipped"
  elif [ -n "$_sn_dev" ]; then
    read -r -d '' _sn_imp_py <<'PY'
import importlib, sys
bad = []
for m in sys.argv[1:]:
    sp = getattr(importlib.import_module(m), "execution_space", None)
    if sp is None:  # a package that does not re-export it (peclet.coupling): ask its extension _<name>
        try:
            sp = getattr(importlib.import_module(f"{m}._{m.rsplit('.', 1)[-1]}"), "execution_space", None)
        except ImportError:
            sp = None
    sp = "-" if sp is None else str(sp)
    print(m, sp)
    if "Cuda" not in sp:
        bad.append(f"{m}={sp}")
sys.exit(f"not Cuda: {' '.join(bad)}" if bad else 0)
PY
    # shellcheck disable=SC2086  # a word list of module names
    timeout -k 10 "$_sn_imp_timeout" srun --job-name=sn-import-check --mpi=pmix --ntasks=1 --gpus-per-task=1 \
      python -u -c "$_sn_imp_py" $_sn_dev > "$SN_OUT/.import_check" 2>&1
    _sn_irc=$?
    case "$_sn_irc" in
      0) ;;
      124|137) _sn_refuse "GPU import check: no answer from its srun step in ${_sn_imp_timeout} s (a hang at import? $SN_OUT/.import_check)" ;;
      *) _sn_refuse "GPU import check (rc $_sn_irc): $(tail -n 2 "$SN_OUT/.import_check" | tr '\n' ' ')" ;;
    esac
    echo "[sn] GPU import check: $(tr '\n' ' ' < "$SN_OUT/.import_check")"
  fi
fi

# --- 3. chain: queue the successor (wall-bounded-turbulence pattern), only now that the job can run ---
# The TERM trap first. Walltime = a TERM at most SN_WALLTIME_WINDOW s before the limit (Slurm may send
# the @120 signal up to 60 s early); an earlier TERM is a cancel (scancel by hand) and ends the chain.
# A TERM while the successor's sbatch is in flight is deferred (_sn_submitting) until _sn_next holds
# its id, and sbatch itself ignores TERM: a successor the controller accepted is always known here, so
# the EXIT trap can cancel it -- never an orphan that runs after this job.
_sn_pid=""; _sn_walltime=0; _sn_cancelled=0; _sn_trc=""; _sn_left=""; _sn_term_at=""
_sn_submitting=0; _sn_term_pending=0
_sn_term() {
  if [ -z "$_sn_term_at" ]; then
    _sn_term_at=$SECONDS; _sn_left=$((SN_LIMIT_S - _sn_term_at))
    echo "[sn] TERM at ${_sn_term_at} s since the job started, ${_sn_left} s before the ${SN_LIMIT_S} s limit"
  fi
  if [ "$_sn_submitting" = 1 ]; then _sn_term_pending=1; return 0; fi
  if [ "$_sn_left" -le "$SN_WALLTIME_WINDOW" ]; then _sn_walltime=1; else _sn_cancelled=1; _sn_why="TERM ${_sn_left} s before the limit (a cancel)"; fi
  if [ -z "$_sn_pid" ]; then echo "[sn] TERM before the driver started" >&2; exit 143; fi
  echo "[sn] TERM forwarded to the driver, waiting <= ${SN_GRACE} s for it"
  # To the job's steps through Slurm, NEVER to srun: srun answers a TERM of its own by ending the step
  # (SIGKILL to the tasks at once; shakedown 11-19, jobs 29476790/29476798). scancel --signal without
  # --batch/--full reaches the steps only, not this shell. After the grace: TERM to srun = end the step.
  scancel --signal=TERM "$SLURM_JOB_ID" 2>/dev/null || kill -TERM "$_sn_pid" 2>/dev/null
  ( sleep "$SN_GRACE"; kill -TERM "$_sn_pid" 2>/dev/null; sleep 40; kill -KILL "$_sn_pid" 2>/dev/null ) &
  local wd=$!
  wait "$_sn_pid"; _sn_trc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return 0
}
trap _sn_term TERM
if [ "$SN_CHAIN" -gt 1 ] && [ "$_sn_n" -lt "$SN_CHAIN" ]; then
  _sn_arr=(); [ "$SN_ARRAY" = 1 ] && _sn_arr=(--array="$SN_IDX")
  # stdout only: SURF's sbatch wrapper writes its notes on stderr
  _sn_submitting=1
  if _sn_next=$(trap '' TERM; exec sbatch --parsable --dependency=afterany:"$SN_JOB" "${_sn_arr[@]}" \
                  "$SN_RUN/job.sh" chain "$SN_BIHASH" $((_sn_n + 1)) 2> "$SN_OUT/.sbatch.err"); then
    _sn_next=$(grep -oE '^[0-9]+' <<< "$_sn_next" | tail -n 1)
    echo "[sn chain] job $_sn_n of at most $SN_CHAIN; successor $_sn_next queued (afterany:$SN_JOB)"
  else
    echo "[sn chain] WARNING: could not queue a successor: $(tail -n 3 "$SN_OUT/.sbatch.err")" >&2; _sn_next=""
  fi
  _sn_submitting=0
  [ "$_sn_term_pending" = 1 ] && _sn_term
elif [ "$SN_CHAIN" -gt 1 ]; then
  echo "[sn chain] job $_sn_n of $SN_CHAIN: the cap; no successor"
fi

# --- 4. the case and the driver -------------------------------------------------------------------
SN_CASE=""
_sn_case=()
if [ "$SN_ARRAY" = 1 ]; then
  SN_CASE=$(sed -n "$((SN_IDX + 1))p" "$SN_RUN/cases.txt")
  read -r -a _sn_case <<< "$SN_CASE"
fi
SN_FRESH=0; [ "$SN_MODE" = fresh ] && SN_FRESH=1
SN_SRUN="${SN_LAUNCH[*]}"
export SN_OUT SN_DONE SN_IDX SN_CASE SN_FRESH SN_TREE SN_BUILD SN_CMAKE_BUILD SN_SRUN
_sn_drv=("${SN_DRIVER[@]}")
# A driver named relative to the tree (flow/scripts/x.py) is taken from the tree.
[ -e "$SN_TREE/${_sn_drv[0]}" ] && _sn_drv[0]="$SN_TREE/${_sn_drv[0]}"
case "${_sn_drv[0]}" in *.py) _sn_drv=(python "${_sn_drv[@]}") ;; esac
if [ "$SN_NOSRUN" = 1 ]; then _sn_cmd=("${_sn_drv[@]}" "${_sn_case[@]}")
else _sn_cmd=("${SN_LAUNCH[@]}" "${_sn_drv[@]}" "${_sn_case[@]}"); fi
echo "[sn] job $SN_JOB idx $SN_IDX submit $_sn_n of $SN_CHAIN ($SN_MODE) tree $SN_TREE_NAME target $SN_TARGET fresh $SN_FRESH toolkit $SN_TOOLKIT"
echo "[sn] cwd $SN_OUT; run: ${_sn_cmd[*]}"

# --- 5. run; a TERM is forwarded and waited for (the trap above) --------------------------------
cd "$SN_OUT" || _sn_refuse "cd $SN_OUT"
_sn_t0=$SECONDS
"${_sn_cmd[@]}" > "$_sn_log" 2>&1 &
_sn_pid=$!
wait "$_sn_pid"; _sn_rc=$?
# a TERM that interrupted the wait above was handled in the trap, which reaped the driver
[ -n "$_sn_trc" ] && _sn_rc=$_sn_trc
_sn_wall=$((SECONDS - _sn_t0))
tail -n 5 "$_sn_log"

# --- 6. classify the end: walltime, done, stopped, crash, or a clean exit that continues ----------
if [ "$_sn_walltime" = 1 ]; then
  _sn_summary TERM "$_sn_wall" "term_at_s=$_sn_term_at left_s=$_sn_left"
  echo "[sn] walltime end (driver rc $_sn_rc after TERM): the chain goes on"
  _sn_exit=143
elif [ "$_sn_cancelled" = 1 ]; then
  _sn_summary CANCEL "$_sn_wall" "term_at_s=$_sn_term_at left_s=$_sn_left"; _sn_exit=143
else
  _sn_summary "$_sn_rc" "$_sn_wall"
  _sn_exit=$_sn_rc
fi
if [ -f "$SN_DONE" ]; then _sn_why=".done"
elif [ -f "$SN_RUN/.stop" ] || [ -f "$SN_OUT/.stop" ]; then _sn_why=".stop"
elif [ "$_sn_cancelled" = 1 ]; then :
elif [ "$_sn_walltime" = 1 ] || [ "$_sn_rc" = 0 ]; then _sn_keep_next=1
else
  _sn_why="rc $_sn_rc"
  echo "rc $_sn_rc job $SN_JOB" > "$SN_OUT/.failed"
fi
exit "$_sn_exit"
