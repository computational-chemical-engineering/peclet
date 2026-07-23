#!/usr/bin/env bash
# bootstrap_deps.sh — build & install the suite's pinned Kokkos + ArborX into a
# local per-backend prefix, so every repo can consume them via find_package.
# This is the local-dev stand-in for a cluster `module load`.
#
# Usage:
#   tools/bootstrap_deps.sh <nvidia-cuda|host-openmp|host-serial|lumi-hip>
#
# Installs to:  extern/install/<backend>
# Sources in:   extern/src/{kokkos,arborx}   (cloned at the pinned tags)
#
# The matching CMake preset (CMakePresets.json) puts extern/install/<backend> on
# CMAKE_PREFIX_PATH, so `cmake --preset <backend>` then finds these.
set -euo pipefail

BACKEND="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned versions are kept in lockstep with cmake/Suite*.cmake.
KOKKOS_TAG="5.1.1"
ARBORX_TAG="v2.1"

PREFIX="$ROOT/extern/install/$BACKEND"
SRC="$ROOT/extern/src"
JOBS="$(nproc)"

common_args=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_CXX_STANDARD=20
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_PREFIX_PATH="$PREFIX"
  # PIC so the (static) Kokkos can be linked into shared objects, e.g. the
  # pybind11 Python modules (demgpu_kokkos / sdflow).
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)

# GPU architecture is target-specific. Defaults match the local dev box (RTX 5080 = Blackwell sm_120,
# AMD MI250X = gfx90a); override via env for other hardware — e.g. on Snellius:
#   KOKKOS_ARCH=AMPERE80 CUDA_ARCH=80 tools/bootstrap_deps.sh nvidia-cuda   # A100
#   KOKKOS_ARCH=HOPPER90 CUDA_ARCH=90 tools/bootstrap_deps.sh nvidia-cuda   # H100
# On LUMI the gfx90a default already matches the MI250X.
KOKKOS_ARCH="${KOKKOS_ARCH:-}"               # Kokkos arch flag suffix: AMPERE80 / HOPPER90 / AMD_GFX90A / ...
CUDA_ARCH="${CUDA_ARCH:-}"                    # CMAKE_CUDA_ARCHITECTURES: 80 / 90 / ...
CUDA_COMPILER="${CUDA_COMPILER:-/usr/local/cuda/bin/nvcc}"

case "$BACKEND" in
  nvidia-cuda)
    kokkos_args=(
      -DKokkos_ENABLE_CUDA=ON -DKokkos_ENABLE_SERIAL=ON
      # --expt-relaxed-constexpr on the Kokkos interface: device code may call constexpr host
      # functions (std::array::operator[] etc.). REQUIRED by core's AMR device assembly (the
      # morton encode/decode on device); without it nvcc only WARNS (#20013/#20015) and the
      # device call yields garbage (returns 0) — a silent-corruption failure mode.
      -DKokkos_ENABLE_CUDA_CONSTEXPR=ON
      "-DKokkos_ARCH_${KOKKOS_ARCH:-BLACKWELL120}=ON"
      -DCMAKE_CUDA_COMPILER="$CUDA_COMPILER"
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH:-120}"
    )
    ;;
  host-openmp)
    kokkos_args=( -DKokkos_ENABLE_OPENMP=ON -DKokkos_ENABLE_SERIAL=ON )
    ;;
  host-serial)
    # Serial-only: Kokkos::Serial is the DefaultExecutionSpace (no OpenMP), so it is the
    # single-thread device baseline — Kokkos-overhead vs raw serial C++, and the reference
    # the OpenMP/CUDA backends are measured against.
    kokkos_args=( -DKokkos_ENABLE_SERIAL=ON )
    ;;
  lumi-hip)
    kokkos_args=(
      -DKokkos_ENABLE_HIP=ON -DKokkos_ENABLE_SERIAL=ON
      "-DKokkos_ARCH_${KOKKOS_ARCH:-AMD_GFX90A}=ON"
      -DCMAKE_CXX_COMPILER="${CXX:-hipcc}"
    )
    ;;
  *)
    echo "usage: $0 <nvidia-cuda|host-openmp|host-serial|lumi-hip>" >&2
    exit 2
    ;;
esac

echo "==> bootstrap deps for backend '$BACKEND' -> $PREFIX"
mkdir -p "$SRC"

clone_tag() {  # repo_url tag dest
  local url="$1" tag="$2" dest="$3"
  if [[ ! -d "$dest" ]]; then
    git clone --depth 1 --branch "$tag" "$url" "$dest"
  else
    echo "    ($dest already present; reusing)"
  fi
}

# --- Kokkos (the heavy build) ---
clone_tag https://github.com/kokkos/kokkos.git "$KOKKOS_TAG" "$SRC/kokkos"
cmake -S "$SRC/kokkos" -B "$ROOT/extern/build/$BACKEND/kokkos" \
  "${common_args[@]}" "${kokkos_args[@]}"
cmake --build "$ROOT/extern/build/$BACKEND/kokkos" -j "$JOBS"
cmake --install "$ROOT/extern/build/$BACKEND/kokkos"

# --- ArborX (header-only; finds the Kokkos we just installed) ---
clone_tag https://github.com/arborx/ArborX.git "$ARBORX_TAG" "$SRC/arborx"
cmake -S "$SRC/arborx" -B "$ROOT/extern/build/$BACKEND/arborx" "${common_args[@]}"
cmake --install "$ROOT/extern/build/$BACKEND/arborx"

echo "==> done. Configure the suite with:  cmake --preset $BACKEND"
