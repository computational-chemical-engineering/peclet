#!/bin/bash
# ==========================================================================================
# Site install of a peclet RELEASE on Snellius (docs/RELEASE.md §7): the whole family, from a tag,
# into its own tree + venv, leaving a wheelhouse for other project members.
#
# Submit from INSIDE a tree that carries tools/hpc (see ENVDIR below); each backend gets its OWN
# tree, so the three may run concurrently:
#   cd $PROJ/suite-v0.7.0
#   sbatch --nodes=1 --gpus-per-node=1 --ntasks-per-node=1      tools/hpc/install_snellius.sh v0.7.0 h100
#   sbatch -p gpu_a100 --nodes=1 --gpus-per-node=1 --ntasks-per-node=1 tools/hpc/install_snellius.sh v0.7.0 a100
#   sbatch -p genoa --gpus-per-node=0 --ntasks=1 --cpus-per-task=32    tools/hpc/install_snellius.sh v0.7.0 cpu
# (`--gpus=0` does NOT override the #SBATCH --gpus-per-node=1 below on a GPU-less partition; the
#  submission is rejected with "Requested node configuration is not available".)
#
# Arguments are POSITIONAL (SURF's sbatch drops leading VAR=x). Products:
#   $PROJ/suite-<tag>-<backend>/           the checkout (never the shared campaign tree)
#   $PROJ/suite-<tag>-<backend>/.venv      venv with the family installed (PECLET_*_MPI=ON)
#   $PROJ/wheelhouse/<tag>-<backend>/      site-specific wheels: pip install --no-index --find-links
# Wheels built here link the module OpenMPI + CUDA 12.6 + sm_80/90 — NEVER upload them to PyPI.
#
# Ancestor: peclet-examples/examples/wall-bounded-turbulence/install_snellius.sh (validated for flow
# only). This family-wide version is NEW — first run is part of the release checklist, and the
# smoke job (smoke_snellius.slurm) is what certifies it.
# ==========================================================================================
#SBATCH --job-name=peclet-install
#SBATCH --partition=gpu_h100
#SBATCH --gpus-per-node=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=03:00:00
#SBATCH --output=peclet-install-%j.out
#SBATCH --account=tes24005
set -euo pipefail
TAG="${1:?usage: install_snellius.sh <tag> <h100|a100|cpu>}"
TARGET="${2:-h100}"
PROJ="${PROJ:-/projects/0/prjs1022/peclet}"
# ONE TREE PER BACKEND. h100 and a100 both build the `nvidia-cuda` prefix but at different arch
# (HOPPER90 vs AMPERE80), and step 2 does `venv --clear` on $SUITE/.venv while step 3 does
# `rm -rf extern/install/$BACKEND` -- so two backends sharing a tree destroy each other's install,
# concurrently OR sequentially (last one wins). Measured 2026-09-16 on the first real run of this
# script: three backends submitted together, two died on a half-built venv
# ("Permission denied: .../.venv/bin/activate.csh") and the survivor would have left a tree whose
# venv matched only itself.
SUITE="$PROJ/suite-$TAG-$TARGET"
WHEELS="$PROJ/wheelhouse/$TAG-$TARGET"

# sbatch copies the script to /var/spool/slurm/..., so $BASH_SOURCE is NOT in the repo and the
# $SLURM_SUBMIT_DIR fallback is what actually resolves -- which means you must submit from INSIDE a
# tree that has tools/hpc/. Submitting from its parent (as RELEASE.md used to say) silently resolved
# to $PROJ/tools/hpc and died with a bare "No such file or directory" (measured 2026-09-16).
ENVDIR=""
for _c in "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" \
          "${SLURM_SUBMIT_DIR:-}/tools/hpc" "${SLURM_SUBMIT_DIR:-}"; do
  [ -n "$_c" ] && [ -f "$_c/snellius_env.sh" ] && { ENVDIR="$_c"; break; }
done
if [ -z "$ENVDIR" ]; then
  echo "FATAL: snellius_env.sh not found. Tried the script dir, \$SLURM_SUBMIT_DIR/tools/hpc" >&2
  echo "       and \$SLURM_SUBMIT_DIR (= '${SLURM_SUBMIT_DIR:-unset}')." >&2
  echo "       Submit from INSIDE the release tree:  cd \$PROJ/suite-<tag> && sbatch tools/hpc/install_snellius.sh <tag> <target>" >&2
  exit 1
fi
source "$ENVDIR/snellius_env.sh"

# --- 1. checkout at the tag (HTTPS: compute nodes have no GitHub key) ------------------------
git config --global url."https://github.com/".insteadOf "git@github.com:"
if [ ! -d "$SUITE/.git" ]; then
  git clone --branch "$TAG" --recurse-submodules https://github.com/computational-chemical-engineering/peclet.git "$SUITE"
fi
cd "$SUITE"
# A tree left by an earlier run may sit at another commit: put it ON the tag, then sync + init so
# submodules added since that clone (geom and amr, family 1.2.0+) are registered and checked out too.
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git fetch --tags origin
git -c advice.detachedHead=false checkout --quiet "$TAG"
git submodule sync --recursive
git submodule update --init --recursive
for _s in morton geom core flow pnm dem voro amr coupling; do
  [ -f "$_s/pyproject.toml" ] || { echo "FATAL: submodule $_s not checked out at $TAG" >&2; exit 1; }
done
echo "== suite $(git describe --tags --always) ; $(git submodule status | awk '{print $2":"substr($1,1,8)}' | tr '\n' ' ')"

# --- 2. venv --------------------------------------------------------------------------------
python3 -c 'import sys; assert sys.version_info[:2]>=(3,10), sys.version'
python3 -m venv --clear .venv
source .venv/bin/activate
pip install -U pip wheel nanobind numpy scipy mpi4py matplotlib scikit-build-core hatchling
[ "$TARGET" = cpu ] || pip install cupy-cuda12x

# --- 3. Kokkos (+ArborX) prefix for the backend ---------------------------------------------
case "$TARGET" in
  h100) BACKEND=nvidia-cuda; KA=HOPPER90; CA=90 ;;
  a100) BACKEND=nvidia-cuda; KA=AMPERE80; CA=80 ;;
  cpu)  BACKEND=host-openmp; KA=; CA= ;;
  *) echo "usage: $0 <tag> [h100|a100|cpu]"; exit 1 ;;
esac
rm -rf "extern/build/$BACKEND" "extern/install/$BACKEND"      # a release tree starts clean
if [ "$BACKEND" = nvidia-cuda ]; then
  KOKKOS_ARCH=$KA CUDA_ARCH=$CA CUDA_COMPILER=$(which nvcc) tools/bootstrap_deps.sh nvidia-cuda
else
  tools/bootstrap_deps.sh host-openmp
fi
PREFIX="$SUITE/extern/install/$BACKEND"

# --- 4. build wheels for the family, in dependency order, then install them -----------------
# The distributions since family 1.2.0 (docs/CORE_BOUNDARY.md): core's pyproject.toml builds
# peclet-halo (peclet.halo, host-only MPI, no Kokkos); peclet-core is only a pure-Python
# compatibility shell over peclet.geom + peclet.halo (warns since core 1.3.1, gone in 2.0.0); geom
# (peclet-geom) needs neither Kokkos nor MPI; amr (peclet-amr) always links MPI + Kokkos -- it has
# no switch for either, so it takes no define here.
#   A venv has no Python.h: pass the base interpreter's include dir (INCLUDEPY is right from a venv).
PYINC=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("INCLUDEPY"))')
export CMAKE_PREFIX_PATH="$PREFIX"
export CMAKE_ARGS="-DPython_EXECUTABLE=$SUITE/.venv/bin/python -DPython_INCLUDE_DIR=$PYINC -DMPIEXEC_EXECUTABLE=$(which mpirun)"
mkdir -p "$WHEELS"
wheel() {  # <dir> [extra --config-settings ...]
  local d="$1"; shift
  echo "== pip wheel $d $*"
  pip wheel --no-deps --no-build-isolation -w "$WHEELS" "$@" "$d"
}
wheel ./morton
wheel ./geom
wheel ./core                                                  # -> peclet-halo
# The peclet-core shell is core/packaging/pyproject-core.toml copied over pyproject.toml (the pattern
# of core/.github/workflows/release.yml). Copy into a STAGING dir, never in the tree: a run that died
# between the copy and a restore would build the shell under ./core's name on every rerun.
CORE_SHELL=$(mktemp -d)
cp -r core/packaging core/README.md core/LICENSE "$CORE_SHELL/"
cp core/packaging/pyproject-core.toml "$CORE_SHELL/pyproject.toml"
wheel "$CORE_SHELL"                                           # -> peclet-core (pure Python)
rm -rf "$CORE_SHELL"
wheel ./flow     --config-settings=cmake.define.PECLET_FLOW_MPI=ON
wheel ./pnm      --config-settings=cmake.define.PECLET_PNM_MPI=ON
wheel ./dem      --config-settings=cmake.define.PECLET_DEM_MPI=ON
wheel ./voro     --config-settings=cmake.define.PECLET_VORO_KOKKOS=ON --config-settings=cmake.define.PECLET_VORO_BUILD_PYTHON=ON --config-settings=cmake.define.PECLET_VORO_MPI=ON
wheel ./amr
wheel ./coupling
pip install --no-index --find-links "$WHEELS" peclet-morton peclet-geom peclet-halo peclet-core \
    peclet-flow peclet-pnm peclet-dem peclet-voro peclet-amr peclet-coupling
ls -la "$WHEELS"

# --- 5. import check: every package by its CANONICAL module, never peclet.core.* -------------------
#   DeprecationWarning is an error, so a caller still on a retired spelling (e.g. one that reaches
#   the peclet.core shell) fails HERE rather than in a user's run. The job runs on a node of the
#   target backend; a failure leaves the wheelhouse intact but fails the job.
IMPORT_OK=1
python -W "error:peclet.core:DeprecationWarning" - <<'PY' || IMPORT_OK=0
import sys
import peclet.morton, peclet.geom, peclet.halo, peclet.amr, peclet.coupling
import peclet.flow as f, peclet.dem as d, peclet.voro as v, peclet.pnm as p
shell = sorted(m for m in sys.modules if m == "peclet.core" or m.startswith("peclet.core."))
assert not shell, f"a canonical module imported the retired peclet.core shell: {shell}"
print("flow", f.execution_space, "has_mpi", f.has_mpi)
print("dem", d.execution_space, "| voro", v.execution_space, "| pnm", p.execution_space)
print("imported: peclet.{morton,geom,halo,flow,pnm,dem,voro,amr,coupling}")
PY
echo "-> tree $SUITE ; venv $SUITE/.venv ; wheelhouse $WHEELS"
if [ "$IMPORT_OK" != 1 ]; then
  echo "FAILED: import check (canonical modules; a peclet.core import is an error) -- see above" >&2
  exit 1
fi
echo "-> next: sbatch --nodes=1 --gpus-per-node=4 --ntasks-per-node=4 $SUITE/tools/hpc/smoke_snellius.slurm $TAG $TARGET"
