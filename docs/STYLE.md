# Suite Style & Tooling

> Status: design document (living). What to standardize, and the rationale. The baseline is
> `voronoi_dynamics`, the only code that already has formatting, linting, and CI.

## Language standard

- **Host C++: C++20.** `block_decomposer` is already C++20; concepts give us compile-checked
  interfaces (see [INTERFACES](INTERFACES.md)), and `<bit>`/`<span>`/ranges are useful.
- **Device (CUDA) and `morton`: C++17-compatible.** nvcc lags on C++20 and morton pins
  C++17. The rule: **anything that must compile as device code, or be `#include`d by morton, stays
  within C++17.** Concepts and other C++20-only constructs live in host-only headers.
- Practically: the core's interface headers are C++20; the parts pulled into `.cu` translation units
  are C++17. Guard with `__cplusplus`/`__CUDACC__` where a header straddles both.

## Formatting & linting

Adopt `voronoi_dynamics`'s configuration suite-wide (copy `.clang-format` and `.clang-tidy` into each
repo and `transport-core`):

- **clang-format:** `BasedOnStyle: Google`, `ColumnLimit: 100`, `IndentWidth: 2`,
  `NamespaceIndentation: None`.
- **clang-tidy:** the curated check set with naming rules — `NamespaceCase: lower_case`,
  `ClassCase: CamelCase`, `FunctionCase: camelBack`, `VariableCase: camelBack`, member prefix `m_`,
  `ConstantCase: kCamelCase`.
- CUDA `.cu`/`.cuh` follow the same format; clang-tidy coverage of device code is best-effort.

## Naming

- **Namespaces:** lower-case, one per library/module. Suite root namespace `tpx` (transport phenomena);
  modules `tpx::common`, `tpx::decomp`, `tpx::halo`, `tpx::geom`, `tpx::ibm`. Existing method
  namespaces keep their identity (`vor::`, `pbs::`, `morton::`); sdflow/dem, currently in the
  global namespace, move solver classes into a method namespace (`cfd::`, `dem::`) as they integrate.
- **CUDA kernels:** `__global__ void <operation>_kernel(...)` — the `_kernel` suffix is already the
  de-facto convention in sdflow/dem; make it the rule.
- **GPU data:** Structure-of-Arrays for hot device data; `d_`-prefixed device pointers
  (`d_pos`, `d_vel`) as dem does.
- **Members:** `m_` prefix (voronoi convention). Compile-time template params for `Dim`/`Bits` stay in
  the hot path — never add runtime dimension/bit-width to inner loops (morton lesson).

## Build system

- **CMake ≥ 3.24** suite-wide (dem's floor; needed for modern CUDA handling). Each repo
  installs/exports a package config so consumers do `find_package(<pkg> CONFIG)` →
  `target_link_libraries(app PRIVATE tpx::core)`.
- **Dependencies:** prefer `find_package` for system libs (MPI, Boost, CUDAToolkit, OpenMP); use
  `FetchContent` with a pinned tag for source deps (pybind11, cuBQL, Voro++, and `transport-core`
  itself when a method consumes it). Pin versions; don't track `master`.
- **CUDA architectures:** set an explicit list for release artifacts (sdflow uses `75;80;86;120`);
  `native` is fine for local dev builds only.
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
