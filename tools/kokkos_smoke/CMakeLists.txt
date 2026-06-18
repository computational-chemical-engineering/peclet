# Kokkos backend smoke test. Built by the top-level Phase 0 harness.
add_executable(kokkos_smoke main.cpp)

# Compile the device source with the active backend's device compiler
# (nvcc for CUDA; no-op for host/HIP backends).
suite_kokkos_device_sources(main.cpp)

target_link_libraries(kokkos_smoke PRIVATE Kokkos::kokkos)
