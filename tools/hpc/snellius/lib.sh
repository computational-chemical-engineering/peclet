# shellcheck shell=bash
# Pure helpers of the `sn` Snellius toolkit (tools/hpc/sn): no ssh, no side effects, so
# selftest.sh can check them on TRS2. Sourced by sn and by selftest.sh. See docs/SNELLIUS.md.

# --- the repos -------------------------------------------------------------------------------
# Submodules in install (= dependency) order. "core" builds two distributions: peclet-halo from
# core/ and the pure-Python peclet-core shell from core/packaging (as install_snellius.sh does).
SN_REPOS=(morton geom core flow pnm dem voro amr coupling)

# Repos whose SOURCE a repo needs in the tree to build: the sibling headers its CMake takes from
# ../core and ../morton (peclet_sibling_include; core's optional ../morton), plus coupling's runtime
# imports of flow and dem. A sibling missing from the tree makes CMake FetchContent the pinned TAG
# from GitHub without an error -- a silently different core -- so push adds these and build refuses
# a tree without them.
sn_build_deps() {
  case "$1" in
    morton) echo "" ;;
    core) echo "morton" ;;
    geom|flow|pnm|dem) echo "core" ;;
    voro|amr) echo "core morton" ;;
    coupling) echo "core flow dem" ;;
    *) return 1 ;;
  esac
}

sn_is_repo() { local r; for r in "${SN_REPOS[@]}"; do [ "$r" = "$1" ] && return 0; done; return 1; }

# Closure of a repo list under sn_build_deps, printed in SN_REPOS order, one line.
sn_closure() {
  local -A want=() ; local r d changed=1
  for r in "$@"; do sn_is_repo "$r" || { echo "sn: unknown repo '$r' (known: ${SN_REPOS[*]})" >&2; return 1; }; want[$r]=1; done
  while [ $changed = 1 ]; do
    changed=0
    for r in "${!want[@]}"; do
      for d in $(sn_build_deps "$r"); do [ -n "${want[$d]:-}" ] || { want[$d]=1; changed=1; }; done
    done
  done
  local out=()
  for r in "${SN_REPOS[@]}"; do [ -n "${want[$r]:-}" ] && out+=("$r"); done
  echo "${out[*]}"
}

# --- Desk action ------------------------------------------------------------------------------
# The canonical action text of a billed command: "sn <subcommand> <args...>", the exact argument
# vector with --card/--desk (and their values) removed, single-spaced. This is the string the
# Decision Desk card must carry and decision_desk_verify.py --action compares. The flags that never
# reach a real submit (--print-action, --test-only, --emit <file>) are dropped too, so
# `sn ... --test-only --print-action` prints the text of the submit it previews. Arguments after
# "--" (the driver's) are kept verbatim.
sn_canonical_action() {
  local out=(sn) skip=0 a verbatim=0
  for a in "$@"; do
    if [ $verbatim = 1 ]; then out+=("$a"); continue; fi   # after "--": the driver's own arguments
    if [ $skip = 1 ]; then skip=0; continue; fi
    case "$a" in
      --) verbatim=1; out+=("$a") ;;
      --card|--desk|--emit) skip=1 ;;
      --card=*|--desk=*|--emit=*|--print-action|--test-only) ;;
      *) out+=("$a") ;;
    esac
  done
  local s="${out[*]}"
  # single-spaced: collapse any whitespace runs an argument carried
  echo "$s" | tr -s '[:space:]' ' ' | sed 's/ $//'
}

# --- cost -------------------------------------------------------------------------------------
# SBU rates per allocated unit-hour. Source (2026-11-19): the `billing=` TRES that sacct reports
# for past jobs of this account, checked against accuse: gpu_h100 job 28537289 billing=768 for
# 4 GPUs (192/GPU-h; 236 s -> 50.3 SBU), gpu_a100 job 28555799 billing=512 for 4 GPUs
# (128/GPU-h; 184 s -> 26.2 SBU), genoa jobs 28535366 (24 cores, billing=24) and 28464076
# (192 cores, billing=192, 449 s -> 23.9 SBU): 1 SBU per core-h. Consistent with the L3 grant
# (357k SBU ~ 1,860 H100 GPU-h). cbuild: assumed 1 SBU per allocated core-h (no job to check).
sn_rate() {  # <partition> -> "<rate> <unit>"
  case "$1" in
    gpu_h100) echo "192 GPU" ;;
    gpu_a100) echo "128 GPU" ;;
    genoa|rome|cbuild|staging|interactive) echo "1 core" ;;
    *) return 1 ;;
  esac
}

# Walltime "[D-]HH:MM:SS" | "HH:MM" (sbatch minutes:seconds is not accepted here) -> hours (float).
sn_hours() {
  local t="$1" d=0
  case "$t" in *-*) d="${t%%-*}"; t="${t#*-}" ;; esac
  awk -v d="$d" -v t="$t" 'BEGIN{n=split(t,a,":"); if(n==3)h=a[1]+a[2]/60+a[3]/3600; else if(n==2)h=a[1]+a[2]/60; else exit 1; printf "%.6f\n", d*24+h}'
}

# Estimate = allocation x rate x walltime x array size x chain cap, in SBU (one decimal).
sn_cost() {  # <alloc units> <rate> <walltime> <array size> <chain cap>
  local h; h=$(sn_hours "$3") || return 1
  awk -v n="$1" -v r="$2" -v h="$h" -v a="$4" -v k="$5" 'BEGIN{printf "%.1f\n", n*r*h*a*k}'
}

# --- manifest ---------------------------------------------------------------------------------
# MANIFEST = sorted "repo sha source" lines. The tree NAME hashes the "repo sha" columns only, so the
# same sources reach the same tree whichever way they were named (pin, ref or worktree).
sn_manifest_hash() {  # MANIFEST text on stdin -> first 8 hex of sha256
  awk 'NF>=2{print $1, $2}' | LC_ALL=C sort | sha256sum | cut -c1-8
}

# Resolve one override "repo=value" to "sha source". value: a git worktree of that repo (absolute,
# relative to $PWD, or relative to the submodule dir $suite/<repo>, so `voro=../voro-x` works from
# either place) -> its HEAD, refused if dirty (untracked files ignored); else a commit-ish in the
# submodule's own repo -> "ref:<value>".
sn_resolve() {  # <suite> <repo> <value>
  local suite="$1" repo="$2" val="$3" dir="" base cand
  if [ "$repo" = umbrella ]; then base="$suite"; else base="$suite/$repo"; fi
  for cand in "$val" "$base/$val"; do
    case "$cand" in /*) ;; *) cand="$PWD/$cand" ;; esac
    if [ -d "$cand" ] && git -C "$cand" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      dir="$(cd "$cand" && git rev-parse --show-toplevel)"; break
    fi
  done
  if [ -n "$dir" ]; then
    local u1 u2
    u1=$(git -C "$dir" config --get remote.origin.url || true)
    u2=$(git -C "$base" config --get remote.origin.url || true)
    if [ -n "$u1" ] && [ -n "$u2" ] && [ "${u1%.git}" != "${u2%.git}" ]; then
      echo "sn: $repo=$val: $dir is a checkout of $u1, not of $repo ($u2)" >&2; return 1
    fi
    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
      echo "sn: $repo=$val: $dir is dirty (commit or stash first; untracked files are ignored)" >&2; return 1
    fi
    echo "$(git -C "$dir" rev-parse HEAD) worktree:$dir"
    return 0
  fi
  local sha
  sha=$(git -C "$base" rev-parse --verify -q "$val^{commit}") \
    || { echo "sn: $repo=$val: neither a worktree of $repo nor a commit in $base" >&2; return 1; }
  echo "$sha ref:$val"
}

# Names: campaigns, tags and trees are path components on Snellius and job-name parts.
sn_valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
