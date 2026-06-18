# SuiteArborX.cmake — shared ArborX provisioning for the peclet suite.
#
# ArborX is the Kokkos-native geometric-search library that replaces packing-gpu's
# CUDA-only cuBQL broad-phase. It is header-only but does find_package(Kokkos
# CONFIG) internally, so suite_require_kokkos() (an *installed* Kokkos) must
# already be satisfied. Same provisioning policy as Kokkos: find_package(CONFIG),
# provided by a cluster module or tools/bootstrap_deps.sh.

include_guard(GLOBAL)

set(SUITE_ARBORX_VERSION "v2.1" CACHE STRING
    "ArborX version/tag installed by tools/bootstrap_deps.sh")

function(suite_require_arborx)
  if(TARGET ArborX::ArborX)
    return()
  endif()
  find_package(ArborX QUIET CONFIG)
  if(NOT ArborX_FOUND)
    message(FATAL_ERROR
      "[suite] ArborX not found. Provide it via a cluster module or build it locally:\n"
      "    tools/bootstrap_deps.sh <nvidia-cuda|host-openmp|lumi-hip>\n"
      "The matching CMake preset puts the install prefix on CMAKE_PREFIX_PATH.")
  endif()
  message(STATUS "[suite] Using ArborX ${ArborX_VERSION}")
endfunction()
