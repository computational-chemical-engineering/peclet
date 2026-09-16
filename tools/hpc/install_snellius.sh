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
git submodule update --init --recursive
echo "== suite $(git describe --tags --always) ; $(git submodule status | awk '{print $2":"substr($1,1,8)}' | tr '\n' ' ')"

# --- 2. venv --------------------------------------------------------------------------------
python3 -c 'import sys; assert sys.version_info[:2]>=(3,10), sys.version'
python3 -m venv --clear .venv
source .venv/bin/activate
pip install -U pip wheel nanobind numpy scipy mpi4py matplotlib scikit-build-core
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
#   A venv has no Python.h: pass the base interpreter's include dir (INCLUDEPY is right from a venv).
PYINC=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("INCLUDEPY"))')
export CMAKE_PREFIX_PATH="$PREFIX"
export CMAKE_ARGS="-DPython_EXECUTABLE=$SUITE/.venv/bin/python -DPython_INCLUDE_DIR=$PYINC -DMPIEXEC_EXECUTABLE=$(which mpirun)"
mkdir -p "$WHEELS"
wheel() {  # <dir> [extra --config-settings ...]
  local d="$1"; shift
  echo "== pip wheel $d $*"
  pip wheel --no-deps --no-build-isolation -w "$WHEELS" "$@" "./$d"
}
wheel morton
wheel core     --config-settings=cmake.define.PECLET_CORE_KOKKOS=ON
wheel flow     --config-settings=cmake.define.PECLET_FLOW_MPI=ON
wheel pnm      --config-settings=cmake.define.PECLET_PNM_MPI=ON
wheel dem      --config-settings=cmake.define.PECLET_DEM_MPI=ON
wheel voro     --config-settings=cmake.define.PECLET_VORO_KOKKOS=ON --config-settings=cmake.define.PECLET_VORO_BUILD_PYTHON=ON --config-settings=cmake.define.PECLET_VORO_MPI=ON
wheel coupling
pip install --no-index --find-links "$WHEELS" peclet-morton peclet-core peclet-flow peclet-pnm peclet-dem peclet-voro peclet-coupling
ls -la "$WHEELS"

# --- 5. import check (backend needs a GPU; on a login node the wheels are still valid) --------
python - <<'PY' || echo "(import check skipped/failed here — run smoke_snellius.slurm on a GPU node)"
import peclet.flow as f, peclet.dem as d, peclet.voro as v, peclet.pnm as p, peclet.morton, peclet.core.mpi
print("flow", f.execution_space, "has_mpi", f.has_mpi)
print("dem", d.execution_space, "| voro", v.execution_space, "| pnm", p.execution_space)
PY
echo "-> tree $SUITE ; venv $SUITE/.venv ; wheelhouse $WHEELS"
echo "-> next: sbatch --nodes=1 --gpus-per-node=4 --ntasks-per-node=4 $SUITE/tools/hpc/smoke_snellius.slurm $TAG $TARGET"
