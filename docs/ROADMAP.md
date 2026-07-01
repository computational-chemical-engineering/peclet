# Suite Roadmap

> Status: living tracker. Long-term plan to give the suite a shared MPI block decomposition with
> efficient asynchronous ghost-layer exchange, common SDF/IBM, GPU support, and Python bindings — while
> keeping each method its own code. See [ARCHITECTURE](ARCHITECTURE.md) for the layering.
>
> **2026-06-20 — CUDA retired, Kokkos canonical.** sdflow (`sdflow`/`pnm`), dem
> (`dem`, ArborX broad-phase), and core now build on Kokkos (CUDA/HIP/OpenMP) with the CUDA
> implementations deleted and merged to `main`. Historical phase entries below that name `.cu`/`.cuh`
> files describe the original CUDA path. See [CUDA_RETIREMENT](CUDA_RETIREMENT.md) and
> [PORTABILITY](PORTABILITY.md).

## Guiding decisions

- Shared **`core`** library repo; method codes stay separate repos depending on it.
- **C++20 host & Kokkos device; `morton` pins C++17** (see [STYLE](STYLE.md)).
- **Keep computation on the device; minimize host↔device movement** — the cross-cutting plan for
  migrating remaining host-only compute to Kokkos and removing avoidable data movement is in
  [DEVICE_RESIDENCY_PLAN](DEVICE_RESIDENCY_PLAN.md).
- One `HaloExchange` interface, two engines (NBX for dynamic, persistent-neighbor for static),
  GPU-aware. CPU-correct first, then GPU.
- First solver wired in: **sdflow** (most grid-native). `morton` is a core dependency.

## Phase 0 — Foundations (DONE)

- [x] Architecture, conventions, style, interfaces, roadmap documents (`suite/docs/`).
- [x] Link the documents from the top-level `suite/CLAUDE.md`.
- [x] Scaffold `core`: header-only C++20, CMake ≥3.24 with install/export target
      (`tpx::core`/`tpx::halo`), `include/tpx/{common,decomp,halo}/` layout, `.clang-format` from
      `vorflow`, auto-detects `morton`. Git repo initialized.
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
      [x] morton-based Z-order indexing option — `tpx::decomp::MortonIndexer` (`decomp/morton_indexer.hpp`,
          guarded `TPX_HAVE_MORTON`): `codeOf`/`multiIndex` + Morton-space `neighborCode`, device-callable
          (`MORTON_HD`→`KOKKOS_FUNCTION`). The cache-friendly alternative to x-fastest (which stays the
          convention). Serial ctest `morton_indexer`. *(morton itself now ships a portable Kokkos backend;
          `vorflow`'s device tessellator also consumes `morton::Morton` for its Z-order grid ordering.)*
- [x] **Particle migration** (`ParticleMigrator`) — Lagrangian path, landed early (Phase 4 item).
- [x] Correctness tests under `mpirun -np {1,2,4,8}`: serial decomposition tiling/ownership; grid-halo
      vs analytic field (NBX≡persistent, periodic/open/mixed); particle migration conservation over
      random-walk steps; **end-to-end distributed diffusion vs serial reference**. Microbenchmark:
      NBX vs persistent weak scaling (persistent wins for the static pattern). **13/13 ctest pass.**
      [ ] Lees–Edwards halo variant (deferred to voronoi integration).
      [ ] Replace broken `Pbs`/`main.cpp` demo + finish/delete `NbrList` (in the old `block_decomposer`
          repo; lower priority now that the core supersedes it).

## Phase 2 — GPU-aware halo + unified geometry (halo done; geometry next)

- [x] GPU-resident halo (`tpx::halo::GridHalo`, `grid_halo.hpp` + `grid_halo_topology.hpp`): portable
      (Kokkos: CUDA/HIP/OpenMP) on-device pack/unpack/self-copy, **host-staged** MPI of the compact halo
      buffers (the full field stays on the device; opt-in GPU-aware via `TPX_GPU_AWARE_MPI`). Validated
      bit-for-bit against the CPU path, np=1,2,4. *(The original native-CUDA `grid_halo_cuda.cuh`
      `DeviceGridExchange` was retired when Kokkos became canonical — see `docs/CUDA_RETIREMENT.md`.)*
- [x] `geometry/SDF`: analytic primitives (`Sphere`, `Box`, `HollowCylinder`, `Complement`) + sampled
      `GridSdf` (trilinear) behind the `tpx::geom::Sdf` concept, shared sign convention, generic
      finite-difference normal, `sample()` to bake analytic → grid. Unit-tested.
      [x] VTI (.vti ImageData) ASCII read/write for sampled fields (`vti_io.hpp`), round-trip tested.
      [ ] binary/base64 "appended" VTI (existing files) + VTP; consolidate sdflow/packing readers.

## Phase 3 — Wire in sdflow (first Eulerian consumer) (working distributed solver)

A **complete distributed incompressible Navier–Stokes solver** is built on core and
validated; see the "MPI / sdflow" section of `sdflow/CLAUDE.md` for the current details. Opt-in
`-DCFD_BUILD_MPI=ON`; the production `pnm` module is untouched.

- [x] `sdflow/src/mac_halo.cuh` (`MacGridHalo`) — ORB decomposition + ghost exchange (width 1/2) for
      `double` MAC cell-fields, on `tpx::halo::DeviceGridExchange`. Validated against cfd's own `get_idx`
      stencils.
- [x] `sdflow/src/staggered_advection.cuh` — cfd's exact staggered Koren TVD advection (momentum-
      conserving), templated accessor for full-grid / local-block.
- [x] `sdflow/src/distributed_stokes.cuh` (`dstokes::DistributedStokes`) — reusable solver: implicit
      diffusion (RB-GS) + Chorin projection + optional nonlinear advection + body force + SDF solids
      (no-slip masking) + `gather_to_root` → VTI. Full Navier–Stokes.
- [x] Validated **cell-for-cell vs serial** and against analytics (Taylor–Green ~2e-15, Poiseuille,
      NS-around-solid), **36/36 ctests real multi-rank np=1,2,4**.
- [x] **Distributed Navier–Stokes solver (done):** the full cut-cell IBM + MG-PCG step runs
      multi-rank, bit-exact to single-rank — extended-block state/scratch + MPI global reductions
      (`max_abs`, `remove_mean`, pressure pin) + distributed **multigrid** (restriction/prolongation
      across blocks) + Robust-Scaled cut-cell IBM. `tests/kokkos_mpi`, 18 ctests np=1,2,4 (gated
      `CFD_MPI`).

## Phase 4 — Wire in dem (Lagrangian)

Concrete plan (dem's data is SoA `float4` arrays — `d_pos` [.xyz pos, .w inv_mass], `d_vel`,
`d_quat`, `d_ang_vel`, `d_inv_inertia`, `d_scale`, `d_shape_ids` — with `domain_min/max`, periodic
flags, and existing ghost-particle infrastructure `num_real`/`d_top_ghost`). The shared
`tpx::halo::ParticleMigrator` (validated in core) and block decomposition map directly:

- [x] **Step 1 — migration (done):** `dem/mpi/test_particle_migration.cpp` decomposes the
      periodic domain, builds a `DomainMap` from packing's domain+periodicity, and migrates
      packing-style particles (full SoA record as opaque payload) with `ParticleMigrator`. Conservation
      + correct placement validated over random-walk steps, np=1,2,4. Standalone build
      (`dem/mpi/`), decoupled from the dem (Kokkos+ArborX) build. Branch `mpi-integration`.
- [x] **Step 2 — ghost particles (done):** `ParticleMigrator::gatherGhosts(rcut)` gathers copies within
      one interaction radius of each block boundary (periodic images handled) for a local ArborX
      broadphase. Rigorously validated vs a brute-force reference in core's
      `test_ghost_particles_mpi` (np=1,2,4,8), and exercised on packing's layout.
- [x] **Per-step distributed loop (done):** `dem`'s `step_mpi` runs predict → migrate → gather ghosts
      → local ArborX broadphase + narrowphase + XPBD solve, with periodic **load rebalancing**
      (`enable_mpi_step(rebalance_every=…)` / `Sim.rebalance()` — SoA ownership migration on the
      weighted ORB). Validated in `tests/kokkos_mpi` (6 ctests).
- [x] Decision (resolved): the distributed step lives inside the `dem` module itself
      (`enable_mpi_step`), driven from Python under `mpirun` — no separate C++ driver.

## Phase 5 — vorflow (mixed) + Python parity

- [x] Add nanobind bindings (Kokkos device module) — first Python surface for vorflow, on the shared
      zero-copy bridge, following the binding conventions.
- [ ] Block decomposition + ghost particles (one interaction radius) so boundary Voronoi cells close
      correctly; validate vs serial tessellation.

## Phase 6 — Consolidation

- [ ] Promote the common **IBM** library; share cut-cell machinery between Eulerian solvers.
- [ ] Cross-code verification harness (same SDF geometry through CFD + packing + voronoi).
- [ ] Unified Python packaging + CI templates across all repos; migrate stragglers to shared
      conventions; reconcile remaining divergences (namespaces, C++ standard, dep management).

## Phase 7 — Dynamic load balancing (cross-cutting infra) — DONE

Both consumers create *non-uniform* work that the equal-cell-count ORB does not balance:
**AMR** dynamically refines (a feature refined into one block leaves that rank heavier — see
`docs/AMR.md`, `distributedAdapt`), and **dem** packs particles densely (particle counts per block
drift far apart). The fix is the same primitive for both, so it lives in `core`.

- [x] **Weighted ORB** — `tpx::decomp::BlockDecomposer::init(numBlocks, globalSize, weights)`. The split
  position is chosen on the integer cell boundary whose **cumulative weight** along the largest axis is
  closest to the sub-block's target fraction, balancing total weight per block instead of cell count.
  Factored through a shared `splitPosition()` helper so the unweighted `init()` is byte-identical and
  equal weights reduce to it bit-for-bit. (`test_decomposition`.)
- [x] **AMR rebalance** — `tpx::amr::DistributedOctree::rebalance(fields)`. weight = octree leaf-count per
  global root cell (SUM-Allreduce) → weighted re-decompose → migrate leaves (global Morton code + level)
  **and field columns** to new owners over NBX → rebuild each rank's local octree (`BlockOctree::assign`)
  + swap in the new decomposition/block geometry. A pure migration of the *same* global mesh: exactly
  conservative, field bit-identical. (`test_amr_distributed_rebalance_mpi`, np=1,2,4,8: WORLD==SELF mesh
  + field, Σ V·f + leaf count conserved, max/mean imbalance drops.)
- [x] **Lagrangian rebalance** — `tpx::halo::rebalanceByParticleCount(dec, mig, pos, payload, …)`: bin
  particles onto the grid → weighted re-decompose in place → migrate with the existing
  `tpx::halo::ParticleMigrator`. The dem consumer (`KokkosParticleHalo::rebalance`) packs the committed
  SoA, migrates ownership, and re-uploads; wired into `demStepMpi` via
  `enable_mpi_step(rebalance_every=N)` / the `rebalance()` binding. (`test_particle_rebalance` np=1,2,4,8;
  dem `tests/kokkos_mpi/test_rebalance_mpi` np=1,2,4 on OpenMP + CUDA/Blackwell.)
- [x] **Python**: `tpx_mpi.Migrator.rebalance()` (core, mpi4py) and `Sim.rebalance()` /
  `enable_mpi_step(rebalance_every=…)` (dem) expose it; validated count-conserving with an imbalance drop.

## Cross-cutting / ongoing

- Keep `morton` as the spatial-index primitive; adopt its octree where hierarchical indexing
  helps. **Integrated (2026-06-22):** `morton` ships a portable Kokkos backend and is consumed
  through the Kokkos-MPI build by `core` (`MortonIndexer`) and `vorflow` (device
  tessellator Z-order grid ordering); raw CUDA in `morton` retired.
- Each phase lands with tests + docs; no method depends on another method (dependencies point down).
