# SuiteNanobind.cmake — shared nanobind provisioning for the peclet suite.
#
# Policy: the suite's Python bindings use nanobind (replacing pybind11), built through
# scikit-build-core for wheels and through plain CMake for the developer `cmake -S . -B build`
# workflow. nanobind ships a CMake config inside its Python package; we locate it the same way
# scikit-build-core does — by asking the active interpreter — so a single mechanism covers both
# `pip install .` and a venv-driven dev build.
#
# Usage in a consumer CMakeLists:
#     include(${SUITE_CMAKE_DIR}/SuiteNanobind.cmake)   # or list-append to CMAKE_MODULE_PATH
#     suite_require_nanobind()
#     nanobind_add_module(mymod NB_STATIC src/bindings.cpp)
#     target_link_libraries(mymod PRIVATE Kokkos::kokkos)
#
# The Kokkos View <-> nanobind ndarray zero-copy bridge consumed by every binding lives in
# transport-core/include/tpx/python/ndarray_interop.hpp.

include_guard(GLOBAL)

# A macro (not a function): find_package(Python) sets plain variables like Python_INCLUDE_DIRS that
# nanobind reads at module-creation time. A function would scope those locally, so nanobind-static
# would later be compiled at directory scope without the Python headers. A macro runs in the
# caller's scope, so the variables are visible where nanobind_add_module() is invoked.
macro(suite_require_nanobind)
  if(NOT COMMAND nanobind_add_module)
    # Need the Development.Module component so nanobind can build extension modules. Honor an already
    # chosen interpreter (scikit-build-core / an activated venv set Python_EXECUTABLE).
    find_package(Python 3.10 REQUIRED COMPONENTS Interpreter Development.Module)

    # Ask the interpreter where nanobind's CMake config lives (works for both pip-installed and
    # venv-resident nanobind, and matches how scikit-build-core resolves it).
    if(NOT nanobind_DIR)
      execute_process(
        COMMAND "${Python_EXECUTABLE}" -m nanobind --cmake_dir
        OUTPUT_VARIABLE _suite_nb_cmake_dir
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _suite_nb_result)
      if(NOT _suite_nb_result EQUAL 0 OR NOT EXISTS "${_suite_nb_cmake_dir}")
        message(FATAL_ERROR
          "[suite] nanobind not found via '${Python_EXECUTABLE} -m nanobind --cmake_dir'. "
          "Install it into the active environment:\n"
          "    pip install nanobind\n"
          "(scikit-build-core adds it automatically when building a wheel via pyproject.toml).")
      endif()
      set(nanobind_DIR "${_suite_nb_cmake_dir}")
    endif()

    find_package(nanobind CONFIG REQUIRED)
    message(STATUS "[suite] Using nanobind from ${nanobind_DIR}")
  endif()
endmacro()
