#!/bin/bash
# Local selftest of the sn toolkit -- no ssh, nothing billed. Run on TRS2:
#   tools/hpc/snellius/selftest.sh            -> one line "selftest: PASS n/n" (exit 0) or the failures
# Checks: Desk action canonicalization, cost arithmetic, manifest hashing and override resolution
# (same inputs -> same tree name; a dirty worktree is refused), dependency closure, the templates'
# resource arithmetic, the billed-command refusals, and a generated job script run end to end with a
# fake SLURM (SLURM_* set, srun/sbatch/scancel stubs): summary.tsv lines, array cases, the chain
# (successor queued, stopped and cancelled on .done, cap respected) and a walltime TERM.
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
ok "$(SN_HOST=nohost.invalid "$SN" build m7-x h100 voro --card c9 --desk /d --print-action)" "sn build m7-x h100 voro" action-cli

# --- 2. cost ----------------------------------------------------------------------------------
ok "$(sn_cost 1 192 03:00:00 1 1)" "576.0" cost-build-h100
ok "$(sn_cost 4 192 00:20:00 1 1)" "256.0" cost-smoke-4gpu
ok "$(sn_cost 1 192 01:00:00 10 4)" "7680.0" cost-array-chain
ok "$(sn_cost 48 1 03:00:00 1 1)" "144.0" cost-genoa-build
ok "$(sn_cost 4 128 1-00:00:00 1 1)" "12288.0" cost-days
ok "$(sn_rate gpu_a100)" "128 GPU" rate-a100
no_ sn_hours "90"

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
ok "$(SN_HOST=nohost.invalid "$SN" run t h100 c/t gpu1 --array "$CF" --print-action -- d.py)" "sn run t h100 c/t gpu1 --array $CF@$ch -- d.py" action-cases-cli
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

# --- 7. billed commands refuse without a card (before any ssh: the host does not resolve) ------
export SN_HOST=nohost.invalid
no_ "$SN" build m7-x h100
no_ "$SN" run m7-x h100 c/t gpu1 -- d.py
no_ "$SN" smoke m7-x h100
no_ "$SN" check-gpu-aware m7-x h100
ok "$("$SN" build m7-x h100 2>&1 | grep -c 'needs --card')" 1 refuse-message

# --- 8. a generated job script, run locally under a fake SLURM -------------------------------------
P="$W/proj"; TR="$P/src/fake-00000000"; B="$P/build/fake-00000000-h100"; STUB="$W/stub"
mkdir -p "$TR/drv" "$B/.venv/bin" "$STUB"
: > "$B/env.sh"; : > "$B/.venv/bin/activate"
echo "MANIFEST umbrella:aaaaaaaaaaaa core:bbbbbbbbbbbb (fake-00000000)" > "$B/BUILD_INFO"
cat > "$TR/drv/fake.sh" <<'EOF'
#!/bin/bash
# fake driver: args echo, CERT line; with "finish-after N" writes .done on its N-th call; "hang" sleeps
n=$(( $(cat calls 2>/dev/null || echo 0) + 1 )); echo $n > calls
echo "args: $* fresh=$SN_FRESH idx=$SN_IDX case=[$SN_CASE] srun=[$SN_SRUN]"
[ "${1:-}" = hang ] && { sleep 30; exit 0; }
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
echo "sbatch $*" >> "$SN_STUBLOG"; echo "sbatch: Single-node jobs run on a shared node by default." >&2
echo $(( 900000 + $(grep -c '^sbatch' "$SN_STUBLOG") ))
EOF
cat > "$STUB/scancel" <<'EOF'
#!/bin/bash
echo "scancel $*" >> "$SN_STUBLOG"
EOF
chmod +x "$STUB"/*
export SN_STUBLOG="$W/stub.log"; : > "$SN_STUBLOG"
runjob() {  # <job.sh> <mode> <jobid> [array idx]
  ( export PATH="$STUB:$PATH" SLURM_JOB_ID="$3"; [ -n "${4:-}" ] && export SLURM_ARRAY_TASK_ID="$4"
    bash "$1" "$2" ) > "$W/job-$3.out" 2>&1
}
R="$P/runs/c1/chain"; mkdir -p "$R"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/chain gpu1 --chain 3 --emit "$R/job.sh" -- drv/fake.sh finish-after 2 >/dev/null
runjob "$R/job.sh" fresh 101; ok $? 0 job1-rc
ok "$(wc -l < "$R/summary.tsv")" 1 job1-summary
ok "$(cut -f1,2,3,4,5 "$R/summary.tsv")" "$(printf '101\t0\tfake-00000000\th100\t0')" job1-summary-fields
ok "$(cut -f7 "$R/summary.tsv")" "CERT fake call=1 idx=0" job1-cert
ok "$(grep -c 'dependency=afterany:101' "$SN_STUBLOG")" 1 job1-successor
ok "$(grep -c '^srun --mpi=pmix --ntasks=1' "$SN_STUBLOG")" 1 job1-srun-line
ok "$(grep -c 'fresh=1' "$R/0/driver-101.log")" 1 job1-fresh
ok "$(grep -c 'MANIFEST umbrella:' "$W/job-101.out")" 1 job1-prints-manifest
runjob "$R/job.sh" resume 102; ok $? 0 job2-rc
ok "$(grep -c 'fresh=0' "$R/0/driver-102.log")" 1 job2-not-fresh
ok "$(test -f "$R/0/.done" && echo y)" y job2-done
ok "$(grep -c '^scancel 900002$' "$SN_STUBLOG")" 1 job2-cancels-successor
runjob "$R/job.sh" resume 103; ok $? 0 job3-rc
ok "$(wc -l < "$R/summary.tsv")" 2 job3-no-run-after-done
ok "$(grep -c 'nothing to run' "$W/job-103.out")" 1 job3-stops-on-done
# the cap: chain 2, a driver that never finishes -> job 2 queues no successor
R2="$P/runs/c1/cap"; mkdir -p "$R2"; : > "$SN_STUBLOG"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/cap gpu1 --chain 2 --emit "$R2/job.sh" -- drv/fake.sh >/dev/null
runjob "$R2/job.sh" fresh 201; runjob "$R2/job.sh" resume 202
ok "$(grep -c '^sbatch' "$SN_STUBLOG")" 1 cap-one-successor
ok "$(grep -c 'the cap; no successor' "$W/job-202.out")" 1 cap-message
# a crash cancels the successor and leaves .failed
R3="$P/runs/c1/crash"; mkdir -p "$R3"; : > "$SN_STUBLOG"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/crash gpu1 --chain 5 --emit "$R3/job.sh" -- drv/fake.sh fail >/dev/null
runjob "$R3/job.sh" fresh 301; ok $? 7 crash-rc
ok "$(grep -c '^scancel ' "$SN_STUBLOG")" 1 crash-cancels-successor
ok "$(test -f "$R3/0/.failed" && echo y)" y crash-failed-marker
# an array: case lines become the driver's trailing args, one summary line per index
R4="$P/runs/c1/arr"; mkdir -p "$R4"; printf '# comment\nalpha 1\n\nbeta 2\n' > "$W/cases.txt"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/arr gpu1 --array "$W/cases.txt" --emit "$R4/job.sh" -- drv/fake.sh >/dev/null
ok "$(grep -c '^#SBATCH --array=0-1$' "$R4/job.sh")" 1 array-header
runjob "$R4/job.sh" fresh 401 0; runjob "$R4/job.sh" fresh 402 1
ok "$(wc -l < "$R4/summary.tsv")" 2 array-summary
ok "$(grep -c 'case=\[beta 2\]' "$R4/1/driver-402.log")" 1 array-case-args
ok "$(grep -c '^args: beta 2 ' "$R4/1/driver-402.log")" 1 array-case-argv
# a walltime TERM still writes its summary line
R5="$P/runs/c1/term"; mkdir -p "$R5"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/term gpu1 --emit "$R5/job.sh" -- drv/fake.sh hang >/dev/null
PATH="$STUB:$PATH" SLURM_JOB_ID=501 bash "$R5/job.sh" fresh > "$W/job-501.out" 2>&1 &
jp=$!; for _ in $(seq 50); do [ -f "$R5/0/calls" ] && break; sleep 0.1; done; sleep 0.3
kill -TERM "$jp"; wait "$jp"; _t=$?; ok $_t 143 term-rc
ok "$(cut -f5 "$R5/summary.tsv")" TERM term-summary
# a driver from an extra repo, named relative to the tree
mkdir -p "$TR/extra/study/perf"; cp "$TR/drv/fake.sh" "$TR/extra/study/perf/run.sh"
R7="$P/runs/c1/extra"; mkdir -p "$R7"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/extra gpu1 --emit "$R7/job.sh" -- extra/study/perf/run.sh >/dev/null
runjob "$R7/job.sh" fresh 701; _t=$?; ok $_t 0 extra-driver-rc
ok "$(cut -f7 "$R7/summary.tsv")" "CERT fake call=1 idx=0" extra-driver-cert
ok "$(grep -c "run: srun .* $TR/extra/study/perf/run.sh" "$W/job-701.out")" 1 extra-driver-resolved
# --no-srun: the driver runs in the batch shell and gets the srun line in SN_SRUN
R6="$P/runs/c1/nosrun"; mkdir -p "$R6"; : > "$SN_STUBLOG"
SN_PROJ="$P" "$SN" run fake-00000000 h100 c1/nosrun gpu-mpi --gpus 4 --no-srun --emit "$R6/job.sh" -- drv/fake.sh >/dev/null
runjob "$R6/job.sh" fresh 601
ok "$(grep -c '^srun' "$SN_STUBLOG")" 0 nosrun-no-srun
ok "$(grep -c 'srun=\[srun --mpi=pmix --ntasks=4 ' "$R6/0/driver-601.log")" 1 nosrun-gets-srun-line

echo "selftest: $([ $fail = 0 ] && echo PASS || echo FAIL) $pass/$((pass + fail))"
[ $fail = 0 ]
