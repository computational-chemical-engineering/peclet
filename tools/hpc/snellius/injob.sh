# shellcheck shell=bash
# In-job body of every `sn run` job. sn writes the job script as: #SBATCH header + the SN_* settings
# of this run + this file, verbatim, into runs/<campaign>/<tag>/job.sh -- the script is self-contained,
# so a chain successor resubmits the very same file. Positional $1: "fresh" on the first submit,
# "resume" on a chain successor or `sn run --resume`. Arguments are positional because SURF's sbatch
# drops a leading VAR=x (SNELLIUS.md).
#
# Set by sn above this body:
#   SN_TREE SN_TREE_NAME SN_TARGET SN_BUILD SN_RUN SN_CAMPAIGN SN_TAG SN_CHAIN SN_NOSRUN SN_ARRAY
#   SN_LAUNCH=(srun ...)  SN_DRIVER=(driver args...)  SN_ENVS=(K=V ...)
#
# Per array index (0 without --array) the driver runs in SN_OUT = $SN_RUN/<idx>, which stays the same
# across a chain so a successor resumes from the driver's checkpoint. The driver ends the chain by
# creating $SN_DONE (= $SN_OUT/.done). Exported to the driver: SN_OUT SN_DONE SN_IDX SN_CASE
# SN_FRESH (1 only on the first submit) SN_TREE SN_BUILD SN_SRUN (the template's srun line, for
# --no-srun drivers that launch their own steps).
set -uo pipefail
SN_MODE="${1:-resume}"
SN_IDX="${SLURM_ARRAY_TASK_ID:-0}"
SN_OUT="$SN_RUN/$SN_IDX"
SN_DONE="$SN_OUT/.done"
SN_JOB="${SLURM_JOB_ID:-nojob}"
mkdir -p "$SN_OUT" || { echo "FATAL(sn): cannot create $SN_OUT" >&2; exit 1; }
_sn_log="$SN_OUT/driver-$SN_JOB.log"

_sn_summary() {  # <rc> <wall_s>: one line in summary.tsv (flock: array tasks append concurrently)
  local cert
  cert=$(grep -E '^CERT ' "$_sn_log" 2>/dev/null | tail -n 1)
  local line
  line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$SN_JOB" "$SN_IDX" "$SN_TREE_NAME" "$SN_TARGET" "$1" "$2" "$cert")
  echo "SUMMARY $line"
  if command -v flock >/dev/null 2>&1; then
    flock "$SN_RUN/summary.tsv.lock" bash -c 'printf "%s\n" "$1" >> "$2"' _ "$line" "$SN_RUN/summary.tsv"
  else
    printf '%s\n' "$line" >> "$SN_RUN/summary.tsv"
  fi
}

# --- 1. chain: stop on .done, count submits, queue the successor (wall-bounded-turbulence pattern) ---
if [ -f "$SN_DONE" ]; then
  echo "[sn chain] $SN_OUT complete ($(head -c 200 "$SN_DONE")); nothing to run."
  exit 0
fi
if [ "$SN_MODE" = fresh ] || [ ! -f "$SN_OUT/.chain_n" ]; then _sn_n=1; else _sn_n=$(( $(cat "$SN_OUT/.chain_n") + 1 )); fi
echo "$_sn_n" > "$SN_OUT/.chain_n"
rm -f "$SN_OUT/.failed"
_sn_next=""
if [ "$SN_CHAIN" -gt 1 ] && [ "$_sn_n" -lt "$SN_CHAIN" ]; then
  _sn_arr=(); [ "$SN_ARRAY" = 1 ] && _sn_arr=(--array="$SN_IDX")
  # stdout only: SURF's sbatch wrapper writes its notes on stderr
  if _sn_next=$(sbatch --parsable --dependency=afterany:"$SN_JOB" "${_sn_arr[@]}" "$SN_RUN/job.sh" resume 2> "$SN_OUT/.sbatch.err"); then
    _sn_next=$(grep -oE '^[0-9]+' <<< "$_sn_next" | tail -n 1)
    echo "[sn chain] job $_sn_n of at most $SN_CHAIN; successor $_sn_next queued (afterany:$SN_JOB)"
  else
    echo "[sn chain] WARNING: could not queue a successor: $(tail -n 3 "$SN_OUT/.sbatch.err")" >&2; _sn_next=""
  fi
elif [ "$SN_CHAIN" -gt 1 ]; then
  echo "[sn chain] job $_sn_n of $SN_CHAIN: the cap; no successor"
fi

# --- 2. environment: the build's own env file and venv, so build and run cannot disagree ---------
# shellcheck disable=SC1091
source "$SN_BUILD/env.sh" || { echo "FATAL(sn): $SN_BUILD/env.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$SN_BUILD/.venv/bin/activate" || { echo "FATAL(sn): $SN_BUILD/.venv" >&2; exit 1; }
for _kv in "${SN_ENVS[@]}"; do export "${_kv?}"; done
grep -m1 '^MANIFEST ' "$SN_BUILD/BUILD_INFO" || echo "WARNING(sn): no MANIFEST line in $SN_BUILD/BUILD_INFO" >&2

# --- 3. the case and the driver -------------------------------------------------------------------
SN_CASE=""
_sn_case=()
if [ "$SN_ARRAY" = 1 ]; then
  SN_CASE=$(sed -n "$((SN_IDX + 1))p" "$SN_RUN/cases.txt")
  read -r -a _sn_case <<< "$SN_CASE"
fi
SN_FRESH=0; [ "$SN_MODE" = fresh ] && [ "$_sn_n" = 1 ] && SN_FRESH=1
SN_SRUN="${SN_LAUNCH[*]}"
export SN_OUT SN_DONE SN_IDX SN_CASE SN_FRESH SN_TREE SN_BUILD SN_SRUN
_sn_drv=("${SN_DRIVER[@]}")
# A driver named relative to the tree (flow/scripts/x.py) is taken from the tree.
[ -e "$SN_TREE/${_sn_drv[0]}" ] && _sn_drv[0]="$SN_TREE/${_sn_drv[0]}"
case "${_sn_drv[0]}" in *.py) _sn_drv=(python "${_sn_drv[@]}") ;; esac
if [ "$SN_NOSRUN" = 1 ]; then _sn_cmd=("${_sn_drv[@]}" "${_sn_case[@]}")
else _sn_cmd=("${SN_LAUNCH[@]}" "${_sn_drv[@]}" "${_sn_case[@]}"); fi
echo "[sn] job $SN_JOB idx $SN_IDX submit $_sn_n tree $SN_TREE_NAME target $SN_TARGET fresh $SN_FRESH"
echo "[sn] cwd $SN_OUT; run: ${_sn_cmd[*]}"

# --- 4. run; a walltime TERM still leaves its summary line ---------------------------------------
cd "$SN_OUT" || exit 1
_sn_t0=$SECONDS
_sn_pid=""
_sn_term() {
  [ -n "$_sn_pid" ] && kill -TERM "$_sn_pid" 2>/dev/null
  _sn_summary TERM $((SECONDS - _sn_t0))
  exit 143
}
trap _sn_term TERM
"${_sn_cmd[@]}" > "$_sn_log" 2>&1 &
_sn_pid=$!
wait "$_sn_pid"; _sn_rc=$?
trap - TERM
_sn_wall=$((SECONDS - _sn_t0))
tail -n 5 "$_sn_log"
_sn_summary "$_sn_rc" "$_sn_wall"

# --- 5. end of chain: done, or a crash (rc != 0 that is not the walltime) -> no successor -------
if [ -n "$_sn_next" ] && { [ -f "$SN_DONE" ] || [ "$_sn_rc" != 0 ]; }; then
  _sn_why="rc $_sn_rc"; [ -f "$SN_DONE" ] && _sn_why=".done"
  scancel "$_sn_next" && echo "[sn chain] cancelled successor $_sn_next ($_sn_why)"
fi
if [ "$_sn_rc" != 0 ]; then echo "rc $_sn_rc job $SN_JOB" > "$SN_OUT/.failed"; fi
exit "$_sn_rc"
