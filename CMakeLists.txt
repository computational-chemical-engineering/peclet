# Phase 0 toolchain harness for the peclet suite.
#
# This is NOT a superbuild: it deliberately does NOT add_subdirectory() the
# method codes (cfd-gpu, packing-gpu, ...). Those remain independent repos with
# their own CMakeLists and are built on their own. This top-level project exists
# only to validate the shared Kokkos/ArborX provisioning (cmake/Suite*.cmake)
# end-to-end via the smoke tests under tools/. Configure it with a preset:
#
#   tools/bootstrap_deps.sh nvidia-cuda   # one-time: build+install Kokkos/ArborX
#   cmake --preset nvidia-cuda            # local RTX 5080 / CUDA 13.2
#   cmake --build  --preset nvidia-cuda
#   ./build/nvidia-cuda/tools/kokkos_smoke/kokkos_smoke
#
# See docs/PORTABILITY.md.

cmake_minimum_required(VERSION 3.24)
project(peclet_toolchain LANGUAGES CXX)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)

option(SUITE_BUILD_ARBORX_SMOKE "Build the ArborX smoke test" ON)

# Kokkos is consumed as an installed package (CXX compilation path; the CUDA
# backend's nvcc is wired up by Kokkos via its launch compiler, so this project
# stays CXX-only). See cmake/SuiteKokkos.cmake.
include(SuiteKokkos)
suite_require_kokkos()

add_subdirectory(tools/kokkos_smoke)

if(SUITE_BUILD_ARBORX_SMOKE)
  include(SuiteArborX)
  suite_require_arborx()
  add_subdirectory(tools/arborx_smoke)
endif()
