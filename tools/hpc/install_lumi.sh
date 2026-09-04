#!/bin/bash
# ==========================================================================================
# Site install of a peclet RELEASE on LUMI-G — UNTESTED (docs/LUMI.md). Mirrors install_snellius.sh.
#
#   sbatch -p dev-g --gpus-per-node=1 --ntasks-per-node=1 -t 2:00:00 tools/hpc/install_lumi.sh v0.7.0
#
# Known blocker: the HIP link of the nanobind modules fails ("undefined hidden symbol: vtable for
# Kokkos::Impl::SharedAllocationRecord<HIPSpace...>") — see docs/LUMI.md §4 for the experiments.
# Products (on success): $PROJ/suite-<tag>/.venv and $PROJ/wheelhouse/<tag>-lumi-hip/
# ==========================================================================================
#SBATCH --job-name=peclet-install-lumi
#SBATCH --partition=dev-g
#SBATCH --gpus-per-node=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=02:00:00
#SBATCH --output=peclet-install-%j.out
#SBATCH --account=project_46XXXXXXX
set -euo pipefail
TAG="${1:?usage: install_lumi.sh <tag>}"
PROJ="${PROJ:-/project/${SLURM_JOB_ACCOUNT:-project_46XXXXXXX}/peclet}"
SUITE="$PROJ/suite-$TAG"; WHEELS="$PROJ/wheelhouse/$TAG-lumi-hip"

module load LUMI/24.03 partition/G
module load PrgEnv-gnu craype-accel-amd-gfx90a rocm cray-python
export MPICH_GPU_SUPPORT_ENABLED=1 CXX=hipcc
echo "[lumi_env] $(module -t list 2>&1 | grep -iE 'LUMI|rocm|cray-mpich|cray-python|PrgEnv' | tr '\n' ' ')"

git config --global url."https://github.com/".insteadOf "git@github.com:"
[ -d "$SUITE/.git" ] || git clone --branch "$TAG" --recurse-submodules https://github.com/computational-chemical-engineering/peclet.git "$SUITE"
cd "$SUITE"; git submodule update --init --recursive

# venv inherits cray-python's mpi4py (built against Cray-MPICH) via --system-site-packages
python3 -m venv --clear --system-site-packages .venv
source .venv/bin/activate
pip install -U pip wheel nanobind numpy scipy matplotlib scikit-build-core
python -c "from mpi4py import MPI; print('mpi4py:', MPI.Get_library_version().splitlines()[0])"

rm -rf extern/build/lumi-hip extern/install/lumi-hip
KOKKOS_ARCH=AMD_GFX90A CXX=hipcc tools/bootstrap_deps.sh lumi-hip
PREFIX="$SUITE/extern/install/lumi-hip"

PYINC=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("INCLUDEPY"))')
export CMAKE_PREFIX_PATH="$PREFIX"
export CMAKE_ARGS="-DPython_EXECUTABLE=$SUITE/.venv/bin/python -DPython_INCLUDE_DIR=$PYINC -DMPIEXEC_EXECUTABLE=$(which srun) -DCMAKE_CXX_COMPILER=hipcc"
mkdir -p "$WHEELS"
wheel() { local d="$1"; shift; echo "== pip wheel $d $*"; pip wheel --no-deps --no-build-isolation -w "$WHEELS" "$@" "./$d"; }
wheel morton
wheel core     --config-settings=cmake.define.PECLET_CORE_KOKKOS=ON
wheel flow     --config-settings=cmake.define.PECLET_FLOW_MPI=ON      # <- the link error shows up here first
wheel pnm      --config-settings=cmake.define.PECLET_PNM_MPI=ON
wheel dem      --config-settings=cmake.define.PECLET_DEM_MPI=ON
wheel voro     --config-settings=cmake.define.PECLET_VORO_KOKKOS=ON --config-settings=cmake.define.PECLET_VORO_BUILD_PYTHON=ON --config-settings=cmake.define.PECLET_VORO_MPI=ON
wheel coupling
pip install --no-index --find-links "$WHEELS" peclet-morton peclet-core peclet-flow peclet-pnm peclet-dem peclet-voro peclet-coupling
ROCR_VISIBLE_DEVICES=0 python - <<'PY'
import peclet.flow as f, peclet.dem as d, peclet.voro as v
print("flow", f.execution_space, "has_mpi", f.has_mpi, "| dem", d.execution_space, "| voro", v.execution_space)
assert f.execution_space == "HIP"
PY
echo "-> tree $SUITE ; wheelhouse $WHEELS"
