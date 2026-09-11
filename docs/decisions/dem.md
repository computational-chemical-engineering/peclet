# Design decisions — dem

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### Acceptance bar for solver-internals changes is run-scatter parity + gated defaults, not bit-identity
- area: dem
- source: dem-sweep-efficiency-plan.md:246
- decided: undated
- status: settled
- quote: |
    - Bit-identity is NOT the bar (GPU float atomics make even the baseline run-nondeterministic);
      the bar is: same model, gates green, physics numbers inside run scatter, off-by-default env
      gate until proven.
- rejected: bit-identity as the acceptance bar
- why: "GPU float atomics make even the baseline run-nondeterministic"

### Adaptive multilevel stop uses the quasi-static (QS) residual, not the full fine residual or coarse-only
- area: dem
- source: dem-multilevel-contact-solver.md:27
- decided: 2026-07-23
- status: settled
- quote: |
    Per iteration: 1 fine smoothing sweep + coarse leg; adaptive stop on the QS residual
    (`maxApproachQS`: fine corrections with |vn0| <= 4 vRest, + all coarse) — gating on the FULL fine
    residual burns the whole budget in flowing scenes (over-convergence brake); on coarse-only,
    statics degrade.
- rejected: gating the adaptive stop on the full fine residual (over-converges flowing scenes); gating on coarse-only residual (statics degrade)
- why: "gating on the FULL fine residual burns the whole budget in flowing scenes (over-convergence brake); on coarse-only, statics degrade"

### Blanket persistent-contact e=0 is rejected; restitution is one-sided-only when grounded and not rising
- area: dem
- source: packing-velocity-position-split.md:17
- decided: undated
- status: settled
- quote: |
    ONE-SIDED inelastic impulses (shock propagation, Guendelman 2003) for persistent contacts whose
    lower body is (a) NOT RISING (a rising support copies its bounce up the chain — fountain, measured
    +160) and (b) GROUNDED (warm-started decaying BFS support levels from wall contacts,
    `updateGroundedLevelsKokkos`; a gas-borne emulsion/lifted slug stays momentum-conserving so its
    weight stays on the gas); e is forced 0 ONLY in this one-sided branch (blanket persistent-e0 made
    the dense phase fully plastic — LSD springs return elastic energy in sustained contact — killing
    granular temperature: coupled bed showed plug heaving at mean dP 0.8 Mg/A; narrowing it restored
    chaotic bubbling at dP/(Mg/A) = 1.03).
- rejected: blanket persistent-contact e=0 for all persistent contacts
- why: "blanket persistent-e0 made the dense phase fully plastic ... killing granular temperature: coupled bed showed plug heaving at mean dP 0.8 Mg/A"

### Body-body friction accumulates normal impulse across velocity-solve iterations; plane/wall uses one-shot post-gravity load
- area: dem
- source: packing-velocity-position-split.md:45
- decided: 2026-06-13
- status: settled
- quote: |
    Friction is bounded by the velocity-level normal impulse: **body-body**
    accumulates each contact's normal impulse ACROSS the velocity-solve iterations (captures force-chain loads — a
    velocity *approach* proxy alone can't, since a stiff chain has ~`g·dt` approach at every depth); **plane/wall**
    uses the one-shot post-gravity load `approach·m` (a flat face's coplanar contacts converge poorly in the
    manifold, so accumulating over-holds).
- rejected: a velocity-approach-only proxy for body-body; accumulating normal impulse for plane/wall contacts
- why: body-body: "a velocity approach proxy alone can't [capture force-chain loads], since a stiff chain has ~g·dt approach at every depth"; plane/wall: "a flat face's coplanar contacts converge poorly in the manifold, so accumulating over-holds"

### Body-body multi-contact friction is quantitatively too weak (by ~coordination number Z); the fix is deferred sequential-impulse friction
- area: dem
- source: packing-friction-followup.md:17
- decided: 2026-06-14
- status: settled
- quote: |
    **Deferred (user said "note for future consideration, leave it for now", 2026-06-14).** The
    consolidated velocity-solve friction ... is stable but its **body-body multi-contact friction is
    quantitatively too weak — by ~the coordination number Z**. Reason: the Jacobi count-averaging that
    fixed the energy-injection instability divides each contact's friction by the per-body contact
    count, but body-body contacts are bounded by their *own per-contact* normal load (not an
    aggregate)...
- rejected: dividing each contact's friction bound by the per-body contact count (Jacobi count-averaging) as adequate for multi-contact bulk friction
- why: "body-body contacts are bounded by their own per-contact normal load (not an aggregate), so a packed particle's total friction comes out ≈ μ·(one contact's load) instead of μ·(sum over its ~Z contacts)"

### Both-asleep contacts are excluded from colouring by seeding colour = -2
- area: dem
- source: dem-sweep-efficiency-plan.md:95
- decided: 2026-08-07
- status: settled
- quote: |
    - **Exclusion = set both-asleep manifold/contact colour to -2** (a `sleepMask` seed param added to
      colorManifolds{,Incremental}/colorContacts{,Incremental}). eligible() ALREADY returns false for
      mColor<0, so this ALSO drops them from buildContactHierarchy (the 540-launch cost) AND the
      buckets — for free. The ledger kernels ... never take sleepMask, so the frozen force network is
      carried (LEDGER TRAP respected).
- rejected: none stated (chosen for reusing the existing mColor<0 eligibility path "for free")
- why: reuses eligible()'s existing mColor<0 check to also skip buildContactHierarchy and the buckets

### Boundary contact alignment must use the absolute wall contact point (rAavg), not rAavg−rBavg
- area: dem
- source: dem-sdf-walls-moving.md:43
- decided: undated (commit 505b194)
- status: settled
- quote: |
    Boundary-restitution fix (dem commit 505b194): the velocity solve's approaching-sign gate used
    `diffCenters = rAavg − rBavg` for ALL contacts, but for a boundary rBavg is the ABSOLUTE wall
    contact point ..., so `alignment` flipped sign around a curved/off-origin wall → cascading grains
    got restitution while SEPARATING → energy injection ("drum jumping", peak grain speed > wall
    speed ωR). Fix: boundaries use `diffCenters = rAavg` ...; body-body keeps rAavg−rBavg.
- rejected: using diffCenters = rAavg − rBavg uniformly for boundary and body-body contacts
- why: "for a boundary rBavg is the ABSOLUTE wall contact point ... alignment flipped sign around a curved/off-origin wall → cascading grains got restitution while SEPARATING → energy injection"

### Bug fix: hertzCommitHistory must not wipe carried previous state on the post-migration sentinel
- area: dem
- source: dem-mpi-solver-port-plan.md:50
- decided: 2026-07-24
- status: settled
- quote: |
    KEY BUG FIXED: `hertzCommitHistory` wiped the carried prev store when
    hertzNumPairs = -1 (the post-migration state) — a rebalance silently reset every Mindlin spring
    (6e-3 shift → 2e-6 after fix).
- rejected: none stated
- why: "a rebalance silently reset every Mindlin spring (6e-3 shift → 2e-6 after fix)"

---

### Cleared hypotheses during the H100 corruption investigation
- area: dem
- source: porous-scaling-benchmark.md:60-84
- decided: 2026-08-17
- status: settled
- quote: |
    Cleared: pair-buffer
    capacity (findCollisionsGrow auto-grows), sleeping, boundary/ghost-slab. ... probe_dem5 VERDICT (2026-08-17): -O0, -O0+ptxas-O0
    AND CUDA 12.9.1 ALL FAIL identically → compile-side hypotheses DEAD. ... probe_dem6 VERDICT (2026-08-17):
    ALL FIVE exec modes fail identically (graph/fused/plain-launch/full-recolor + default) →
    fault is INSIDE the device kernels; colorKey collisions excluded (unique idx in low word).
- rejected: pair-buffer capacity, sleeping, boundary/ghost-slab handling, compile-flag/toolchain differences, execution-mode (graph/fused/etc.) differences, colorKey collisions
- why: each was tested and ruled out by targeted probes before the real root cause (materialId OOB) was found

### Collision solve moved from count-averaged Jacobi to graph-colored Gauss-Seidel
- area: dem
- source: dem-colored-gauss-seidel-solver.md:10-23
- decided: 2026-07-10
- status: settled
- quote: |
    The dem single-GPU `step()` collision solve was moved from **count-averaged Jacobi** to **graph-colored
    Gauss–Seidel** for BOTH the restitution (velocity) and overlap (position) solves. ... **Why count-averaging existed and why GS retires it.** Two DIFFERENT over-counting problems:
    `reduceContactsToManifolds` collapses multiple contact POINTS of one PAIR into one constraint
    (sums normals/arms, `num_points`); the `min(1,2/count)` velocity / `1/count` position factors damped
    the JACOBI over-relaxation of a body touching many DISTINCT NEIGHBOURS (all impulses summed onto it →
    ~degree× overshoot → the e=0.8 resting-pile energy bomb). GS removes the SECOND: coloring guarantees a
    body is touched by ≤1 constraint per colour, impulses applied sequentially in place against already-
    updated velocities → no summing, no over-relaxation, no count factor.
- rejected: count-averaged Jacobi (min(1,2/count) velocity / 1/count position damping factors) as the primary over-relaxation fix
- why: it only masked the over-relaxation symptom for a body touching many distinct neighbours; GS removes the root cause via per-colour exclusivity

### Colouring stall-break needs a filtered count-averaged-Jacobi fallback for uncolourable manifolds
- area: dem
- source: dem-colored-gauss-seidel-solver.md:64-67
- decided: 2026-07-16
- status: settled
- quote: |
    two robustness additions after the SI fluidized-bed crush:
    (1) colouring stall-break + leftover count (64-colour bitmask saturates at contact degree > 62) with
    a filtered count-averaged Jacobi fallback pass for the uncolourable manifolds/contacts — previously
    those were SILENTLY SKIPPED by the GS sweeps, so deep overlap could never resolve;
- rejected: silently skipping uncolourable manifolds/contacts (the pre-fix behaviour)
- why: silent skipping meant deep overlap could never resolve when contact degree exceeded the 64-colour bitmask cap

---

### Contact/manifold buffer sizing must scale with per-particle shell point count
- area: dem
- source: dem-sdf-general-particles.md:65
- decided: undated
- status: settled
- quote: |
    **Contact buffer starvation** (real bug, fixed): default `maxContacts=capacity*16` is one-per-pair
    (sphere) sizing; a point-shell shape emits ~one contact per shell point, and since boundary/wall
    contacts are appended AFTER body-body ones, buffer saturation dropped WALL contacts → particles
    tunnelled through the floor / segfaults. `setSdfShape` now grows the contacts+manifolds Views to
    `capacity*max(16,nPts)`.
- rejected: fixed capacity*16 sizing regardless of shell point count
- why: "buffer saturation dropped WALL contacts → particles tunnelled through the floor / segfaults"

### Core principle: velocity solve owns all dissipation, position solve only removes overlap, no back-coupling
- area: dem
- source: packing-velocity-position-split.md:27
- decided: undated
- status: settled
- quote: |
    - **The velocity solve carries the full resting normal impulse** for a persistent contact (a resting/sliding
      body's load is held at the velocity level, not leaked to the position solve).
    - **ALL dissipative mechanisms (restitution AND friction, normal AND tangential) belong in the velocity solve.**
    - **The position solve only handles displacement / overlap removal** — pure geometry.
    - **No back-coupling from displacement to the velocity update.** The position correction must never feed back
      into velocity. (This was the user's deliberate stability choice — coupling Δx→Δv risks huge velocities at
      small dt.)
- rejected: back-coupling from the position correction into velocity
- why: "coupling Δx→Δv risks huge velocities at small dt"

### Cube-drum confinement requires a z-periodic barrel with no end caps — corner rounding does not work
- area: dem
- source: dem-cubes-gpu-pyvista.md:20-24
- decided: undated
- status: settled
- quote: |
    **Cube CONFINEMENT gotchas** (spent a lot here):
    - A cube CORNER tunnels the sharp barrel/cap join of a closed drum → mass leakage during spin (65k of
      85k escaped once). Rounding the corner did NOT fix cubes (unlike spheres). The fix: **z-periodic
      barrel, NO end caps** → 0 escaped. (z-periodic is slower: z-ghosts + big-domain broadphase, ~10× a
      capped drum, but it's the only clean confinement.)
- rejected: rounding the cube corner to prevent tunneling at the barrel/cap join; a closed (capped) drum for cubes
- why: rounding "did NOT fix cubes (unlike spheres)"; z-periodic barrel is "the only clean confinement" despite ~10x broadphase cost

### DEM particle radius/halo sizing must derive from baseRadius*scale*globalScale, not globalScale alone
- area: dem
- source: multiphysics-framework-plan.md:376
- decided: 2026-07-05
- status: settled
- quote: |
    (1) **DEM SI-units halo sizing** — the broadphase `rad` kernel + ghost band + margin were sized off
    `globalScale` ALONE, but the effective radius is `scale*globalScale*baseRadius`. A grain ≪
    globalScale ... got a halo 10-2000× its size → broadphase O(N²) hang / manifold OOM. FIX: added
    `Particles.baseRadius`..., `rad(i)=scale*gs*baseRadius`, `maxOwnedRadius(P)` reduce → ghost band
    `= maxRad`, margin `= 0.1*maxRad`. Backward-compat EXACT for grain-radius (radius=1); SI units now
    work with default gs ... (the set_global_scale workaround is GONE).
- rejected: sizing broadphase/halo/margin off globalScale alone; the prior workaround of forcing set_global_scale(rp)
- why: "the effective radius is scale*globalScale*baseRadius. A grain ≪ globalScale ... got a halo 10-2000× its size → broadphase O(N²) hang / manifold OOM"

### DEM velocity solve: over-relaxed min(1, 2/count) average, not raw Jacobi sum — needed together with a resting-contact threshold
- area: dem
- source: porous-cfddem-cuda-two-bugs.md:44
- decided: 2026-07-09/10
- status: settled
- quote: |
    Two-part fix: (a) resting-contact threshold e:=0 below 2·g·dt (threshold alone insufficient!); (b) the velocity solve applied the RAW Jacobi sum of manifold impulses (position solve always count-averaged) — now `min(1, 2/count)`·sum (ω=2 over-relaxed average: binary collisions exact, piles converge). Threshold+averaging TOGETHER defuse it; either alone fails.
- rejected: raw Jacobi sum of manifold impulses in the velocity solve; threshold alone
- why: "either alone fails" — the two fixes only work together

### Direction-aware (vector) orphan accounting is a measured negative result; scalar orphan stays production
- area: dem
- source: dem-event-level-restitution.md:83
- decided: 2026-07-25
- status: settled
- quote: |
    ## Direction-aware orphan: MEASURED NEGATIVE RESULT (2026-07-25, tried + reverted)

    Implemented the full vector-account variant ... Result: 25k 0.176 / 100k −0.051 (marginally
    better than scalar 0.170/−0.054) BUT the flowing scenes lose most of the orphan win — DRUM amp
    7838→7156, SILO 23.9→21.5 k/s. WHY (the physics lesson): each dying pair's budget is an
    INDEPENDENT stored event energy; two grinding contacts on opposite sides both stored elastic
    energy and both should return it — vector accounting annihilates them pairwise, deleting real
    stores. ... Scalar orphan (491e61a) stays production.
- rejected: direction-aware (vector) orphan accounting
- why: "vector accounting annihilates them pairwise, deleting real stores"

### Distributed (MPI) sleeping is out of scope for the first pass
- area: dem
- source: dem-sweep-efficiency-plan.md:188
- decided: undated (pre-made design)
- status: settled
- quote: |
    - MPI: out of scope first pass — gate sleeping to the non-distributed hooks; MPI ctests then
      unaffected. (Distributed sleeping needs asleep in MigratePack + ghost mirror + cross-rank
      wake via the sync cadence; do only after single-GPU validation.)
- rejected: implementing distributed sleeping in the first pass
- why: "do only after single-GPU validation"

---

### Drum stick/slip is a position-channel Coulomb-bound carry problem, not missing elasticity
- area: dem
- source: dem-dosta-benchmark.md:272
- decided: 2026-07-23 night
- status: settled
- quote: |
    **DRUM STICK/SLIP RESOLVED — POSITION-CHANNEL COULOMB-BOUND CARRY (2026-07-23 night, dem
    `eb89790`, pushed):** the user insisted stick (not elasticity) is the physics and NSCD literature
    agrees... ROOT CAUSE: the position projection is a SECOND normal-force channel invisible to the
    Coulomb bound — whatever load the velocity sweeps don't converge de-penetrates positionally, so
    friction saturates at a fraction of mu*N in any jostled bed... FIX: colored position solve
    accumulates per-contact positional lambdas -> ... next substep's cone bound = mu*(lambdaAcc*|Nsum|
    + posImpulse), GATED QUASI-STATIC.
- rejected: attributing the drum lag to missing Mindlin sustained-contact elasticity (the prior Hertz-control conclusion)
- why: "the user insisted stick (not elasticity) is the physics and NSCD literature agrees"
- conflict: supersedes dem-dosta-benchmark.md:251 (Hertz control experiment) as the final explanation of the drum-period residual.

### Drum-lag "faceted-wall" geometry explanation was falsified; root cause is missing sustained-contact tangential elasticity
- area: dem
- source: dem-dosta-benchmark.md:251
- decided: 2026-07-22
- status: superseded
- quote: |
    **HERTZ CONTROL EXPERIMENT — GEOMETRY DIAGNOSIS FALSIFIED (2026-07-22, published `5d9e7d2`, CI
    green):** the user challenged the faceted-wall explanation (GranOO matched the drum with PRIMITIVE
    geometry in the study)... RESULT: Hertz on the SMOOTH drum at verbatim mu_w=0.2 PHASE-LOCKS with
    the references... => impulse-solver drum lag = MISSING SUSTAINED-CONTACT TANGENTIAL ELASTICITY
    (Mindlin spring on enduring contacts), NOT geometry; wall-mu=0.4 was compensation.
- rejected: the earlier faceted-wall (200-gon geometry fidelity) explanation for the drum period lag
- why: "Hertz on the SMOOTH drum ... PHASE-LOCKS with the references and matches EVERY other case ... => ... MISSING SUSTAINED-CONTACT TANGENTIAL ELASTICITY ... NOT geometry"
- conflict: this itself supersedes the earlier "BETA + DRUM-PERIOD DEBUGGING" entry (dem-dosta-benchmark.md:222) which attributed the lag to faceted-wall geometry fidelity and shipped wall-mu=0.4 as a compensating companion.

### During the CUDA→Kokkos migration, the velocity/position split must be ported faithfully; physical validation and the friction fix are separate post-migration tasks
- area: dem
- source: packing-friction-followup.md:12
- decided: 2026-06-19
- status: settled
- quote: |
    During the Kokkos migration, port it FAITHFULLY to the current CUDA demgpu (machine-precision
    parity); flag the split's physical validation + the friction fix as a SEPARATE post-migration
    numerics task. See [[migration-faithful-port]].
- rejected: changing numerics/friction behavior during the backend migration
- why: none stated beyond keeping migration and numerics work separate (ties to the migration-faithful-port directive)

---

### Forward predicted position, not committed position, through ghost gather
- area: dem
- source: suite-distributed-status.md:23-26
- decided: undated (before 2026-06-09)
- status: settled
- quote: |
    Energy leak in fast dynamics was a **stale ghost `d_pos_pred`** — the gather copied committed
    `d_pos` instead of forwarding the *predicted* position (`predict_velocity` advances `d_pos_pred`
    before the gather). Fixed: forward `d_pos_pred`. Drivers must also carry quat+ang_vel through
    migration (dropping rotational state discarded spin energy).
- rejected: gathering committed `d_pos`
- why: dropping predicted position / rotational state caused an energy leak (discarded spin energy)

### Friction consolidated into one per-contact Coulomb friction in the velocity solve, replacing three overlapping patches
- area: dem
- source: packing-velocity-position-split.md:41
- decided: 2026-06-13
- status: settled
- quote: |
    The three overlapping
    friction patches (Fix A center-of-pressure friction in the manifold velocity solver, Fix B tangential friction
    inside the *position* solve, Fix C velocity feedback read from the position solve's `friction_lambda_n`) were
    replaced by ONE per-contact Coulomb friction in the velocity solve
- rejected: Fix A (manifold-only), Fix B (position-solve tangential friction), Fix C (velocity feedback from position solve's friction_lambda_n)
- why: consistent with the velocity-owns-dissipation / no-back-coupling contract

### Friction stability fix: Jacobi count-averaging instead of Jacobi-summed impulses
- area: dem
- source: packing-velocity-position-split.md:53
- decided: undated
- status: settled
- quote: |
    (1) body-body friction was per-contact
    Jacobi-SUMMED → over-relaxation pumped rotational energy (Σω² ×3700) → blow-up; fixed with Jacobi
    count-averaging (divide each contact's friction impulse by max of the two bodies' active-contact counts,
    `count_friction_contacts_kernel` + `d_plane_friction.y`; momentum-conserving; single contacts unchanged).
- rejected: Jacobi-summed per-contact friction impulses
- why: "over-relaxation pumped rotational energy (Σω² ×3700) → blow-up"

### Fused colour sweeps: CUDA-graph replay stays the solo default; fused auto-on only where capture is unavailable
- area: dem
- source: dem-perf-campaign.md:33-37
- decided: 2026-07-26
- status: settled
- quote: |
    => DEFAULT POLICY (demFusedWanted): CUDA-graph replay stays the solo default; fused auto-ON
    exactly where capture is unavailable — the DISTRIBUTED step (its per-iteration launch storm had
    no graphs; MPI-CUDA ctests now run fused) and PECLET_DEM_NO_GRAPH. Force with PECLET_DEM_FUSED=1
    / PECLET_DEM_NO_FUSED=1; PECLET_DEM_FUSED_GRID tunes grid. Solo default path = bit-for-bit the
    shipped 0c37c81 behaviour.
- rejected: making fused loop-kernels the universal default; a per-block-flag + block0-scan barrier variant (measured slower)
- why: graph-node transitions are cheaper than software barriers when graph capture is available; fused only helps where capture is impossible (e.g. the distributed step)

### Gallery fixes: dem OOB writes, wrong docstrings, opt-in reaction torque — root-caused, not worked around
- area: dem
- source: peclet-examples-gallery.md:256-264
- decided: 2026-08-30
- status: settled
- quote: |
    **THE GALLERY PAID FOR ITSELF IN SUITE FIXES:** dem `53fab35` — the raw narrow-phase contact count
    was used as a loop bound over maxContacts-sized views AND twelve capacity-sized per-body arrays
    were never resized when the SoA grew (two out-of-bounds writes; the pall-ring pour aborted with
    "corrupted double-linked list"). Fixing them moved that pour's mean coordination 3.38 → 4.04 and the
    peak contact overlap 63% → 32% of the wall. Plus dem `6d27ba4` (two wrong docstrings: `step()`
    with no argument advances NOTHING, and the default BODY-BODY friction is zero, which silently leaks
    a deep bed through an analytic wall) and coupling `3b24934` (the reaction TORQUE is opt-in and
    OFF by default — the force's exactness rests on −grad(pi) telescoping and that does not survive the
    first moment).
- rejected: none stated
- why: none stated

---

### General-particle shells must be voxel-decimated to a target point count
- area: dem
- source: dem-sdf-general-particles.md:60
- decided: undated
- status: settled
- quote: |
    Shell must be **decimated** — raw marching-cubes at res 64 = thousands of pts; builder voxel-thins
    to ~`target_shell_points` (few hundred, like the analytic shells).
- rejected: using the raw marching-cubes point count directly
- why: raw marching-cubes gives "thousands of pts"; decimation matches analytic-shell point density

### Grain-radius units remain an acceptable, but no longer required, convention
- area: dem
- source: dem-global-scale-sphere-limitation.md:23-26
- decided: 2026-07-05
- status: settled
- quote: |
    Consequence: `set_global_scale(s)` with `s != 1` now works (physical-unit grains). You can still
    prefer **grain-radius units** (global_scale = 1, size the geometry in radii) — the working
    examples do — but it is no longer required.
- rejected: requiring grain-radius units (global_scale=1) as the only correct usage
- why: the narrowphase fix makes global_scale != 1 correct

---

### Grid-SDF particle data is flat and x-fastest
- area: dem
- source: dem-sdf-general-particles.md:49
- decided: undated
- status: settled
- quote: |
    Grid is flat **x-fastest**
    (`idx=x+y*nx+z*nx*ny`); Python passes `phi.ravel(order='F')` of a `(nx,ny,nz)` array.
- rejected: none stated
- why: none stated (indexing convention, matches suite-wide x-fastest indexing per docs/CONVENTIONS.md)

### Growth-view sizing bug: every maxContacts-sized view must be grown together, not just contacts+manifolds
- area: dem
- source: dem-sdf-general-particles.md:69
- decided: 2026-07-23
- status: uncertain
- quote: |
    LIKELY FIXED 2026-07-23 (dem `7b5d1b8`): the `setSdfShape` growth in (2) enlarged only
    contacts+manifolds — every OTHER maxContacts-sized view (colors, pairKeys, lambda state…) stayed
    small → OOB device writes = silent corruption for ANY shape with >16 shell points. Retest before
    trusting the old crash report.
- rejected: growing only contacts+manifolds while leaving other maxContacts-sized views at the old size
- why: "OOB device writes = silent corruption for ANY shape with >16 shell points"

---

### HCS benchmark contact-solver exonerated via the colored-GS A/B
- area: dem
- source: hcs-mfix-benchmark-evidence.md:31-32
- decided: undated
- status: settled
- quote: |
    residual
    factor-2 stage offset at the labelled time cannot be settled without their input deck (their own
    Fig 33 KE only just plateaus at t*=1000, internally favoring a less-developed field). Contact solver
    exonerated via the colored-GS A/B ([[dem-colored-gauss-seidel-solver]]).
- rejected: the contact solver as the source of the residual factor-2 stage offset
- why: the colored-GS A/B comparison exonerated it

---

### Incremental colouring gated OFF under MPI, and position conflict detection avoids a host sync
- area: dem
- source: dem-sweep-efficiency-plan.md:47
- decided: 2026-08-07
- status: settled
- quote: |
    **Item 1 — SHIPPED (dem `061a553`, umbrella `29fa3a6`).** ... Gated OFF under MPI (carried colour
    can cross an un-arbitrated rank boundary) and via `PECLET_DEM_NO_INCR_COLOR=1` (A/B). Position path
    is CONFLICT-SELF-HEALING without a host sync (a host readback for conflict detection measured
    NET-SLOWER +0.5 ms — it stalls the async submission pipeline; a conflicting contact demotes to -1
    and re-arbitrates, spurious mask bits only over-constrain).
- rejected: enabling incremental colouring under MPI as-is; a host readback for conflict detection
- why: "carried colour can cross an un-arbitrated rank boundary"; host readback "measured NET-SLOWER +0.5 ms — it stalls the async submission pipeline"

### Interim DEM back-coupling commit reverted on user instruction
- area: dem
- source: porous-cfddem-cuda-two-bugs.md:76-77
- decided: 2026-07-16
- status: settled
- quote: |
    Final solver: dem
    `72353b0` (persistent contacts + grounded rise-gated inelastic shock propagation; the interim
    back-coupling `374565d` was REVERTED on user instruction) + eps hygiene (coupling
    `dfafc54`,`b79e0b7`)
- rejected: the interim back-coupling commit 374565d
- why: none stated beyond "REVERTED on user instruction"

### Interim dx→dv back-coupling was reverted on explicit user instruction — the no-back-coupling clause stands absolutely
- area: dem
- source: packing-velocity-position-split.md:10
- decided: 2026-07-16
- status: settled
- quote: |
    **REAFFIRMED 2026-07-16 (dem `0da7d0f`):** an interim dx->dv back-coupling (`374565d`) was
    REVERTED on explicit user instruction — the no-back-coupling clause stands absolutely.
- rejected: interim dx→dv back-coupling (commit 374565d)
- why: "REVERTED on explicit user instruction"

### Island sleeping shipped default-OFF, then found to explode statics to NaN, fixed and flipped to default-ON
- area: dem
- source: dem-perf-campaign.md:96-109
- decided: 2026-08-09
- status: settled
- quote: |
    **Item 2 (island sleeping) SHIPPED default-OFF dem `8ad905b` / umbrella `527d5cf`** ... **BUT it was EXPLODING to NaN on statics (fixed 2026-08-09,
    dem `8a25901`, default FLIPPED ON `0ba1433`, umbrella `25e8492`).** ... a sleeper made EXACTLY immovable (invMass
    0) let a wedged awake body's warm-started PGS NORMAL impulse DIVERGE -> friction cone ejects it to NaN
    (even N=720; MU=0 avoids it, posImpulse-zeroed does NOT — it's the normal channel). FIX = finite
    sleeper inverse mass (`sleepImmovableFrac=0.01`, heavy-not-rigid; multilevel `excludeImmovable` now
    keys on the asleep flag).
- rejected: making a sleeping body exactly immovable (invMass=0)
- why: exactly-zero inverse mass let a wedged awake body's warm-started PGS normal impulse diverge to NaN via the friction cone

---

### Kinetic-separation unloading gate beats eager v0til<0 gate
- area: dem
- source: dem-event-level-restitution.md:47
- decided: undated
- status: settled
- quote: |
    - Kinetic-separation unloading gate (+0.88) BEATS eager v0til<0 (+0.79): jitter separations
      drain the bank as fast as it fills mid-compression.
- rejected: eager v0til<0 unloading gate
- why: "jitter separations drain the bank as fast as it fills mid-compression"

### Legacy one-shot friction cluster stays gated off on the PGS path
- area: dem
- source: dem-dosta-benchmark.md:154
- decided: 2026-07-20
- status: settled
- quote: |
    **FRICTION-CONE PGS IMPLEMENTED (2026-07-20, dem-exp; step-2 of the approved plan):** ...cone
    sub-solve INSIDE solveVelocityPGSKokkos after the normal update... legacy friction cluster gated
    OFF on the PGS path (kept for Jacobi/g=0/MPI).
- rejected: running the legacy one-shot friction cluster on the PGS path
- why: none stated beyond the cone sub-solve replacing it on that path

### MPI drum geometry must use a rounded profile, not a sharp barrel+flat-cap min-SDF
- area: dem
- source: dem-sdf-walls-moving.md:33
- decided: undated
- status: settled
- quote: |
    MPI geometry caveats: (1) sharp SDF corners (barrel+flat-cap `min`) leak grains under trilinear
    smoothing, WORSE at MPI rank boundaries — use a ROUNDED drum (inflate an inset cylinder by a
    radius) for zero leakage.
- rejected: a sharp barrel+flat-cap min-composited SDF for a drum under MPI
- why: "leak grains under trilinear smoothing, WORSE at MPI rank boundaries"

---

### Mode "ordered" (level-ordered symmetric sweeps) is measured insufficient and kept only for A/B, not shipped as default
- area: dem
- source: dem-multilevel-contact-solver.md:67
- decided: 2026-07-23
- status: settled
- quote: |
    - Mode 4 "ordered" (level-ordered symmetric sweeps, candidate 1) measured INSUFFICIENT: pairwise
      inelastic impulses only EQUALIZE, a column cools one halving per up-down cycle (column |vz| 0.71,
      pour crush) — kept for A/B.
- rejected: "ordered" mode as a production stabilization mode
- why: "pairwise inelastic impulses only EQUALIZE, a column cools one halving per up-down cycle (column |vz| 0.71, pour crush)"

---

### Multilevel slip gate ships at 8·g·dt, not ungated, persistent+cone, or 2·g·dt
- area: dem
- source: dem-multilevel-contact-solver.md:52
- decided: 2026-07-23
- status: settled
- quote: |
    ## Gate trade-offs (all measured, battery pour vs silo large)
    - ungated: pour PASS, silo 16.7 (coarse cancels lateral aggregate approach = fake bulk viscosity)
    - persistent+cone: pour CRUSH (nn 0.61), silo 21.7
    - slip @ 8 g dt (SHIPPED): pour PASS, silo 20.9
    - slip @ 2 g dt: pour CRUSH, silo 21.4 — pour load-bearing contacts slip at 2–8 g dt, silo creep
      <= 8 g dt: the distributions OVERLAP in g dt units, no absolute slip threshold separates them...
- rejected: ungated aggregation (fake bulk viscosity, silo 16.7); persistent+cone gate (pour CRUSH); slip @ 2 g dt (pour CRUSH)
- why: slip @ 8 g dt is the only setting where both pour statics PASS and silo throughput is within an acceptable band

### Never use get_max_overlap() as the sole packing-quality gate
- area: dem
- source: porous-scaling-benchmark.md:53-56, 99
- decided: 2026-08-16
- status: settled
- quote: |
    dem's get_max_overlap ≈1e-4 even on good beds whose true pairwise overlap is 0.05–0.08R
    — it does NOT measure geometric overlap: it is the max constraint violation over the CONTACT LIST
    during the position solve (dem solver_position.hpp:130) — pairs dropped by broadphase are
    invisible to it. ... Never use get_max_overlap as the sole gate.
- rejected: using get_max_overlap() alone to validate packing quality
- why: it only measures the max constraint violation over the tracked contact list; pairs dropped by broadphase are invisible to it

### New per-pair/experimental features must default off and reduce bit-identically
- area: dem
- source: dem-dosta-benchmark.md:107
- decided: 2026-07-17
- status: settled
- quote: |
    Default-off = bit-identical. Validated: binary impact pair-e overrides global exactly
    (0.2/0.7/0.9-cases).
- rejected: none stated
- why: none stated (stated as a validation property of the design)

---

### Newton-e-alive-on-persistent-contacts plus banking beats bank-owns-restitution
- area: dem
- source: dem-event-level-restitution.md:42
- decided: undated
- status: settled
- quote: |
    - Newton e ALIVE on persistent contacts + bank (+0.88) BEATS bank-owns-restitution/Newton-off
      (+0.57): the micro-reflections are genuine returned energy; pR prevents double-count.
      `PECLET_DEM_REST_NEWTON_OFF=1` re-enables the A/B.
- rejected: bank-owns-restitution / Newton-off
- why: "the micro-reflections are genuine returned energy; pR prevents double-count"

### One fence after the whole GS sweep suffices — per-colour fencing is a needless host stall
- area: dem
- source: dem-colored-gauss-seidel-solver.md:36-38
- decided: undated
- status: settled
- quote: |
    **Perf gotcha (important):** a per-colour `space.fence()` is a HOST stall and made GS ~2× slower;
    consecutive `parallel_for` on one Kokkos exec space are stream-ordered on the device, so colour c+1
    already sees colour c's writes — ONE fence after the whole sweep suffices.
- rejected: fencing after every colour sweep
- why: consecutive parallel_for calls on one Kokkos exec space are already stream-ordered on device, making per-colour fences redundant host stalls

### One-sided grounded contacts are a momentum sink; the resolution is a staged symmetric+one-sided solver
- area: dem
- source: dem-dosta-benchmark.md:182
- decided: 2026-07-20
- status: settled
- quote: |
    **STAGED SOLVER = THE RESOLUTION (2026-07-20, dem-exp):** the naive per-pair ballistic gate
    FAILED (silo still 18.3, drum flat, impacts arrested high — any one-sided contact at the
    moving/static interface is a MOMENTUM SINK; the wavefront dies at the first held pair regardless
    of gating). Correct design = Guendelman staging: **Phase A = ALL sweeps symmetric (cone friction,
    momentum-conserving; side-flag view P.sideFlags zeroed); Phase B = stabilization pass only if the
    post-loop residual maxApproach > 2 g dt** — computeSideFlags (persistence+grounded+quasi-static
    |vn0|<=8 g dt gate, NO warm-zeroing — obsolete in staging) then up to 4x velocityIterations
    one-sided sweeps with adaptive stop (1x budget held the column but NOT the violent pour; 4x holds
    BOTH: column nn 0.988/ov 0.13, pour nn 0.985/ov 0.11).
- rejected: "the naive per-pair ballistic gate" (any one-sided contact at the moving/static interface is a momentum sink); pure symmetric PGS (crushes deep statics, see the ONE-SIDED DECISION EVIDENCE entry below); pure one-sided (breaks dynamics)
- why: "any one-sided contact at the moving/static interface is a MOMENTUM SINK; the wavefront dies at the first held pair regardless of gating"

### Orphan credit is mass-weighted to the heavier endpoint
- area: dem
- source: dem-event-level-restitution.md:69
- decided: 2026-07-25
- status: settled
- quote: |
    a scatter
    kernel credits unmatched-with-budget entries to their endpoint bodies MASS-WEIGHTED (heavy end =
    safe store, J²/2m; wall pairs → all to the particle)
- rejected: even/unweighted crediting between endpoints
- why: heavy end is "safe store, J²/2m"

---

### Orphan decay constant is 1/64 per substep, not 1/256
- area: dem
- source: dem-event-level-restitution.md:73
- decided: 2026-07-25
- status: settled
- quote: |
    Decay 1/64 per substep —
    CRITICAL: 1/256 failed the multilevel column battery (|vz| 0.30 vs ≤0.22); 1/64 restores 0.19
    with the 25k payout intact (completes ~2 ms after turnaround).
- rejected: decay constant 1/256
- why: "1/256 failed the multilevel column battery (|vz| 0.30 vs ≤0.22)"

### PGS friction bound must come from the converged normal accumulator, not from live approach velocity
- area: dem
- source: dem-dosta-benchmark.md:91
- decided: 2026-07-17 (bug found) / 2026-07-17 night (fixed)
- status: settled
- quote: |
    **WIP PGS FRICTION BUG (mechanism confirmed in code, 2026-07-17):** solver_friction.hpp derives
    the Coulomb bound from CURRENT approach velocities... The WIP PGS warm start applies last
    substep's converged impulses BEFORE the iteration loop -> approaches ~0 -> friction bound ~0
    -> body-body AND wall friction are structurally INERT for warm/persistent contacts in BOTH PGS
    configs... Natural fix: bound friction by the PGS accumulator lambdaAcc (the converged normal
    impulse x dt, already per-manifold) instead of re-deriving from approach.
- rejected: deriving the Coulomb friction bound from current approach velocity each iteration
- why: "the WIP PGS warm start applies last substep's converged impulses BEFORE the iteration loop -> approaches ~0 -> friction bound ~0 -> ... friction are structurally INERT for warm/persistent contacts"

### Particle data layout: plain Kokkos SoA Views, backend-default layout, not float4, not Cabana
- area: dem
- source: cuda-kokkos-migration.md:152-158
- decided: undated (Phase 2 session)
- status: settled
- quote: |
    - DATA-LAYER DECISION (user-confirmed): drop float4; use **plain Kokkos multidim SoA Views with
      backend-DEFAULT layout** — `View<float*[3]>` positions, `View<float*[4]>` quats, scalars as own
      Views. Default layout = LayoutLeft on GPU (coalesced) / LayoutRight on CPU (cache+SIMD), optimal
      per backend from one source. Packed `.w` scalars (inv_mass, phase) split into own Views. Keep
      transport-core MPI (NBX + persistent neigh-collective; unifies grid+particle on one decomp) — do
      NOT adopt Cabana (would duplicate the validated DeviceParticleHaloKokkos + silo particles from the
      grid side). Grid Field3D stays LayoutLeft (hard x-fastest interop contract); particles use default.
- rejected: float4 packed layout; adopting Cabana
- why: "Cabana would duplicate the validated DeviceParticleHaloKokkos + silo particles from the grid side"

### Per-pair material rebound gap was a material-approximation error, not a solver defect
- area: dem
- source: dem-dosta-benchmark.md:114
- decided: 2026-07-17
- status: settled
- quote: |
    **PER-PAIR RERUN RESULT (2026-07-17):** with exact pair materials the 25k impact rebound moved
    -0.083 -> **-0.040 disp = mid published band** (penetration unchanged -0.140) — the rebound
    deficit WAS the material approximation, not the solver.
- rejected: the assumption that the rebound deficit was a solver-level defect
- why: "with exact pair materials the 25k impact rebound moved ... to mid published band ... the rebound deficit WAS the material approximation, not the solver"

### Persistent-pair keys under MPI are gid-based, not index-based
- area: dem
- source: dem-mpi-solver-port-plan.md:22
- decided: undated
- status: settled
- quote: |
    **Global ids**: `Particles::gid` (identity single-rank, set in setPositions); step_mpi Exscan-
    re-bases once per particle set (`mpiGidsGlobal_` flag, reset by setPositions). Persistent-pair
    keys (`pairKeyOf`) are gid-based under MPI; ghosts get gid/materialId/groundedLevel via
    MpiGatherPack.
- rejected: index-based persistent-pair keys under MPI
- why: none stated (indices are not stable under migration/rebalance; gids are)

### Phase-B stabilization budget of 2x is the shipped default
- area: dem
- source: dem-dosta-benchmark.md:201
- decided: 2026-07-20 night
- status: settled
- quote: |
    **LANDED (2026-07-20 night): dem `f6fb7d2` + umbrella `4f75929`, pushed.** Friction-cone PGS +
    staged stabilization (Phase-B budget 2x = the sweet spot: statics hold AND 100k plateau -0.091 vs
    refs -0.090; 4x over-stiffens to -0.075, 1x fails the violent pour) + `set_stabilization(bool)`
    binding (replaces the sandbox env var)...
- rejected: Phase-B budget 4x (over-stiffens to -0.075); 1x (fails the violent pour)
- why: "2x = the sweet spot: statics hold AND 100k plateau -0.091 vs refs -0.090"

### Position solve is translation-only; overlap removal stays decoupled from velocity
- area: dem
- source: dem-colored-gauss-seidel-solver.md:31-34
- decided: 2026-07-10
- status: settled
- quote: |
    Position is translation-only (matches `applyUpdatesKokkos`, which drops
    `deltaQuat`; angular contact response lives in the velocity solve) and never writes velocity (overlap
    removal stays decoupled from velocity, per the design principle).
- rejected: none stated
- why: per the design principle that overlap removal is decoupled from the velocity solve

### Root cause of H100-only DEM corruption: Particles::ensureCapacity never resized materialId
- area: dem
- source: porous-scaling-benchmark.md:85-96
- decided: 2026-08-18
- status: settled
- quote: |
    **ROOT CAUSE FOUND + FIXED
    2026-08-18** (probe7 = compute-sanitizer): `Particles::ensureCapacity` never resized
    `materialId` — `generateGhostsKokkos` writes it per ghost slot guarded by the PADDED capacity →
    silent 1-byte OOB writes into the neighbouring allocation. Harmless on sm_120's layout,
    corrupted live solver state on H100 (explains: CPU clean, -O0/12.9 fail, all exec modes fail,
    per-machine determinism, non-monotone N = ghost-count/layout dependence). Fired on PASSING
    configs too (s104: 16 errors — latent everywhere).
- rejected: none stated
- why: none stated (this is the root-cause finding itself)

### Sleep hysteresis must use a wake threshold far above the jitter tail (40x vRest), not close to the sleep threshold
- area: dem
- source: dem-sweep-efficiency-plan.md:100
- decided: 2026-08-07
- status: settled
- quote: |
    - **HYSTERESIS is essential.** vRest~1e-3, median bed speed ~1e-3, but the residual jitter TAIL is
      0.03 (=30 vRest). cSleep=2 sleeps 97.6% (measured distribution). But wake@wakeScale=4 let the
      jittery 2.4% wake everyone -> 32%<->3% OSCILLATION, no freeze. Fix: sleep@2 vRest, wake ONLY above
      **wakeScale=40 vRest** (>> jitter) -> the bed freezes bottom-up to 97.7% and STAYS. Rule (b)
      contact-flicker wake DROPPED by default...
- rejected: wakeScale=4 (causes 32%<->3% oscillation, no freeze); rule (b) contact-flicker wake enabled by default
- why: "wake@wakeScale=4 let the jittery 2.4% wake everyone -> 32%<->3% OSCILLATION, no freeze"

### Sleepers must carry finite (not exactly zero) inverse mass
- area: dem
- source: dem-sweep-efficiency-plan.md:133
- decided: 2026-08-09
- status: settled
- quote: |
    **THE FIX = finite sleeper inverse mass.** buildInvMassEffKokkos gives a sleeper
    `sleepImmovableFrac * invMass` (default 0.01 = 100x a grain's mass) instead of 0: heavy but not
    perfectly rigid, so a wedged awake body relieves against it instead of the impulse diverging; the
    sleeper's velPred is re-zeroed each substep (no momentum) and both-asleep interior manifolds are
    still fully excluded (the speed win is intact).
- rejected: exactly-zero inverse mass for sleepers (invMass=0) — "made EXACTLY immovable"; an earlier attempted fix ("overload-wake rule d + sleep-overlap gate via a per-body bodyMaxPen") which did NOT fix it and was REMOVED
- why: exact immovability "let a wedged awake body's PGS normal impulse diverge -> friction cone ejection -> NaN, even at N=720"

### Sleeping default flipped ON
- area: dem
- source: dem-sweep-efficiency-plan.md:146
- decided: 2026-08-09
- status: settled
- quote: |
    ... DEFAULT FLIPPED ON (P.sleepingEnabled=true; PECLET_DEM_SLEEP=0 disables), validated a second
    time with the default on.
- rejected: sleeping default OFF (the prior state)
- why: none beyond the validated battery (statics hold, drum/silo inert 0.1–0.3%, 48 MPI ctests green)

### Sleeping is implemented as an invMassEff swap around the solve call, not a per-manifold kinematic flag
- area: dem
- source: dem-sweep-efficiency-plan.md:89
- decided: 2026-08-07
- status: settled
- quote: |
    - **invMassEff SWAP, not a per-manifold kinematic flag.** sim.hpp demStep swaps `P.invMass ->
      P.invMassEff` (sleepers + their ghosts -> 0) around the ONE demSolveContacts call, restores after.
      A sleeper is then immovable EVERYWHERE in the driver with ZERO driver edits... This is far less
      invasive than threading invMassEff through ~15 sites. Kernels live in `sleeping.hpp`.
- rejected: threading an invMassEff flag through ~15 call sites; a per-manifold kinematic flag
- why: "far less invasive than threading invMassEff through ~15 sites"

### Sleeping pairs must remain in the pair ledger (broadphase/narrowphase keep tracking them)
- area: dem
- source: dem-sweep-efficiency-plan.md:180
- decided: undated (pre-made design, carried into the shipped design)
- status: settled
- quote: |
    - LEDGER TRAP (critical): sleeping pairs MUST stay in the pair ledger. Keep broadphase +
      narrowphase running over everyone initially (the solve is the expensive part); sleeping
      pairs keep num_points/manifold entries and commit their frozen lambdaAcc/lambdaT/restBank
      through commitPairKeysLambda so (i) the warm-start network restores instantly on wake and
      (ii) Poisson orphan transfer does NOT fire for pairs that merely sleep...
- rejected: dropping sleeping pairs from the pair ledger
- why: "the warm-start network restores instantly on wake" and "Poisson orphan transfer does NOT fire for pairs that merely sleep"

### Stabilization iteration cap K=64, not 16
- area: dem
- source: dem-sweep-efficiency-plan.md:106
- decided: 2026-08-07
- status: settled
- quote: |
    - **K=64, not 16.** K=16 froze the impact's unloading network mid-rebound -> ball stuck at -0.0802
      (2/5 runs) + penetration shallow -0.0788. K=64 lets the rebound finish -> penetration -0.0801
      exact, z(end) in scatter. Default K=64.
- rejected: K=16
- why: "K=16 froze the impact's unloading network mid-rebound -> ball stuck ... K=64 lets the rebound finish -> penetration ... exact"

### Statics fix: persistent-contact tracking + grounded rise-gated inelastic shock; interim back-coupling reverted on user instruction
- area: dem
- source: dem-colored-gauss-seidel-solver.md:64-70
- decided: 2026-07-16
- status: settled
- quote: |
    **Update 2026-07-16 (dem `374565d`):** ... (2) the decisive
    statics fix (after the interim back-coupling was reverted on user instruction) is persistent-contact
    tracking + grounded rise-gated INELASTIC one-sided shock propagation in the velocity solve (dem
    `0da7d0f` + `72353b0`) — see [[packing-velocity-position-split]] for the full mechanism + refuted
    variants.
- rejected: the interim back-coupling approach
- why: reverted on user instruction

### Strategy B: build standalone Kokkos units, then one clean cut to flip demgpu
- area: dem
- source: cuda-kokkos-migration.md:143-146
- decided: undated (Phase 2 session)
- status: settled
- quote: |
    - STRATEGY (user-chosen "B"): build portable Kokkos kernel units validated STANDALONE (no cuBQL+Kokkos
      coexistence), then flip demgpu onto Kokkos+ArborX (drop cuBQL) in ONE clean cut once all pieces ready.
- rejected: making cuBQL and Kokkos coexist incrementally in demgpu
- why: avoids "mixing cuBQL(CUDA) + ArborX(Kokkos launch-compiler) + pybind in one module build" risk

### Symmetric PGS alone cannot hold deep statics; one-sided alone breaks ballistic dynamics
- area: dem
- source: dem-dosta-benchmark.md:167
- decided: 2026-07-20
- status: superseded
- quote: |
    **ONE-SIDED DECISION EVIDENCE (2026-07-20 late):** statics battery (96k, 60-layer column +
    violent pour...): **sym+cone CRUSHES the deep column** (nn 0.545 d_p, overlap 1.1, |vz| 5.45
    still collapsing) while one-sided holds it perfectly (nn 0.999, overlap 0.03) — increment
    propagation ~1 layer/sweep means 8 sweeps cannot carry 60 layers; the branch IS load-bearing for
    deep statics. But sym+cone WINS everything dynamic... RESOLUTION IMPLEMENTED: **ballistic gate**
    on the one-sided branch — computeSideFlagsKokkos now requires |vn0| <= 8*g*dt (quasi-static
    approach) for one-sidedness...
- rejected: none stated as an alternative here — this IS the (later superseded) "ballistic gate" resolution
- why: "increment propagation ~1 layer/sweep means 8 sweeps cannot carry 60 layers; the branch IS load-bearing for deep statics"
- conflict: the "ballistic gate" resolution here is itself superseded by the STAGED SOLVER decision above (dem-dosta-benchmark.md:182), which the same file records as the actual fix after the per-pair ballistic gate failed.

### Symmetric release beats one-sided grounded release
- area: dem
- source: dem-event-level-restitution.md:45
- decided: undated
- status: settled
- quote: |
    - SYMMETRIC release (+0.88) BEATS one-sided grounded release (+0.60) — the light partner's
      downward reaction re-compresses/re-releases layers below. `PECLET_DEM_REST_ONESIDED=1`.
- rejected: one-sided grounded release
- why: "the light partner's downward reaction re-compresses/re-releases layers below"

### The MPI velocity/position solve reuses the single-GPU driver via a Hooks template, not a separate implementation
- area: dem
- source: dem-mpi-solver-port-plan.md:15
- decided: 2026-07-23
- status: settled
- quote: |
    - `src/solve_driver.hpp`: the whole velocity+position solve (warm-started PGS, statics/stabilization
      modes 1–4, friction cone, colored-GS position solve, adaptive stops) lives in ONE Hooks-templated
      `demSolveContacts(P, nc, nm, nBodies, keyIdx, hooks)`. `SoloSolveHooks` = no-ops (demStep,
      validated BIT-EXACT on Serial pre/post extraction); `MpiSolveHooks` (sim.hpp) = syncEvery ghost
      refresh + post-phase refresh + `allMax` = MPI_Allreduce(MAX) on every adaptive-stop residual — a
      rank-local break would deadlock the collective forwards.
- rejected: a rank-local adaptive-stop break under MPI
- why: "a rank-local break would deadlock the collective forwards"

### The correct fix, if needed, is proper sequential-impulse friction with an accumulated per-contact tangential impulse clamped to the total Coulomb bound
- area: dem
- source: packing-friction-followup.md:26
- decided: 2026-06-14
- status: uncertain
- quote: |
    **Fix (if a concrete need arises):** proper sequential-impulse friction — store the accumulated
    per-contact tangential impulse in `ContactConstraint`, each sweep compute Δλ_t = -v_t/w_t, clamp
    the *total* |λ_t| ≤ μ·λ_n, apply Δλ_t, iterate. Converges to full Coulomb strength without the
    over-relaxation that caused the blow-up.
- rejected: the current Jacobi count-averaged friction scheme, for quantitative frictional-packing studies
- why: converges to full Coulomb strength "without the over-relaxation that caused the blow-up"

### The force engine was generalized into a Law/Hooks-templated driver per the device-first + MPI directive
- area: dem
- source: dem-mpi-solver-port-plan.md:40
- decided: 2026-07-24
- status: settled
- quote: |
    **Force engine DONE too (2026-07-24, dem 253049b + ee1249f, umbrella e8f425d):** per user
    directive (every method MPI + multicore + GPU), the Hertz engine was generalized into the
    force-based driver `src/solve_driver_force.hpp` — `demStepForce<Law, Hooks>` owns the Verlet pair
    cache with gid-key-carried per-pair history ... `HertzMindlinLaw` is the first law policy (future:
    linear spring-dashpot, JKR, bonded).
- rejected: a Hertz-only, non-generalized implementation
- why: "per user directive (every method MPI + multicore + GPU)"

### The multilevel-stabilizer rebound loss is an under-convergence artifact, not a momentum-sink effect — refuting the project's original premise
- area: dem
- source: dem-multilevel-contact-solver.md:42
- decided: 2026-07-23
- status: settled
- quote: |
    ## DECISIVE MEASUREMENT (kills the brief's premise)
    `escalate` (pure extra symmetric sweeps, provably momentum-conserving) ALSO deletes the 25k
    rebound (z(0.1) −0.0797 ≈ onesided) while `off` rebounds (−0.0375). The rebound was never deleted
    by the momentum sink: it is an UNDER-CONVERGENCE artifact — the converged rigid-inelastic model has
    no rebound... Consequence: transport acceleration alone can never restore it; the principled fix is
    [[dem-event-level-restitution]] (Poisson bank)...
- rejected: the mission brief's premise that a momentum-conserving stabilizer sink was deleting the rebound
- why: "escalate (pure extra symmetric sweeps, provably momentum-conserving) ALSO deletes the 25k rebound ... the converged rigid-inelastic model has no rebound (rigid chains bank no elastic energy...)"

### Uncapped grid is the default for the fused kernel launch
- area: dem
- source: dem-perf-campaign.md:31-32
- decided: 2026-07-26
- status: settled
- quote: |
    Grid-cap
    sweep: fewer blocks = worse (16→20.4ms); uncapped best.
- rejected: capping the launch grid to fewer blocks
- why: measured worse (16 blocks -> 20.4ms vs uncapped)

### Verlet-cached broadphase gated to non-periodic single-GPU only
- area: dem
- source: dem-sweep-efficiency-plan.md:201
- decided: 2026-08-07
- status: settled
- quote: |
    ## Item 3 — SHIPPED default-OFF (dem `eab6499`, umbrella `6ee02e6`)
    findCollisionsVerlet in solve_driver.hpp mirrors the Hertz skin... GATED non-periodic single-GPU
    (periodic ghosts churn slot ids per step -> cached pairs invalid) via `verletOK` in demStep.
- rejected: enabling the Verlet-cached pair list under periodic ghosts / MPI
- why: "periodic ghosts churn slot ids per step -> cached pairs invalid"

### Wall SDF resolution must be finer than the colliding cube, and seeded cubes must start axis-aligned
- area: dem
- source: dem-cubes-gpu-pyvista.md:25-28
- decided: undated
- status: settled
- quote: |
    - Wall SDF must be resolved FINER than a cube (~0.5 spacing) or cubes tunnel the barrel. Pass
      `build_wall_sdf(..., resolution=(nx,ny,nz))` as a TUPLE (fine xy, coarse z for a thin drum).
    - Seed cubes AXIS-ALIGNED (identity quat, the set_positions default). Random orientations at lattice
      spacing 2.1 overlap (cube face-diagonal 2.5 > 2.1) → seed explosion.
- rejected: a coarser wall SDF than the cube size; random initial cube orientations at lattice spacing 2.1
- why: coarse SDF lets cubes tunnel the barrel; random orientations at that spacing overlap (face-diagonal 2.5 > spacing 2.1), causing a seed explosion

### Wall SDF sign convention: val − residual (container convention), not val + residual
- area: dem
- source: porous-cfddem-cuda-two-bugs.md:43
- decided: 2026-07-09/10
- status: settled
- quote: |
    **Root cause of the grain loss = ONE SIGN**: `sampleWallSdf` off-grid extension did `val + residual` (object-SDF convention) but a wall SDF is a CONTAINER (positive void / negative wall, everything beyond the stored box is wall-side) → a grain pushed past the floor plane [...] read "clear" → free-fall forever. Fix: `val − residual`.
- rejected: object-SDF sign convention (val + residual) applied to a container wall SDF
- why: "a wall SDF is a CONTAINER (positive void / negative wall, everything beyond the stored box is wall-side)"

### Wall friction must accumulate the transmitted force-chain load over velocity iterations, like body-body contacts
- area: dem
- source: dem-sdf-walls-moving.md:52
- decided: undated (commit 84a0911)
- status: settled
- quote: |
    Wall-friction FORCE-CHAIN fix (dem commit 84a0911): the wall friction bound was each grain's OWN
    one-shot gravity approach (computePlaneLoad), ignoring the weight transmitted from grains above —
    so a DEEP bed slipped against a moving wall... Fix: accumulateNormalImpulseKokkos now also
    accumulates the wall normal load ..., and solveContactFrictionKokkos uses that accumulated
    friction_lambda_n as the Coulomb bound for walls (was planeFriction(:,0)).
- rejected: bounding wall friction by each grain's own one-shot gravity approach load
- why: "ignoring the weight transmitted from grains above — so a DEEP bed slipped against a moving wall (rotating drum stayed ~flat, only the surface monolayer dragged)"

### WallSdf sign convention: positive in the void, negative inside the solid wall
- area: dem
- source: dem-sdf-walls-moving.md:15
- decided: 2026-07-05
- status: settled
- quote: |
    - `WallSdf` (src/narrowphase.hpp): world-space grid SDF, **positive in the void, negative in
      the solid wall**. `detectWallSdfKokkos` tests each grain surface point (or sphere centre),
      gradient = push-out normal.
- rejected: none stated
- why: none stated (stated as the fixed convention)

### dem set_positions (N,4): w==0 does not mean fixed — invMass remap convention
- area: dem
- source: stale-build-mphys-trees.md:14
- decided: undated
- status: settled
- quote: |
    Also: dem's `set_positions` (N,4) remaps w==0 → invMass 1.0 (CUDA float4 "unspecified mass"
    convention) — "invMass=0 ⇒ fixed" is FALSE through that API; fixed beds are fixed only via
    `move_particles=False`.
- rejected: assuming w==0 in set_positions means invMass=0 (fixed)
- why: "remaps w==0 → invMass 1.0 (CUDA float4 'unspecified mass' convention)"

### dem set_positions resets every particle to shape 0 — set_shape_ids must be called after
- area: dem
- source: sdf-scene-campaign.md:32
- decided: undated
- status: settled
- quote: |
    TRAP re-confirmed: **dem set_positions
    resets every particle to shape 0** — set_shape_ids AFTER positioning, always.
- rejected: none stated
- why: none stated (invariant/API contract)

### dem.step() with no argument advances nothing
- area: dem
- source: sdf-scene-campaign.md:19 (line 40 in per-file numbering: "NEW from Layer 3-4")
- decided: undated
- status: settled
- quote: |
    NEW from Layer 3-4: **`dem.step()` with no argument advances NOTHING** (dt=0 is a relaxation step);
- rejected: none stated
- why: none stated (API/invariant fact)

### globalScale folded into effScaleA/effScaleB throughout body-body narrowphase
- area: dem
- source: dem-global-scale-sphere-limitation.md:10-18
- decided: 2026-07-05
- status: settled
- quote: |
    `detectContactsKokkos` (src/narrowphase.hpp)
    folded per-particle `scale` but NOT `globalScale` into the canonical->world map [...] while the sphere-A probe
    radius `params.x*scaleA*globalScale` DID include globalScale. So with `global_scale != 1` A's
    and B's radii disagreed [...] Fix: use `effScaleA = scale(idA)*globalScale`, `effScaleB = scale(idB)*globalScale` throughout
    the body-body narrowphase. Identical for `global_scale == 1` (so every existing example/test is
    unchanged); makes `global_scale != 1` correct.
- rejected: the prior narrowphase code that omitted globalScale from B's canonical remap
- why: "grains a real diameter apart read a ~(1−globalScale) penetration and the position solve exploded them"

### packing broad-phase: ArborX replaces cuBQL
- area: dem
- source: cuda-kokkos-migration.md:82-86
- decided: 2026-06-18
- status: settled
- quote: |
    - **packing-gpu** (`demgpu`) is the first portability spike: its broad-phase uses **cuBQL**
      (NVIDIA-only BVH, in `src/cuda/broadphase.cu` ~130 LOC) → replace with **ArborX 2.x**
      (Kokkos-native). 28 grid-stride kernels + 38 atomics + thrust sort_by_key/reduce_by_key map
      cleanly. `morton_arithmetic` is NOT used by this broad-phase and is already HIP-guarded — leave it.
- rejected: cuBQL (NVIDIA-only BVH)
- why: "Kokkos-native" portability; cuBQL is NVIDIA-only

### random-packed-bed example: use effective radius including growth_factor; use annealed pack.py protocol
- area: dem
- source: peclet-examples-gallery.md:58-71
- decided: 2026-07 (regenerated after dem 46dbe71)
- status: settled
- quote: |
    TWO example-side lessons: (a) use EFFECTIVE radius
    baseRadius*scale*growth_factor (growth_factor<1 at jamming; omitting it faked g(r)
    overlaps); (b) use the annealed pack.py protocol at phi_ref~0.63 (crude feedback +
    phi_ref 0.66 overshot jamming).
- rejected: baseRadius*scale alone (omitting growth_factor); phi_ref 0.66 crude-feedback protocol
- why: omitting growth_factor faked g(r) overlaps; phi_ref 0.66 overshot jamming

### set_restitution_model default is "newton", bit-identical to prior behaviour
- area: dem
- source: dem-event-level-restitution.md:11
- decided: 2026-07-24
- status: settled
- quote: |
    SHIPPED 2026-07-24: dem `b13b125` (umbrella `775467d`). `set_restitution_model("newton"|"poisson")`
    (default newton = bit-identical pre-existing behaviour; `PECLET_DEM_REST_MODEL` env override read at
    Simulation construction, empty string ignored).
- rejected: making "poisson" the default
- why: preserving bit-identical pre-existing behaviour as default

### set_velocity_use_gs defaults to True; False reverts to legacy Jacobi
- area: dem
- source: dem-colored-gauss-seidel-solver.md:13
- decided: 2026-07-10
- status: settled
- quote: |
    Toggle `Simulation.set_velocity_use_gs(bool)` (default True) gates BOTH solves; False = legacy Jacobi.
- rejected: none stated
- why: none stated

### step(0.0) settling must skip the velocity solve, friction, and thermostat, and zero the growth velocity
- area: dem
- source: packing-velocity-position-split.md:57
- decided: undated
- status: settled
- quote: |
    (2) `step(0.0)` settling ran the full velocity pipeline (growth term, restitution, friction, thermostat) while
    particles couldn't move → velocity accumulated → diverged; fixed by skipping the velocity solve + friction +
    thermostat and zeroing the growth velocity for `dt==0` (a settle is pure overlap removal).
- rejected: running the full velocity pipeline during a dt==0 settle
- why: "particles couldn't move → velocity accumulated → diverged"

---

### step_mpi stays on count-averaged Jacobi — distributed colouring across ghosts is a separate problem
- area: dem
- source: dem-colored-gauss-seidel-solver.md:55-57
- decided: 2026-07-10
- status: settled
- quote: |
    **NOT done — `step_mpi` stays on count-averaged Jacobi.** Distributed colouring across rank ghosts is a
    separate problem and the 6 MPI parity ctests must be preserved.
- rejected: none stated (scope boundary decision)
- why: distributed colouring across rank ghosts is a separate problem from the single-GPU GS solve
