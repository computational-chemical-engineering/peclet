# Device-Residency & Data-Movement Plan

> Status: plan (living). Goal: keep computation on the GPU device and stop moving data across the
> host↔device boundary. Companion to [ROADMAP](ROADMAP.md), [ARCHITECTURE](ARCHITECTURE.md),
> [PORTABILITY](PORTABILITY.md). Derived from a suite-wide audit (2026-06-28); `file:line`
> references are snapshots — re-grep before acting.

## Goal & principles

1. **Compute where the data lives.** Any per-step or per-iteration loop over field/particle/cell/leaf
   data should be a Kokkos `parallel_for`/`parallel_reduce`, not a host `for`. Host loops are allowed
   only for genuinely serial control logic (MPI consensus, topology sort, file I/O).
2. **Move only what must move, and only the compact part.** Scalars (norms, counts, convergence flags)
   crossing to host are fine. Whole fields/SoA crossing the boundary per step are not. MPI should stage
   only compact boundary buffers (or hand device pointers to a GPU-aware MPI), never full fields.
3. **Keep state resident across steps.** Allocate device scratch once; don't re-upload step-invariant
   data; don't round-trip device→host→device inside a loop.
4. **Host oracles stay.** Several codes keep a serial host reference (AMR `applyOpGeometric`, the
   half-edge `voronoi.hpp`, distributed bit-exactness references). These remain as validation oracles —
   device ports are added *beside* them, not in place of them.

## What is already clean (do not touch)

The audit confirmed the steady-state hot paths are device-resident:

- **sdflow** — `SdflowSolver::step()` (diffusion smooth + cut-cell projection + MG-PCG/Chebyshev) is
  fully Kokkos. Only scalars (dot/residual/`max_abs`/`remove_mean`/pressure-pin) reach host, as PCG
  requires. No per-step field copies.
- **dem** — the single-GPU `demStep` (predict / ArborX broad-phase / narrow-phase / velocity+friction /
  position / commit) runs entirely on device; ArborX consumes device Views directly.
- **core AMR** — for a *static* geometry, `AmrFlow::step()` (momentum BiCGStab/MG, pressure
  MG-PCG, divergence/grad/correct, per-step FOU/SOU advection rebuild) is all device kernels.
- **vorflow** — the tessellation CSR stays device-resident within a step; all physics
  (`euler_pressure`, `viscous`, `interface`) are device kernels.
- **GridHalo** (`grid_halo.hpp`) is the reference pattern: field stays on device, only the compact
  `nSend/nRecv` buffers cross, with a GPU-aware path (`TPX_GPU_AWARE_MPI`) that hands device pointers to
  MPI. Everything below should look like this.

The work is therefore concentrated in *dynamic* assembly, *distributed* compute, *particle migration*,
vorflow's *unused* incremental updater, the *pnm* pipeline, and a recurring redundant host-copy idiom.

## Shared infrastructure to build first

Two reusable pieces in `core` unblock most of the per-repo work and prevent re-solving the
same problem five times:

- **S1 — Device CSR-fill primitive** (`tpx::` device util): the canonical
  *count → `parallel_scan` (exclusive prefix) → fill* pattern for building sparse operators on device,
  replacing the `std::vector<std::vector<pair>>` / `std::vector<std::map<Index,double>>` host assembly
  used throughout AMR. Must fill deterministically (own-slice, atomic-free) to preserve OpenMP
  bit-exactness. Consumed by every AMR assembly item (B-series below).
- **S2 — Zero-copy / single-copy ndarray export helper** in the `tpx::python` bridge: (a) a
  `deep_copy(device_view → unmanaged host View over the destination std::vector)` helper to kill the
  redundant *mirror → element-by-element loop → vector* idiom that appears in **every** binding getter
  (dem, vorflow, sdflow/pnm); (b) an opt-in DLPack / `__cuda_array_interface__` **device** export so a
  CuPy/Torch consumer can read results without any D2H (the input path is already proven; outputs are
  not). The bridge already exists (`include/tpx/python/ndarray_interop.hpp`).

## Themes & workstreams

### Theme A — Dynamic AMR assembly on device (core) — biggest structural gap
All AMR operator/geometry **assembly** is host-serial (the existing `amr_device_assembly_plan.md`
D1–D6). For a static run this is cold; the moment the SDF moves or the mesh `adapt`s, every step becomes
host-bound (host walk + re-upload). Port, on top of **S1**, keeping the host geometric oracles:

| Item | What | Where | Effort |
|------|------|-------|--------|
| B2 | FV openness + `assembleFv` on device | `poisson.hpp:84,347` | S–M (start here) |
| B3 | Cut-cell momentum CSR (`build`/`assembleOperator`/`buildCutStencil`) on device | `cut_cell.hpp:83,162,448` | M–L |
| B4 | Per-face geometry (`buildFaceGeom`) on device | `flow.hpp:67` | M |
| B5 | MG-hierarchy operator rebuild on adapt (`Multigrid`/`MomentumMG` Galerkin/`VelocityMG`) on device | `multigrid.hpp:249`, `momentum.hpp:260`, `velocity_mg.hpp:57` | M–L |
| B6 | Indicators + conservative remap on device | `indicators.hpp:39`, `adapt.hpp:70` | M–L |

Caveats: keep `applyOpGeometric`/`applyLaplacian`/host `transferField` as oracles; device CSR fill must
match `forEachFaceFull`/`forEachFaceNeighbor` emit order; `greedyColoring` may stay host but must not
force the device CSR back to host (`velocity_mg.hpp:103-106` currently does).

### Theme C — Distributed compute on device (core) — multi-GPU scaling
The `distributed_*` solvers are labelled "the distributed compute path" but run per-cell apply/jacobi/
residual/vcycle on host `std::vector` every matvec; only the MPI byte exchange need be host.

| Item | What | Where | Effort |
|------|------|-------|--------|
| C1 | Memoize `DistributedPoisson`'s neighbour-gather topology (mirror what `distributed_fv` caches) — removes a per-matvec `std::map`+`find` rebuild | `distributed_poisson.hpp:52`, `distributed_octree.hpp:319` | M (host-only quick win) |
| C2 | Lift `distributed_poisson`/`distributed_fv` apply/jacobi/residual/vcycle onto device; mirror only the compact ghost buffer (à la GridHalo) | `distributed_poisson.hpp`, `distributed_fv.hpp` | L |

Caveat: bit-identical across rank counts is the contract; each cell sums its own faces, so a per-cell
device reduction is safe.

### Theme D — Particle migration on device (core ⇒ dem, vorflow)
`ParticleMigrator`/`rebalance`/`ParticleHaloTopology::build` are 100% host, so dem must copy its device
particle SoA host→migrate→host→device on every migration; dem's `gather()` additionally rebuilds the
neighbour topology on the CPU **every distributed substep**.

| Item | What | Where | Effort |
|------|------|-------|--------|
| D1 | Device particle `migrate` (device binning + device pack into per-rank buffers + GPU-aware NBX; consensus stays host) | `particle_migrator.hpp:87` | L |
| D2 | dem MPI `gather()`: stop the per-substep full-position D2H + host topology rebuild — rebuild only every N steps (sub-skin displacement) or incrementally | `dem/src/mpi_halo.hpp:165` | L |
| D3 | ParticleHalo perf: cache `forward` scratch (no per-call `view_alloc`); `reverse` gather only the sent `[0,numReceived)` slice instead of the whole ghost array | `particle_halo.hpp:57,125` | S–M |

### Theme E — vorflow incremental update (wire up existing device code)
The stepper does a **full `buildTessellation` + `buildAuxMaps` rebuild every step**; the incremental
machinery (`reevalGeometry`, `isSelfConsistent`, `TopologyStore`, skin/candidate emission, `nbrlist`)
is device-resident code that already exists but is only wired into benches/tests. This is the Phase-2/3
program in `vorflow/docs/dynamic_update_decision_and_plan.md`.

| Item | What | Where | Effort |
|------|------|-------|--------|
| E1 | **DONE** (vorflow `3baf127`, opt-in scaffolding). Wire incremental update into `ExplicitEulerDevice::buildAndForce` instead of full rebuild | `device_simulation.hpp` | L |
| E2 | *Deferred to the user's physics work.* Maintain `buildAuxMaps`/reciprocity incrementally rather than rebuilding each step | `transpose.hpp:34` (via `device_simulation.hpp`) | M (coupled to E1) |
| E3 | Cache the **step-invariant** worklist offset table — kill the per-step host `std::sort` + two H2D copies in `buildTessellation` | `tessellator.hpp:516-582` | M |
| E4 | Hoist per-call scratch: persistent `9*N` viscous scratch; upload the mass array once at init | `viscous.hpp:126`, `vorflow_bindings.cpp:93` | S |

Caveats: topology decisions need FP64 (FP32 marginal-face flicker); the half-edge `voronoi.hpp` oracle
stays as the validation reference.

### Theme F — pnm extraction pipeline (sdflow) — one-shot, but big host work
The CFD solver is clean; pnm is where the avoidable host work lives.

| Item | What | Where | Effort |
|------|------|-------|--------|
| F1 | Fuse stages: keep SDF/labels/seg device-resident across `extract_pores`→`segment_volume`→`extract_topology` (today each re-uploads the SDF; `segment_volume` copies the full label volume to host and re-uploads `seg`) | `pore_extraction.hpp:208-227,240-242` | M–L |
| F2 | Device dense-remap to replace the serial host `std::map` relabel over every voxel (preserve the pore>0 asc / solid<0 desc / debris 0 ordering) | `pore_extraction.hpp:214-227` | M |
| F3 | Bulk uploads: replace per-element host fill with an unmanaged-View single `deep_copy` (also S2) | `pore_extraction.hpp:50,110,240` | S |

### Theme G — Cheap, broad cleanups (do early, low risk)
| Item | What | Where | Effort |
|------|------|-------|--------|
| G1 | Replace the redundant *mirror → element loop → vector* idiom in all binding getters with **S2** | `dem/src/sim.hpp:461-483`, `vorflow_bindings.cpp:97-128`, `sdflow pore_extraction.hpp` | S |
| G2 | dem: drop the duplicate pair-count D2H (`broadphase_arborx.hpp:88` vs the `readInt` in `sim.hpp:76`) | dem | S |
| G3 | dem: reduce per-substep scalar count read-backs (4 device fences/substep) via device-side launch sizing or fused kernels — latency, not bandwidth | `dem/src/sim.hpp:69,77,85,88` | M |
| G4 | sdflow: move `setSolid`/`uploadVelocity` single-rank periodic ghost wrap to device (mirror the distributed inner-fill + device `fillGhosts`) | `sdflow_ibm.hpp:196,128` | S–M (cold) |
| G5 | core: `deviceRemoveMeanFv` recomputes each diagonal 3×; cache fluid-mask+volume once | `fv_op.hpp:149` | S |
| G6 | core: batch the 3 separate D2H copies in Python `Flow::velocities()` into one | `tpx_amr.cpp:359` | S |
| G7 | morton: add `MORTON_HD` to `operator== != <= >=` (`morton.hpp:458-463`), `wide_uint` operators, and the range-query primitives `bigmin`/`litmax_bigmin`/`in_box` (`iterate.hpp:64,106,186`) so consumers can do device sort/search/range-scan and build a device-resident octree query path | morton | S–M |

### Theme H — GPU-aware MPI & device outputs (cross-cutting)
- **H1** — `TPX_GPU_AWARE_MPI` exists in GridHalo but is opt-in/host-staged by default. Make GPU-aware
  the validated default where the MPI stack supports it (the multi-GPU tuning track in ROADMAP), so the
  device path never touches host even for the compact buffers. Effort M (mostly validation).
- **H2** — DLPack / `__cuda_array_interface__` device export for `get_*` accessors across sdflow, dem,
  vorflow on the shared bridge (**S2b**), so GPU-resident Python analysis chains avoid D2H entirely.
  Opt-in (changes the return contract numpy→cupy). Effort M.

## Phased roadmap

- **Phase 0 — quick wins (low risk):** ✅ **DONE** (umbrella 774199b, 2026-06-29). S2a helper, then
  G1–G2, G4–G7, E3–E4, C1, D3, F3. Mechanical, high-ratio, no algorithm changes. Knocked out the
  redundant-copy idiom suite-wide and the step-invariant H2D in vorflow. Per-repo commits:
  core b976351 (S2a `tpx::toVector`, C1 gather-plan memoization, D3 ParticleHalo scratch +
  reverse-slice, G5 fused fv removeMean, G6 one-D2H `velocities()`), morton 45be8c7 (G7 `MORTON_HD` on
  comparisons / `wide_uint` / range queries), dem 635b13f (G1 getters, G2 dup pair-count), vorflow
  3a843b9 (G1 getters, E3 `WorklistCache`, E4 viscous scratch + upload-mass-once), sdflow 7c25b9c
  (F3/G1 pnm bulk copies, G4 single-rank IBM device wrap). Validated per-repo on host-openmp
  (core 25/25 ctests np 1–8; device tessellation/step/viscous bit-exact; Python roundtrips).
- **Phase 1 — dynamic AMR assembly (Theme A):** build S1, then B2 → B3 → B4 → B5 → B6. Unlocks
  moving-boundary / solution-adaptive AMR with no host round-trip. Largest single payoff.
  **DONE (core):** S1/D1 + B2/D2 (device FV assembly, `8d32a9e`), B3/D3 (device cut-cell
  stencil + momentum assembly, `f24d72d`), B4/D4 (device face-geometry assembly, `d1d48ad`), B5/D5 +
  B6/D6 (MG-hierarchy rebuild + flow wiring). The S1 CSR-fill primitive (`device_csr.hpp`) + the FV /
  momentum / face-geometry device assemblers (`device_assembly.hpp`, `device_momentum_assembly.hpp`,
  `device_facegeom_assembly.hpp`) are each bit-exact vs their host oracle on OpenMP (`amr_device_assembly`
  / `amr_device_momentum` / `amr_device_facegeom`). D5: the FV **pressure multigrid** rebuilds its
  per-level operators on device (`Multigrid::buildFaceCsr` → `deviceAssembleFv`; `reassembleOperators()`
  is the adapt-time hook). D6: **`AmrFlow::setSolid`** assembles the momentum operator, face geometry, and
  pressure hierarchy entirely on device — no host CSR walk, no operator round-trip (`FaceGeom` extracted to
  `face_geom.hpp` to break the assembler↔flow include cycle). Device flow stays correct
  (`test_amr_flow_solver`: poiseuille L2 7e-17, advection device==host exactly, sphere rel 7e-5; full
  57-test AMR suite green np=1–8). SDF/openness sampling stays host-staged (a device SDF sampler is its own
  item). **Remaining refinements (not blocking):** the momentum *preconditioner* hierarchies still build on
  host — `MomentumMG` is a Galerkin RAP (needs a device SpMM triple-product), `VelocityMG` staircase is a
  per-level rediscretize (a device assembler like the FV one); plus a fine-grained `AmrFlow` dirty-flag
  reassemble (today a moving boundary re-calls `setSolid`, which already assembles on device) and a
  setSolid host-vs-device assembly benchmark.
- **Phase 2 — vorflow incremental update (Theme E):** **E1 DONE** (vorflow `3baf127`, opt-in). The
  fluid step (`ExplicitEulerDevice::buildAndForce`) can now use the moving-point repair
  (`MovingTessellation`) for the topology + a reeval-publish of the force geometry
  (`device/reeval_tessellation.hpp` `reevalPublish` — re-eval each cell over its stored topology and
  pack the same facet-CSR `TessellationView` the full build emits, reusing the repair's volumes)
  instead of a full rebuild each step. Default OFF (`setRepair(true)` / `Simulation.set_repair(True)`
  to enable); the full-rebuild path is byte-unchanged. Validated: repair path reproduces the
  full-rebuild trajectory to round-off (pos 1.5e-11, vol 1.2e-13, internal-E 8.6e-13; ~0.5% of cells
  flicker ±1 marginal zero-area face, no force effect). **E2 (incremental aux/CSR reuse) deferred to
  the user's ongoing physics work** — this is scaffolding to build the physics on, per the user.
- **Phase 3 — distributed device compute + device migration (Themes C, D):** C2, D1, D2, then H1 and at-
  scale multi-GPU validation. The multi-GPU scaling track. **C2 DONE (core 71cd629):** the
  distributed AMR Poisson + multigrid run device-resident — `DistributedGatherHalo` (value-only octree
  gather over a once-established NBX topology; `DistributedOctree::buildGatherHaloTopology`) +
  `DistributedPoissonDevice` + `DistributedMultigridDevice` in `distributed_device.hpp`. The V-cycle is
  all Kokkos kernels, mirroring only the compact ghost buffer across MPI (à la `grid_halo.hpp`); bit-for-
  bit vs the host MG (same decomposition) and the single-block reference at np=1,2,4
  (`amr_distributed_device`). **D1 DONE (core 02de4ce):** `ParticleMigratorDevice`
  (`particle_migrator_device.hpp`) keeps the particle SoA on device — device binning (periodic wrap +
  ORB ownerOf via `BlockDecomposer::flattenTree`) + device compaction/pack of departing particles; only
  the compact migrating records host-stage for the NBX consensus. Validated (`particle_migrator_device`,
  np=1,2,4,8): count conserved, every particle on its owner, id multiset preserved. **D2 DONE (dem
  5c70aa1):** `KokkosParticleHalo::gather` reuses the owner↔ghost topology under a Verlet skin (build with
  rcut+skin, rebuild only when a particle moves > skin) — opt-in via `enable_mpi_step(verlet_skin=…)`,
  skin=0 unchanged. Validated (`test_demstep_mpi`, np=1,2,4, closed+periodic): distributed-with-reuse ==
  single-rank rebuild-every-substep, reuse triggers (1 rebuild / 8 gathers). **H1 PARTIAL (core
  346bf0f):** the device distributed gather halo gained the `TPX_GPU_AWARE_MPI` device-pointer-MPI path
  (host-staged default), validated on OpenMP (both paths pass the bit-exact lock). **Remaining (hardware-
  gated):** flip GPU-aware to the validated default + at-scale multi-GPU benchmark, and a GPU-aware NBX
  engine (which would let D1's migrator skip host-staging too) — both need real multi-GPU hardware.
- **Phase 4 — pnm + device outputs (Themes F, H2):** F1/F2, H2. Lower frequency, real but one-shot.
  **DONE.** F3 landed in Phase 0; F2 (sdflow `26290b0`) replaces the host `std::map` segmentation
  relabel with a device dense-remap (the first-encounter id = exclusive prefix sum of a per-label
  first-occurrence flag — no host map, no labels/roots D2H; proved a fixed point of the host relabel).
  F1 (sdflow `d793ae5`) splits each pnm stage into a device core + thin host wrapper and adds the fused
  `extract_pore_network` (SDF uploaded once, segmentation device-resident across extract_pores →
  segment → topology); also fixes the pre-existing `extract_topology_gpu` `vector<pair>` return via
  `nanobind/stl/pair.h`. H2 (dem `07a8985`) wires the bridge's `view_to_ndarray` (S2b) into opt-in
  zero-copy device getters (`get_positions_device`/`get_velocities_device` — NumPy view on host,
  DLPack/CuPy on GPU; proved zero-copy by shared data pointer); the same pattern applies to
  sdflow/vorflow. Caveat: a device-export array holds a ref-counted View, so release it before the
  module's atexit `Kokkos::finalize` (hence opt-in).

## Validation & correctness invariants

- Every device port keeps its host oracle and is checked against it (AMR geometric operators; vorflow
  half-edge tessellation; distributed bit-exactness across rank counts).
- Device fills must be **deterministic** (own-slice, atomic-free, fixed emit order) to preserve the
  OpenMP-backend bit-exactness the tests rely on; GPU is tolerance-not-bit-exact by the FMA convention
  already documented.
- Topology/geometry decisions that need it stay in FP64 (vorflow marginal faces).
- Add per-step **D2H-byte counters** (debug build) so regressions in data movement are caught the way
  the bit-exact ctests catch numerical regressions.
