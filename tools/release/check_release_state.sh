#!/usr/bin/env bash
# Release pre-flight for the peclet family (docs/RELEASE.md §1, §4.2).
#
#   tools/release/check_release_state.sh            # full report (needs network for PyPI + gh)
#   tools/release/check_release_state.sh --offline  # skip PyPI / GitHub queries
#   tools/release/check_release_state.sh --ci       # exit 1 on any version/tag mismatch (for a tag-run CI step)
#
# Reports, per submodule: pyproject version, packaging __version__, Doxyfile PROJECT_NUMBER, last tag,
# commits since that tag, behind/ahead of origin/main, dirty files, worktrees; the PecletDeps pins of
# every consumer; the metapackage pins; the live PyPI versions. Nothing here modifies anything.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OFFLINE=0; CI=0
for a in "$@"; do case "$a" in --offline) OFFLINE=1;; --ci) CI=1;; esac; done
SUBS="core morton flow pnm dem voro coupling"
declare -A DIST=([core]=peclet-core [morton]=peclet-morton [flow]=peclet-flow [pnm]=peclet-pnm [dem]=peclet-dem [voro]=peclet-voro [coupling]=peclet-coupling)
fail=0
say() { printf '%s\n' "$*"; }
bad() { say "  !! $*"; fail=1; }

pyver() { grep -m1 -E '^version\s*=' "$1/pyproject.toml" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/'; }
initver() {  # packaging/<name>_init.py or morton's package __init__
  local f
  for f in "$1"/packaging/*_init.py "$1"/bindings/python/peclet/morton/__init__.py "$1"/python/peclet_coupling/__init__.py; do
    if [ -f "$f" ]; then
      grep -q '_dist_version("' "$f" && { echo "meta"; return; }   # importlib.metadata: cannot drift
      grep -m1 -E '__version__\s*=' "$f" | sed -E 's/.*"([^"]+)".*/\1/' && return
    fi
  done; echo "-"
}
doxver() { local f; for f in "$1"/docs/Doxyfile "$1"/Doxyfile; do [ -f "$f" ] && grep -m1 -E '^PROJECT_NUMBER' "$f" | sed -E 's/.*=\s*//' && return; done; echo "-"; }

say "== peclet release pre-flight  ($(date +%F))  umbrella $(git rev-parse --short HEAD) on $(git branch --show-current)"
say ""
printf '%-9s %-8s %-8s %-8s %-9s %6s %7s %6s %6s %s\n' sub pyproj __ver__ doxygen last-tag since behind ahead dirty worktrees
for s in $SUBS; do
  [ -d "$s/.git" ] || [ -f "$s/.git" ] || { say "$s: missing"; continue; }
  git -C "$s" fetch -q origin 2>/dev/null
  pv=$(pyver "$s"); iv=$(initver "$s"); dv=$(doxver "$s")
  tag=$(git -C "$s" describe --tags --abbrev=0 2>/dev/null || echo "-")
  since=$([ "$tag" != "-" ] && git -C "$s" rev-list --count "$tag..origin/main" || echo "?")
  behind=$(git -C "$s" rev-list --count HEAD..origin/main 2>/dev/null); ahead=$(git -C "$s" rev-list --count origin/main..HEAD 2>/dev/null)
  dirty=$(git -C "$s" status --porcelain | wc -l); wt=$(git -C "$s" worktree list | wc -l)
  printf '%-9s %-8s %-8s %-8s %-9s %6s %7s %6s %6s %s\n' "$s" "$pv" "$iv" "$dv" "$tag" "$since" "$behind" "$ahead" "$dirty" "$wt"
  [ "$iv" != "-" ] && [ "$iv" != "meta" ] && [ "$iv" != "$pv" ] && bad "$s: __version__ $iv != pyproject $pv"
  [ "$dv" != "-" ] && [ "$dv" != "$pv" ] && bad "$s: Doxyfile PROJECT_NUMBER $dv != pyproject $pv"
  [ "$tag" != "-" ] && [ "$tag" != "v$pv" ] && [ "$since" != "0" ] && say "  .. $s: $since commits since $tag (pyproject $pv) -> needs a bump + tag v$pv? or is unchanged"
  [ "$tag" = "v$pv" ] && [ "$since" != "0" ] && bad "$s: pyproject still $pv but $since commits since tag $tag -> bump before tagging"
  [ "${behind:-0}" != "0" ] && bad "$s: checkout is $behind commits BEHIND origin/main (git -C $s pull --ff-only)"
  [ "${ahead:-0}" != "0" ] && bad "$s: checkout is $ahead commits ahead of origin/main (unpushed)"
  [ "$wt" -gt 1 ] && say "  .. $s worktrees: $(git -C "$s" worktree list | awk 'NR>1{print $1" "$3}' | tr '\n' ';')"
  # ensure the umbrella pointer == checkout HEAD
  ptr=$(git ls-tree HEAD "$s" | awk '{print $3}'); head=$(git -C "$s" rev-parse HEAD)
  [ "$ptr" != "$head" ] && bad "$s: umbrella pointer ${ptr:0:7} != checkout HEAD ${head:0:7}"
done
say ""
say "== unmerged branches (per submodule, vs origin/main)"
for s in $SUBS; do
  u=$(git -C "$s" branch --no-merged origin/main 2>/dev/null | grep -v '^\*' | tr -d ' ' | tr '\n' ' ')
  [ -n "$u" ] && say "  $s: $u"
done
say ""
say "== PecletDeps pins (consumers must pin the NEW core/morton tags before their own release)"
for s in flow pnm dem voro coupling; do
  f="$s/cmake/PecletDeps.cmake"; [ -f "$f" ] || continue
  printf '  %-9s core=%s morton=%s kokkos=%s arborx=%s\n' "$s" \
    "$(grep -m1 'set(PECLET_TPX_TAG' "$f" | grep -oE '"[^"]+"' | head -1 | tr -d '"')" \
    "$(grep -m1 'set(PECLET_MORTON_TAG' "$f" | grep -oE '"[^"]+"' | head -1 | tr -d '"')" \
    "$(grep -m1 'set(PECLET_KOKKOS_TAG' "$f" | grep -oE '"[^"]+"' | head -1 | tr -d '"')" \
    "$(grep -m1 'set(PECLET_ARBORX_TAG' "$f" | grep -oE '"[^"]+"' | head -1 | tr -d '"')"
done
say ""
say "== metapackage (umbrella pyproject.toml) version $(pyver .)"
grep -E 'peclet-[a-z]+==' pyproject.toml | sed -E 's/^\s*/  /'
for s in $SUBS; do
  d=${DIST[$s]}; pin=$(grep -oE "$d==[0-9.]+" pyproject.toml | head -1 | cut -d= -f3); pv=$(pyver "$s")
  [ -n "$pin" ] && [ "$pin" != "$pv" ] && say "  .. $d pinned $pin, submodule pyproject says $pv (fine BEFORE the member is published; must match at umbrella tag time)"
done
# CUDA wheel variants: each member's packaging/pyproject-cuda.toml must carry the member's version, and the
# peclet-cu13 metapackage (packaging/pyproject-cu13.toml) must pin the same versions as the CPU one.
for s in flow pnm dem voro; do
  f="$s/packaging/pyproject-cuda.toml"
  [ -f "$f" ] || { bad "$s: packaging/pyproject-cuda.toml missing (no peclet-$s-cu13 wheel)"; continue; }
  cu=$(grep -m1 -E '^version' "$f" | sed -E 's/.*"([^"]+)".*/\1/')
  [ "$cu" != "$(pyver "$s")" ] && bad "$s: pyproject-cuda.toml version $cu != $(pyver "$s")"
done
f="packaging/pyproject-cu13.toml"
if [ -f "$f" ]; then
  say "== peclet-cu13 metapackage ($f) version $(grep -m1 -E '^version' "$f" | sed -E 's/.*"([^"]+)".*/\1/')"
  grep -E 'peclet-[a-z0-9-]+==' "$f" | sed -E 's/^\s*/  /'
  [ "$(grep -m1 -E '^version' "$f" | sed -E 's/.*"([^"]+)".*/\1/')" != "$(pyver .)" ] && bad "peclet-cu13 version != peclet $(pyver .)"
  for d in peclet-morton peclet-flow peclet-pnm peclet-dem peclet-voro peclet-core peclet-coupling; do
    case $d in peclet-morton|peclet-core|peclet-coupling) dc=$d;; *) dc=$d-cu13;; esac
    cpu=$(grep -oE "$d==[0-9.]+" pyproject.toml | head -1 | cut -d= -f3)
    gpu=$(grep -oE "$dc==[0-9.]+" "$f" | head -1 | cut -d= -f3)
    [ -z "$gpu" ] && { bad "peclet-cu13: no pin for $dc"; continue; }
    [ "$cpu" != "$gpu" ] && bad "peclet-cu13 pins $dc==$gpu but peclet pins $d==$cpu"
  done
else
  bad "packaging/pyproject-cu13.toml missing (no peclet-cu13 metapackage)"
fi
say ""
say "== CITATION.cff: $(grep -m1 -E '^version' CITATION.cff | sed 's/version: *//') ($(grep -m1 date-released CITATION.cff | sed 's/date-released: *//'))   CHANGELOG top: $(grep -m1 -E '^## \[' CHANGELOG.md)"
say "== hard-coded image tags in docs: $(grep -ohE 'peclet-(cpu|cuda|hip):[0-9]+\.[0-9]+\.[0-9]+' docs/containers.md containers/README.md containers/submit/*.slurm | sort | uniq -c | tr '\n' ' ')"
if [ "$OFFLINE" = 0 ]; then
  say ""
  say "== live PyPI"
  PY=".venv/bin/python"; [ -x "$PY" ] || PY=python3
  for s in $SUBS; do d=${DIST[$s]}; say "  $d: $($PY -m pip index versions "$d" 2>/dev/null | head -1 | sed -E 's/.*\((.*)\).*/\1/' || echo '?')  (pyproject $(pyver "$s"))"; done
  say "  peclet: $($PY -m pip index versions peclet 2>/dev/null | head -1 | sed -E 's/.*\((.*)\).*/\1/')  (pyproject $(pyver .))"
  for d in peclet-cu13 peclet-flow-cu13 peclet-pnm-cu13 peclet-dem-cu13 peclet-voro-cu13; do
    say "  $d: $($PY -m pip index versions "$d" 2>/dev/null | head -1 | sed -E 's/.*\((.*)\).*/\1/')"
  done
  say ""
  say "== GitHub CI on main (latest run per repo)"
  for s in $SUBS; do
    gh run list -R "computational-chemical-engineering/${DIST[$s]}" -b main -L 3 --json workflowName,conclusion,createdAt \
      --jq '.[]|"  '"$s"' \(.workflowName): \(.conclusion) (\(.createdAt[:10]))"' 2>/dev/null
  done
  gh run list -R computational-chemical-engineering/peclet -L 3 --json workflowName,conclusion,createdAt --jq '.[]|"  umbrella \(.workflowName): \(.conclusion) (\(.createdAt[:10]))"' 2>/dev/null
fi
say ""
say "== untracked scratch in the umbrella (not part of any release):"
git status --porcelain --ignored=no | grep '^??' | sed 's/^/  /'
[ "$CI" = 1 ] && exit $fail
say ""
[ "$fail" = 0 ] && say "pre-flight: no version/tag/pointer mismatches" || say "pre-flight: mismatches flagged with !! above"
exit 0
