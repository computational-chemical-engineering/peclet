# Design decisions — voro

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### -ffast-math based reciprocal speedups are a ceiling, not shippable
- area: voro
- source: vorflow-cpu-migration-discussion.md:52-54
- decided: 2026-06-27
- status: settled
- quote: |
    Also: a scoped scalar fast-reciprocal (vrcpps+Newton,
    frecip helper) measured NEGLIGIBLE; the big -ffast-math FP32 numbers (scalar 9.1/SIMD 22 synthetic) are a
    package (reassoc+vectorise+vec-reciprocal) that also relaxes FP64 exactness — a ceiling, not shippable.
- rejected: shipping -ffast-math-based reciprocal speedups
- why: the speedup package also relaxes FP64 exactness, making it a ceiling estimate rather than a shippable optimization

### 4th-face restored: cert made complete again, per-step displacement gate and brute fallback removed
- area: voro
- source: vorflow-dynamic-updater-phase01.md:170
- decided: 2026-06-30
- status: settled
- quote: |
    **4th-FACE RESTORED → complete cert + clean side-by-side vs OLD poke — DONE+COMMITTED 2026-06-30
    (vorflow 5b7c23b, umbrella c8f445d, NOT pushed).** The 3-edge adj cert was a strict SUBSET of brute
    (dropped the dual tet's 4th face) → missed far-pokes → needed the per-step disp gate + brute fallback +
    was only within-tol (~1e-4) at smallest δ/h. FIX: added `ConvexCell::face4` ... cert now tests 3 adj-edge
    planes + face4 per triangle = matches brute flag set ... **REMOVED the per-step gate / certDispLimit / xPrev**
    (cert complete → teleports go through normal detect→gather→verify). **Repair MACHINE-EXACT at EVERY δ/h
    (maxRelV~1e-15), matches old, no fallback.**
- rejected: the per-step displacement gate + brute-cert fallback from the TrackAdj-only design
- why: "cert complete → teleports go through normal detect→gather→verify"

### A1 curved-wall shift: in-loop shift and post-pass plane translation rejected on measurement
- area: voro
- source: voronoi-methods-plan.md:50-52
- decided: 2026-09-03
- status: settled
- quote: |
    **Rejected on measurement:** in-loop shift (the vertex
    loop undoes it; suppressing cuts by shift size wrecks concave walls) and post-pass plane
    translation (invalid polytope → certificate flags every step).
- rejected: in-loop shift application; post-pass plane translation
- why: in-loop shift is undone by the vertex loop and wrecks concave walls when cuts are suppressed by shift size; post-pass plane translation produces an invalid polytope that fails certification every step

### A2 re-scoped: exact power diagram not needed for non-overlapping packings
- area: voro
- source: voronoi-methods-plan.md:74-78
- decided: 2026-09-03
- status: settled
- quote: |
    **A2 RE-SCOPED** (`voro/docs/power_large_weights_plan.md`): w=r² of NON-overlapping packings is an
    exact partition (RSA φ=0.25, ratio 1..10: ΣV−1 = 0, no buried cells; d_ij ≥ r_i(r_i+r_j) > 0) ⇒
    D/E/F/G don't need A2; buried cells (engine empties them, wrongly) need a centre inside another
    sphere (uniform-random balls lose 2.5–9 %).
- rejected: treating A2 (exact power diagram at large weights) as a load-bearing prerequisite for tracks D/E/F/G
- why: non-overlapping packings' w=r² already form an exact partition; buried cells only arise from centres inside another sphere, a separate diagnostic issue

### Any per-rank branch between two MPI collectives must be a global (allreduced) decision
- area: voro
- source: vorflow-dynamic-updater-phase01.md:248
- decided: 2026-07-01
- status: settled
- quote: |
    **MPI np≥4 DEADLOCK SOLVED** — was NOT pre-existing-in-unchanged-
    code as I'd thought; it's a `bench_repair_mpi.cpp` DRIVER bug (not transport-core/vorflow): the per-step
    driver chose re-gather (VoronoiHalo::gather, NBX topo rebuild) vs refresh (refreshPositions/forwardDirect)
    PER-RANK from a LOCAL skin-trip test; both COLLECTIVE w/ different patterns → ranks diverge at larger δ/h
    → mismatched collectives → deadlock ... FIX = global decision `MPI_Allreduce(localTrip,MAX)` → ANY
    trip ⇒ ALL re-gather (distributed-Verlet invariant). ... LESSON: any per-rank branch between two collectives
    must be a GLOBAL (allreduced) decision.
- rejected: per-rank local skin-trip decision of which collective pattern to run
- why: "ranks diverge at larger δ/h → mismatched collectives → deadlock"

### Backend-aware grid seed density: 2 seeds/cell on CPU (Voronoi), 1/cell on GPU and for Power
- area: voro
- source: vorflow-kokkos-migration.md:1091-1095
- decided: undated
- status: settled
- quote: |
    (b) **backend-aware grid density** `kSeedsPerCell = (host && !Power) ? 2 : 1` — ~2
    seeds/cell on CPU (fewer, contiguous cell lookups = cache win) but 1/cell on GPU (gather is
    bandwidth-hidden there; coarser only adds per-thread work) and 1/cell for Power (its
    no-early-out full-sphere gather exceeds MAXCAND at 2/cell — that was the bug to avoid).
- rejected: a single fixed seeds/cell density across backends and weight types
- why: 2/cell regresses GPU throughput; 2/cell overflows MAXCAND for Power's full-sphere gather

### Backend-specialise the Voronoi gather: CPU uses worklist, GPU keeps legacy expanding-shell gather
- area: voro
- source: vorflow-worklist-into-tessellator.md:48-58
- decided: 2026-06-27
- status: settled
- quote: |
    A/B (FP64, N=4M) of the worklist on the device
    range path REGRESSED the PRODUCTION force-geometry path: geom-OFF (pure tess) 2.5→3.8 Mcell/s (win) but
    geom-ON 2.13→1.3–1.8 Mcell/s (−15–35%). **Root cause: the device cut is FUSED with the register/occupancy-
    bound geometry kernel [...] so the worklist's heavier gather steals occupancy from geometry** [...]
    **Fix: backend-specialise the Voronoi gather — CPU=worklist on-the-fly (1.4×), GPU=legacy expanding-shell
    gather (unchanged, geom-on back to 2.12 = bit-identical to pre-port, ZERO regression).**
- rejected: the worklist gather on the device (GPU) path
- why: "the worklist's heavier gather steals occupancy from [the fused] geometry [kernel]"

### Blanket reclip-every-cell (S6) does not pay off — persistent Verlet list must be paired with GATED reclip
- area: voro
- source: vorflow-dynamic-update-strategy-study.md:72-77
- decided: undated
- status: settled
- quote: |
    4d. **S6 reclip-all + "does D2 detection earn its keep?" (vorflow b2c6693, pushed)**: S6 = canonical Verlet
       usage = reclip EVERY cell each step off the stored skin list (no re-gather, no detection; Verlet rebuild on
       trip). Exact (mism 0, listMiss 0) but only **3.0× host / 1.05× GPU** vs full rebuild — on GPU ~nothing because
       the production worklist is CLIP-bound (gather already cheap), so reclipping all cells pays ~the whole per-cell
       cost. ⇒ the persistent Verlet list pays off via GATED reclip (reclip only the D2-changed ~15%: S3 9× host /
       3.7× GPU), NOT blanket reclip. At high disp (≥0.005) detection stops paying → S6/Verlet-rebuild win.
- rejected: blanket reclip of every cell each step (S6) as the production strategy
- why: "on GPU ~nothing because the production worklist is CLIP-bound ... reclipping all cells pays ~the whole per-cell cost"

### C1 gate metric was wrong: cellwise-residual "2nd order" is not the right convergence gate
- area: voro
- source: voronoi-methods-plan.md:85-88
- decided: 2026-09-03
- status: superseded
- quote: |
    C1 landed:
    `fv/mesh.hpp` FaceMesh + `fv/operators.hpp` (covolume div/grad/L/Green–Gauss/Perot/CG): Poisson
    SOLUTION order 2.03 on a jittered lattice while the cellwise residual is INCONSISTENT (order 0.2 —
    two-point flux at the connector midpoint, skewness) → the plan's "div grad 2nd order" gate was the
    wrong metric.
- rejected: the plan's original "div grad 2nd order" convergence gate
- why: cellwise residual consistency (order 0.2, from skewness) does not track the solution order (2.03) — they measure different things

### C2b collocated is the ABC approximate projection, NOT Rhie-Chow
- area: voro
- source: voronoi-methods-plan.md:96-97
- decided: 2026-09-03
- status: settled
- quote: |
    **USER RULING (2026-09-03): C2b collocated = ABC approximate projection (as flow's SolverColocated),
    NOT Rhie–Chow.** Plan V4/C2b updated.
- rejected: Rhie-Chow interpolation for the collocated pressure coupling
- why: none stated beyond matching flow's SolverColocated

### C3 wall Poiseuille is not exact to round-off; the plan's claim was wrong
- area: voro
- source: voronoi-methods-plan.md:128-130
- decided: 2026-09-03
- status: superseded
- quote: |
    Poiseuille between SDF slabs order 2.00 both solvers (identical on the
    lattice); the parabola is NOT exact — the two-point wall flux is the derivative at h_A/2 (wall-row
    residual exactly f/4); the plan's "exact to round-off" claim was wrong.
- rejected: the plan's "exact to round-off" claim for wall-bounded Poiseuille
- why: the two-point wall flux is the derivative at h_A/2, leaving a residual exactly f/4, not zero

### C4 closed: quadratic wall gradient (wallGradientLS) is the default viscous wall flux
- area: voro
- source: voronoi-methods-plan.md:147-153
- decided: 2026-09-03
- status: settled
- quote: |
    **C4 CLOSED 2026-09-03 (quadratic wall gradient):** `wallGradientLS` (wall-anchored LS quadratic
    through wall + cell + neighbours, tangential part removed with the cell gradient; flow's
    centerToFaceWallAware idea) as the viscous wall flux, default in both solvers ⇒ Poiseuille EXACT
    (residual 5e-11) and SC sphere drag −2.43/−0.96/−0.37 % at n=16/24/32 vs Z&H (2nd order; flow
    cut-cell −0.49 % @32). The two-point wall flux was the whole C4 problem, not the geometry.
- rejected: the plain two-point wall flux as the viscous wall flux
- why: the two-point wall flux (not wall geometry / fat cells) was the entire source of C4's first-order wall-shear error

### Candidate-array shrink tried and reverted — array size cannot shrink below full-sphere gather need
- area: voro
- source: vorflow-kokkos-migration.md:1141-1147
- decided: undated
- status: settled
- quote: |
    **Candidate-array shrink TRIED, DEAD (commit 360c133):** ckey/cjid[1024]≈12KB/thread can't
    shrink — arrays must hold the full-sphere gather (nOff=667 at sw=4 + Poisson fluctuation; every
    Power cell + any fully-expanding Voronoi cell hits it). GPU cap 512 overflows (all Power + 1/4000
    Voronoi → wrong); safe min ~896 gives no gain (1.5KB of 33KB doesn't move occupancy). Reverted to
    1024 + gated `[worklist] nOff` diagnostic.
- rejected: shrinking the candidate array below 1024 (tried 512, safe-min ~896)
- why: "GPU cap 512 overflows (all Power + 1/4000 Voronoi → wrong); safe min ~896 gives no gain"

### Clip designs must be valid-by-construction; the topological inconsistency is the bug class to design out, not geometric imprecision
- area: voro
- source: robustness-topology-oriented-sugihara.md:26
- decided: undated
- status: settled
- quote: |
    - Prefer clip designs that are **valid by construction**. The convex-clip (intersection of
      half-spaces) is naturally convex-valid... The kind of bug to design OUT is a *topological
      inconsistency*, e.g. the ConvexCell dead-triangle phantom-horizon cascade — a topology-oriented
      construction would keep the dual triangulation consistent by combinatorial rules, not by a
      more-accurate predicate.
- rejected: fixing topological-inconsistency bugs (e.g. dead-triangle phantom-horizon cascades) by using more-accurate geometric predicates
- why: a topology-oriented construction keeps consistency "by combinatorial rules, not by a more-accurate predicate"

### Cold-build construct is DONE at ~14.5 M/s ceiling — do not reopen; Part II (moving points) is the real remaining win
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:156-161
- decided: undated
- status: settled
- quote: |
    **FINAL STANDING (construct is DONE — don't reopen): cached findSharing cell @ ~14.5 M/s (LaunchBounds
    <256,4>) is the GPU ceiling and ≥ the running SOTA code's construct (9.5). All levers tested & lost:
    best-first gather 0.22×, packing/recompute 0.72×, adjacency 0.46× GPU [...] cap-shrink neutral,
    incremental-radius neutral, occupancy +10% (kept), no-op-cull 0.96×. [...] The ONLY real remaining
    win is Part II (moving points: topology reuse, re-runs only G at 12-18 M/s, skips the gather entirely)
    — the actual workload.**
- rejected: further cold-build construct optimization
- why: none beyond the exhaustive negative-result list

### Cold-build gather cost (~70 distance tests/cell) is near-optimal, not wasteful — stop chasing gather tweaks
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:34-50
- decided: undated
- status: settled
- quote: |
    The gather examines **~70–108 distances per 15-face cell — and that is
    ~optimal, not wasteful** [...] **What does NOT help (each measured ≈0):** Morton/Z-order vs row-major point order [...]
    branchless wrap vs int-modulo; caching secR2; shrinking MAXP/MAXT caps [...] **What helps (kept):**
    spatial (binned) seed order 1.16–1.20×; finer grid + matched window [...] **Don't
    chase the cold build with more gather tweaks — Part II (moving points) reuses topology and re-runs only
    G at 12–18 M/s, skipping the gather entirely; that's the real win.**
- rejected: Morton/Z-order point ordering; branchless wrap vs int-modulo; caching secR2; shrinking MAXP/MAXT caps; further gather tuning generally
- why: "the gather is NOT memory-latency-bound, it's distance-COUNT/throughput-bound"

### ConnectivityArena 2-ring surgical retry is also a negative result
- area: voro
- source: vorflow-dynamic-updater-phase01.md:76
- decided: 2026-06-29
- status: settled
- quote: |
    **Phase 4 RETRY with ConnectivityArena 2-ring = ALSO NEGATIVE** (2026-06-29, tried per user request,
    reverted — not committed): fed surgical the 2-ring (buildRing: 1-ring ∪ nbrs' 1-rings from the store)
    instead of stored∪partner. Three obstacles, decisive: (1) gains are invisible to the certificate, so
    ANY almost-complete candidate set compounds ... (2) Unsorted re-clip of the ~60-candidate 2-ring
    overflows ConvexCell's plane cap ... (3) Overflow-safe needs per-cell sort of ~60-128 cands = GPU-local-mem-hostile,
    and the 2-ring isn't smaller than the gather's set anyway → not faster (2.05× vs gated-gather 2.98×).
    CONCLUSION: candidate-re-clip surgical (stored∪partner OR 2-ring) is a dead end on this clip-bound engine;
    only TRUE O(1) dual-triangle single-face surgery could win (needs robust exact predicates, avenue G, high-risk).
    Phase 4 parked.
- rejected: ConnectivityArena 2-ring candidate set for surgical repair
- why: "gains are invisible to the certificate, so ANY almost-complete candidate set compounds"

### Construct is bound by intrinsic clip-chain work; packing and warp-cooperative rejected
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:52-66
- decided: undated
- status: settled
- quote: |
    Tested the footprint hypothesis directly — `convex_cell_compact.hpp` [...] ran **0.72×** the cached cell
    [...] EVERY lever to cut it has lost: packing (0.72×), explicit adjacency
    (earlier GPU-neg), incremental security radius (earlier GPU-neg), cap shrink (neutral). **14.5 M/s IS the
    ceiling and already ≥ Ray V100 12.5.** [...] Warp-cooperative is contraindicated (occupancy says want MORE cells in flight; 1-cell-per-warp =
    32× fewer; the earlier naive attempt's 0.6× was right). **Don't reopen cold-build construct or
    warp-cooperative; the only real win left is Part II (moving points)**
- rejected: packed/compact cell representation; warp-cooperative register-resident cell construction; explicit adjacency; incremental security radius
- why: "the construct is bound by intrinsic serial clip-chain work"

### ConvexCell (dual-triangle) chosen as the GPU topology, not the half-edge cell representation
- area: voro
- source: vorflow-kokkos-migration.md:1233-1241
- decided: undated
- status: settled
- quote: |
    **F2 decision: ConvexCell (dual-triangle) is the GPU topology** (2.2x build, 9x
    smaller frame, fast construct). Keep half-edge as oracle + serial-CPU rep (matches voro++). **G2
    derivatives on ConvexCell DONE + machine-exact** (facetGeometry: dV=∂V/∂r_k=(area/|r_k|)(r_k-centroid),
    validated vs half-edge to 3e-17, test_convexcell_geometry) — so ConvexCell is a COMPLETE physics
    rep.
- rejected: half-edge cell representation as the GPU topology (kept only as CPU oracle)
- why: "2.2x build, 9x smaller frame, fast construct"

### ConvexCell foot-point representation cannot represent live d<0 faces — large-weight power deferred, small-weight solver stays d>0
- area: voro
- source: vorflow-power-cells-deferred.md:20
- decided: 2026-07-03
- status: settled
- quote: |
    1. `ConvexCell` foot-point form `{n·x≤nn}` (nn=|n|²≥0) **cannot represent a live d<0 (seed-excluding) face** — only buried (empty) cells (kNegOffset marks it). Large-weight power needs a generalized origin-excluding half-space. Small-weight solver stays d>0 ⇒ fine.
- rejected: none stated (a limitation, not a chosen alternative — deferred, not rejected)
- why: representation limitation

### ConvexCell geometry decoupled from plane-definition: calculus is a function of {n_k} only
- area: voro
- source: vorflow-convexcell-geometry-split.md:10-17
- decided: undated
- status: settled
- quote: |
    Decided direction for the vorflow ConvexCell (the real physics primitive — a half-space-intersection
    polytope, not intrinsically Voronoi). The convex-cell calculus (V, areas, derivatives) is a function of
    the plane set `{n_k}` ONLY, where `n_k` is the **foot-point / pedal normal**... All cell-type variety lives
    in a separate plane-from-DOFs layer + its Jacobian `dn_k/d(dof)`; a generic chain combiner routes `dGeom/dn_k`
    to neighbour `pnbr[k]` (pnbr is already the routing table). So you get **(4 geometry tiers) + (T plane types)
    + (1 combiner)**, NOT 4×T fused kernels — do not inline plane-from-dofs into the hot geometry kernel.
- rejected: 4×T fused kernels (one kernel per geometry-tier × cell-type combination); inlining plane-from-dofs into the hot geometry kernel
- why: the {n_k}-only formulation lets geometry tiers, plane types, and the combiner vary independently

### Convexity certificate alone is insufficient — propagation to neighbours is essential
- area: voro
- source: vorflow-dynamic-update-strategy-study.md:52-55
- decided: undated
- status: settled
- quote: |
    2. **Convexity certificate WORKS, but PROPAGATION is essential**: S3 independent leaves the gained-face partners
       wrong (residual grows 7→331→1232 cells host-FP64 as disp 0.001→0.002→0.005); S4 propagation (rebuild flagged →
       re-flag asymmetric neighbours that don't list back, iterate) drives residual ~0 (2/22 wrong) for ~1–3% extra
       touch. ⇒ empirical support for the user's conjecture (a flip is a convexity violation in ≥1 of the two cells;
       propagation carries the repair to the partner).
- rejected: independent local repair without propagation (S3 alone)
- why: "S3 independent leaves the gained-face partners wrong"

### Convexity certificate replaced by local-Delaunay (4-poke) test
- area: voro
- source: vorflow-dynamic-updater-phase01.md:106
- decided: 2026-06-30
- status: superseded
- quote: |
    **Cheaper convexity certificate = LOCAL-DELAUNAY (2026-06-30, vorflow c8e32ac):** the sweep showed the
    small-δ/h floor is the CERTIFICATE (brute isSelfConsistent O(nt·np), several× the reeval), not geometry.
    Replaced with a local test: a Voronoi vertex v=(a,b,c)=circumcenter of Delaunay tet (i,a,b,c) can only be
    poked across that tet's FOUR faces → test 4 "poke" planes/vertex (3 edge-opposite via findSharing + the
    4th-face = nearest non-defining plane at build config) not all np.
- rejected: brute isSelfConsistent O(nt·np) certificate
- why: "the small-δ/h floor is the CERTIFICATE (brute isSelfConsistent O(nt·np), several× the reeval), not geometry"
- conflict: this local-Delaunay/4-poke certificate is itself later superseded by TrackAdj (see next entries)

### Cooperative/warp-parallel half-edge cut is a dead end — do not re-attempt
- area: voro
- source: vorflow-kokkos-migration.md:1181-1192
- decided: 2026-06-23
- status: settled
- quote: |
    **COOPERATIVE CUT ATTEMPTED — DEAD END (measured, reverted, NOT committed):** the only data-parallel
    part of cutCell2 is the distance eval (~14 cdist/cut, ~598/cell vs ~130 sequential trace steps).
    Tried warp-precomputing all alive-vertex distances per cut ... Measured **~1% SLOWER** (pure 1554→1529, forces
    1235→1223): the per-cut sync (~3 team_barriers + a TeamThreadRange launch ×~42 cuts/cell) costs more
    than the ~14 saved dots; trace/DFS are pointer-chasing (unparallelizable). DEEPER: for a
    sequential-per-cell algorithm the PER-THREAD decomposition (many independent cuts in flight) is the
    RIGHT GPU design; team-per-cell trades that for intra-cut parallelism the cut can't use. ~0.6× is the
    ceiling of that trade. Beating it needs a DIFFERENT parallel-clip cell rep (face/plane-list à la
    voro++) which is NOT bit-exact with the legacy half-edge oracle = a new method, not an optimisation.
    DON'T re-attempt the cooperative half-edge cut.
- rejected: cooperative/warp-parallel half-edge cut (team-per-cell intra-cut parallelism)
- why: "the per-cut sync ... costs more than the ~14 saved dots; trace/DFS are pointer-chasing (unparallelizable)"

### DEC viscous term shelved — first-order on skewed meshes, unstable explicitly
- area: voro
- source: voronoi-methods-plan.md:174-179
- decided: 2026-09-03
- status: settled
- quote: |
    **C2a′ DEC VISCOUS TERM: BUILT, MEASURED, SHELVED 2026-09-03** ... symmetric 4e-14 +
    dissipative ✓, but first-order like Perot on skewed meshes (face-average flux ≠ midpoint 1-form),
    inconsistent on the degenerate cubic lattice (cospherical Delaunay), ~8× stiffer explicitly (NaN
    even at dt/8). Verdict: covolume 2nd order needs centroidal meshes or the collocated scheme; DEC only
    useful implicitly on the face space (track D). Don't revisit without that.
- rejected: DEC viscous term as an explicit covolume viscous operator
- why: first-order on skewed meshes, inconsistent on the degenerate cubic lattice, and ~8x stiffer explicitly (NaN even at dt/8)

### Device Power/Laguerre diagrams dropped — no ConvexCell radical-plane geometry yet
- area: voro
- source: vorflow-scratchcell-retired-dynamic-cells-next.md:33-37
- decided: 2026-06-27
- status: settled
- quote: |
    ## Scope cuts (NO production consumer of either — grep-verified)
    - **Device Power/Laguerre DROPPED** (`static_assert(!Weighted)` in buildCell). ConvexCell's foot-point
      half-space `{x: nf·x ≤ |nf|²}` ALWAYS contains the seed, but a radical plane can put the seed OUTSIDE its
      cell (negative offset) — unrepresentable. Full Laguerre needs **ConvexCell radical-plane geometry** (the
      planned-but-unbuilt Power policy noted in [[vorflow-convexcell-geometry-split]]). Legacy CPU Power
      (voronoi.hpp) still works (test_power_cells passes).
- rejected: device Power/Laguerre diagrams under the current ConvexCell foot-point half-space representation
- why: a radical plane can place the seed outside its own cell (negative offset), which the foot-point form cannot represent

### Device kernel must scalarize small dynamically-indexed arrays to registers via #pragma unroll, not leave them local-memory
- area: voro
- source: vorflow-convexcell-geometry-split.md:68-72
- decided: undated
- status: settled
- quote: |
    PERF LESSON (don't relitigate): the "recompute" the user flagged was a SMALL fraction; code SHAPE
    dominated. Naive analytic was 1.42× CPU but 0.42× GPU (2.4× slower) — GPU killer = small DYNAMICALLY-INDEXED
    local arrays spilling to local memory, NOT branches (indices are uniform across the warp). Fix = device-only
    `#pragma unroll` (VOR_UNROLL macro) → scalarize to registers. Final: analytic ~1.5× CPU + ~1.09× GPU vs AD —
    wins both.
- rejected: naive analytic dAreaTri implementation with dynamically-indexed local arrays (2.4x slower on GPU)
- why: "small DYNAMICALLY-INDEXED local arrays spilling to local memory" was the GPU killer, not branching

### Distributed cold build: only build cells for original-index < nBuild; ghosts stay candidates only
- area: voro
- source: vorflow-worklist-into-tessellator.md:38-45
- decided: 2026-06-27
- status: settled
- quote: |
    Real cost = ~25% of the build tessellating GHOST cells that get discarded. Ghosts are
    only needed as **cutting candidates**, not as cells to build.
    - Added `int nBuild=-1` param to buildTessellation: build a cell only for original-index < nBuild [...]
    **Result: per-core 42.8 → 83.1 kcell/s (1.94×) at np=2 N=200k, and FLAT across np=1,2,4** [...]
    ghost-bound strong-scaling penalty GONE.
- rejected: tessellating ghost cells that get discarded
- why: "Ghosts are only needed as cutting candidates, not as cells to build"

### Dynamic cell-update study scoped to topology+geometry only, no physics
- area: voro
- source: vorflow-dynamic-update-strategy-study.md:12-13
- decided: 2026-06-27
- status: settled
- quote: |
    The "dynamic cell updating" NEXT from [[vorflow-scratchcell-retired-dynamic-cells-next]], scoped by the user to
    **cell updating ONLY (topology+geometry/volumes), NO physics/forces/dynamics yet** ("do not check physics yet").
- rejected: including physics/forces/dynamics in this study
- why: user scoping instruction ("do not check physics yet")

### Explicit standing instruction: do not propose Shewchuk/SoS robust predicates as the voro robustness plan
- area: voro
- source: robustness-topology-oriented-sugihara.md:32
- decided: undated
- status: settled
- quote: |
    - Do NOT propose Shewchuk/SoS robust predicates as the robustness plan; that contradicts the user.
      Phase 3 of `docs/voronoi_gpu_research_program.md` should be re-read as "topology-oriented
      robustness," not "exact predicates."
- rejected: Shewchuk/SoS robust (exact) predicates as the robustness plan
- why: "that contradicts the user"

---

### Filtered prolongator smoothing is required (unfiltered densifies/destabilizes the hierarchy)
- area: voro
- source: voro-graph-amg-next.md:28-30
- decided: 2026-07-03
- status: settled
- quote: |
    - **Pipeline**: nodal strength-of-connection (s=ndofPerNode block Frobenius) → 3-pass greedy
      aggregation → tentative P₀ (per-component, 1/√|agg| columns; keeps the s translation nullspace
      modes) → **FILTERED** prolongator smoothing (weak off-diagonals lumped to diagonal — essential for
      bounded operator complexity; unfiltered densifies coarse levels + makes the hierarchy
      lmax-hypersensitive/erratic) → Galerkin `A_c=PᵀAP` → V-cycle as CG preconditioner (`amgPcg`).
- rejected: unfiltered prolongator smoothing
- why: "unfiltered densifies coarse levels + makes the hierarchy lmax-hypersensitive/erratic"

### Fixed-K=64 kNN via ArborX BVH is the cold-build engine; best-first traversal rejected
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:20-32
- decided: undated
- status: settled
- quote: |
    **F4 (`bench_bvh_gather.cpp`): ArborX 2.1 BVH fixed-K kNN gather is THE cold-build engine.** K=64 is the
    sweet spot (complete cells, faces/cell 15.52); GPU 6.73 M/s = 1.24× the uniform grid (more on clustered).

    **Option 2 / best-first (`bench_bvh_bestfirst.cpp`) — MEASURED, does NOT beat fixed-K kNN. Don't re-attempt
    for the cold build.** [...] GPU 1.49 vs 6.73 M/s (0.22×), CPU 1.30 vs 1.44 (0.90×).
    **Why:** fixed-K over-gather is cheap + F4's two-pass *coalesced* kNN→construct beats the fused **divergent
    per-thread priority queue** [...] **Best-first's only home is the incremental/repair path (Phase 1.5): tiny per-seed candidate sets.**
- rejected: best-first BVH traversal for the cold build
- why: "fixed-K over-gather is cheap + F4's two-pass coalesced kNN→construct beats the fused divergent per-thread priority queue"

### Free-energy objective (e=−V_ref·log(V)) is the elegant right formulation for graded equal-pressure meshing
- area: voro
- source: voro-mesh-optimizer-wall-force.md:86-91
- decided: undated
- status: settled
- quote: |
    **FREE-ENERGY OBJECTIVE (user idea, VALIDATED)** — voro ee40df3: `freeEnergy` flag ⇒ per-cell
    e=−V_ref·log(V). Pressure −∂e/∂V=V_ref/V constant at equilibrium ⇒ (tessellation fixes ΣV) constrained
    min is V_i∝V_ref (equal pressure) — graded target AUTOMATIC + normalisation-free, and −logV→+∞ resists
    collapse ON ITS OWN (no barrier, no μ). Relaxed below feMin·V_ref (matching quadratic). Grad V_ref/V,
    GN Hess V_ref/V². **VALIDATED NoSdf: variance→1.6e-16 (machine zero), maxVolErr→0 ⇒ V_i→V_ref exactly.**
    The elegant right formulation.
- rejected: the earlier relative-energy + explicit log-barrier (μ Σ log(V/V_ref)) formulation as the primary objective
- why: free energy makes the graded target automatic and collapse-resistant "on its own (no barrier, no μ)"

### GPU lever "warp-shares-one-worklist" is a net loss and was reverted
- area: voro
- source: vorflow-worklist-gather-next.md:19
- decided: 2026-06-26
- status: settled
- quote: |
    **GPU gather levers explored (3):** #1 warp-shares-one-worklist (sort queries by (sub-position,
    Morton) so a warp shares one worklist base) = **NET LOSS −7%** (uniform table loads negligible;
    sub-pos grouping scatters the warp's neighbour reads, wrecking Morton locality) → reverted, note
    kept.
- rejected: lever #1, warp-shares-one-worklist sorting by sub-position+Morton
- why: "sub-pos grouping scatters the warp's neighbour reads, wrecking Morton locality"

### GPU tessellator granularity redesign: team/warp-per-cell landed at ~0.6x default, wall is the sequential half-edge cut
- area: voro
- source: vorflow-kokkos-migration.md:1176-1180
- decided: 2026-06-23
- status: settled
- quote: |
    **VERDICT:** team path now uniformly **~0.6× default** (1554/2459 pure, 1236/2024 forces; 3.5× over
    scaffold), stable N=1-4M. Wall is no longer occupancy but the **leader-serial half-edge cut** (one
    cut/team ≈ 6-8 cut-streams/SM vs one cut/thread ≈ hundreds).
- rejected: none stated as an alternative here (this is a measured ceiling that then motivated the ConvexCell rewrite)
- why: "the leader-serial half-edge cut" throttles the team-per-cell approach

### GPU-vs-CPU tessellator optimizations diverge: reducing work helps GPU, cheaper ops help only CPU
- area: voro
- source: vorflow-kokkos-migration.md:1213-1215
- decided: undated
- status: settled
- quote: |
    **GPU-vs-CPU
    DIVERGENCE (important):** triangle ADJACENCY (O(1) horizon) helped CPU +25% but **GPU −36%**;
    incremental security-radius helped CPU +8%, GPU flat — both REVERTED. Only REDUCING WORK (the cull)
    helps GPU; making ops cheaper helps only CPU (GPU has spare ALU, bound by frame+memory+divergence).
- rejected: triangle adjacency (O(1) horizon) and incremental security-radius as GPU optimizations
- why: measured GPU regression (−36%) despite CPU gain; "GPU has spare ALU, bound by frame+memory+divergence"

### GraphAMG built standalone, not on top of core::amr::MomentumMG
- area: voro
- source: voro-graph-amg-next.md:20-25
- decided: 2026-07-03
- status: settled
- quote: |
    - **Did NOT build on `core::amr::MomentumMG`** (user was right to be hesitant): it is hard-wired to
      BlockOctree (hierarchy = Morton-ancestry octree coarsening) AND its Galerkin triple-product is
      specialised to piecewise-constant INJECTION P — but SA's smoothed prolongator `P=(I−ωD⁻¹A)P₀` is a
      general sparse matrix, so `A_c=PᵀAP` is a general RAP. Neither the hierarchy nor the triple-product
      is reusable. Only reused the genuinely generic `amr/face_csr.hpp` row arithmetic (as the device
      layout target) + the CSR idiom.
- rejected: building the mesh-optimizer's O(N) solve on core::amr::MomentumMG
- why: MomentumMG's hierarchy is hard-wired to BlockOctree and its Galerkin triple-product is specialized to piecewise-constant injection P, neither reusable for SA's general smoothed prolongator

### GraphAMG is not worth it for the mesh-optimizer solve; colored-GS-CG / Jacobi-CG win in wall-clock
- area: voro
- source: voro-mesh-optimizer-wall-force.md:1699-1703 (also 1700)
- decided: undated
- status: settled
- quote: |
    **Also learned (solver study, Part 1/2 of the bench)**: this Gauss-Newton Hessian is NOT
    asymptotically ill-conditioned — iteration counts FALL with N (denser seeding regularises), so cheap
    colored-GS-CG / Jacobi-CG beat GraphAMG in wall-clock (AMG setup not amortised); plain CG 5-10× worse.
    End-to-end cost is dominated by the tessellation REBUILD in the line search, not the solve. First-order
    (steepest descent / nonlinear CG) barely equalise vs Newton.
- rejected: GraphAMG as the preconditioner for this mesh-optimizer solve; plain (unpreconditioned) CG
- why: "AMG setup not amortised" since iteration counts already fall with N; plain CG is 5-10x worse

### GraphAMG strength criterion must compare squared Frobenius norm against sqrt of the diagonal product, not the raw product
- area: voro
- source: voro-graph-amg-next.md:35-37
- decided: undated
- status: settled
- quote: |
    - **Two subtle bugs found+fixed** (both would recur on the device port): (1) strength criterion must
      be `‖S‖_F² ≥ θ²·√(ddiag_I·ddiag_J)` NOT `θ²·ddiag_I·ddiag_J` (don't square the diagonal norms — else
      nothing is "strong", every node singleton, coarsening bails).
- rejected: `θ²·ddiag_I·ddiag_J` as the strength-of-connection threshold
- why: squaring the diagonal norms makes nothing register as "strong", so every node becomes a singleton and coarsening bails

### GraphAMG strength threshold default θ=0.05
- area: voro
- source: voro-graph-amg-next.md:41-42
- decided: undated
- status: settled
- quote: |
    - **θ=0.05 default** (block-Frobenius strength scaling; swept 0.01–0.10, 0.04–0.06 gives consistent
      multilevel coarsening opC~1.6–1.9).
- rejected: none stated (other values in the 0.01-0.10 sweep did not give consistent coarsening)
- why: "0.04–0.06 gives consistent multilevel coarsening opC~1.6–1.9"

### GraphAMG λ_max power-iteration seed must be a well-mixed random ±1 vector, not smooth or degenerate
- area: voro
- source: voro-graph-amg-next.md:37-40
- decided: undated
- status: settled
- quote: |
    (2) the power-iteration λ_max seed
      must be a **well-mixed random ±1** vector (splitmix64), NOT smooth (overlaps low modes → slow
      underestimate) and NOT `i·odd & 1` (degenerate, stuck at wrong value) — the dominant eigenvector of
      D⁻¹A is the highest-frequency mode. Underestimated λ_max makes higher-degree Chebyshev diverge.
- rejected: a smooth seed vector; an `i·odd & 1` seed vector
- why: a smooth seed "overlaps low modes → slow underestimate"; the degenerate seed gets "stuck at wrong value"; underestimated λ_max makes higher-degree Chebyshev diverge

### Inline reshape repair: tried, reverted as marginal, but the local-Delaunay certificate is retained
- area: voro
- source: vorflow-dynamic-updater-phase01.md:122
- decided: 2026-06-30
- status: superseded
- quote: |
    **Over-flag reduction = INLINE RESHAPE REPAIR — TRIED then REVERTED as marginal (2026-06-30, reverted in
    50b1573; the local-Delaunay certificate above is RETAINED).** ... HONEST: reducing over-flag is a MODEST lever here
    (gather it targets isn't the small-δ bottleneck; cheap version hits gain wall → must gate).
- rejected: inline reshape repair as shipped-on optimization
- why: "reducing over-flag is a MODEST lever here (gather it targets isn't the small-δ bottleneck; cheap version hits gain wall → must gate)"

### Interface FORCE (gradFacetAreaSq) retired; ConvexCell replacement is geomVolumeAreaGrad
- area: voro
- source: vorflow-scratchcell-retired-dynamic-cells-next.md:38-39
- decided: 2026-06-27
- status: settled
- quote: |
    - **Interface FORCE** (`gradFacetAreaSq`, half-edge only) retired; ConvexCell replacement =
      `geomVolumeAreaGrad` (validated test_pervertex_geometry §11), to be wired into the device path.
- rejected: gradFacetAreaSq (half-edge-only interface force)
- why: half-edge-only, replaced by the validated ConvexCell geomVolumeAreaGrad

---

### KOKKOS_LAMBDA capturing `this` for a member read is illegal on CUDA only
- area: voro
- source: voronoi-methods-plan.md:79
- decided: 2026-09-03
- status: settled
- quote: |
    **Trap:** a member read inside a KOKKOS_LAMBDA captures `this` → illegal address on CUDA only.
- rejected: none stated
- why: none stated (a Kokkos/CUDA coding invariant)

### Legacy half-edge Voronoi engine retired; device-only ConvexCell architecture is production
- area: voro
- source: vorflow-dynamic-updater-phase01.md:264
- decided: 2026-07-01
- status: settled
- quote: |
    **SOURCE CLEANUP + DEVICE-ONLY CI + EVERYTHING NOW PUSHED — DONE 2026-07-01 (vorflow 17e78cf, umbrella
    308f26a, PUSHED to main).** ... Cleanup (commits 5446a2a→0d4f3b8): DELETED the legacy
    half-edge engine + all experimental code — `convex_cell_adj.hpp`/`convex_cell_compact.hpp`, the parked
    BVH + SIMD-cells benches, `python/bindings.cpp` (old pybind11), the half-edge headers
    (`voronoi.hpp`/`nbrlist.hpp`/`vor_types.hpp`/`simulation.hpp`/`tessellation_build.hpp`/`skin_refresh.hpp`),
    the whole legacy `tests/test_*.cpp`+golden tree, the 10 half-edge-oracle device tests, `data/` (128 MB).
- rejected: the legacy half-edge CPU-oracle engine and its associated test/golden data tree
- why: "none stated" beyond the moving-point updater work being complete on the device architecture

### Legacy half-edge engine kept only as test oracle; production path must stay legacy-free (enforced)
- area: voro
- source: vorflow-kokkos-migration.md:1034-1039
- decided: undated
- status: settled
- quote: |
    **Incompressible (Phase 5): NO faithful port** — legacy Incompressible is an
    incomplete stub (assembles A=D M^-1 D^T, never solves); real elliptic solver = new-method
    work. **Phase 8: production path is legacy-free + ENFORCED** (check_include_graph.sh:
    device/physics/host/tessellation_view/src include no voronoi/simulation); legacy engine
    kept ONLY as test oracle + the mpi/validate_*.py Python surface + incompressible ref.
    Literal legacy deletion deferred (gated on golden-data oracle conversion + validate-script
    migration + incompressible solver) so the validation oracle survives the port.
- rejected: porting the legacy Incompressible stub faithfully; letting production code include voronoi/simulation
- why: legacy Incompressible "is an incomplete stub ... never solves"; production purity is enforced by check_include_graph.sh

### Local Newton-on-positions cannot equalize or grade cell volumes from a random seeding — needs global seed redistribution
- area: voro
- source: voro-mesh-optimizer-wall-force.md:69-72
- decided: undated
- status: settled
- quote: |
    **THE BARRIER REVEALED THE REAL ISSUE**: it correctly PREVENTS collapse ⇒ the earlier "progress"
    (variance 2.3e-5) was FAKE — achieved only by collapsing ~1/4 of the cells (nBad→700, invalid mesh).
    With collapse forbidden, local Newton-on-positions has NO feasible descent step from a random seeding →
    stalls at iter 0 (alpha=0). Both uniform equalisation AND a graded target need GLOBAL seed
    redistribution (seeds migrating between pores), which a LOCAL method cannot do.
- rejected: local Newton-on-positions alone (without global seed redistribution) for equalizing/grading volumes
- why: "local Newton-on-positions has NO feasible descent step from a random seeding"; the earlier apparent progress was fake (collapsed cells)

### M0/D0 derivation doc deferred by the user — do not start unprompted
- area: voro
- source: voronoi-methods-plan.md:234-236
- decided: 2026-09-05
- status: settled
- quote: |
    **SESSION 2026-09-05 (release prep, not voro work):** M0 + M1 DONE (voro 91daffc, umbrella pointer
    bumped). USER: M2/D0 derivation doc `voro/docs/moving_cell_fluid.md` DEFERRED by the user ("at a later
    time") — do not start it unprompted.
- rejected: starting the M2/D0 derivation doc unprompted
- why: user directive to defer it

### Montgomery-batch reciprocal reduction reverted — FP32-unsafe
- area: voro
- source: vorflow-cpu-migration-discussion.md:44-56
- decided: 2026-06-27
- status: settled
- quote: |
    **Reciprocal fix ATTEMPTED then REVERTED — FP32-unsafe (2026-06-27, final state vorflow `338f86f`,
    umbrella `84696a2`).** Did option 3 (3 edgeFoot divides/triangle → 1 via the identity
    `det3(e,edgeFoot(v,ck),v)=(v·ck)(e·(v×ck))/|ck|²`, common denom g1·g2·g3) ... **But NaN in FP32**: the 3→1 reduction is a Montgomery batch inversion needing the product
    g1·g2·g3 of the three |c_k|², which leaves FP32's range → bench_convexcell_f32 Σvol err = NaN.
    My FP64-only validation HID it (lesson: ALWAYS run bench_convexcell_f32 / GPU-FP32 after touching the
    geometry kernels). Reverted (commits 5d56adc/0036757 → revert a65d430); FP32 back to 2.9e-8. Since FP32 is
    GPU/production precision the fold is dead — divide stays 3/triangle.
- rejected: the 3-divide-to-1 Montgomery-batch-inversion reciprocal reduction
- why: the product of three |c_k|² terms overflows/underflows FP32's range, producing NaN; FP32 is the GPU/production precision so the optimization cannot ship

### Morton (Z-order) grid indexing kept GPU-only, not for CPU backend
- area: voro
- source: vorflow-kokkos-migration.md:1104-1109
- decided: undated
- status: settled
- quote: |
    **Morton (Z-order) grid indexing DONE (commit 231b5aa) — measured GPU-only:** device-portable
    `morton3` magic-bits encoder + Z-order cell index, gated `useMorton = !kHostBackend && (2^mbits
    padding ≤ 8×ncell linear fallback)`. GPU pure 30→31x, **with-forces 21→25x voro++ (+18%, gather
    coalescing)**; CPU REGRESSES (0.91→0.87x — Morton codes non-additive ⇒ per-cell re-encode in the
    hot gather loop not hidden, and 2-seeds/cell density already gives CPU locality) so CPU keeps
    linear.
- rejected: using Morton grid indexing on the CPU/host backend
- why: "CPU REGRESSES (0.91→0.87x — Morton codes non-additive ⇒ per-cell re-encode in the hot gather loop not hidden"

### No-op-clip avoidance (culling pre-clip candidates) prototyped and rejected
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:147-154
- decided: undated
- status: settled
- quote: |
    **No-op-clip avoidance PROTOTYPED — also negative (GPU 0.96×, CPU 0.95×).** [...]
    Negative because no-op clips are individually CHEAP (flat coalesced O(28) scan); cost is
    dominated by the CUTS (retriangulation+geometry) which the cull doesn't touch.
- rejected: the AABB/6-DOP mayCut pre-clip culling test
- why: "no-op clips are individually CHEAP... cost is dominated by the CUTS"

### Nondeterministic miss root cause: plane-count cap and facet over-buffer both miscounted; fixed to compact/rebuild at exact demand
- area: voro
- source: voronoi-methods-plan.md:181-191
- decided: 2026-09-08
- status: settled
- quote: |
    **"NONDETERMINISTIC MISS" ROOT-CAUSED + FIXED 2026-09-08 (voro 9ce81c8):** two silent caps in the
    cold build, victims chosen by OpenMP scheduling of `tess.scatter`'s atomic slot (= plane insertion
    order): (1) `ConvexCell::clip` declared overflow at np == MAXP although np counts REDUNDANT committed
    planes (2-3x faces) — a 29-face cell committed 64 planes in one order, 59 in another → zero volume
    (the 2.3e-4 cavity miss = one cell); now `compactPlanes()` at the cap. (2) the facet over-buffer
    (N×18 mean estimate) overflowed on wall-heavy builds and the LAST-finished 400-600 cells lost their
    facets (status kOverflow only) → run-to-run wall-facet counts; now rebuild at the cursor's exact
    demand.
- rejected: capping on raw plane count without compaction; sizing the facet buffer by an N×18 mean estimate
- why: raw plane count over-counts redundant planes causing spurious overflow; the mean-based facet buffer estimate undersizes wall-heavy builds

---

### Order-free volume walk without stored adjacency does not help; atan2 is not the bottleneck
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:176-189
- decided: undated
- status: settled
- quote: |
    **Order-free + atan2-free volume TRIED — neither helps (the gather is the cost, not atan2):** [...]
    (a) pseudo-angle (diamond, transcendental-free): SAME speed 65.1 vs 65.0 → atan2 NOT the bottleneck (GPU hides it); kept it (free,
    robust, geometry+dV tests pass). (b) order-free topological walk (ConvexCell::volumeWalk, cyclic order from
    shared-plane adjacency, cross products only): correct (Δ6e-11) but 0.70× (45.5) — no stored adjacency → each
    hop is O(nt) findSharing > the atan2 removed; kept as documented variant (wins only WITH adjacency, itself
    GPU-negative).
- rejected: order-free volume walk without stored adjacency, as a performance win
- why: "no stored adjacency → each hop is O(nt) findSharing > the atan2 removed"

### Per-sub-position rmin worklist gather replaces the adaptive shell-offset walk, on the host build path
- area: voro
- source: vorflow-worklist-into-tessellator.md:14-19
- decided: 2026-06-27
- status: settled
- quote: |
    Replaced the adaptive shell-offset walk (`offX/offY/offZ`+`shellStart`+`swInit`) with the per-sub-position
    rmin worklist from `bench_convexcell` [...] Result: serial cold build **48.8 → 66.7 kcell/s (1.37×)**
    N=200k 1-thread (A/B via git stash).
- rejected: the adaptive shell-offset walk
- why: measured 1.37x speedup

### Per-vertex flag/divergence geometry (sort-free, adjacency-free) adopted as the default re-eval kernel, superseding the atan2 and stored-adjacency paths
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:190-229
- decided: undated
- status: superseded
- quote: |
    **BREAKTHROUGH — vertex-local flag/divergence geometry (user's design note, Ray et al TOG2018 / geogram):
    SORT-FREE AND ADJACENCY-FREE, 2.57×, machine-exact.** [...] Perf
    (5080 FP32 N=1M re-eval): volumePerVertex 166 Mc/s vs atan2 65 (2.57×) [...] **Made
    re-eval default → re-eval over resident topology 65→167 Mc/s = 11.4× full rebuild (was 4.9×)**
    [...] **Follow-ups DONE (commit 70a5c5f):** cold construct [...] switched to volumePerVertex/geometryPerVertex [...]
    faceOrdered/atan2/facetGeometry RETIRED from hot path (kept only as FP64 oracle in tests). [...]
    **REMOVED superseded adjacency-walk** (adjT field, buildAdjacency, volumeAdj, volumeWalk) → cell back to
    3084B
- rejected: atan2 cyclic-order face-ordered volume computation as the hot-path kernel; the stored-adjacency (`volumeAdj`) variant
- why: "atan2 NOT the bottleneck (GPU hides it)... BUT order-free DOES win with STORED adjacency" then further superseded because vertex-local scatter beats both

### Phase-3 gate: churn thresholds and dilate() default
- area: voro
- source: vorflow-dynamic-updater-phase01.md:61
- decided: undated
- status: settled
- quote: |
    **Phase 3 DONE+PUSHED (PRODUCTION)** (vorflow 6ed3b76): `step()` adaptive gate decided after the free
    certificate, before any gather, from `churn = flagged/nProc`: high churn → full rebuild (per-backend
    `churnThresh` set in alloc: GPU 0.50, host/serial 0.70 — the "never much slower than rebuild" guard);
    dense local cluster → `dilate()` regional buffer (DEFAULT OFF — over-fires on Poisson, verify loop
    already closes cascades); sparse → two-pass.
- rejected: none stated (dilate() considered but shipped OFF by default)
- why: "the 'never much slower than rebuild' guard"; dilate() "over-fires on Poisson, verify loop already closes cascades"

---

### Plan of record §12 rulings (approved 2026-09-03)
- area: voro
- source: voronoi-methods-plan.md:8-13
- decided: 2026-09-03
- status: settled
- quote: |
    **Plan of record:** `suite/docs/VORONOI_METHODS_PLAN.md`, **APPROVED 2026-09-03** (umbrella
    48f1185). Rulings (§12): (1) internal `PolyMesh` only, no OpenFOAM writer; (2) build BOTH the
    covolume (C2a) and collocated (C2b) static solvers; (3) BOTH moving-cell integrators (Verlet +
    weight projection AND implicit midpoint with consistent mass) behind one interface, gates pick the
    default; (4) track F targets the DENSE regime; (5) D before E; (6) Snellius scaling runs approved
    (still right-size, billed per GPU).
- rejected: an OpenFOAM writer; picking only one of covolume/collocated; picking only one moving-cell integrator up front
- why: none stated beyond the ruling itself (user-approved plan)

### Power-cell solver physics deliberately not built yet — user wants it brainstormed first
- area: voro
- source: vorflow-power-cells-deferred.md:10
- decided: 2026-07-03
- status: settled
- quote: |
    The solver *physics* (pressure-Poisson, `docs/power_cell_solver_spec.md`) is deliberately NOT built — user wants it brainstormed first; this is the infrastructure it sits on.
- rejected: building the solver physics before the design is brainstormed
- why: user wants it brainstormed first

---

### Production dynamic-update strategy is S5: persistent Verlet skin-list + propagating repair
- area: voro
- source: vorflow-dynamic-update-strategy-study.md:80-88
- decided: undated
- status: settled
- quote: |
    5. **S5 (persistent Verlet skin-list + propagating repair) = the production strategy.** Each cell keeps the
       candidate (skin) list from the last full rebuild; while max-disp<skin/2 (Verlet) the list is complete, so
       local repair re-clips the STORED list (NO grid, NO re-gather) — vs S3/S4 which re-gather the grid EVERY step
       (the gap the user flagged). disp 0.001: S5 skin 0.2 = **23×** vs full rebuild (GPU FP32 N500k AND host FP64
       N80k) = ~4× better than S4's 6×; skin 0.1 near-exact ~7-8×. Optimal **skin ≈ 0.1-0.2 cell-sizes**...
       disp≥0.005 → S5 fallback every step → use S2 Verlet instead.
- rejected: S3/S4 (which re-gather the grid every step) as the production strategy
- why: S5 avoids the per-step re-gather and measures ~4x better than S4

### Reconstructing the clipped cell externally for dV/dn was unnecessary — use the tessellator's published facet areas
- area: voro
- source: voro-mesh-optimizer-wall-force.md:53-56
- decided: undated
- status: settled
- quote: |
    Detour I
    wasted a lot on: trying to RECONSTRUCT the clipped cell externally (buildConvexCell/initBox+clip) to
    get dV/dn — balloons / can't match the tessellator's exact clip → segfaults. UNNECESSARY: the areas
    are published.
- rejected: externally reconstructing the clipped cell (buildConvexCell/initBox+clip) to get dV/dn
- why: "can't match the tessellator's exact clip → segfaults"; the tessellator already publishes facetArea for wall facets

### Reframe: the neighbour-query GATHER, not the topology decision/repair, is the core problem to solve next
- area: voro
- source: vorflow-dynamic-update-strategy-study.md:92-94
- decided: undated
- status: superseded
- quote: |
    User pushed back: stop skin-tuning; the GATHER (finding all relevant neighbours, Verlet-style = guarantee all
    future neighbours until a criterion breaks) is the CORE problem (it's ~60% of cold-build cost; the 2-3× gap to
    GPU SOTA is ENTIRELY the neighbour query). Wrote **`docs/voronoi_neighbor_update_overview.md`** = self-contained
    handoff (for another LLM)...
- rejected: continuing to tune the skin-width / repair strategy as the primary optimization target
- why: "the GATHER ... is the CORE problem ... the 2-3× gap to GPU SOTA is ENTIRELY the neighbour query"
- conflict: supersedes the finding-1 framing ("the WHOLE dynamic cost is the topology decision+repair, not geometry") once the harness-vs-production rebuild cost was corrected

### Robustness approach: topology-oriented (Sugihara), valid-by-construction, NOT exact predicates
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:232-233
- decided: undated
- status: settled
- quote: |
    Robustness: topology-oriented (Sugihara), valid-by-construction, NOT exact predicates — see
    [[robustness-topology-oriented-sugihara]].
- rejected: exact-arithmetic predicates for robustness
- why: none stated in this file (points to a dedicated note)

---

### SDF wall force uses Option A (exact flat / first-order curved), user's choice
- area: voro
- source: vorflow-power-cells-deferred.md:16
- decided: 2026-07-03
- status: settled
- quote: |
    **P5 SDF differentiable wall force** (Effort 2, `sdf.hpp` `addSdfWallForce`+`sdfHessian`): seed-foot model n_wall=−φû, J_wall=−|∇φ|ûûᵀ−(φ/|∇φ|)(I−ûûᵀ)H; call AFTER `chainToDofs`, adds J_wallᵀg over pnbr==−2 facets to fSelf. **Option A** (user chose): exact flat / first-order curved. |∇φ|~0 crease guarded.
- rejected: an alternative (presumably higher-order curved) SDF wall-force option, not detailed in the note
- why: user's choice (no reason stated)

### SDF wall term still stalls the optimizer — diagnosed as the approximate wall-gradient's first-order error, not the objective
- area: voro
- source: voro-mesh-optimizer-wall-force.md:92-97
- decided: undated
- status: uncertain
- quote: |
    **SDF STILL STALLS — and free energy DIAGNOSED WHY**: its gradient is ~40× SMALLER than the data-fit
    one, so the SDF wall-term gradient's FIRST-ORDER (sphere) inaccuracy now dominates the direction ⇒
    Armijo rejects every step (alpha=0). NoSdf (exact grad) converges; SDF (approx wall grad) stalls. So the
    2 real remaining pieces: (a) an EXACT/validated wall-facet gradient (current = seed-foot model, exact
    flat / 1st-order sphere) and (b) clean seeding (no seeds in un-meshable throats).
- rejected: none stated — this is an open/unsolved gap, not a settled choice
- why: "the SDF wall-term gradient's FIRST-ORDER (sphere) inaccuracy now dominates the direction ⇒ Armijo rejects every step"

### SOTA adjacency-based cell structure loses on GPU; linear findSharing wins for ~28-triangle cells
- area: voro
- source: vorflow-gpu-voronoi-build-engine.md:68-82
- decided: undated
- status: settled
- quote: |
    Results (construct-from-cache, bit-identical
    vols): cached findSharing (current) **14.0 M/s = best**; packed+recompute 0.72×; adjacency+recompute 0.46×;
    adjacency+CACHED 0.46×. **Adj-recompute == Adj-cache ⇒ the slowdown is the ADJACENCY MACHINERY itself
    (ring-link O(new²), free list, scatter writes, divergence), not recompute. For ~28-tri cells the simple
    O(n) linear findSharing WINS — geogram itself "prefers complete linear scan."**
- rejected: the Ray-et-al/geogram adjacency-pointer cell representation on GPU
- why: "the slowdown is the ADJACENCY MACHINERY itself... not recompute"

### ScratchCell half-edge device cutter retired in favor of ConvexCell
- area: voro
- source: vorflow-scratchcell-retired-dynamic-cells-next.md:10-16
- decided: 2026-06-27
- status: settled
- quote: |
    **DONE 2026-06-27** (vorflow `31b8468`, umbrella `ce72845`, pushed to main). Retired the half-edge
    **ScratchCell** device cutter; `vor::device::buildTessellation` now builds on the compact dual-triangle
    **ConvexCell** (convex_cell.hpp). ... DELETED: `device/cell_cutter.hpp` (ScratchCell), `host/incremental.hpp`, `host/interface_force.hpp`,
    tests test_cell_cutter / bench_cutter / test_incremental_device / test_interface_force (all half-edge +
    test-only). **Kept `voronoi.hpp`** = the legacy CPU `CellMaker` oracle (its OWN cutCell2, NOT ScratchCell).
- rejected: the half-edge ScratchCell device cutter
- why: ConvexCell is more compact (~5KB vs ~20KB) with cheap geometry, giving a measured 1.49x GPU throughput win with no occupancy penalty

### Seeding heuristic: grade a Voronoi mesh by placing seeds at target spacing (shells), not by rejection-sampling a density
- area: voro
- source: voro-mesh-optimizer-wall-force.md:109-120
- decided: undated
- status: settled
- quote: |
    SEEDING HEURISTIC (the real fix for "no grading / poor tiling") — peclet-examples 0cd044b, PURE-PYTHON
    (no package change): user noted the grading (small cells at walls) wasn't visible + tiling poor, blamed
    the heuristic — CORRECT. Old `seed_pore_space` (rejection ∝1/V_ref + fixed wall shell) never places
    cells at the TARGET LOCAL SIZE. Replaced with **`seed_graded(s_lo,s_hi)`**: concentric shells around
    each sphere at distances d (radial step = in-surface spacing = local size s(d)=clip(d,s_lo,s_hi)),
    jittered, kept where |φ−d|<0.75h. ⇒ a seed at wall-distance φ gets a cell ≈ s(φ)³ → small hugging walls,
    growing into pores — the graded inflation-layer mesh STRAIGHT FROM SEEDING, NO RELAXATION. ...
    KEY LESSON: to grade a Voronoi mesh, place seeds at target SPACING s(φ)
    (shells), don't rejection-sample a density — Poisson points don't hit a target size.
- rejected: rejection-sampling seeds proportional to 1/V_ref density (old seed_pore_space)
- why: "Poisson points don't hit a target size"

### Single-face surgical re-clip is a negative result vs gated gather
- area: voro
- source: vorflow-dynamic-updater-phase01.md:69
- decided: 2026-06-29
- status: settled
- quote: |
    **Phase 4 single-face surgical = NEGATIVE RESULT** (implemented behind `surgical`, DEFAULT OFF):
    re-clip flip cells from known candidates (stored ∪ partner-pair extras, scattered in certify) without a
    gather — but (1) SLOWER (unsorted re-clip loses to the sorted gather + security-radius early-out: 2.08×
    vs 2.98×) and (2) NOT exact — a surgical cell that GAINS a neighbour absent from its candidate set stays
    convex, certificate/verify can't see the gain (§1c), error COMPOUNDS (maxRelV 7e-2→0.45 over a sweep).
    Production = Phase-3 gated gather.
- rejected: single-face surgical re-clip (stored∪partner candidate set)
- why: "(1) SLOWER ... and (2) NOT exact — a surgical cell that GAINS a neighbour absent from its candidate set stays convex, certificate/verify can't see the gain"

### Smoother is 4th-kind Chebyshev, not colored-GS
- area: voro
- source: voro-graph-amg-next.md:31-34
- decided: 2026-07-03
- status: settled
- quote: |
    - **Smoother = 4th-kind Chebyshev** (Lottes/Phillips-Fischer), degree 2 default. Chose 4th-kind over
      1st-kind because it needs ONLY an upper bound λ_max (no lower-bound guess that goes wrong on
      Galerkin coarse levels); its first step = optimal 4/(3λ) damped Jacobi. chebDegree=0 ⇒ damped-Jacobi
      smoother fallback (also mesh-independent). NOT colored-GS (GPU/MPI, decided against earlier).
- rejected: colored Gauss-Seidel smoother (for GPU/MPI reasons, decided earlier); 1st-kind Chebyshev (needs a lower-bound guess)
- why: 4th-kind Chebyshev "needs ONLY an upper bound λ_max (no lower-bound guess that goes wrong on Galerkin coarse levels)"

### Steepest descent (plain −g), not Newton, is the robust move direction — GN Hessian is rank-deficient
- area: voro
- source: voro-mesh-optimizer-wall-force.md:76-79
- decided: undated
- status: settled
- quote: |
    **GRADIENT DESCENT MOVES (I was wrong that it "can't move")** — voro 9652e89: `Precond::SteepestDescent`
    (dq=−g directly, the volume-pressure force −Σ(∂E/∂V_c)∇V_c). Newton STALLED (alpha→0) only because the
    GN Hessian Σ Hw ∇V∇Vᵀ is rank-deficient ⇒ H⁻¹g amplifies near-nullspace dirs into infeasible territory;
    plain −g is a robust descent dir and MOVES the seeds (E 1494→858, many iters). User's intuition correct.
- rejected: relying on the Gauss-Newton Hessian direction (H⁻¹g) when it is rank-deficient
- why: "H⁻¹g amplifies near-nullspace dirs into infeasible territory; plain −g is a robust descent dir"

### Test equivalence contract: 1e-9 volume tolerance + exact neighbour set, NOT bit-exactness — cut order is free to change
- area: voro
- source: vorflow-worklist-into-tessellator.md:28-31
- decided: undated
- status: settled
- quote: |
    KEY INSIGHT that unblocked design: test_tessellator/test_voronoi_mpi compare to the LEGACY serial cutter
    at **1e-9 vol tol + exact neighbour SET** (NOT bit-exact), so cut ORDER is free to change.
- rejected: requiring bit-exact agreement with the legacy serial cutter
- why: none stated beyond the test contract itself

---

### The voro mesh optimizer's host-orchestrated first cut was a violation of the device-first principle and had to be re-architected
- area: voro
- source: device-first-mpi-design-principle.md:20
- decided: 2026-07-03
- status: superseded
- quote: |
    **Status of the voro mesh optimiser** ([[vorflow-power-cells-deferred]] → mesh_optimizer.hpp): its
    FIRST cut was host-orchestrated (download the facet CSR each Newton step, host assembly + host CG +
    host colored-GS) — a VIOLATION flagged by the user. Being re-architected to device-resident +
    MPI-aware. The host version is retained as the validation oracle.
- rejected: the host-orchestrated mesh-optimizer implementation as production code
- why: "a VIOLATION flagged by the user" of the device-first-mpi-design-principle

---

### Topology decisions must be computed in FP64; geometry/volume can be FP32
- area: voro
- source: vorflow-dynamic-update-strategy-study.md:58-61
- decided: undated
- status: settled
- quote: |
    4. **Precision**: d2tol is precision-aware (1e-4·cellSize FP64, 2e-3·cellSize FP32) or FP32 over-flags. With that,
       touch% and topoMism are ~precision-INDEPENDENT; FP32 only worsens the volume-significant residual (~5×: 34 FP64
       vs 165 FP32 at disp0.001 skin0.2). Do TOPOLOGY decision in FP64, geometry/volume can be FP32.
- rejected: doing the topology (convexity) decision in FP32
- why: FP32 over-flags without precision-aware tolerance; the volume-significant residual is ~5x worse in FP32

### TrackAdj/adjacency-maintained Lawson certificate replaces the 4-poke local-Delaunay certificate
- area: voro
- source: vorflow-dynamic-updater-phase01.md:140
- decided: 2026-06-30
- status: superseded
- quote: |
    **TrackAdj axis on ConvexCell — DONE+COMMITTED (NOT pushed) 2026-06-30 (vorflow cc9990c, umbrella
    3a581e2).** Per a detailed user spec: replaced the 4-poke local-Delaunay certificate with an
    ADJACENCY-maintained Lawson certificate. ... **KEY: the 3-edge Lawson cert is a strict SUBSET of brute
    (drops the old 4th-face poke) → misses far-pokes**, so a per-step max-displacement gate
    (`certDispLimit≈0.0015·spacing` + `xPrev`) keeps it to its small-disp validity; larger moves + teleports
    fall back to the COMPLETE brute cert — machine-exact on the far-jump stress.
- rejected: the 4-poke local-Delaunay certificate (computePokePlanes/isSelfConsistentLocal, deleted)
- why: "per a detailed user spec"; the 3-edge Lawson cert is cheaper (O(nt) + packed adj) but "a strict SUBSET of brute ... → misses far-pokes" requiring a displacement gate + brute fallback
- conflict: this per-step gate + brute fallback is itself removed in the next entry (4th-face restored)

### Use geomVolumeGrad (3-array), not geomVolumeArea, for force-only computation
- area: voro
- source: vorflow-convexcell-geometry-split.md:48-55
- decided: undated
- status: settled
- quote: |
    **Phase 2 — `geomVolumeArea` DONE** (commit `a922e48`): V + outward area-vectors A_k·n_k/|n_k| + dV/dn
    in one pass, ALSO fully sqrt-free ... PERF
    CAVEAT (unlike geomVolumeGrad): CPU ~1.2× faster but GPU ~0.89× (70.3 vs 78.9 Mc/s) — materializing 6
    per-facet arrays costs occupancy that the old 4-array+register-derive avoids; single-pass wins only under
    global staging. Use geomVolumeGrad (3-array, wins both) for force-only.
- rejected: geomVolumeArea (6-array, single-pass) for force-only use cases
- why: geomVolumeArea is GPU-slower (0.89x) because "materializing 6 per-facet arrays costs occupancy"

### Use the sqrt-free area-vector formula for physics, not facetAreasPerVertex's magnitude form
- area: voro
- source: vorflow-cpu-migration-discussion.md:59-61
- decided: undated
- status: settled
- quote: |
    Sqrt note: `facetAreasPerVertex` has a
    per-facet `sqrt(|n_i|)` only because it returns scalar area MAGNITUDES; the area VECTOR is sqrt-free
    `A_k=S_a·n_k/(2·nn[k])` and `geomVolumeArea`/`geomVolumeGrad` already compute it that way — use those for
    physics, the user was right.
- rejected: using facetAreasPerVertex's sqrt-based scalar magnitude for physics computations
- why: the area vector form is sqrt-free and already implemented correctly in geomVolumeArea/geomVolumeGrad; the user was right

---

### Voro++-style worklist gather is now the default engine on both CPU and GPU backends
- area: voro
- source: vorflow-worklist-gather-next.md:11
- decided: 2026-06-26
- status: settled
- quote: |
    **DONE 2026-06-26.** Added the voro++-style **worklist gather** in
    `vorflow/tests/kokkos/bench_convexcell.cpp`, now the **DEFAULT on both backends** (`CC_GATHER`
    overrides). Closed the prior 0.89× CPU deficit → **voro++ parity (≈1.0–1.05×)** serial FP64; and —
    contrary to the initial "branching will hurt GPU" worry — it ALSO wins on GPU...
- rejected: the whole-block-accept approach for the earlier deficit; the prior assumption that branching would hurt GPU throughput
- why: "the gather keeps the same branchless inner loop, just walks fewer blocks (less work AND less warp divergence)"

### Voronoi robustness follows Sugihara's topology-oriented approach; exact/robust predicates are explicitly rejected
- area: voro
- source: robustness-topology-oriented-sugihara.md:10
- decided: undated
- status: settled
- quote: |
    For the GPU Voronoi work ..., robustness must follow **Sugihara's topology-oriented approach**,
    NOT exact/adaptive robust predicates (Shewchuk-style orientation/incircle). The user explicitly
    wants to **avoid robust predicates** and is **not concerned with the Delaunay triangulation** being
    consistent.
- rejected: exact/adaptive robust predicates (Shewchuk-style orientation/incircle tests)
- why: "exact/adaptive predicates are complex and slow (and awkward on GPU), and a globally consistent Delaunay dual is not needed — only the per-cell Voronoi geometry matters for the physics"

### VoronoiHalo disables periodic self-images (includePeriodicSelf=false) — device tessellator is periodic-native
- area: voro
- source: vorflow-kokkos-migration.md:1014
- decided: undated
- status: settled
- quote: |
    `include/vorflow/mpi/voronoi_halo.hpp` — `VoronoiHalo` wraps tpx BlockDecomposer+ParticleMigrator+ParticleHalo (includePeriodicSelf=FALSE because the device tessellator is periodic-native via minimal image).
- rejected: enabling periodic self-images in the halo (redundant with the tessellator's own minimal-image periodicity)
- why: "the device tessellator is periodic-native via minimal image"

### Wall-facet foot uses the general Newton foot n=−φ∇φ/|∇φ|², not the SDF-only n=−φû
- area: voro
- source: voro-mesh-optimizer-wall-force.md:57-59
- decided: undated
- status: settled
- quote: |
    - Chain uses the GENERAL foot n=−φ∇φ/|∇φ|² (Newton to sdf(x+n)=0); leading Jacobian dn/dx=−ûûᵀ is
      |∇φ|-INDEPENDENT ⇒ works for general level sets, not just proper SDF (|∇φ|=1). (User: don't hardcode
      |∇φ|=1.) NOT the addSdfWallForce n=−φû (has an extra |∇φ| in the leading term).
- rejected: addSdfWallForce's n=−φû foot (has an extra |∇φ| term)
- why: "User: don't hardcode |∇φ|=1" — the general form works for arbitrary level sets, not just proper SDFs

### Warp-cooperative clip / shared-memory neighbour staging (lever #2) was deliberately not pursued
- area: voro
- source: vorflow-worklist-gather-next.md:22
- decided: 2026-06-26
- status: settled
- quote: |
    #2 warp-cooperative clip / shared-mem neighbour staging = NOT done: the clip is inherently
    SEQUENTIAL (ConvexCell is one evolving polytope, can't split across a warp), and the evidence
    (#1 −7%, #3 only +1%) says the gather is compute/latency-bound, not bandwidth-bound, so staging
    warm-cache loads into scratch has a low ceiling + high rewrite risk.
- rejected: implementing warp-cooperative clip / shared-memory neighbour staging
- why: "the clip is inherently SEQUENTIAL ... the gather is compute/latency-bound, not bandwidth-bound, so staging ... has a low ceiling + high rewrite risk"

### Whole-block-accept (rmax) is a net loss on the fine grid and stays gated off by default
- area: voro
- source: vorflow-worklist-gather-next.md:30
- decided: 2026-06-26
- status: settled
- quote: |
    **Phase B** — `rmax` (farthest-corner dist²) whole-block-accept (`CC_WBA=1`) IS A NET LOSS on this
    fine grid (≤~1 seed/block ⇒ amortises over nothing, adds a per-block branch; ~3% slower at every
    density 0.3–4). Gated OFF by default.
- rejected: whole-block-accept (CC_WBA) as a default optimization
- why: "amortises over nothing, adds a per-block branch; ~3% slower at every density 0.3–4"

---

### dAreaTri kernel renamed to geomVolumeAreaGrad; policy named Voronoi, not PlaneVoronoi (user naming decision)
- area: voro
- source: vorflow-convexcell-geometry-split.md:74-77
- decided: undated
- status: settled
- quote: |
    NAMING: area-Jacobian kernel renamed `dAreaTri` → `geomVolumeAreaGrad` (+ `...AD` oracle) per user;
    policy named `Voronoi` (not `PlaneVoronoi`).
- rejected: the names dAreaTri and PlaneVoronoi
- why: "per user" (no further reason stated)

### geomVolumeGrad: sqrt-free 3-array form chosen over per-vertex normalization or a 4th scratch array
- area: voro
- source: vorflow-convexcell-geometry-split.md:36-46
- decided: undated
- status: settled
- quote: |
    **Phase 2 — `geomVolumeGrad` DONE** (commit `3251618`, vorflow main, not pushed): V + per-plane dV/dn
    directly, no area arrays exposed. KEY INSIGHT (don't relitigate): it is **sqrt-free AND 3-array**.
    dV/dn_k = (2·A_k·n_k − m_k)/|n_k|; scatter the RAW numerator `2·da·n_k − mom` per vertex ... fold
    per facet by `1/(2·nn[k])` so |n_k| cancels into stored nn=|n|² → NO transcendental (position force is
    cheaper than areas, which DO need a sqrt). Two failed intermediates I already ruled out: (a) normalizing
    inside the per-vertex scatter = 6× the sqrts → slow on CPU; (b) a separate raw `sacc[MAXP]` 4th array =
    GPU occupancy hit (124→82 M/s). The 3-array sqrt-free form wins on both.
- rejected: normalizing inside the per-vertex scatter (6x the sqrts); a separate raw sacc[MAXP] 4th scratch array
- why: normalizing per-vertex is "slow on CPU"; the 4th array is "a GPU occupancy hit (124→82 M/s)"

### nvcc: no first-capture inside `if constexpr`
- area: voro
- source: voronoi-methods-plan.md:29-30
- decided: 2026-09-03
- status: settled
- quote: |
    nvcc rule: no first-capture inside `if constexpr` (hoist).
- rejected: none stated
- why: none stated

### poke4 caching makes the new (TrackAdj) certificate uniformly beat the old poke design
- area: voro
- source: vorflow-dynamic-updater-phase01.md:191
- decided: 2026-06-30
- status: settled
- quote: |
    **poke4 OPTIMIZATION DONE → NEW UNIFORMLY BEATS OLD (vorflow 41eed26, umbrella cc50e8b, NOT pushed
    2026-06-30).** ... This = OLD's cheap cert (direct read) + NEW's cheap gather (computePoke4 from adj, NO
    findSharing). **RESULT: NEW faster than OLD at EVERY δ/h ...**
- rejected: the plain TrackAdj adjacency-derivation-per-query approach (pricier cert) and the OLD poke approach (expensive gather with findSharing)
- why: caching the 4 cert planes into a packed store buffer combines OLD's cheap cert read with NEW's cheap incremental gather

### vorflow get_num_neighbors must read the explicit cellFacetCount, not diff the device cellFacetOffset
- area: voro
- source: nanobind-zero-copy-migration.md:28
- decided: undated
- status: settled
- quote: |
    Also FIXED **vorflow get_num_neighbors** (separate bug, the original ask): differenced device `cellFacetOffset` which is a per-cell *base* in cell-finish order + size N (OOB) — NOT a CSR prefix sum (host struct's is; device's isn't, see tessellation_view.hpp). Read the explicit `cellFacetCount`.
- rejected: computing neighbour count as off(i+1)-off(i) over the device cellFacetOffset
- why: the device cellFacetOffset is a per-cell base in cell-finish order, not a CSR prefix sum (unlike the host struct's)

### voronoi_dynamics Kokkos port is OpenMP-first, no GPU backend this effort
- area: voro
- source: cuda-kokkos-migration.md:90-91
- decided: 2026-06-18
- status: settled
- quote: |
    - **voronoi_dynamics**: in scope but **OpenMP first** — rebuild on Kokkos OpenMP backend,
      keep half-edge mesh + incremental repair on host; no GPU backend this effort.
- rejected: doing a GPU backend for voronoi in this effort
- why: none stated beyond scoping

### voronoi_dynamics renamed to vorflow, not "voronoi"
- area: voro
- source: cuda-kokkos-migration.md:65-67
- decided: 2026-06-20/21
- status: settled
- quote: |
    **VORONOI -> `vorflow` DONE** (2026-06-20/21): the bare `voronoi` was taken (separate private repo) AND clashes
    with Voro++'s `voro::` namespace, so chose `vorflow` (a moving-Voronoi flow solver, parallels sdflow).
- rejected: naming it "voronoi"
- why: "the bare `voronoi` was taken (separate private repo) AND clashes with Voro++'s `voro::` namespace"
