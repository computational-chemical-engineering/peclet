cmake_minimum_required(VERSION 3.24)
project(peclet_coupling LANGUAGES CXX)

# peclet.coupling -- CFD-DEM exchange kernels (particle<->grid deposition, drag, momentum feedback)
# as an importable Python module. Physics-free glue: the Python CfdDem driver (python/peclet_coupling)
# composes peclet.flow + peclet.dem, and this module runs the kernels in place on the arrays they
# expose. Header-only compute (core interp primitive + drag laws), Kokkos backend from the install
# prefix (extern/install/<backend>), nanobind via the shared SuiteNanobind helper.
#
#   cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/host-openmp"
#   cmake --build build -j        ->  build/peclet/coupling/_coupling.*.so

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(Kokkos CONFIG REQUIRED)
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/SuiteNanobind.cmake)
suite_require_nanobind()

nanobind_add_module(coupling NB_STATIC NOMINSIZE src/coupling_bindings.cpp)
set_target_properties(coupling PROPERTIES OUTPUT_NAME _coupling  # -> peclet.coupling._coupling
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/peclet/coupling")
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/python/peclet_coupling/__init__.py
               ${CMAKE_CURRENT_BINARY_DIR}/peclet/coupling/__init__.py COPYONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/python/peclet_coupling/driver.py
               ${CMAKE_CURRENT_BINARY_DIR}/peclet/coupling/driver.py COPYONLY)
target_include_directories(coupling PRIVATE src "${CMAKE_CURRENT_SOURCE_DIR}/../core/include")
target_link_libraries(coupling PRIVATE Kokkos::kokkos)
if(Kokkos_ENABLE_HIP)
  target_link_options(coupling PRIVATE -Wl,--no-gc-sections)
endif()

option(PECLET_COUPLING_TESTS "Register the Python CFD-DEM integration tests as ctests" OFF)
if(PECLET_COUPLING_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
