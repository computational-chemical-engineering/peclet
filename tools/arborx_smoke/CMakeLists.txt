# ArborX broad-phase smoke test. Built by the top-level Phase 0 harness.
add_executable(arborx_smoke main.cpp)

# ArborX is header-only but its kernels run on the Kokkos backend, so the source
# must be compiled by the device compiler (nvcc for CUDA).
suite_kokkos_device_sources(main.cpp)

target_link_libraries(arborx_smoke PRIVATE ArborX::ArborX Kokkos::kokkos)
