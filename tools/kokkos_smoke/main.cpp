// Kokkos toolchain smoke test for the peclet suite.
//
// Proves end-to-end that the active Kokkos backend (CUDA / HIP / OpenMP) builds,
// links, launches a parallel kernel on the device, and returns the right answer.
// It exercises the two patterns that dominate the suite's kernels: a parallel_for
// fill and a parallel_reduce sum (cf. cfd-gpu's mac_reductions, packing-gpu's
// Jacobi accumulation).

#include <Kokkos_Core.hpp>
#include <cmath>
#include <cstdio>

int main(int argc, char* argv[]) {
  Kokkos::initialize(argc, argv);
  int status = 0;
  {
    using exec = Kokkos::DefaultExecutionSpace;
    std::printf("[kokkos_smoke] default execution space: %s\n", exec::name());

    const long n = 1 << 20;  // 1,048,576
    Kokkos::View<double*, exec> x("x", n);

    // parallel_for fill: x[i] = i + 1
    Kokkos::parallel_for(
        "fill", Kokkos::RangePolicy<exec>(0, n),
        KOKKOS_LAMBDA(const long i) { x(i) = static_cast<double>(i) + 1.0; });

    // parallel_reduce sum: expect n*(n+1)/2
    double sum = 0.0;
    Kokkos::parallel_reduce(
        "sum", Kokkos::RangePolicy<exec>(0, n),
        KOKKOS_LAMBDA(const long i, double& acc) { acc += x(i); }, sum);
    Kokkos::fence();

    const double expected = 0.5 * static_cast<double>(n) * (static_cast<double>(n) + 1.0);
    const double rel_err = std::abs(sum - expected) / expected;
    std::printf("[kokkos_smoke] sum=%.1f expected=%.1f rel_err=%.3e\n", sum, expected, rel_err);

    if (rel_err > 1e-12) {
      std::printf("[kokkos_smoke] FAIL: reduction mismatch\n");
      status = 1;
    } else {
      std::printf("[kokkos_smoke] PASS\n");
    }
  }
  Kokkos::finalize();
  return status;
}
