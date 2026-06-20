# Suite Roadmap

> Status: living tracker. Long-term plan to give the suite a shared MPI block decomposition with
> efficient asynchronous ghost-layer exchange, common SDF/IBM, GPU support, and Python bindings — while
> keeping each method its own code. See [ARCHITECTURE](ARCHITECTURE.md) for the layering.
>
> **2026-06-20 — CUDA retired, Kokkos canonical.** cfd-gpu (`sdflow`/`pnm_backend`), packing-gpu
> (`demgpu`, ArborX broad-phase), and transport-core now build on Kokkos (CUDA/HIP/OpenMP) with the CUDA
> implementations deleted and merged to `main`. Historical phase entries below that name `.cu`/`.cuh`
> files describe the original CUDA path. See [CUDA_RETIREMENT](CUDA_RETIREMENT.md) and
> [PORTABILITY](PORTABILITY.md).

## Guiding decisions

- Shared **`transport-core`** library repo; method codes stay separate repos depending on it.
- **C++20 host / C++17 device** (see [STYLE](STYLE.md)).
- One `HaloExchange` interface, two engines (NBX for dynamic, persistent-neighbor for static),
  GPU-aware. CPU-correct first, then GPU.
- First solver wired in: **cfd-gpu** (most grid-native). `morton_arithmetic` is a core dependency.

## Phase 0 — Foundations (DONE)

- [x] Architecture, conventions, style, interfaces, roadmap documents (`suite/docs/`).
- [x] Link the documents from the top-level `suite/CLAUDE.md`.
- [x] Scaffold `transport-core`: header-only C++20, CMake ≥3.24 with install/export target
      (`tpx::core`/`tpx::halo`), `include/tpx/{common,decomp,halo}/` layout, `.clang-format` from
      `voronoi_dynamics`, auto-detects `morton_arithmetic`. Git repo initialized.
- [x] Extract the reusable code from `block_decomposer` into `tpx::decomp` + `tpx::halo` (ported &
      modernized): `BlockDecomposer` (+`ownerOf`), `BlockIndexer`, the `MPISync` NBX engine.
      (`GhostLayers`/`CellList` superseded by the owner-based `GridHalo`; `PbsCommon` → `common/types`.)

## Phase 1 — Halo engine v1 (CPU) (DONE except noted)

- [x] `GridHalo` with **topology/exchange separation** and **field-agnostic pack/unpack** (one path
      for grid fields and particle arrays via `GridFieldView` / the migrator).
- [x] `NbxEngine` (canonical NBX consensus) for dynamic/sparse; `GridHalo::exchangePersistent`
      (dist-graph + `MPI_Neighbor_alltoallv`) for static grid halos.
- [x] **Compute/comm overlap** API (`start` → compute interior → `wait`).
- [x] Port `BlockDecomposer`/`BlockIndexer` (x-fastest indexing per CONVENTIONS).
      [ ] morton-based Z-order indexing option (deferred; linear indexing in place).
- [x] **Particle migration** (`ParticleMigrator`) — Lagrangian path, landed early (Phase 4 item).
- [x] Correctness tests under `mpirun -np {1,2,4,8}`: serial decomposition tiling/ownership; grid-halo
      vs analytic field (NBX≡persistent, periodic/open/mixed); particle migration conservation over
      random-walk steps; **end-to-end distributed diffusion vs serial reference**. Microbenchmark:
      NBX vs persistent weak scaling (persistent wins for the static pattern). **13/13 ctest pass.**
      [ ] Lees–Edwards halo variant (deferred to voronoi integration).
      [ ] Replace broken `Pbs`/`main.cpp` demo + finish/delete `NbrList` (in the old `block_decomposer`
          repo; lower priority now that the core supersedes it).

## Phase 2 — GPU-aware halo + unified geometry (halo done; geometry next)

- [x] GPU-resident halo (`tpx::halo::DeviceGridExchangeKokkos`, `grid_halo_kokkos.hpp`): portable
      (Kokkos: CUDA/HIP/OpenMP) on-device pack/unpack/self-copy, **host-staged** MPI of the compact halo
      buffers (the full field stays on the device; opt-in GPU-aware via `TPX_GPU_AWARE_MPI`). Validated
      bit-for-bit against the CPU path, np=1,2,4. *(The original native-CUDA `grid_halo_cuda.cuh`
      `DeviceGridExchange` was retired when Kokkos became canonical — see `docs/CUDA_RETIREMENT.md`.)*
- [x] `geometry/SDF`: analytic primitives (`Sphere`, `Box`, `HollowCylinder`, `Complement`) + sampled
      `GridSdf` (trilinear) behind the `tpx::geom::Sdf` concept, shared sign convention, generic
      finite-difference normal, `sample()` to bake analytic → grid. Unit-tested.
      [x] VTI (.vti ImageData) ASCII read/write for sampled fields (`vti_io.hpp`), round-trip tested.
      [ ] binary/base64 "appended" VTI (existing files) + VTP; consolidate cfd-gpu/packing readers.

## Phase 3 — Wire in cfd-gpu (first Eulerian consumer) (working distributed solver)

A **complete distributed incompressible Navier–Stokes solver** is built on transport-core and
validated; see `cfd-gpu/doc/mpi_parallelization_status.md` for the 13-step breakdown. Branch
`mpi-halo-integration`, opt-in `-DCFD_BUILD_MPI=ON`; the production `pnm_backend` module is untouched.

- [x] `cfd-gpu/src/mac_halo.cuh` (`MacGridHalo`) — ORB decomposition + ghost exchange (width 1/2) for
      `double` MAC cell-fields, on `tpx::halo::DeviceGridExchange`. Validated against cfd's own `get_idx`
      stencils.
- [x] `cfd-gpu/src/staggered_advection.cuh` — cfd's exact staggered Koren TVD advection (momentum-
      conserving), templated accessor for full-grid / local-block.
- [x] `cfd-gpu/src/distributed_stokes.cuh` (`dstokes::DistributedStokes`) — reusable solver: implicit
      diffusion (RB-GS) + Chorin projection + optional nonlinear advection + body force + SDF solids
      (no-slip masking) + `gather_to_root` → VTI. Full Navier–Stokes.
- [x] Validated **cell-for-cell vs serial** and against analytics (Taylor–Green ~2e-15, Poiseuille,
      NS-around-solid), **36/36 ctests real multi-rank np=1,2,4**.
- [ ] **In-place `cfd_solver.cu` rewrite** (largest remaining): extended-block state/scratch + MPI
      global reductions (`max_abs`, `remove_mean`, pressure pin) + distributed **multigrid**
      (restriction/prolongation across blocks) + Robust-Scaled cut-cell IBM (vs masking). The
      `DistributedStokes` solver is the working single-level path that proves the approach.

## Phase 4 — Wire in packing-gpu (Lagrangian)

Concrete plan (packing-gpu's data is SoA `float4` arrays — `d_pos` [.xyz pos, .w inv_mass], `d_vel`,
`d_quat`, `d_ang_vel`, `d_inv_inertia`, `d_scale`, `d_shape_ids` — with `domain_min/max`, periodic
flags, and existing ghost-particle infrastructure `num_real`/`d_top_ghost`). The shared
`tpx::halo::ParticleMigrator` (validated in transport-core) and block decomposition map directly:

- [x] **Step 1 — migration (done):** `packing-gpu/mpi/test_particle_migration.cpp` decomposes the
      periodic domain, builds a `DomainMap` from packing's domain+periodicity, and migrates
      packing-style particles (full SoA record as opaque payload) with `ParticleMigrator`. Conservation
      + correct placement validated over random-walk steps, np=1,2,4. Standalone build
      (`packing-gpu/mpi/`), decoupled from the demgpu (Kokkos+ArborX) build. Branch `mpi-integration`.
- [x] **Step 2 — ghost particles (done):** `ParticleMigrator::gatherGhosts(rcut)` gathers copies within
      one interaction radius of each block boundary (periodic images handled) for a local ArborX
      broadphase. Rigorously validated vs a brute-force reference in transport-core's
      `test_ghost_particles_mpi` (np=1,2,4,8), and exercised on packing's layout.
- [ ] **Per-step loop** in the solver: predict → migrate → gather ghosts → local broadphase +
      narrowphase + XPBD solve. Validate the existing `verify_*` scripts (packing fraction, restitution)
      match single-rank across ranks.
- [ ] Decision: keep packing single-process (run distributed under `mpirun` with mpi4py) vs. a C++
      driver — same question cfd faces; the standalone tests/driver path avoids touching the pybind
      module first.

## Phase 5 — voronoi_dynamics (mixed) + Python parity

- [ ] Add pybind11 bindings (first Python surface for voronoi) following the binding conventions.
- [ ] Block decomposition + ghost particles (one interaction radius) so boundary Voronoi cells close
      correctly; validate vs serial tessellation.

## Phase 6 — Consolidation

- [ ] Promote the common **IBM** library; share cut-cell machinery between Eulerian solvers.
- [ ] Cross-code verification harness (same SDF geometry through CFD + packing + voronoi).
- [ ] Unified Python packaging + CI templates across all repos; migrate stragglers to shared
      conventions; reconcile remaining divergences (namespaces, C++ standard, dep management).

## Cross-cutting / ongoing

- Keep `morton_arithmetic` as the spatial-index primitive; adopt its octree where hierarchical indexing
  helps.
- Each phase lands with tests + docs; no method depends on another method (dependencies point down).
