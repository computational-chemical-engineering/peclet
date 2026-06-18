// ArborX toolchain smoke test for the peclet suite.
//
// Proves that ArborX (the Kokkos-native replacement for packing-gpu's CUDA-only
// cuBQL broad-phase) builds, links, and runs a spatial query on the active
// backend. It mirrors the DEM broad-phase pattern: build a BVH over axis-aligned
// boxes, then issue intersection queries and read back the hit indices.
//
// API surface follows ArborX 2.1 (examples/simple_intersection).

#include <ArborX.hpp>
#include <Kokkos_Core.hpp>
#include <cstdio>

int main(int argc, char* argv[]) {
  Kokkos::ScopeGuard guard(argc, argv);

  using ExecutionSpace = Kokkos::DefaultExecutionSpace;
  using MemorySpace = ExecutionSpace::memory_space;
  using Box = ArborX::Box<3>;
  using Point = ArborX::Point<3>;

  std::printf("[arborx_smoke] execution space: %s\n", ExecutionSpace::name());

  // N unit boxes laid out along x: box i spans [i, i+1] x [0,1] x [0,1].
  const int N = 5;
  Kokkos::View<Box*, MemorySpace> boxes("boxes", N);
  auto boxes_host = Kokkos::create_mirror_view(boxes);
  for (int i = 0; i < N; ++i) {
    boxes_host[i] = {{static_cast<float>(i), 0.f, 0.f},
                     {static_cast<float>(i) + 1.f, 1.f, 1.f}};
  }
  Kokkos::deep_copy(boxes, boxes_host);

  // One query per box: a point at the box center hits exactly that box.
  Kokkos::View<decltype(ArborX::intersects(Point{})) *, MemorySpace> queries("queries", N);
  auto queries_host = Kokkos::create_mirror_view(queries);
  for (int i = 0; i < N; ++i) {
    queries_host[i] = ArborX::intersects(Point{static_cast<float>(i) + 0.5f, 0.5f, 0.5f});
  }
  Kokkos::deep_copy(queries, queries_host);

  ExecutionSpace space;
  ArborX::BoundingVolumeHierarchy const tree(
      space, ArborX::Experimental::attach_indices(boxes));

  Kokkos::View<typename decltype(tree)::value_type*, MemorySpace> values("values", 0);
  Kokkos::View<int*, MemorySpace> offsets("offsets", 0);
  tree.query(space, queries, values, offsets);

  auto offsets_host = Kokkos::create_mirror_view_and_copy(Kokkos::HostSpace{}, offsets);
  auto values_host = Kokkos::create_mirror_view_and_copy(Kokkos::HostSpace{}, values);

  // Each query must return exactly its own box index.
  int status = 0;
  for (int i = 0; i < N; ++i) {
    const int begin = offsets_host(i);
    const int end = offsets_host(i + 1);
    if (end - begin != 1 || values_host(begin).index != i) {
      std::printf("[arborx_smoke] FAIL: query %d returned %d hits (first index %d)\n", i,
                  end - begin, (end > begin) ? values_host(begin).index : -1);
      status = 1;
    }
  }
  std::printf("[arborx_smoke] %d queries, %d total hits -> %s\n", N,
              static_cast<int>(values.size()), status ? "FAIL" : "PASS");
  return status;
}
