#!/bin/bash
# Local selftest of the sn toolkit -- no ssh, nothing billed. Run on TRS2:
#   tools/hpc/snellius/selftest.sh            -> one line "selftest: PASS n/n" (exit 0) or the failures
# Checks: Desk action canonicalization (lossless quoting), cost arithmetic, walltime parsing, manifest
# hashing and override resolution (same inputs -> same tree name; a dirty worktree is refused),
# dependency closure, names, the templates' resource arithmetic and accepted flags, the billed-command
# refusals; a generated job script run end to end with a fake SLURM (SLURM_* set, srun/sbatch/scancel
# stubs): summary.tsv lines, array cases, the chain (successor queued after the checks, stopped and
# cancelled on .done/.stop/.failed, cap, count positional, resume resets it), the walltime TERM with a
# checkpointing driver and the grace bound, a cancel-TERM, a TERM during the successor's sbatch, the
# TERM's seconds (log line, summary field 8), a requeue, BUILD_INFO refusals, the GPU import check (in a
# srun step, first job of a chain only, a hang bounded), early-exit cleanup; sn cancel's dependents
# and .stop files (stub squeue); the real submit path through a stub ssh (Desk verify, ledger before
# sbatch, override/dirty-kit/--env refusals, --resume and --rebuild guards, --define); the build job's
# GPU preflight.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SN="$KIT/../sn"
# shellcheck source=lib.sh
source "$KIT/lib.sh"
W=$(mktemp -d); trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$1" = "$2" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $3: got [$1] want [$2]"; fi; }
yes_() { if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL (expected success): $*"; fi; }
no_() { if "$@" >/dev/null 2>&1; then fail=$((fail + 1)); echo "FAIL (expected refusal): $*"; else pass=$((pass + 1)); fi; }

# --- 1. Desk action ---------------------------------------------------------------------------
ok "$(sn_canonical_action build m7-1a2b3c4d h100 voro --card c1 --desk /d)" "sn build m7-1a2b3c4d h100 voro" action-card
ok "$(sn_canonical_action build --card=c1 m7-x  h100 --desk=/d --print-action)" "sn build m7-x h100" action-eq
ok "$(sn_canonical_action build m7-x h100 --test-only)" "sn build m7-x h100" action-testonly
ok "$(sn_canonical_action run t h100 a/b gpu1 --chain 4 -- d.py --card x)" "sn run t h100 a/b gpu1 --chain 4 -- d.py --card x" action-driver-verbatim
# #14 lossless: one argument "a b" and two arguments a b give different texts
ok "$(sn_canonical_action run t h100 a/b gpu1 -- bash -c "a b")" 'sn run t h100 a/b gpu1 -- bash -c a\ b' action-quoted
if [ "$(sn_canonical_action run t -- bash -c "a b")" != "$(sn_canonical_action run t -- bash -c a b)" ]; then _d=0; else _d=1; fi; ok $_d 0 action-lossless
ok "$(sn_canonical_action run t -- x '$HOME;rm' "")" 'sn run t -- x \$HOME\;rm '"''" action-quoted-meta

# --- 2. cost ----------------------------------------------------------------------------------
ok "$(sn_cost 1 192 03:00:00 1 1)" "576.0" cost-build-h100
ok "$(sn_cost 4 192 00:20:00 1 1)" "256.0" cost-smoke-4gpu
ok "$(sn_cost 1 192 01:00:00 10 4)" "7680.0" cost-array-chain
ok "$(sn_cost 48 1 03:00:00 1 1)" "144.0" cost-genoa-build
ok "$(sn_cost 4 128 1-00:00:00 1 1)" "12288.0" cost-days
ok "$(sn_rate gpu_a100)" "128 GPU" rate-a100
# #11 walltime forms: H:MM:SS, D-HH, D-HH:MM, D-HH:MM:SS only
ok "$(sn_hours 0:03:00)" "0.050000" time-hmmss
ok "$(sn_hours 2-12)" "60.000000" time-d-hh
ok "$(sn_hours 1-01:30)" "25.500000" time-d-hhmm
ok "$(sn_hours 0-00:00:36)" "0.010000" time-d-hhmmss
no_ sn_hours "90"
no_ sn_hours "30:00"
no_ sn_hours "02:00"
no_ sn_hours "1:60:00"
no_ sn_hours "1-24"
no_ sn_hours "0:00:00"
no_ sn_hours "1-2:3"

# --- 3. manifest hashing ----------------------------------------------------------------------
m1=$'core aaaa pin\numbrella bbbb ref:origin/main\nvoro cccc worktree:/x/voro-m7'
m2=$'voro cccc ref:HEAD\numbrella bbbb pin\ncore aaaa ref:main'
m3=$'core aaaa pin\numbrella bbbb pin\nvoro dddd pin'
ok "$(sn_manifest_hash <<< "$m1")" "$(sn_manifest_hash <<< "$m2")" hash-same-sources
if [ "$(sn_manifest_hash <<< "$m1")" != "$(sn_manifest_hash <<< "$m3")" ]; then _d=0; else _d=1; fi; ok $_d 0 hash-differs
ok "$(sn_manifest_hash <<< "$m1" | wc -c)" 9 hash-8hex

# --- 4. overrides: worktree HEAD, dirty refused, ref, wrong repo refused ------------------------
S="$W/suite"; mkdir -p "$S/core"; git init -q "$S"; git init -q "$S/core"
git -C "$S/core" config remote.origin.url git@example:peclet-core.git
git -C "$S/core" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
c1=$(git -C "$S/core" rev-parse HEAD)
git -C "$S/core" worktree add -q "$S/core-feat" -b feat 2>/dev/null
echo x > "$S/core-feat/f.txt"; git -C "$S/core-feat" add f.txt
git -C "$S/core-feat" -c user.email=t@t -c user.name=t commit -q -m two
c2=$(git -C "$S/core-feat" rev-parse HEAD)
ok "$(cd "$W" && sn_resolve "$S" core ../core-feat)" "$c2 worktree:$S/core-feat" override-worktree-rel-submodule
ok "$(sn_resolve "$S" core "$S/core-feat")" "$c2 worktree:$S/core-feat" override-worktree-abs
ok "$(sn_resolve "$S" core "$c1")" "$c1 ref:$c1" override-ref
ok "$(sn_resolve "$S" core feat)" "$c2 ref:feat" override-branch-not-on-origin
echo dirty >> "$S/core-feat/f.txt"
no_ sn_resolve "$S" core ../core-feat
git -C "$S/core-feat" checkout -q f.txt; echo u > "$S/core-feat/untracked.txt"
yes_ sn_resolve "$S" core ../core-feat
mkdir -p "$W/other" && git -C "$W/other" init -q && git -C "$W/other" config remote.origin.url git@example:peclet-voro.git
git -C "$W/other" -c user.email=t@t -c user.name=t commit -q --allow-empty -m o
no_ sn_resolve "$S" core "$W/other"
no_ sn_resolve "$S" core no-such-ref

# --- 4b. extra repos: committed git repos only, at HEAD or a ref; they enter the tree hash ------
X="$W/study"; mkdir -p "$X/perf"; git init -q "$X"; echo 'echo hi' > "$X/perf/d.sh"; git -C "$X" add perf/d.sh
git -C "$X" -c user.email=t@t -c user.name=t commit -q -m d; x1=$(git -C "$X" rev-parse HEAD)
git -C "$X" tag v1
ok "$(sn_resolve_extra "st:$X")" "st $x1 extra:$X@HEAD" extra-head
ok "$(cd "$W" && sn_resolve_extra "st:study/perf@v1")" "st $x1 extra:$X@v1" extra-rel-subdir-ref
echo more >> "$X/perf/d.sh"
no_ sn_resolve_extra "st:$X"
ok "$(sn_resolve_extra "st:$X@v1" | cut -d' ' -f2)" "$x1" extra-dirty-ok-at-explicit-ref
git -C "$X" checkout -q perf/d.sh
mkdir -p "$W/plain"; no_ sn_resolve_extra "pl:$W/plain"
no_ sn_resolve_extra "bad/name:$X"
no_ sn_resolve_extra "$X"
no_ sn_resolve_extra "st:$X@nosuchref"
mx="$m1"$'\n'"extra/st $x1 extra:$X@HEAD"
if [ "$(sn_manifest_hash <<< "$m1")" != "$(sn_manifest_hash <<< "$mx")" ]; then _d=0; else _d=1; fi; ok $_d 0 extra-in-hash

# --- 4c. the cases file in the action text: path@sha256[:12], refused on a mismatch -------------
CF="$W/cases-a.txt"; printf 'a 1\nb 2\n' > "$CF"; ch=$(sha256sum < "$CF" | cut -c1-12)
ok "$(sn_canonical_action run t h100 c/t gpu1 --array "$CF" -- d.py)" "sn run t h100 c/t gpu1 --array $CF@$ch -- d.py" action-cases-hash
ok "$(sn_canonical_action run t h100 c/t gpu1 --array "$CF@000000000000" -- d.py)" "sn run t h100 c/t gpu1 --array $CF@$ch -- d.py" action-cases-rehash
ok "$(sn_canonical_action run t h100 c/t gpu1 -- d.py --array "$CF")" "sn run t h100 c/t gpu1 -- d.py --array $CF" action-cases-driver-verbatim
yes_ env SN_HOST=nohost.invalid "$SN" run t h100 c/t gpu1 --array "$CF@$ch" --emit "$W/e1.sh" -- d.py
no_ env SN_HOST=nohost.invalid "$SN" run t h100 c/t gpu1 --array "$CF@000000000000" --emit "$W/e2.sh" -- d.py
printf 'a 1\nc 3\n' > "$CF"
no_ env SN_HOST=nohost.invalid "$SN" run t h100 c/t gpu1 --array "$CF@$ch" --emit "$W/e3.sh" -- d.py
if [ "$(sn_canonical_action run t h100 c/t gpu1 --array "$CF" -- d.py)" != "sn run t h100 c/t gpu1 --array $CF@$ch -- d.py" ]; then _d=0; else _d=1; fi
ok $_d 0 action-cases-content-changes-text

# --- 5. closure -------------------------------------------------------------------------------
ok "$(sn_closure voro)" "morton core voro" closure-voro
ok "$(sn_closure coupling)" "morton core flow dem coupling" closure-coupling
ok "$(sn_closure flow pnm)" "morton core flow pnm" closure-flow-pnm
no_ sn_closure vof
# #5 names: a campaign has no "." (the job-name separator), is not "build" nor all digits
yes_ sn_valid_campaign sn-selftest; yes_ sn_valid_campaign x-y; no_ sn_valid_campaign a.b
no_ sn_valid_campaign build; no_ sn_valid_campaign 123
ok "$(sn_jobname x-y t.1)" "sn-x-y.t.1" jobname

# --- 6. templates -----------------------------------------------------------------------------
tpl() {  # <template> <target> [L_*=v ...] -> "partition|sbatch|launch|alloc"
  ( SN_TARGET="$2"; local t="$1"; shift 2; L_GPUS=""; L_RANKS=""; L_NODES=""; L_THREADS=""; L_EXCLUSIVE=0
    for kv in "$@"; do eval "$kv"; done
    # shellcheck disable=SC1090
    source "$KIT/templates/$t.tpl" || exit 1
    echo "$T_PART|${T_SBATCH[*]}|${T_LAUNCH[*]}|$T_ALLOC" )
}
ok "$(tpl gpu1 h100)" "gpu_h100|--partition=gpu_h100 --nodes=1 --gpus-per-node=1 --ntasks-per-node=1 --cpus-per-task=16|srun --mpi=pmix --ntasks=1 --cpus-per-task=16 --gpus-per-task=1 --gpu-bind=per_task:1|1" tpl-gpu1
ok "$(tpl gpu-mpi a100 L_GPUS=8 | cut -d'|' -f2)" "--partition=gpu_a100 --nodes=2 --gpus-per-node=4 --ntasks-per-node=4 --cpus-per-task=18" tpl-gpu-mpi-8
no_ tpl gpu-mpi h100 L_GPUS=6
no_ tpl gpu1 cpu
ok "$(tpl genoa-mpi cpu L_RANKS=200 | cut -d'|' -f2,4)" "--partition=genoa --nodes=2 --ntasks=200 --cpus-per-task=1 --exclusive --mem=0|384" tpl-genoa-underfilled
ok "$(tpl genoa-mpi cpu L_RANKS=1536 | cut -d'|' -f2)" "--partition=genoa --nodes=8 --ntasks=1536 --cpus-per-task=1 --exclusive" tpl-genoa-1536
ok "$(tpl genoa-mpi cpu L_RANKS=4 | cut -d'|' -f2,4)" "--partition=genoa --nodes=1 --ntasks=4 --cpus-per-task=1|4" tpl-genoa-shared
ok "$(tpl genoa-hybrid cpu L_NODES=2 | cut -d'|' -f3)" "srun --mpi=pmix --ntasks=48 --ntasks-per-node=24 --cpus-per-task=8 --distribution=block:block --cpu-bind=cores" tpl-hybrid
no_ tpl genoa-hybrid cpu L_THREADS=3
ok "$(tpl quiet1 cpu | cut -d'|' -f2,4)" "--partition=genoa --nodes=1 --exclusive --mem=0 --ntasks-per-node=1 --cpus-per-task=24|192" tpl-quiet1
no_ tpl genoa-mpi h100
# #10 a flag a template does not read is refused (gpu1/gpu-mpi never take --exclusive)
export SN_HOST=nohost.invalid
no_ "$SN" run t h100 c/t gpu1 --exclusive --emit "$W/x.sh" -- d.py
no_ "$SN" run t h100 c/t gpu-mpi --exclusive --emit "$W/x.sh" -- d.py
no_ "$SN" run t h100 c/t gpu1 --ranks 2 --emit "$W/x.sh" -- d.py
yes_ "$SN" run t cpu c/t genoa-mpi --ranks 4 --exclusive --emit "$W/x.sh" -- d.py
no_ "$SN" run t cpu c/t genoa-mpi --threads 4 --emit "$W/x.sh" -- d.py
# #11 at the CLI; #5 a dotted campaign
no_ "$SN" run t h100 c/t gpu1 --time 30:00 --emit "$W/x.sh" -- d.py
no_ "$SN" run t h100 c.x/t gpu1 --emit "$W/x.sh" -- d.py
# #1 #4 every template's job: TERM to the batch shell 120 s before the limit, no requeue
for _t in gpu1:h100 gpu-mpi:a100 genoa-mpi:cpu genoa-hybrid:cpu quiet1:cpu; do
  "$SN" run t "${_t#*:}" c/t "${_t%%:*}" --emit "$W/t.sh" -- d.py >/dev/null 2>&1
  ok "$(grep -cxE '#SBATCH --(signal=B:TERM@120|no-requeue)' "$W/t.sh")" 2 "tpl-signal-norequeue-${_t%%:*}"
done
unset SN_HOST

# --- 7. billed commands refuse without a card (before any ssh: the host does not resolve) ------
export SN_HOST=nohost.invalid
no_ "$SN" build m7-x h100
no_ "$SN" run m7-x h100 c/t gpu1 -- d.py
no_ "$SN" smoke m7-x h100
no_ "$SN" check-gpu-aware m7-x h100
ok "$("$SN" build m7-x h100 2>&1 | grep -c 'needs --card')" 1 refuse-message

# --- 8. a generated job script, run locally under a fake SLURM -------------------------------------
P="$W/proj"; TR="$P/src/fake-00000000"; B="$P/build/fake-00000000-h100"; STUB="$W/stub"; PM="$W/pymods"
mkdir -p "$TR/drv" "$B/.venv/bin" "$STUB" "$PM"
: > "$B/env.sh"
ln -s "$(command -v python3)" "$B/.venv/bin/python"
printf 'export PATH=%q:$PATH PYTHONPATH=%q\n' "$B/.venv/bin" "$PM" > "$B/.venv/bin/activate"
echo 'execution_space = "Cuda"' > "$PM/peclet_fake_cuda.py"; echo 'execution_space = "OpenMP"' > "$PM/peclet_fake_host.py"
printf 'MANIFEST umbrella:aaaaaaaaaaaa core:bbbbbbbbbbbb (fake-00000000)\ndevice_modules peclet_fake_cuda\n' > "$B/BUILD_INFO"
BIH=$(sha256sum < "$B/BUILD_INFO" | cut -c1-16)
cat > "$TR/drv/fake.sh" <<'EOF'
#!/bin/bash
# fake driver: args echo, CERT line; "finish-after N" writes .done on its N-th call; "hang" sleeps;
# "ckpt" checkpoints for 1 s on TERM; "deaf" ignores TERM; "stopme" writes the run's .stop
n=$(( $(cat calls 2>/dev/null || echo 0) + 1 )); echo $n > calls
echo "args: $* fresh=$SN_FRESH idx=$SN_IDX case=[$SN_CASE] srun=[$SN_SRUN] cmake=[$SN_CMAKE_BUILD]"
case "${1:-}" in
  hang) sleep 30; exit 0 ;;
  ckpt) trap 'sleep 1; echo ckpt > ckpt; echo "CERT fake checkpoint=1"; exit 0' TERM; while :; do sleep 0.1; done ;;
  deaf) trap '' TERM; sleep 20; exit 0 ;;
  stopme) touch "$SN_OUT/../.stop"; exit 0 ;;
esac
echo "CERT fake call=$n idx=$SN_IDX"
[ "${1:-}" = finish-after ] && [ "$n" -ge "$2" ] && echo "done at call $n" > "$SN_DONE"
[ "${1:-}" = fail ] && exit 7
exit 0
EOF
chmod +x "$TR/drv/fake.sh"
cat > "$STUB/srun" <<'EOF'
#!/bin/bash
echo "srun $*" >> "$SN_STUBLOG"; while [[ "${1:-}" == -* ]]; do shift; done; exec "$@"
EOF
cat > "$STUB/sbatch" <<'EOF'
#!/bin/bash
# SN_STUB_SBATCH_SLOW=s: the call is in flight for s s after it was accepted (pid in $SN_STUBLOG.sbatch)
echo "sbatch $*" >> "$SN_STUBLOG"; echo "sbatch: Single-node jobs run on a shared node by default." >&2
_id=$(( 900000 + $(grep -c '^sbatch' "$SN_STUBLOG") ))
if [ -n "${SN_STUB_SBATCH_SLOW:-}" ]; then echo $$ > "$SN_STUBLOG.sbatch"; sleep "$SN_STUB_SBATCH_SLOW"; fi
echo "$_id"
EOF
cat > "$STUB/scancel" <<'EOF'
#!/bin/bash
echo "scancel $*" >> "$SN_STUBLOG"
EOF
chmod +x "$STUB"/*
export SN_STUBLOG="$W/stub.log"; : > "$SN_STUBLOG"
runjob() {  # <job.sh> <jobid> <array idx|-> <positional...>
  local j="$1" id="$2" ix="$3"; shift 3
  ( export PATH="$STUB:$PATH" SLURM_JOB_ID="$id"; [ "$ix" = - ] || export SLURM_ARRAY_TASK_ID="$ix"
    bash "$j" "$@" ) > "$W/job-$id.out" 2>&1
}
emit() {  # <campaign/tag> <sn run flags and driver...>: job.sh in the run dir
  local ct="$1"; shift; mkdir -p "$P/runs/$ct"
  SN_PROJ="$P" SN_HOST=nohost.invalid "$SN" run fake-00000000 h100 "$ct" "$@" >/dev/null 2>&1
}
nsb() { grep -c '^sbatch' "$SN_STUBLOG"; }
R="$P/runs/c1/chain"
emit c1/chain gpu1 --chain 3 --emit "$R/job.sh" -- drv/fake.sh finish-after 2
ok "$(grep -cxF "SN_BUILD=$B" "$R/job.sh")" 1 job-build-line
runjob "$R/job.sh" 101 - fresh "$BIH"; ok $? 0 job1-rc
ok "$(wc -l < "$R/summary.tsv")" 1 job1-summary
ok "$(cut -f1,2,3,4,5 "$R/summary.tsv")" "$(printf '101\t0\tfake-00000000\th100\t0')" job1-summary-fields
ok "$(cut -f7 "$R/summary.tsv")" "CERT fake call=1 idx=0" job1-cert
ok "$(grep -c "dependency=afterany:101 $R/job.sh chain $BIH 2\$" "$SN_STUBLOG")" 1 job1-successor-chain-positional
ok "$(grep -c '^srun --mpi=pmix --ntasks=1' "$SN_STUBLOG")" 1 job1-srun-line
ok "$(grep -c 'fresh=1' "$R/0/driver-101.log")" 1 job1-fresh
ok "$(grep -c "cmake=\[$B/cmake\]" "$R/0/driver-101.log")" 1 job1-sn-cmake-build
ok "$(grep -c 'MANIFEST umbrella:' "$W/job-101.out")" 1 job1-prints-manifest
ok "$(grep -c 'GPU import check: peclet_fake_cuda Cuda' "$W/job-101.out")" 1 job1-gpu-import-check
# WO-SN3 #2 the import check runs in a 1-task srun step (never in the batch shell), on the first job only
nimp() { grep -c '^srun --job-name=sn-import-check --mpi=pmix --ntasks=1 --gpus-per-task=1 python -u -c ' "$SN_STUBLOG"; }
ok "$(nimp)" 1 job1-import-check-in-srun
runjob "$R/job.sh" 102 - chain "$BIH" 2; ok $? 0 job2-rc
ok "$(grep -c 'fresh=0' "$R/0/driver-102.log")" 1 job2-not-fresh
ok "$(nimp)" 1 job2-chain-no-import-check
ok "$(grep -c 'GPU import check: done by the first job of this chain' "$W/job-102.out")" 1 job2-import-check-skipped-msg
ok "$(test -f "$R/0/.done" && echo y)" y job2-done
ok "$(grep -c '^scancel 900002$' "$SN_STUBLOG")" 1 job2-cancels-successor
runjob "$R/job.sh" 103 - chain "$BIH" 3; ok $? 0 job3-rc
ok "$(wc -l < "$R/summary.tsv")" 2 job3-no-run-after-done
ok "$(grep -c 'nothing to run' "$W/job-103.out")" 1 job3-stops-on-done
# the cap: chain 2, a driver that never finishes -> job 2 queues no successor
R2="$P/runs/c1/cap"; : > "$SN_STUBLOG"
emit c1/cap gpu1 --chain 2 --emit "$R2/job.sh" -- drv/fake.sh
runjob "$R2/job.sh" 201 - fresh "$BIH"; runjob "$R2/job.sh" 202 - chain "$BIH" 2
ok "$(nsb)" 1 cap-one-successor
ok "$(grep -c 'the cap; no successor' "$W/job-202.out")" 1 cap-message
# #12 a resume from sn after an exhausted chain starts the count again: it queues a successor
runjob "$R2/job.sh" 203 - resume "$BIH"
ok "$(nsb)" 2 resume-resets-count
ok "$(nimp)" 2 resume-runs-import-check   # 201 fresh + 203 resume; not 202 (chain)
ok "$(grep -c "afterany:203 $R2/job.sh chain $BIH 2\$" "$SN_STUBLOG")" 1 resume-successor-is-2
no_ runjob "$R2/job.sh" 204 - chain "$BIH"
# a crash cancels the successor and leaves .failed; a successor that runs anyway stops on it (#12)
R3="$P/runs/c1/crash"; : > "$SN_STUBLOG"
emit c1/crash gpu1 --chain 5 --emit "$R3/job.sh" -- drv/fake.sh fail
runjob "$R3/job.sh" 301 - fresh "$BIH"; ok $? 7 crash-rc
ok "$(grep -c '^scancel 900001$' "$SN_STUBLOG")" 1 crash-cancels-successor
ok "$(test -f "$R3/0/.failed" && echo y)" y crash-failed-marker
runjob "$R3/job.sh" 302 - chain "$BIH" 2; ok $? 0 failed-successor-rc
ok "$(cat "$R3/0/calls")" 1 failed-successor-no-driver
ok "$(nsb)" 1 failed-successor-no-new-successor
# an array: case lines become the driver's trailing args, one summary line per index
R4="$P/runs/c1/arr"; printf '# comment\nalpha 1\n\nbeta 2\n' > "$W/cases.txt"
emit c1/arr gpu1 --array "$W/cases.txt" --emit "$R4/job.sh" -- drv/fake.sh
ok "$(grep -c '^#SBATCH --array=0-1$' "$R4/job.sh")" 1 array-header
runjob "$R4/job.sh" 401 0 fresh "$BIH"; runjob "$R4/job.sh" 402 1 fresh "$BIH"
ok "$(wc -l < "$R4/summary.tsv")" 2 array-summary
ok "$(grep -c 'case=\[beta 2\]' "$R4/1/driver-402.log")" 1 array-case-args
ok "$(grep -c '^args: beta 2 ' "$R4/1/driver-402.log")" 1 array-case-argv
bgjob() {  # <job.sh> <jobid> <positional...>: start in the background, wait for the driver, TERM the shell
  local j="$1" id="$2" d; d="$(dirname "$1")/0"; shift 2
  PATH="$STUB:$PATH" SLURM_JOB_ID="$id" bash "$j" "$@" > "$W/job-$id.out" 2>&1 &
  local jp=$!; for _ in $(seq 100); do [ -f "$d/calls" ] && break; sleep 0.1; done; sleep 0.5
  kill -TERM "$jp"; wait "$jp"
}
# #1 the walltime TERM (--time 0:03:00: inside the window) reaches the batch shell: forwarded to the
# driver, which checkpoints (1 s) before it exits; the chain goes on (no scancel, no .failed)
R5="$P/runs/c1/term"; : > "$SN_STUBLOG"
emit c1/term gpu1 --chain 3 --time 0:03:00 --emit "$R5/job.sh" -- drv/fake.sh ckpt
bgjob "$R5/job.sh" 501 fresh "$BIH"; ok $? 143 term-rc
ok "$(cut -f5 "$R5/summary.tsv")" TERM term-summary
# WO-SN3 #3 the TERM's time since the job started and before the limit: one job-log line, summary field 8
_ts=$(sed -nE 's/^\[sn\] TERM at ([0-9]+) s since the job started, (-?[0-9]+) s before the 180 s limit$/\1 \2/p' "$W/job-501.out")
ok "$(wc -w <<< "$_ts")" 2 term-seconds-log-line
ok "$(cut -f8 "$R5/summary.tsv")" "term_at_s=${_ts% *} left_s=${_ts#* }" term-seconds-summary
ok "$(( ${_ts% *} + ${_ts#* } ))" 180 term-seconds-sum-to-limit
ok "$(cut -f7 "$R5/summary.tsv")" "CERT fake checkpoint=1" term-driver-checkpointed
ok "$(cat "$R5/0/ckpt" 2>/dev/null)" ckpt term-ckpt-file
ok "$(grep -c '^scancel' "$SN_STUBLOG")" 0 term-keeps-successor
ok "$(nsb)" 1 term-successor-queued
ok "$(test -e "$R5/0/.failed" && echo y || echo n)" n term-no-failed
# the grace is bounded: a driver deaf to TERM is killed after SN_GRACE
R5b="$P/runs/c1/deaf"; : > "$SN_STUBLOG"
emit c1/deaf gpu1 --chain 2 --time 0:03:00 --emit "$R5b/job.sh" -- drv/fake.sh deaf
sed -i 's/SN_GRACE=90 /SN_GRACE=2 /' "$R5b/job.sh"
_t0=$SECONDS; bgjob "$R5b/job.sh" 511 fresh "$BIH"; _rc=$?; _dt=$((SECONDS - _t0))
ok "$_rc" 143 deaf-rc; ok "$([ "$_dt" -lt 10 ] && echo y)" y deaf-bounded
ok "$(cut -f5 "$R5b/summary.tsv")" TERM deaf-summary
ok "$(grep -c '^scancel' "$SN_STUBLOG")" 0 deaf-keeps-successor
# a TERM long before the limit is a cancel (scancel by hand): the chain ends, without .failed
R5c="$P/runs/c1/cancel"; : > "$SN_STUBLOG"
emit c1/cancel gpu1 --chain 3 --time 1:00:00 --emit "$R5c/job.sh" -- drv/fake.sh ckpt
bgjob "$R5c/job.sh" 521 fresh "$BIH"
ok "$(cut -f5 "$R5c/summary.tsv")" CANCEL cancel-summary
ok "$(cut -f8 "$R5c/summary.tsv" | grep -cE '^term_at_s=[0-9]+ left_s=3[0-9]{3}$')" 1 cancel-seconds-summary
ok "$(grep -c '^scancel 900001$' "$SN_STUBLOG")" 1 cancel-cancels-successor
ok "$(test -e "$R5c/0/.failed" && echo y || echo n)" n cancel-no-failed
# WO-SN3 #1 a TERM while the successor's sbatch is in flight (accepted, id not yet back; the TERM goes
# to the shell and to sbatch, as a scancel's does): the job learns the id and cancels it -- no orphan
R5d="$P/runs/c1/insubmit"; : > "$SN_STUBLOG"; rm -f "$SN_STUBLOG.sbatch"
emit c1/insubmit gpu1 --chain 3 --time 1:00:00 --emit "$R5d/job.sh" -- drv/fake.sh
SN_STUB_SBATCH_SLOW=2 PATH="$STUB:$PATH" SLURM_JOB_ID=531 bash "$R5d/job.sh" fresh "$BIH" > "$W/job-531.out" 2>&1 &
_jp=$!; for _ in $(seq 100); do [ -s "$SN_STUBLOG.sbatch" ] && break; sleep 0.1; done
kill -TERM "$_jp" "$(cat "$SN_STUBLOG.sbatch")"; wait "$_jp"; ok $? 143 insubmit-rc
ok "$(nsb)" 1 insubmit-one-successor
ok "$(grep -c '^scancel 900001$' "$SN_STUBLOG")" 1 insubmit-cancels-successor
ok "$(test -e "$R5d/0/calls" && echo y || echo n)" n insubmit-no-driver
ok "$(grep -c '^\[sn\] TERM at [0-9]* s since the job started' "$W/job-531.out")" 1 insubmit-term-logged
rm -f "$SN_STUBLOG.sbatch"
# #4 a requeued job refuses: no driver, no successor, .failed says why
R8="$P/runs/c1/requeue"; : > "$SN_STUBLOG"
emit c1/requeue gpu1 --chain 3 --emit "$R8/job.sh" -- drv/fake.sh
( export SLURM_RESTART_COUNT=1; runjob "$R8/job.sh" 801 - fresh "$BIH" ); ok $? 1 requeue-rc
ok "$(test -e "$R8/0/calls" && echo y || echo n)" n requeue-no-driver
ok "$(nsb)" 0 requeue-no-successor
ok "$(grep -c requeued "$R8/0/.failed")" 1 requeue-failed-marker
# #2 no BUILD_INFO, or one rebuilt since the submit: refused before a successor is queued (#6)
runjob "$R8/job.sh" 802 - fresh 0000000000000000; ok $? 1 bihash-mismatch-rc
ok "$(grep -c 'not 0000000000000000 as at submit' "$W/job-802.out")" 1 bihash-mismatch-msg
mv "$B/BUILD_INFO" "$B/BUILD_INFO.x"; runjob "$R8/job.sh" 803 - fresh "$BIH"; ok $? 1 no-buildinfo-rc
mv "$B/BUILD_INFO.x" "$B/BUILD_INFO"
mv "$B/env.sh" "$B/env.x"; runjob "$R8/job.sh" 804 - fresh "$BIH"; ok $? 1 no-env-rc; mv "$B/env.x" "$B/env.sh"
ok "$(nsb)" 0 early-exits-queue-no-successor
ok "$(test -e "$R8/0/calls" && echo y || echo n)" n early-exits-no-driver
no_ runjob "$R8/job.sh" 805 - bogus "$BIH"
# #7 a GPU target whose module is not Cuda: refused, no successor
sed -i 's/^device_modules .*/device_modules peclet_fake_cuda peclet_fake_host/' "$B/BUILD_INFO"; BIH2=$(sha256sum < "$B/BUILD_INFO" | cut -c1-16)
runjob "$R8/job.sh" 806 - fresh "$BIH2"; ok $? 1 gpu-check-rc
ok "$(grep -c 'not Cuda: peclet_fake_host=OpenMP' "$W/job-806.out")" 1 gpu-check-msg
ok "$(nsb)" 0 gpu-check-no-successor
# WO-SN3 #2 an import that hangs (MPI/Kokkos init outside a usable step): bounded, refused, no successor
echo 'import time; time.sleep(60)' > "$PM/peclet_fake_hang.py"
sed -i 's/^device_modules .*/device_modules peclet_fake_hang/' "$B/BUILD_INFO"; BIH3=$(sha256sum < "$B/BUILD_INFO" | cut -c1-16)
R8h="$P/runs/c1/imphang"; : > "$SN_STUBLOG"
emit c1/imphang gpu1 --chain 3 --emit "$R8h/job.sh" -- drv/fake.sh
sed -i 's/^_sn_imp_timeout=120$/_sn_imp_timeout=2/' "$R8h/job.sh"
_t0=$SECONDS; runjob "$R8h/job.sh" 807 - fresh "$BIH3"; _rc=$?; _dt=$((SECONDS - _t0))
ok "$_rc" 1 import-hang-rc; ok "$([ "$_dt" -lt 20 ] && echo y)" y import-hang-bounded
ok "$(grep -c 'GPU import check: no answer from its srun step in 2 s' "$R8h/0/.failed")" 1 import-hang-failed-msg
ok "$(nsb)" 0 import-hang-no-successor
ok "$(test -e "$R8h/0/calls" && echo y || echo n)" n import-hang-no-driver
sed -i 's/^device_modules .*/device_modules peclet_fake_cuda/' "$B/BUILD_INFO"
# #5 .stop: honoured at the start, and one written during the run cancels the successor
R9="$P/runs/c1/stop"; : > "$SN_STUBLOG"
emit c1/stop gpu1 --chain 3 --emit "$R9/job.sh" -- drv/fake.sh stopme
runjob "$R9/job.sh" 901 - fresh "$BIH"; ok $? 0 stop-during-rc
ok "$(grep -c '^scancel 900001$' "$SN_STUBLOG")" 1 stop-during-cancels-successor
runjob "$R9/job.sh" 902 - chain "$BIH" 2
ok "$(grep -c 'stopped by sn cancel' "$W/job-902.out")" 1 stop-at-start
ok "$(cat "$R9/0/calls")" 1 stop-at-start-no-driver
# a driver from an extra repo, named relative to the tree
mkdir -p "$TR/extra/study/perf"; cp "$TR/drv/fake.sh" "$TR/extra/study/perf/run.sh"
R7="$P/runs/c1/extra"
emit c1/extra gpu1 --emit "$R7/job.sh" -- extra/study/perf/run.sh
runjob "$R7/job.sh" 701 - fresh "$BIH"; _t=$?; ok $_t 0 extra-driver-rc
ok "$(cut -f7 "$R7/summary.tsv")" "CERT fake call=1 idx=0" extra-driver-cert
ok "$(grep -c "run: srun .* $TR/extra/study/perf/run.sh" "$W/job-701.out")" 1 extra-driver-resolved
# --no-srun: the driver runs in the batch shell and gets the srun line in SN_SRUN
R6="$P/runs/c1/nosrun"; : > "$SN_STUBLOG"
emit c1/nosrun gpu-mpi --gpus 4 --no-srun --emit "$R6/job.sh" -- drv/fake.sh
runjob "$R6/job.sh" 601 - fresh "$BIH"
ok "$(grep '^srun' "$SN_STUBLOG" | grep -vc 'job-name=sn-import-check')" 0 nosrun-no-srun
ok "$(grep -c 'srun=\[srun --mpi=pmix --ntasks=4 ' "$R6/0/driver-601.log")" 1 nosrun-gets-srun-line

# --- 9. sn cancel: dependents and .stop files (remote.sh against a stub squeue) -------------------
# shellcheck source=remote.sh
source "$KIT/remote.sh"
CP="$W/cproj"; mkdir -p "$CP/runs/x/t1" "$CP/runs/x/arr" "$CP/runs/x-y/t1"
cat > "$W/squeue.txt" <<'EOF'
1001|1001|1001|N/A|sn-x.t1|(null)
1002|1002|1002|N/A|sn-x.t1|afterany:1001(unfulfilled)
1003|1003|1003|N/A|sn-x.t1|afterany:1002(unfulfilled)
2001|2001|2001|N/A|sn-x-y.t1|(null)
2002|2002|2002|N/A|sn-x-y.t1|afterany:2001(unfulfilled)
3005|3000_5|3000|5|sn-x.arr|(null)
3006|3006_5|3006|5|sn-x.arr|afterany:3005(unfulfilled)
4001|4001|4001|N/A|sn-build.x-0123abcd.h100|(null)
4002|4002|4002|N/A|sn-build.x-y-0123abcd.h100|(null)
EOF
squeue() { cat "$W/squeue.txt"; }
scancel() { echo "scancel $*" >> "$W/scancel.log"; }
: > "$W/scancel.log"; snr_cancel "$CP" 1001 >/dev/null
ok "$(cat "$W/scancel.log")" "scancel 1001 1002 1003" cancel-job-with-dependents
ok "$(test -f "$CP/runs/x/t1/0/.stop" && echo y)" y cancel-job-stop-file
: > "$W/scancel.log"; snr_cancel "$CP" 3000_5 >/dev/null
ok "$(cat "$W/scancel.log")" "scancel 3000_5 3006_5" cancel-array-task-with-successor
ok "$(test -f "$CP/runs/x/arr/5/.stop" && echo y)" y cancel-array-task-stop-file
: > "$W/scancel.log"; snr_cancel "$CP" x >/dev/null
ok "$(cat "$W/scancel.log")" "scancel 1001 1002 1003 3000_5 3006_5 4001" cancel-campaign-exact
ok "$(test -f "$CP/runs/x/t1/.stop" && test -f "$CP/runs/x/arr/.stop" && echo y)" y cancel-campaign-stop-files
ok "$(test -e "$CP/runs/x-y/t1/.stop" && echo y || echo n)" n cancel-campaign-not-x-y
echo "SN_BUILD=/b/one" > "$CP/runs/x/t1/job.sh"
ok "$(snr_jobs_using_build "$CP" /b/one)" "sn-x.t1" build-in-use
ok "$(snr_jobs_using_build "$CP" /b/two)" "" build-not-in-use
yes_ snr_name_queued sn-x.t1; no_ snr_name_queued sn-x.t
unset -f squeue scancel

# --- 10. the real submit path, through a stub ssh (no network: "remote" = this host) ---------------
# The toolkit runs from a committed copy (a real submit refuses a dirty one); HOME holds a fake
# decision_desk_verify.py (VERIFIED iff the card file holds exactly the action) and the ledger; ssh
# runs the remote command here with /projects/0/prjs1022/peclet mapped to a fake project.
H="$W/home"; KR="$W/kitrepo"; FP="$W/fproj"; RS="$W/rstub"; LS="$W/lstub"; D="$W/desk"
mkdir -p "$H/.claude/tools" "$KR/tools/hpc" "$RS" "$LS" "$D"
cp "$SN" "$KR/tools/hpc/sn"; cp -r "$KIT" "$KR/tools/hpc/snellius"
git -C "$KR" init -q; git -C "$KR" add tools; git -C "$KR" -c user.email=t@t -c user.name=t commit -q -m kit
KSN="$KR/tools/hpc/sn"
cat > "$H/.claude/tools/decision_desk_verify.py" <<'EOF'
import sys
d, c, a = sys.argv[1], sys.argv[2], sys.argv[4]
try: want = open(f"{d}/{c}").read()
except OSError: print("NO CARD"); sys.exit(1)
print("VERIFIED card " + c) if want == a else (print("MISMATCH"), sys.exit(1))
EOF
cat > "$LS/ssh" <<'EOF'
#!/bin/bash
while [ "${1:-}" = -o ]; do shift 2; done; shift
c="$*"; c="${c//\/projects\/0\/prjs1022\/peclet/$SN_FAKEPROJ}"
PATH="$SN_RSTUB:$PATH" exec bash -c "$c"
EOF
cat > "$RS/sbatch" <<'EOF'
#!/bin/bash
if [[ " $* " == *" --test-only "* ]]; then cat > /dev/null
  echo "sbatch: Job 4242 to start at 2026-11-20T10:00:00 using 16 processors on nodes gcn9 in partition gpu_h100" >&2
  echo "sbatch: This job will be charged for 1 GPUs" >&2; exit 0; fi
echo "sbatch $* | ledger: $(tr '\n' ' ' < "$HOME/.cache/sn/used_cards")" >> "$SN_RLOG"
[ -f "$SN_FAKEPROJ/.sbatch_fail" ] && { echo "sbatch: error: fake failure" >&2; exit 1; }
echo 777
EOF
cat > "$RS/accinfo" <<'EOF'
#!/bin/bash
printf 'Budget name      : L3t\nRemaining budget : 100000.00 SBU\nProducts         : gpu_h100, gpu_a100\n'
printf 'Budget name      : L1t\nRemaining budget : 500.00 SBU\nProducts         : genoa, rome, cbuild\n'
EOF
printf '#!/bin/bash\ncat "$SN_FAKEPROJ/.squeue" 2>/dev/null\n' > "$RS/squeue"
printf '#!/bin/bash\necho "scancel $*" >> "$SN_RLOG"\n' > "$RS/scancel"
chmod +x "$LS"/* "$RS"/*
FB="$FP/build/tr-00000000-h100"; mkdir -p "$FP/src/tr-00000000" "$FB" "$FP/runs"
printf 'umbrella aaaa pin\ncore bbbb pin\nmorton cccc pin\nvoro dddd pin\n' > "$FP/src/tr-00000000/MANIFEST"
echo "MANIFEST x" > "$FB/BUILD_INFO"; FBIH=$(sha256sum < "$FB/BUILD_INFO" | cut -c1-16)
export SN_RLOG="$W/rlog"; : > "$SN_RLOG"
unset SN_HOST SN_PROJ SN_ACCOUNT SN_VERIFY SN_LEDGER
xsn() { env HOME="$H" PATH="$LS:$PATH" SN_FAKEPROJ="$FP" SN_RSTUB="$RS" "$KSN" "$@"; }
card() { local id="$1"; shift; xsn "$1" --print-action "${@:2}" 2>/dev/null > "$D/$id.tmp"; tr -d '\n' < "$D/$id.tmp" > "$D/$id"; }
TH=$(sha256sum < "$KIT/templates/gpu1.tpl" | cut -c1-12)
card c1 run tr-00000000 h100 c9/t1 gpu1 -- d.py
ok "$(cat "$D/c1")" "sn run tr-00000000 h100 c9/t1 gpu1 -- d.py | time 01:00:00, template gpu1@$TH, estimate 192.0 SBU" action-effective-settings
ok "$(wc -l < "$D/c1.tmp")" 1 print-action-one-line
ok "$(xsn run tr-00000000 h100 c9/t1 gpu1 --card c1 --desk "$D" -- d.py 2>&1 | grep -c 'submitted job 777')" 1 real-submit
ok "$(grep -c "^sbatch --parsable $FP/runs/c9/t1/job.sh fresh $FBIH | ledger: c1 \$" "$SN_RLOG")" 1 submit-bihash-and-ledger-first
ok "$(xsn run tr-00000000 h100 c9/t1 gpu1 --card c1 --desk "$D" -- d.py 2>&1 | grep -c 'refused\|already used')" 1 card-once
ok "$(xsn run tr-00000000 h100 c9/t1b gpu1 --card c1 --desk "$D" -- d.py 2>&1 | grep -c 'already used')" 1 card-once-other-action
printf 'sn run tr-00000000 h100 c9/t2 gpu1 -- d.py' > "$D/c2"    # no effective settings: not the card text
ok "$(xsn run tr-00000000 h100 c9/t2 gpu1 --card c2 --desk "$D" -- d.py 2>&1 | grep -c 'not verified')" 1 card-without-settings-refused
# #8 the ledger line is written before the sbatch: a failed submit still spends the card here
card c3 run tr-00000000 h100 c9/t3 gpu1 -- d.py; touch "$FP/.sbatch_fail"
ok "$(xsn run tr-00000000 h100 c9/t3 gpu1 --card c3 --desk "$D" -- d.py 2>&1 | grep -c 'card c3 is spent')" 1 failed-submit-spends-card
ok "$(grep -cx c3 "$H/.cache/sn/used_cards")" 1 ledger-has-failed-card
rm -f "$FP/.sbatch_fail"
# #9 environment overrides and #13 a dirty toolkit are refused on a real submit
card c4 run tr-00000000 h100 c9/t4 gpu1 -- d.py
ok "$(SN_PROJ=/projects/0/prjs1022/peclet xsn run tr-00000000 h100 c9/t4 gpu1 --card c4 --desk "$D" -- d.py 2>&1 | grep -c 'overrides SN_PROJ')" 1 refuse-env-override
ok "$(SN_ACCOUNT=other xsn run tr-00000000 h100 c9/t4 gpu1 --card c4 --desk "$D" -- d.py 2>&1 | grep -c 'overrides SN_ACCOUNT')" 1 refuse-account-override
echo "# local edit" >> "$KR/tools/hpc/snellius/templates/gpu1.tpl"
ok "$(xsn run tr-00000000 h100 c9/t4 gpu1 --card c4 --desk "$D" -- d.py 2>&1 | grep -c 'uncommitted changes')" 1 refuse-dirty-kit
git -C "$KR" checkout -q tools/hpc/snellius/templates/gpu1.tpl
ok "$(xsn run tr-00000000 h100 c9/t4 gpu1 --card c4 --desk "$D" -- d.py 2>&1 | grep -c 'submitted job')" 1 clean-kit-submits
ok "$(grep -c "^# generated by sn (toolkit $(git -C "$KR" rev-parse --short=12 HEAD), template gpu1@$TH)" "$FP/runs/c9/t4/job.sh")" 1 job-records-kit-commit
# #13 --env PYTHONPATH / LD_*: a note in test-only, refused for real
ok "$(xsn run tr-00000000 h100 c9/t5 gpu1 --env PYTHONPATH=/x --test-only -- d.py 2>&1 | grep -c 'would be refused')" 1 env-pythonpath-note
card c5 run tr-00000000 h100 c9/t5 gpu1 --env LD_PRELOAD=/x.so -- d.py
ok "$(xsn run tr-00000000 h100 c9/t5 gpu1 --env LD_PRELOAD=/x.so --card c5 --desk "$D" -- d.py 2>&1 | grep -c 'refused on a real submit')" 1 env-ld-refused
# #3 --resume: refused while jobs of the tag are queued, and with another cases file
printf 'a 1\nb 2\n' > "$W/rc.txt"; card c6 run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --chain 2 -- d.py
xsn run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --chain 2 --card c6 --desk "$D" -- d.py >/dev/null 2>&1
ok "$(cat "$FP/runs/c9/ar/cases.txt")" "$(printf 'a 1\nb 2')" array-cases-uploaded
ok "$(grep -c -- "--array $W/rc.txt@$(sha256sum < "$W/rc.txt" | cut -c1-12) --chain 2 -- d.py | time 01:00:00, template gpu1@$TH, estimate 768.0 SBU" "$D/c6")" 1 action-cases-cli
echo "1|1|1|N/A|sn-c9.ar|(null)" > "$FP/.squeue"
ok "$(xsn run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --resume --test-only -- d.py 2>&1 | grep -c 'note: jobs of c9/ar are queued')" 1 resume-queued-note
card c7 run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --resume -- d.py
ok "$(xsn run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --resume --card c7 --desk "$D" -- d.py 2>&1 | grep -c 'refused')" 1 resume-queued-refused
: > "$FP/.squeue"
printf 'a 1\nc 3\n' > "$W/rc2.txt"
ok "$(xsn run tr-00000000 h100 c9/ar gpu1 --array "$W/rc2.txt" --resume --test-only -- d.py 2>&1 | grep -c 'is not the cases.txt')" 1 resume-other-cases
ok "$(xsn run tr-00000000 h100 c9/ar gpu1 --resume --test-only -- d.py 2>&1 | grep -c 'give the same --array')" 1 resume-array-needs-array
mkdir -p "$FP/runs/c9/ar/0"; touch "$FP/runs/c9/ar/.stop" "$FP/runs/c9/ar/0/.stop"
card c8 run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --resume --chain 3 -- d.py
ok "$(xsn run tr-00000000 h100 c9/ar gpu1 --array "$W/rc.txt" --resume --chain 3 --card c8 --desk "$D" -- d.py 2>&1 | grep -c 'submitted job')" 1 resume-same-cases
ok "$(grep -c "c9/ar/job.sh resume $FBIH " "$SN_RLOG")" 1 resume-positional
ok "$(ls -A "$FP/runs/c9/ar" "$FP/runs/c9/ar/0" | grep -c '^\.stop$')" 0 resume-clears-stop
# #16 build --define: on the card and in the job script; bad defines refused
ok "$(xsn build --print-action tr-00000000 h100 voro --define voro:PECLET_VORO_BUILD_TESTS=ON 2>/dev/null)" "sn build tr-00000000 h100 voro --define voro:PECLET_VORO_BUILD_TESTS=ON | time 03:00:00, where gpu, estimate 576.0 SBU" build-action-define
xsn build tr-00000000 h100 voro --define voro:PECLET_VORO_BUILD_TESTS=ON --emit "$W/b.sh" >/dev/null 2>&1
ok "$(grep -cxF 'SN_DEFINES=(voro:PECLET_VORO_BUILD_TESTS=ON)' "$W/b.sh")" 1 build-job-defines
ok "$(grep -cxF '#SBATCH --job-name=sn-build.tr-00000000.h100' "$W/b.sh")" 1 build-job-name
no_ xsn build tr-00000000 h100 voro --define flow:X=1 --emit "$W/b.sh"
no_ xsn build tr-00000000 h100 voro --define voro:PECLET_VORO_MPI=OFF --emit "$W/b.sh"
no_ xsn build tr-00000000 h100 voro --define "voro:A B=1" --emit "$W/b.sh"
# #2 build: an existing build is refused; --rebuild is refused while a run job uses the build dir
ok "$(xsn build tr-00000000 h100 voro --test-only 2>&1 | grep -c 'is already built')" 1 build-built-note
mkdir -p "$FP/runs/c9/live"; echo "SN_BUILD=$FB" > "$FP/runs/c9/live/job.sh"    # (the stub ssh maps the project path to $FP)
echo "5|5|5|N/A|sn-c9.live|(null)" > "$FP/.squeue"
ok "$(xsn build tr-00000000 h100 voro --rebuild --test-only 2>&1 | grep -c 'job sn-c9.live uses')" 1 rebuild-in-use-note
card c9 build tr-00000000 h100 voro --rebuild
ok "$(xsn build tr-00000000 h100 voro --rebuild --card c9 --desk "$D" 2>&1 | grep -c 'refused')" 1 rebuild-in-use-refused
ok "$(test -f "$FB/BUILD_INFO" && echo y)" y rebuild-refused-keeps-build
: > "$FP/.squeue"
# #5 sn cancel end to end (remote.sh shipped over the stub ssh)
cp "$W/squeue.txt" "$FP/.squeue"; mkdir -p "$FP/runs/x/t1"; : > "$SN_RLOG"
xsn cancel 1001 >/dev/null 2>&1
ok "$(cat "$SN_RLOG")" "scancel 1001 1002 1003" sn-cancel-e2e
: > "$FP/.squeue"

# the walltime test as the shakedown runs it (sn walltime-test's job, its driver and the verdict of
# walltime_test.sh check, pulled through the stub ssh): job 1 TERM -> 5 s checkpoint -> job 2 resumes
FC="$FP/build/tr-00000000-cpu"; mkdir -p "$FC"; cp -r "$B/." "$FC/"; BIHC=$(sha256sum < "$FC/BUILD_INFO" | cut -c1-16)
WR="$FP/runs/wt/w1"; mkdir -p "$WR"; : > "$SN_STUBLOG"
SN_PROJ="$FP" SN_HOST=nohost.invalid "$SN" run tr-00000000 cpu wt/w1 genoa-mpi --ranks 1 --chain 2 --time 0:03:00 \
  --emit "$WR/job.sh" -- bash "$KIT/walltime_driver.sh" >/dev/null 2>&1
PATH="$STUB:$PATH" SLURM_JOB_ID=1101 bash "$WR/job.sh" fresh "$BIHC" > "$W/job-1101.out" 2>&1 &
_jp=$!; for _ in $(seq 100); do grep -qs 'sleeping until TERM' "$WR/0/driver-1101.log" && break; sleep 0.1; done
kill -TERM "$_jp"; wait "$_jp"; ok $? 143 wt-job1-rc
ok "$(grep -c "afterany:1101 $WR/job.sh chain $BIHC 2\$" "$SN_STUBLOG")" 1 wt-job1-successor
runjob "$WR/job.sh" 1102 - chain "$BIHC" 2; ok $? 0 wt-job2-rc
_wv=$(env HOME="$H" PATH="$LS:$PATH" SN_FAKEPROJ="$FP" SN_RSTUB="$RS" "$KR/tools/hpc/snellius/walltime_test.sh" check wt/w1)
ok "$(cut -c1-29 <<< "$_wv")" "walltime_test: PASS job1 TERM" wt-verdict-pass
# WO-SN3 #3 the verdict quotes when the TERM came: since the job started, and before the 180 s limit
_wl=$(cut -f8 "$WR/summary.tsv" | head -n 1); _wa=${_wl#term_at_s=}; _wa=${_wa%% *}; _wb=${_wl##*left_s=}
ok "$(grep -c "TERM at ${_wa} s of the job, ${_wb} s before its 180 s limit (driver: after [0-9]* s" <<< "$_wv")" 1 wt-verdict-term-seconds
rm -f "$WR/0/.done"
ok "$(env HOME="$H" PATH="$LS:$PATH" SN_FAKEPROJ="$FP" SN_RSTUB="$RS" "$KR/tools/hpc/snellius/walltime_test.sh" check wt/w1 | cut -c1-29)" "walltime_test: FAIL; no .done" wt-verdict-fail
ok "$(xsn walltime-test --print-action tr-00000000 2>/dev/null | sed 's/@[0-9a-f]*,/@H,/')" "sn walltime-test tr-00000000 | time 0:03:00, template genoa-mpi@H, estimate 1.6 SBU" wt-action   # the stub says 16 processors; Snellius charges 24 cores: 2.4

# --- 11. the build job's GPU preflight: no nvcc, or a Kokkos without CUDA, fails before any pip ---
BT="$W/bproj"; mkdir -p "$BT/src/tb-00000000/tools/hpc" "$W/nvstub"
printf 'umbrella aaaa pin\nmorton cccc pin\n' > "$BT/src/tb-00000000/MANIFEST"
echo 'echo "[snellius_env] fake"' > "$BT/src/tb-00000000/tools/hpc/snellius_env.sh"
cat > "$BT/src/tb-00000000/tools/bootstrap_deps.sh" <<'EOF'
#!/bin/bash
d="$(dirname "$0")/../extern/install/$1/lib/cmake/Kokkos"; mkdir -p "$d"
echo 'set(Kokkos_DEVICES "OPENMP;SERIAL")' > "$d/KokkosConfigCommon.cmake"
EOF
chmod +x "$BT/src/tb-00000000/tools/bootstrap_deps.sh"
printf '#!/bin/bash\necho "Cuda compilation tools, release 12.6, V12.6.20"\n' > "$W/nvstub/nvcc"; chmod +x "$W/nvstub/nvcc"
SN_PROJ="$BT" xsn build tb-00000000 h100 morton --emit "$W/bj.sh" >/dev/null 2>&1 || echo "exit 99" > "$W/bj.sh"
module() { :; }; export -f module
( PATH=/usr/bin:/bin SLURM_JOB_ID=1 bash "$W/bj.sh" ) > "$W/bj1.out" 2>&1; ok $? 1 build-no-nvcc-rc
ok "$(grep -c 'needs nvcc on PATH' "$W/bj1.out")" 1 build-no-nvcc-msg
( PATH="$W/nvstub:/usr/bin:/bin" SLURM_JOB_ID=2 bash "$W/bj.sh" ) > "$W/bj2.out" 2>&1; ok $? 1 build-host-kokkos-rc
ok "$(grep -c "Kokkos_DEVICES is 'OPENMP;SERIAL' (no CUDA)" "$W/bj2.out")" 1 build-host-kokkos-msg
ok "$(test -e "$BT/build/tb-00000000-h100/.venv" && echo y || echo n)" n build-preflight-before-venv
unset -f module

echo "selftest: $([ $fail = 0 ] && echo PASS || echo FAIL) $pass/$((pass + fail))"
[ $fail = 0 ]
