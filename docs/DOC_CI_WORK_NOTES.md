# Documentation & CI overhaul — work notes

Autonomous session started 2026-06-21. Goal (from user): improve/update all documentation, Doxygen
and docstrings in every module **except `vorflow`** (another agent is editing it), and add GitHub
workflows for CI and for building/publishing the docs pages. User unavailable for approvals — working
around roadblocks and recording them here.

## Plan

Per module (`transport-core`, `morton`, `sdflow`, `dem`):
1. Doxyfile (create or refresh — several reference retired CUDA / old repo names).
2. `.github/workflows/`: a Doxygen → GitHub Pages deploy workflow, and a CI workflow where feasible.
3. Improve in-source doc comments (Doxygen `///` / `@brief`) and Python docstrings.
4. Commit inside each submodule, then bump pointers in the umbrella.

## Constraints / decisions

- **GPU CI is not runnable on free GitHub runners** (no CUDA/HIP hardware). For `sdflow` and `dem`
  the CI workflow builds the **Kokkos OpenMP (Serial/host) backend** via `tools/bootstrap_deps.sh`
  and runs the CPU-only tests. These bootstrap builds are heavy; workflows cache the `extern/install`
  prefix. Marked clearly in each workflow header.
- `transport-core` is header-only + MPI and fully CPU-testable → real CI (build + ctest np=1,2,4).
- `morton` already had CI + release; I add a Pages deploy job (it previously only uploaded an artifact).
- Pages deploy requires each repo to have Pages enabled with "Source: GitHub Actions" (Settings→Pages).
  Recorded as a manual step the user must do once per repo; workflows are otherwise self-contained.

## Roadblocks encountered

- **GPU CI not runnable on free runners** (no CUDA/HIP). Worked around: `sdflow`/`dem` CI builds the
  Kokkos **OpenMP** backend from source (cached) and builds the single-rank modules + CPU tests. The
  single-rank modules don't link MPI/transport-core (gated behind `CFD_MPI`/`DEM_MPI`), so the
  dependency set is just Kokkos (+ ArborX for dem) + pybind11 — feasible in CI.
- **Doxygen invisibility of `//` headers.** Every `sdflow`/`dem` source file led with a plain `//`
  block (and the stale `cfd-gpu`/`packing-gpu` name), so nothing rendered. Converted all to Doxygen
  `/// @file` + `/// @brief` via a scripted leading-block transform; fixed the names in the same pass.
- **morton library/package names** (`morton-arithmetic`, `mortonarith`) left unchanged: they're the
  published conan/PyPI/vcpkg names; renaming risks breaking the release pipeline. Only the repo
  *directory* was renamed to `morton` (already reflected in the umbrella). Decision, not a blocker.
- **Cleanup scope.** Removed only clearly-obsolete *tracked* material: 7 `dem/build_log*.txt` CUDA-era
  build logs (referenced deleted `src/cuda/*` TUs; ~2 MB). Left committed result PNGs (`sdflow/output`,
  `notebooks/output`) and `dem/test.vtp` — they're intentional records, not stale. Left untracked
  experiment dirs at suite root (`RingBed-CFD-Surrogate/`, `sphere-cfd-validation/`,
  `69503dc…/`) untouched: not created by this task, possibly active, and deletion is hard to reverse.

## Progress log

- transport-core: Doxyfile + CI (build+ctest np 1/2/4) + Pages docs workflow + geom doc-comments. Done.
- morton: Pages-deploy workflow + Doxygen-ified the 5 public headers + Doxyfile INPUT fixes. Done.
- sdflow: Doxyfile/docs.yml de-CUDA'd, new Kokkos-OpenMP CI, 17 headers Doxygen-ified, README/AGENTS
  refreshed. Done.
- dem: new Doxyfile + CI (Kokkos+ArborX) + Pages docs workflow, 16 headers Doxygen-ified, mpi/README
  refreshed, obsolete build logs removed. Done.
- Suite README: rewrote the submodule table for the renames (sdflow/dem/vorflow/morton), Kokkos era,
  retired block_decomposer, and added a CI/docs section.
