# Design decisions — core

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### AMR PCG must mask solid AND project onto the fluid range (mask + fluid-only mean), not just deflate the constant mode
- area: core
- source: device-naming-retirement.md:89-95
- decided: undated
- status: settled
- quote: |
    **maskSolid FIX (transport-core 3aff1ab, pushed):** the AMR PCG (`pcg.hpp`) deflated only the
    constant (`removeMeanVol`), NO maskSolid ⇒ CG amplified the solid/near-disconnected null modes ⇒ the
    Stokes ~1e24 blow-up. Added `buildFluidMask` (op diagonal Σ_f w_f + bcDiag > tiny) + project every
    Krylov vector onto the fluid range (mask solid + fluid-only mean — the old mean wrongly averaged over
    ALL cells incl. pinned solid).
- rejected: deflating only the constant/all-cell mean without masking solid cells
- why: without masking, CG amplified the solid/near-disconnected null modes, causing the Stokes blow-up (~1e24)

---

### Anisotropic coarse-grid partitioning requires cellExtent, not raw cell-count kLargest
- area: core
- source: mg-decomposition-alignment.md:43
- decided: undated
- status: settled
- quote: |
    - **The anisotropy trap.** First coarse-first attempt made imbalance WORSE (up to 4.0) and split
      the channel's wall-normal y on 24/24 ranks: a coarse grid whose axes were coarsened by DIFFERENT
      factors has anisotropic cells, so the ORB's raw-cell-count `kLargest` picks the wrong axis. Hence
      `cellExtent`. Any new coarse-grid partitioning must carry it.
- rejected: partitioning by raw cell-count kLargest on an anisotropic coarse grid
- why: "a coarse grid whose axes were coarsened by DIFFERENT factors has anisotropic cells, so the ORB's raw-cell-count kLargest picks the wrong axis"

### Convention: keep NBX tag families >= 64 apart
- area: core
- source: nbx-round-tag-race.md:28
- decided: 2026-09-02
- status: settled
- quote: |
    **How to apply:** for any MPI hang, first `snellius/stack_census.sh` (parallel gdb over a node),
    then `PECLET_CORE_HALO_TIMEOUT=<s>` on a `-g` build (core `daf6881`) [...] Keep NBX tag
    families >= 64 apart.
- rejected: none stated
- why: none stated (follows from the round%64 tag scheme)

---

### Device-vs-host numerical comparison policy: bit-exact assembly, tolerance-based apply on CUDA/HIP
- area: core
- source: kokkos-cuda-constexpr-required.md:27-30
- decided: 2026-07-23
- status: settled
- quote: |
    - Device-vs-host comparison policy (locked into the core tests 2026-07-23): assembled
      CSRs/coefficients bit-exact on ALL backends; apply/V-cycle results bit-exact on
      OpenMP/Serial, round-off relative tolerance (1e-12 apply / 1e-9 V-cycle) on CUDA/HIP —
      FMA contraction reorders per-face sums.
- rejected: requiring bit-exact apply/V-cycle results on CUDA/HIP (impossible given FMA contraction)
- why: "FMA contraction reorders per-face sums" on CUDA/HIP, so only OpenMP/Serial can be bit-exact for apply/V-cycle; assembly itself must still be bit-exact everywhere

### GPU-aware MPI auto-detection uses query + checksum loopback probe, never blind probing
- area: core
- source: suite-mpi-gpu-campaign.md:16
- decided: undated
- status: settled
- quote: |
    core 589969a: ... GPU-aware MPI auto-default = MPIX_Query_cuda_support AND checksum loopback probe (blind probing SEGFAULTS on non-cuda UCX — probe is validation only, not discovery); env PECLET_CORE_GPU_AWARE_MPI still forces;
- rejected: blind device-pointer probing to auto-detect CUDA-aware MPI
- why: blind probing segfaults on non-CUDA UCX builds

---

### Gate the CUDA-aware MPI device path on an explicit env var, not the MPI query API
- area: core
- source: suite-distributed-status.md:353
- decided: undated
- status: settled
- quote: |
    Device-pointer MPI works; gate the device path on env
    `TPX_CUDA_AWARE_MPI=1` (NOT `MPIX_Query_cuda_support()`, which mis-reports 0).
- rejected: relying on MPIX_Query_cuda_support() to detect CUDA-aware MPI
- why: MPIX_Query_cuda_support() mis-reports 0 in this environment

---

### Halo topology vs exchange split: topology stays host MPI plumbing, exchange is the device kernel
- area: core
- source: device-naming-retirement.md:32-40
- decided: 2026-06-27
- status: settled
- quote: |
    ## Halos (Phase 2-3, transport-core + sdflow + dem)
    The exchange and the topology are split: **topology = host MPI plumbing (neighbour discovery, not a
    kernel) — keep; exchange = the device kernel.** So:
    - `DeviceGridExchangeKokkos` → **`GridHalo`** (canonical device exchange); host `GridHalo` (topology +
      oracle host-exchange) → **`GridHaloTopology`**. Device built from `GridHaloTopology::flatten()`.
    - `DeviceParticleHaloKokkos` → **`ParticleHalo`**; host `ParticleHalo` → **`ParticleHaloTopology`**.
    - **`ParticleMigrator` UNCHANGED** (migration ≠ ghost halo; distinct op).
- rejected: none stated
- why: topology (neighbour discovery) is not itself a kernel and stays host-side plumbing; only the exchange is device work

### Kokkos CUDA installs MUST set Kokkos_ENABLE_CUDA_CONSTEXPR=ON
- area: core
- source: kokkos-cuda-constexpr-required.md:10-22
- decided: 2026-07-23
- status: settled
- quote: |
    **Failure mode (hit 2026-07-23, cost hours):** `extern/install/nvidia-cuda` was built without
    `Kokkos_ENABLE_CUDA_CONSTEXPR` ⇒ no `--expt-relaxed-constexpr` on the Kokkos interface ⇒ nvcc
    compiles a constexpr **host** function called from `__host__ __device__` code (morton's
    `std::array::operator[]` inside `Morton::encode`/`decode`) with only warning #20013/#20015 —
    and the device call **silently returns 0**. Symptom in core: every device-assembled AMR operator
    came out empty (`nFaces dev=0`), the AMR flow projection was a no-op (div ≡ 0, pres iters 0),
    Z&H flows free-accelerated. The device-assembly phases (D1–D6) had only ever been validated on
    OpenMP, where device==host hides it.

    **Why:** fixed in umbrella `tools/bootstrap_deps.sh` (nvidia-cuda branch now passes
    `-DKokkos_ENABLE_CUDA_CONSTEXPR=ON`, commit 0375abc). Rebuild the install
    (`tools/bootstrap_deps.sh nvidia-cuda`) after pulling; with it core's device AMR suite passes
    113/113 on CUDA (assembled CSRs bit-exact host==device; only the apply differs by FMA ~1e-16).
- rejected: building the nvidia-cuda Kokkos install without Kokkos_ENABLE_CUDA_CONSTEXPR
- why: without it, nvcc silently returns 0 from constexpr-host-called-from-device code (morton's std::array indexing), silently emptying device-assembled AMR operators

### NBX consecutive rounds must use distinct message tags
- area: core
- source: amr-octree-status.md:786-791
- decided: undated
- status: settled
- quote: |
    NBX BUG FIXED: faceNeighborGather's 2 rounds shared tag 0 → a rank
    draining the request round Iprobe-received another rank's reply (same tag), 8-byte-misaligned parse →
    garbage reqId → segfault at np=4 PERIODIC (periodic=false didn't trigger it, so latent in the Phase-4
    gather). Fix: distinct tags (req=11, reply=12). balance() OK (Allreduce separates its rounds). NBX
    cross-round aliasing lesson: Ibarrier guarantees all ENTER, NOT that a rank finished draining before
    others send the next round — consecutive unsynced NBX rounds MUST use distinct tags.
- rejected: sharing tag 0 across NBX request/reply rounds
- why: "Ibarrier guarantees all ENTER, NOT that a rank finished draining before others send the next round"

### NBX inter-round tag race fixed by rotating the tag per round; buildTopology now verifies promised==requested cells
- area: core
- source: nbx-round-tag-race.md:17-19
- decided: 2026-09-02
- status: settled
- quote: |
    Fixed in core `10294e6`: tag = baseTag + round % 64, counter as an MPI communicator attribute;
    buildTopology allreduce-checks promised == requested cells and throws; gate
    `core/tests/test_nbx_rounds.cpp` (ablated fix fails on a laptop, np=8: 62 wrong-round messages).
- rejected: running consecutive NBX consensus rounds on one communicator with a single fixed tag
- why: "a rank that observed round k's Ibarrier complete posts round k+1's Issends while a neighbour still probing round k's tag swallows them"

### NBX tag interaction: two standing rules for wire tags
- area: core
- source: amr-march-distributed-campaign.md:66-77
- decided: 2026-09-05
- status: settled
- quote: |
    Two standing rules came out of it, now in
    core/CLAUDE.md: direct point-to-point tags stay below 24576, and distinct NBX call sites need
    baseTags distinct modulo 128.
- rejected: none stated
- why: the per-round tag rotation (baseTag + round) walked over the AMR gather tags, breaking np>=4 AMR; fixed with a reserved wire-tag range [24576, 32768) and modulo-128 baseTag separation

### No Rhie-Chow update at cell centres — RC is purely the face term, automatic once uf is separate from interp(u)
- area: core
- source: device-naming-retirement.md:106-108
- decided: 2026-06-28
- status: superseded
- quote: |
    **Rhie–Chow note (Frank corrected me):** there is NO Rhie–Chow update of the CELL centres — cells get
    the plain cell pressure gradient (= gradOf = ½(g⁻+g⁺), already there); RC is purely the FACE term
    (compact face grad vs averaged cell grad) and is automatic once uf is kept separate from interp(u).
- rejected: the earlier framing that treated Rhie-Chow as something applied at cell centres
- why: correction from Frank; RC is entirely a face-term effect

### ParticleHalo gather() throws on capacity overflow instead of silently truncating
- area: core
- source: cuda-kokkos-migration.md:627-629
- decided: undated (packing MPI session)
- status: settled
- quote: |
    FIX: gather() now THROWS on
    no+ng>capacity (no silent truncate); size Simulation capacity for the worst-case band. LESSON: a "numerical
    instability" that only appears past a size threshold and recovers/varies -> suspect buffer overflow, compare
    against the single-GPU ghost count + positions with ample capacity BEFORE theorizing about the solver.
- rejected: silent truncation of ghost count on overflow
- why: silent truncation caused out-of-bounds SoA writes and corruption that looked like a numerical instability

### ParticleHalo periodic self-ghosts default OFF for byte-identical compatibility
- area: core
- source: cuda-kokkos-migration.md:618-621
- decided: undated (packing MPI session)
- status: settled
- quote: |
    Fixed: ParticleHalo::build(pos,rcut,includePeriodicSelf=false) + ParticleMigrator::imagesWithinRcutOfBlock
    (enumerate up-to-3^Dim periodic images, keep those within rcut of a block; allowIdentity=false for self). Self-ghosts
    are LOCAL (no MPI self-messages), appended after received ghosts ([numReceived,numGhost)); forward/forwardPositions/
    reverse + DeviceParticleHaloKokkos handle the tail (flatten() exposes selfIdx+numReceived). Default OFF => byte-identical
    (legacy CUDA device path / python / existing tests untouched, transport-core 12/12); packing KokkosParticleHalo opts IN.
- rejected: making periodic self-ghosts on by default
- why: "byte-identical (legacy CUDA device path / python / existing tests untouched...)"

### Periodic axis needs >=2 ranks
- area: core
- source: suite-distributed-status.md:27-28
- decided: undated
- status: settled
- quote: |
    Periodic-wrap validated (`mpi/validate_periodic.py`): a periodic axis needs ≥2 ranks (no
    self-ghosts); deterministic 2-body + corner wrap exact; serial reference must use TRUE [0,L] domain.
- rejected: none stated
- why: 1 rank on a periodic axis creates self-ghosts

### Port transport-core's device layer first (foundation-first sequencing)
- area: core
- source: cuda-kokkos-migration.md:79-82
- decided: 2026-06-18
- status: settled
- quote: |
    Confirmed decisions (2026-06-18):
    - **Foundation first**: port `transport-core`'s device layer (`DeviceGridExchange` in
      `grid_halo_cuda.cuh`) to a shared `tpx::View<T>`/`Kokkos::View` field + Kokkos halo
      exchange (keep host-staged fallback, add GPU-aware MPI). Then consumers. No double-porting.
- rejected: porting each consumer's halo independently (double-porting)
- why: "No double-porting."

### Rebalance is pure migration (same global mesh, new owners) and must never use transferField
- area: core
- source: dynamic-load-balancing.md:62
- decided: undated
- status: settled
- quote: |
    - Migration ≠ remap: rebalance MOVES cells to new owners (same global mesh), it does NOT change
      refinement — so it's exactly conservative and the global field is bit-identical (no
      interpolation). Don't use transferField for it.
- rejected: using transferField (same-domain old→new octree conservative remap) to implement rebalance migration
- why: rebalance is exact/conservative (no interpolation), whereas transferField is a different operation (remap across changed refinement)

### Treat nvcc warnings #20013/#20015 as errors, not style noise
- area: core
- source: kokkos-cuda-constexpr-required.md:26-27
- decided: 2026-07-23
- status: settled
- quote: |
    - Treat nvcc warnings #20013/#20015 as ERRORS — they mean silent garbage on device, not style.
- rejected: treating #20013/#20015 as benign style warnings
- why: "they mean silent garbage on device"

### Weighted ORB dynamic load balancing is one shared primitive that lives in the core layer
- area: core
- source: dynamic-load-balancing.md:18
- decided: undated
- status: settled
- quote: |
    The fix is ONE shared primitive ⇒ it lives in **transport-core** (the shared layer).
- rejected: implementing separate load-balancing logic per consumer (AMR, dem)
- why: both AMR and dem need the same weighted-ORB rebalance mechanism

### Weighted ORB split boundary must remain on integer cell boundaries
- area: core
- source: dynamic-load-balancing.md:65
- decided: undated
- status: settled
- quote: |
    - Weighted ORB split must stay on integer cell boundaries (blocks are cell-aligned boxes); pick the
      boundary whose cumulative weight is closest to the target fraction.
- rejected: none stated
- why: blocks are cell-aligned boxes

### block_decomposer retired/archived, replaced by transport-core (core)
- area: core
- source: cuda-kokkos-migration.md:57-58
- decided: 2026-06-20
- status: settled
- quote: |
    `block_decomposer` ARCHIVED on GitHub + removed as a suite submodule.
- rejected: none stated (superseded, not a chosen alternative)
- why: none stated in this note (see suite CLAUDE.md: reusable parts extracted into core/)

### coarsenAlignment bug: natural-max alignment over-constrains ORB; cap alignment at 2^4
- area: core
- source: parallel-scaling-study.md:60-64
- decided: undated
- status: settled
- quote: |
    **coarsenAlignment BUG FOUND+FIXED (flow 10872a7):** natural-max alignment (64 for 192^3, 1024
    for 3072-axis) over-constrains ORB → snap turns 96|96 into 128|64 (2:1 cascade, 12:1 worst) AND
    sub-boxes <2*align skip alignment → MG depth collapse. Measured: np24 192^3 27.2→8.0 iters,
    10273→2091 ms (4.9x); weak np24 114→7.0 iters (6.4x). Fix = cap align at 2^4 (all 5 levels
    need). 33/33 ctests; np=2^k paths land on same splits (why channel 1-8 GPU never saw it).
- rejected: natural-max alignment for ORB decomposition snapping
- why: it over-constrains the decomposition and collapses multigrid depth on non-power-of-two rank counts

### peclet-core sdist must vendor its own SuiteNanobind copy, not depend on the umbrella cmake/
- area: core
- source: release-workflow-prep.md:93
- decided: 2026-09-05
- status: settled
- quote: |
    (3) the
    peclet-core sdist was never self-contained (SuiteNanobind from the
    umbrella cmake/) → `peclet[mpi]` broken 0.1.0–0.6.0; vendored copy in core/cmake/, core 0.6.1 +
    peclet 0.7.1;
- rejected: the core sdist referencing the umbrella's cmake/ directory for SuiteNanobind
- why: "peclet[mpi] broken 0.1.0–0.6.0"

---

### toVector must repack a strided device subview to a contiguous buffer before cross-space deep_copy
- area: core
- source: dem-cubes-gpu-pyvista.md:30-34
- decided: undated
- status: settled
- quote: |
    **CUDA getter fix (core commit 1044a95)**: [[dem-global-scale-sphere-limitation]] sibling — `toVector`
    (core/common/view.hpp) aborted for a STRIDED device subview (pos[0:numReal] of a grown LayoutLeft SoA):
    cross-space deep_copy of a strided layout has no copy mechanism. Fix: repack to a contiguous same-space
    buffer first. This is why GPU get_positions/get_quaternions failed mid-sim before. CPU (LayoutRight)
    never hit it.
- rejected: cross-space deep_copy directly on a strided device subview
- why: "cross-space deep_copy of a strided layout has no copy mechanism"
