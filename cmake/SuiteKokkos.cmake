# SuiteKokkos.cmake — shared Kokkos provisioning for the peclet suite.
#
# Policy (see docs/PORTABILITY.md): Kokkos is consumed via find_package(CONFIG).
# It is provided by either
#   * a cluster module (Snellius/LUMI: `module load Kokkos`), or
#   * a local install prefix produced once by tools/bootstrap_deps.sh, which the
#     CMake presets put on CMAKE_PREFIX_PATH.
# This single mechanism composes with ArborX (which itself does
# find_package(Kokkos CONFIG)) and avoids rebuilding Kokkos in every repo.
#
# Backend + architecture come from the Kokkos build (preset / bootstrap), not
# from here, so the same sources stay portable across NVIDIA and AMD.

include_guard(GLOBAL)

# Version the bootstrap installs; find_package itself is version-agnostic so a
# cluster module of any ArborX-compatible (>= 4.5) Kokkos is accepted.
set(SUITE_KOKKOS_VERSION "5.1.1" CACHE STRING
    "Kokkos version/tag installed by tools/bootstrap_deps.sh")

function(suite_require_kokkos)
  if(TARGET Kokkos::kokkos)
    return()
  endif()
  find_package(Kokkos QUIET CONFIG)
  if(NOT Kokkos_FOUND)
    message(FATAL_ERROR
      "[suite] Kokkos not found. Provide it via a cluster module "
      "(module load Kokkos) or build it locally:\n"
      "    tools/bootstrap_deps.sh <nvidia-cuda|host-openmp|lumi-hip>\n"
      "The matching CMake preset puts the install prefix on CMAKE_PREFIX_PATH.")
  endif()
  if(Kokkos_VERSION VERSION_LESS 4.5)
    message(FATAL_ERROR "[suite] Kokkos ${Kokkos_VERSION} found, but ArborX needs >= 4.5")
  endif()
  message(STATUS "[suite] Using Kokkos ${Kokkos_VERSION} (backends: ${Kokkos_DEVICES})")
endfunction()

# Device-source marker. Kokkos 5.x compiles device code through its CXX path
# (the installed KokkosConfig wires up the kokkos_launch_compiler / device flags
# for any target linking Kokkos::kokkos). Suite device sources are therefore
# plain .cpp compiled as CXX, NOT .cu, and this helper is intentionally a no-op
# — kept as the one documented seam if a native-CUDA-language path is ever needed.
function(suite_kokkos_device_sources)
  # no-op: device sources compile as CXX via Kokkos. See docs/PORTABILITY.md.
endfunction()
