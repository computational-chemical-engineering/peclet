#!/bin/bash
# Driver of `sn walltime-test` (uploaded next to the run; see walltime_test.sh). Job 1 of the chain
# sleeps until the walltime TERM (--signal=B:TERM@120 on a --time 0:03:00 job: at ~60 s), then
# "checkpoints" for 5 s -- longer than a kill without the grace wait would allow -- and exits 0.
# Job 2, the successor, finds the checkpoint, prints the CERT line and ends the chain with $SN_DONE.
ck="$SN_OUT/ckpt"
if [ -f "$ck" ]; then
  echo "CERT walltime_test resumed=1 $(cat "$ck")"
  echo "walltime test complete" > "$SN_DONE"
  exit 0
fi
t0=$(date +%s)
_term() {
  local at=$(( $(date +%s) - t0 ))
  echo "TERM after ${at} s; checkpointing (5 s)"
  sleep 5
  echo "term_after_s=$at checkpoint_s=5 job1=${SLURM_JOB_ID:-?}" > "$ck.tmp" && mv "$ck.tmp" "$ck"
  echo "CERT walltime_test checkpoint=1 term_after_s=$at"
  exit 0
}
trap _term TERM
echo "walltime test job 1: sleeping until TERM"
while :; do sleep 1; done
