# Suite Style & Tooling

> Status: design document (living). What to standardize, and the rationale. The baseline is
> `voro`, the only code that already has formatting, linting, and CI.

## Language standard

- **Host C++: C++20.** `core` is C++20; concepts give us compile-checked interfaces (see
  [INTERFACES](INTERFACES.md)), and `<bit>`/`<span>`/ranges are useful.
- **Device code under Kokkos: C++20.** GPU kernels are ordinary C++ in `.hpp`
  headers compiled through the Kokkos launch compiler (which routes them to `nvcc`/`hipcc`) — there are
  no `.cu` translation units, and the device side moves to C++20 under Kokkos (see
  [PORTABILITY](PORTABILITY.md)).
- **`morton`: C++17.** morton pins C++17 by design; **anything `#include`d by morton stays within
  C++17.** Concepts and other C++20-only constructs live in host-only headers.

## Formatting & linting

Adopt `voro`'s configuration suite-wide (copy `.clang-format` and `.clang-tidy` into each
repo and `core`):

- **clang-format:** `BasedOnStyle: Google`, `ColumnLimit: 100`, `IndentWidth: 2`,
  `NamespaceIndentation: None`.
- **clang-tidy:** the curated check set with naming rules — `NamespaceCase: lower_case`,
  `ClassCase: CamelCase`, `FunctionCase: camelBack`, `VariableCase: camelBack`, member prefix `m_`,
  `ConstantCase: kCamelCase`.
- Kokkos device headers (`.hpp`) follow the same format; clang-tidy coverage of device code is best-effort.

## Naming

- **Namespaces:** lower-case, one per library/module. Suite root namespace `tpx` (transport phenomena);
  modules `peclet::core::common`, `peclet::core::decomp`, `peclet::core::halo`, `peclet::core::geom`, `peclet::core::ibm`. Existing method
  namespaces keep their identity (`peclet::voro::`, `pbs::`, `morton::`); flow/dem, currently in the
  global namespace, move solver classes into a method namespace (`cfd::`, `dem::`) as they integrate.
- **Kokkos kernels:** prefer named functors/tags or descriptive `parallel_*` labels over anonymous
  lambdas in the hot path; keep the `_kernel`/`_op` suffix on functor types so device work is greppable.
- **GPU data:** Structure-of-Arrays for hot device data; `d_`-prefixed device pointers
  (`d_pos`, `d_vel`) as dem does.
- **Members:** `m_` prefix (voronoi convention). Compile-time template params for `Dim`/`Bits` stay in
  the hot path — never add runtime dimension/bit-width to inner loops (morton lesson).

## Build system

- **CMake ≥ 3.24** suite-wide (dem's floor). Each repo installs/exports a package config so consumers
  do `find_package(<pkg> CONFIG)` → `target_link_libraries(app PRIVATE peclet::core::core)`.
- **Dependencies:** `find_package` for the GPU/parallel stack (`Kokkos`, `ArborX`, MPI, OpenMP) against
  the bootstrapped `extern/install/<backend>` prefix; `nanobind` is provisioned via the shared
  `cmake/SuiteNanobind.cmake` helper (found through the active interpreter, not a pinned tag). Use
  `FetchContent` with a pinned tag only for the remaining source deps (Voro++, and `core`
  itself when a method consumes it). Pin versions; don't track `master`.
- **GPU architecture:** the backend (CUDA/HIP/OpenMP) and arch are baked into the bootstrapped Kokkos
  prefix (`KOKKOS_ARCH` at Kokkos build time), not set per-method in CMake; the build is just pointed at
  `extern/install/<backend>`.
- **Options:** gate tests/benchmarks/docs behind `<PKG>_BUILD_TESTS`/`_BENCHMARKS`/`_DOCS` (voronoi
  pattern), default tests `ON`, docs `OFF`.

## CI

Adopt the two-pronged CI already present in the suite:

- **Correctness/build** (voronoi + morton patterns): Ubuntu with g++ and clang++; build + `ctest`.
  For MPI code, run `ctest` under `mpirun -np {1,2,4,8}`. For GPU code, a GPU runner builds and runs
  the device tests; CPU CI at least compiles the device TUs.
- **Hygiene** (voronoi pattern): `clang-format --dry-run --Werror`, `clang-tidy -p build`, and Doxygen
  build as a non-blocking doc check.
- **Special emulation** (morton pattern): where SIMD/ISA paths exist, validate under Intel SDE.

## Documentation

- **Doxygen** for API docs (morton + voronoi already do this); `<PKG>_BUILD_DOCS=ON` →
  `cmake --build build --target docs`.
- **Per-repo `CLAUDE.md`** for agent-facing guidance; the suite-level `CLAUDE.md` links these shared
  documents.
- Keep `AGENTS.md`/`GEMINI.md` if present, but `CLAUDE.md` is authoritative for Claude Code.
