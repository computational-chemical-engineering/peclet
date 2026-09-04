#!/bin/bash
# ==========================================================================================
# Site install of a peclet RELEASE on Snellius (docs/RELEASE.md §7): the whole family, from a tag,
# into its own tree + venv, leaving a wheelhouse for other project members.
#
#   sbatch --nodes=1 --gpus-per-node=1 --ntasks-per-node=1 tools/hpc/install_snellius.sh v0.7.0 h100
#   sbatch -p gpu_a100 --gpus-per-node=1 --ntasks-per-node=1  tools/hpc/install_snellius.sh v0.7.0 a100
#   sbatch -p genoa --gpus=0 -c 32                              tools/hpc/install_snellius.sh v0.7.0 cpu
#
# Arguments are POSITIONAL (SURF's sbatch drops leading VAR=x). Products:
#   $PROJ/suite-<tag>/                     the checkout (never the shared campaign tree)
#   $PROJ/suite-<tag>/.venv                venv with the family installed (PECLET_*_MPI=ON)
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
SUITE="$PROJ/suite-$TAG"
WHEELS="$PROJ/wheelhouse/$TAG-$TARGET"

ENVDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$ENVDIR/snellius_env.sh" ] || ENVDIR="$SLURM_SUBMIT_DIR/tools/hpc"
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
