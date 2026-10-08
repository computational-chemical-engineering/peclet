# Design decisions — coupling

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### CFD-DEM couples flow and dem in Python only, via DLPack, with no C++ link
- area: coupling
- source: multiphysics-framework-plan.md:408
- decided: undated
- status: settled
- quote: |
    CFD-DEM = unresolved point-particle two-way (ε in drag only, Model-A deferred); P2G/G2P in core,
    drag laws in new top-level `coupling/` (`peclet.coupling`), Python-composed via DLPack — no C++
    link between flow and dem.
- rejected: a direct C++ link between flow and dem
- why: none stated beyond the DLPack/Python-composed design choice

### Causes ruled out before finding the epsilon-conservative-momentum fix
- area: coupling
- source: porous-eps-conservative-momentum.md:17-19
- decided: 2026-07-12/13
- status: settled
- quote: |
    Diagnosis chain: NOT the ∂ε/∂t RHS
    term (both variants pumped), NOT the conservative-flux advection alone (compensation u·∇u = ∇·(uu) −
    u∇·u implemented — necessary, measured insufficient), NOT PCG/Chebyshev/GraphAMG (that was the
    separate stale-AMG NaN, flow `3daf641`).
- rejected: ∂ε/∂t RHS term as the cause; conservative-flux advection compensation alone as sufficient; PCG/Chebyshev/GraphAMG solver choice as the cause
- why: each was tested and either still pumped energy or was a separate, already-identified bug (stale-AMG NaN)

### Centre-of-rotation convention: NaN follows the body, any finite point (including origin) pins
- area: coupling
- source: sdf-scene-campaign.md:139
- decided: 2026-09-02
- status: settled
- quote: |
    **§7 item 3 RESOLVED (2026-09-02):** centre of rotation — NaN = follows the body (builder default),
    any finite point pins (origin included), explicit flag `centerPinned` as an 18th instance real
    (`kInstanceRealStride=18`; legacy 17-real raw arrays decode with the old zeros-follow rule);
    `set_instance_motion(center=...)` pins by flag.
- rejected: the old zeros-follow rule as ambiguous going forward (kept only for legacy 17-real array decode)
- why: none stated beyond disambiguating follow-vs-pin semantics

### Coupled decomposition uses weight-field-based rebalance, never exposing decomposition objects to Python
- area: coupling
- source: multiphysics-framework-plan.md:371
- decided: 2026-07-05
- status: settled
- quote: |
    coupling `CfdDem.rebalance(gamma)`: bin owned particles→Allreduce global count→ w=1+gamma*count →
    flow.rebalance_by_weights(w)+dem.migrate_to_weights(w) (both build SAME deterministic weighted ORB
    from one array — no BlockDecomposer crosses to Python). KEY design: weight-field-based rebalance
    avoids exposing decomposition objects.
- rejected: passing/crossing BlockDecomposer objects to Python
- why: "weight-field-based rebalance avoids exposing decomposition objects"

### Drag coupling must be implicit (semi-implicit on the momentum diagonal), not explicit
- area: coupling
- source: multiphysics-framework-plan.md:387
- decided: 2026-07-05
- status: settled
- quote: |
    dem extForce SoA; core `interp/particle_grid.hpp` trilinear gather/scatter; flow
    `enable_cell_force`/`enable_drag` (IMPLICIT semi-implicit drag = β on momentum diagonal, rebuilt
    per-step under hasDrag_ — explicit −βu DIVERGES for dense-bed β~1e3)...
- rejected: explicit −βu drag forcing
- why: "explicit −βu DIVERGES for dense-bed β~1e3"

### Exponential-integrator effective drag replaces plain explicit particle-side drag exchange
- area: coupling
- source: porous-eps-conservative-momentum.md:46-54
- decided: 2026-07-16
- status: settled
- quote: |
    **Follow-up (2026-07-16, coupling `e221052` + dem `c765c80`, umbrella `9b8d963`):** the ε-conservative
    projection's larger interstitial velocities (correction ∝ 1/ε in dense beds) pushed the EXPLICIT
    particle-side drag exchange past its stability margin in the gallery fluidized bed (β·dt/m ≳ 1 →
    |v| doubling per step → NaN by step 41 → contact storm that LOOKED like a hang; diagnose via
    per-iteration |v|/contacts heartbeat, NOT wall-time). Fix: **exponential-integrator effective drag**
    β_eff = (m/dt)(1−exp(−β·dt/m)) in both coupling drag kernels (`effectiveBeta`), applied consistently
    to particle force + fluid deposits (momentum-conserving); needs dem `get_inv_mass_view` (zero-copy).
    Exact for linear drag; ≡ β for β·dt/m ≪ 1 (dilute HCS bit-identical); saturates at m/dt (lands ON
    u_g, never beyond).
- rejected: explicit particle-side drag exchange (β·dt/m unconstrained)
- why: the ε-conservative projection's larger interstitial velocities pushed explicit drag past its stability margin, causing |v| doubling per step and NaN

---

### GraphAMG default restricted to !hasBc_ (domain-BC path defect)
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:13
- decided: undated (session predating 2026-07-06 fix below)
- status: superseded
- quote: |
    **GraphAMG bottom ∧ domain-BC diverges**: `configurePorousDragSolver` forced GraphAMG for porous+drag; on domain-BC operators a hard-converged PCG NaNs within ONE solve, even at β≡0 (code-path defect; periodic fine). Also `set_pressure_graph_amg` only took effect at the next `set_solid` — toggles silently no-ops. Fixed: live propagation + GraphAMG default only `!hasBc_` (**flow 6823dc0**). GraphAMG∧BC itself still open (documented in plan §2).
- rejected: forcing GraphAMG unconditionally for porous+drag
- why: "on domain-BC operators a hard-converged PCG NaNs within ONE solve"
- conflict: superseded later same file (2026-07-06): "GraphAMG∧domain-BC FIXED (was gated off) [...] GraphAMG re-enabled as porous+drag default"

### Kuipers deposit-after-push reorder tested, not adopted
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:39
- decided: 2026-07-09
- status: settled
- quote: |
    **Kuipers deposit-after-push reorder TESTED, NOT adopted**: moving update_void_fraction after the DEM substeps (eps^{n+1} synchronous with particles, Deen/Kuipers ordering) did NOT change stability (glass bed blew up earlier, 363 vs 689 — the pump was the DEM leak, not the eps lag). Kept the original ordering.
- rejected: Deen/Kuipers synchronous eps-update ordering
- why: "did NOT change stability... the pump was the DEM leak, not the eps lag"

### Model-B drag conversion: β_B = β_A/ε; CfdDem defaults changed (advection=True; eps_min 0.4, a floor since superseded — now 0.25)
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:25-26
- decided: 2026-07-06
- status: settled
- quote: |
    **Model-B drag conversion**: drag.hpp closures are literature Model-A forms; porous mode now divides the per-particle force by local eps in the kernels (`model_b` flag, driver passes `porous`) — β_B=β_A/ε. [...] **CfdDem defaults**: `advection=True` (driver sets flow.set_advection+set_implicit_advection — implicit FOU + deferred TVD, stable at coupled dt); `eps_min` 0.2→**0.4** (≈ RCP voidage; at 0.3 the porous bed diverges — Ergun β with 1/ε powers explodes below a physical packing; 0.4 stable).
- rejected: eps_min=0.2 or 0.3
- why: "at 0.3 the porous bed diverges — Ergun β with 1/ε powers explodes below a physical packing"
- conflict: eps_min later changed again to 0.05 with smoothing (session 2026-07-10), see below, and then to 0.25 (coupling `dfafc54`, 2026-07-16) — see "Void-fraction floor eps_min = 0.25". The Model-B conversion and `advection=True` stand.

### Porosity clip changed from a 0.4 floor to [0,1]-only, per user directive; MFIX-faithful smoothing/drag law added instead
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:59-62
- decided: 2026-07-10
- status: superseded
- superseded-by: "Void-fraction floor eps_min = 0.25: a physical regularisation at the random-close-packing limit" (coupling `dfafc54`, 2026-07-16) — the floor is no longer [0,1]-only; the superficial-velocity rule and the MFIX smoothing stand
- quote: |
    User directive: impose SUPERFICIAL velocity always (already done — fillPorousEpsGhosts face-eps≡1); clip porosity to [0,1] only (no 0.4 floor — small physical ε OK, change the drag law if it misbehaves, don't clamp); do EXACTLY what MFIX does for bidisperse; look up + implement MFIX's coarse-grid deposition.
    [...] **SHIPPED (coupling `9827523`)**: `smoothField()` = volume-conserving diffusive smoothing of deposited solidvol [...] default `eps_min` 0.4→0.05.
- rejected: clamping ε at a 0.4 floor
- why: "small physical ε OK, change the drag law if it misbehaves, don't clamp"

### Reaction torque coupling stays off by default despite being resolved
- area: coupling
- source: sdf-scene-campaign.md:56
- decided: 2026-08-31
- status: settled
- quote: |
    coupling `3b24934` can hand
    the reaction torque over but it is **OFF by default** — §7 item 9: the force's exactness rests on
    −grad(pi) telescoping over an owner region and that argument does NOT survive the first moment
    (|T|/(|F|R) = 3.2e-07 on a sphere whose true torque is exactly zero, vs the traction's 5.0e-14), and
    dem's default inverse inertia is not the grain's, so turning it on without `set_inv_inertia`
    diverges the settling gate to 5.9e+09.
- rejected: turning reaction-torque coupling on by default
- why: "dem's default inverse inertia is not the grain's, so turning it on without set_inv_inertia diverges the settling gate to 5.9e+09"

### Rebuild all three mphys host trees before diagnosing a coupling test failure
- area: coupling
- source: stale-build-mphys-trees.md:10
- decided: undated
- status: settled
- quote: |
    **How to apply:** Before diagnosing any coupling test failure, `cmake --build` all three mphys trees from current sources first; treat "works on CUDA tree, fails on host tree" as a stale-build smell.
- rejected: none stated
- why: "committed API/physics changes ... leave them silently stale" — on 2026-07-20 this burned an hour diagnosing a phantom failure

### The CFD-DEM coupling force is the discrete reaction (route b), not the traction integral
- area: coupling
- source: sdf-scene-campaign.md:18
- decided: undated
- status: settled (refined 2026-09-30 by "The public force API returns the reaction; the traction is a named diagnostic": the traction's Python name is now `diagnostics.hydro_force_torque_traction()`, and `hydro_force_torque()` is deprecated)
- quote: |
    Layer 4 = resolved
    CFD-DEM; **the coupling force is `hydro_force_torque_reaction` (route b)** — the discrete
    reaction, R_i = rho/dt(u−uⁿ) − f_c − Σ_fluid-nbrs mu(u*_nb − u*_i) summed per owner, pressure
    never read (it telescopes inside owner regions). Identity ΣF = f·N_fluid gated to **−8.8e-15**;
    the traction integral (`hydro_force_torque`) is a DIAGNOSTIC only (29% low, resolution
    independent).
- rejected: hydro_force_torque (the traction integral) as the production coupling force
- why: "the traction integral (hydro_force_torque) is a DIAGNOSTIC only (29% low, resolution independent)"

### The public force API returns the reaction; the traction is a named diagnostic
- area: coupling (flow's public force/torque API)
- source: USER decision 2026-09-30 (relayed in the force-api brief); flow branch `force-api` 749ca03 (names), ed1f27a (the warning), 90ddeca (callers); coupling branch `force-api` e41410f
- decided: 2026-09-30
- status: settled (USER approved 2026-09-30)
- quote: |
    1. The public "force on the particles" API must return the reaction.
    2. The traction integral stays available, under an explicit diagnostic name, documented as
       under-reading the viscous part by ~30 %.
    3. A consistent traction, i.e. the wall shear from the momentum operator's small-cell-robust
       reconstruction, is a planned item, not part of this change.
- rejected: leaving the traction under the natural name `hydro_force_torque()` (a user asking for "the force on my particles" got one ~30 % low with no signal); making `hydro_force_torque()` return the reaction in place (changes a shipped name's meaning and shape (4,n,3) → (2,n,3): a break, so a major under QUALITY_PLAN D9 — and the reaction refuses collocated / porous / variable-property / domain-BC runs, where the traction is the only estimate); the one-silent-release schedule of NAMING §0 for the old name (a silent release would ship the very error being removed)
- why: the traction differences the velocity across the wall with a central difference and under-reads the viscous part at every resolution — traction/reaction 0.685–0.730 over φ 0.008–0.45 and N 24–128 (flow 25a0e7c, 2026-09-30). The canon's additive path fixes the hazard without a break: `hydro_force_torque_reaction()` is THE force API (shipped, documented with its accuracy); the traction is `diagnostics.hydro_force_torque_traction()` (D2 tier; the `hydro_force_torque_<method>` pattern of the shipped reaction name and of coupling's `force_method=`); `hydro_force_torque()` returns the same traction array but raises a DeprecationWarning naming both, and goes at the next major. `ResolvedCfdDem(force_method="traction")` reads the new name.
- evidence: |
    TORQUE, measured before the public docs claim it (steady Stokes, periodic cube; reference
    8πμa³Ω/(1−φ), under which φ 0.008 and 0.027 agree to 3e-4 at equal R/h):
      spinning sphere, φ 0.027, R/h 6 / 9 / 12:  reaction 1.0275 / 1.0252 / 1.0193,
                                                  traction 0.593 / 0.653 / 0.723
      (φ 0.008, R/h 6 / 9: reaction 1.0270 / 1.0248, traction 0.596 / 0.655;
       φ 0.216, R/h 9 / 12 / 18: reaction 1.0451 / 1.0377 / 1.0290, traction 0.636 / 0.697 / 0.608)
      translating sphere, true torque 0, |T|/(|F|R): on the cell vertex reaction ≤ 1.6e-15
      (traction 1.4e-15); off it (+0.31, 0.17, 0.43 h) reaction 1.1e-3 / 6.4e-4 (φ 0.027, R/h 6 / 9)
      and 2.6e-4 / 6.4e-5 / 4.9e-5 (φ 0.216, R/h 9 / 12 / 18), traction 2.8e-3 … 5.0e-3.
    So the reaction torque is accurate in magnitude (~+2 %, falling with resolution, against the
    traction's −28 … −41 %) and the public getter returns it. The 3.2e-7 spurious torque in "Reaction
    torque coupling stays off by default" was not reproduced on these cases (≤ 1.6e-15 on the
    vertex); that entry's reason for the default — dem's default inverse inertia — is unaffected.
    Gate: flow `tests/python/test_hydro_force_units.py` (ctest `hydro_force_units`).
- note: PLANNED — a consistent wall traction from the Robust-Scaled (small-cell-robust) wall reconstruction of the momentum operator, so that traction → reaction under refinement; unlocks wall-shear maps, the pressure/viscous split of the accurate force and local surface fluxes; a candidate section of the M3 method paper (peclet-papers PLAN.md D8; flow CLAUDE.md "Open items"). Known dead end: the one-sided difference to the wall over the crossing distance θ — 1/θ unbounded on small cut cells, drag 17× too large.
- supersedes: none (refines "The CFD-DEM coupling force is the discrete reaction (route b), not the traction integral")

### The cross-module CUDA porous-CFD-DEM crash was an async stream race, not a GraphAMG bug
- area: coupling
- source: multiphysics-framework-plan.md:382
- decided: 2026-07-06
- status: superseded
- superseded-by: "The July porous CFD-DEM CUDA crash was three real bugs, not a stream race; a genuine cross-module stream race exists and is fenced by HandOff" (2026-10-08 correction)
- quote: |
    NEW ISSUE FOUND + FULLY DIAGNOSED + DOCUMENTED (2026-07-06, coupling `645752f`): porous CFD-DEM
    crashes on CUDA (illegal address, ~step 3 ...; OpenMP fine). ROOT CAUSE = a cross-module ASYNC
    RACE, **NOT graphAMG** (my initial guess was WRONG — it crashes with EVERY pressure driver:
    graphAMG, V-cycle, PCG). flow/dem/coupling are separate nanobind .so's -> separate Kokkos default
    CUDA streams; flow.step() returns while its porous kernels still READ the eps flow field, and the
    next cpl.step()'s coupling deposit OVERWRITES eps on a different stream -> race.
- rejected: "NOT graphAMG (my initial guess was WRONG)"
- why: "it crashes with EVERY pressure driver: graphAMG, V-cycle, PCG" — proven by CUDA_LAUNCH_BLOCKING=1 and deviceSynchronize placement A/Bs

### USER DIRECTIVE: porous=True (volume-averaged NS) is the default for CFD-DEM
- area: coupling
- source: cfddem-porous-default-directive.md:10
- decided: 2026-07-11
- status: settled
- quote: |
    USER DIRECTIVE (2026-07-11, HCS benchmark forensics): "For the fluid velocity the porosity should
    always enter the volume averaged Navier-Stokes equations. I think porous=True should be the default
    for CFD-DEM."
- rejected: porous=False (plain incompressible NS with ε only in the drag closure) as the default
- why: "solving plain incompressible NS with ε only in the drag closure (old porous=False default) drops the ∇ε flux divergence (gas diverted around dense regions) and ∂ε/∂t"

### Volume-averaged gas momentum must be epsilon-weighted with a matched projection pair
- area: coupling
- source: porous-eps-conservative-momentum.md:10-31
- decided: 2026-07-12/13
- status: settled
- quote: |
    **Formulation requirement found via the MFIX-Exa HCS benchmark (2026-07-12/13), fixed in flow
    `2d1564a` (umbrella `2f5ecc8`):** a volume-averaged (porous) gas must advance the momentum in its
    ε-weighted form with a projection pair derived from the SAME inertia. The old porous path (plain-u
    momentum (ρ/dt)I−μ∇², ε only in drag/constraint/coefficients) let the projection generate gas
    velocity following the moving porosity at zero inertia cost; the drag handed that energy to the
    particles: HCS particle variance ROSE ×30 past the clustering plateau (no physical source — exceeded
    total gas KE many-fold; clusters re-melted; benchmark decays).
- rejected: the old plain-u momentum path with epsilon only in drag/constraint/coefficients
- why: it let the projection generate gas velocity following moving porosity at zero inertia cost, and drag handed that spurious energy to the particles (measured 30x variance rise past the clustering plateau)

### porous=False is NOT "Model B" — terminology correction
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:22
- decided: undated
- status: settled
- quote: |
    Terminology: the repo's `porous=False` path is NOT "Model B" — it's div(u)=0 with ε only in the drag (dilute simplification); Model A/B both use full ∂ε/∂t+∇·(εu)=0 and differ only in the −ε∇p vs −∇p split (README mislabels this).
- rejected: calling porous=False "Model B"
- why: "Model A/B both use full ∂ε/∂t+∇·(εu)=0 and differ only in the −ε∇p vs −∇p split"

### porous=False is only a justified cheap approximation, never for published benchmark comparisons
- area: coupling
- source: cfddem-porous-default-directive.md:23
- decided: 2026-07-11
- status: settled
- quote: |
    **How to apply:** CfdDem(porous=True) is now the default (coupling driver.py, flipped 2026-07-11).
    Only use porous=False as an explicitly-justified cheap approximation for dilute/steady beds, never in
    published benchmark comparisons.
- rejected: using porous=False in published benchmark comparisons
- why: none stated beyond the correctness argument above

---

### One partition from construction on, chosen by the combined CFD + DEM cost
- area: coupling
- source: user decision 2026-09-25 (coupling session); implemented in coupling `CfdDem.__init__` → `_corebalance`
- decided: 2026-09-25
- status: settled
- quote: |
    rebalance at construction. In CFD-DEM there should be one partition, and it should be determined
    by a combined weighing of the costs of CFD and DEM.
- rejected: dem adopting flow's `init_mpi` partition at start-up (and the interim guard that raised at the first step and told the user to call `rebalance()` by hand)
- why: a coupled run's cost per rank is fluid work plus particle work, so the partition that balances it is the weighted ORB of the combined field `1 + gamma × particles per cell` (gamma = 1 until calibrated), not flow's equal-cell split; copying flow's partition would co-locate the codes but leave the DEM load, usually the dominant cost, unbalanced from the first step. Doing it at construction, through the same path as `rebalance()` (flow `rebalance_by_weights` → alignment → dem `migrate_to_weights(w, align)` → co-location assertion), also closes the start-up mismatch (48³ at np = 4: flow 32|16 vs dem 24|24) without user action. Fixed beds (`move_particles=False`) are exempt: dem never migrates there, so particles stay in flow's `init_mpi` block.

---

### Void-fraction floor eps_min = 0.25: a physical regularisation at the random-close-packing limit
- area: coupling
- source: coupling `dfafc54` (commit message); `coupling/README.md` (void fraction); flow `doc/porous_drag_scheme.md` §4 table
- decided: 2026-07-16 (recorded in the register 2026-10-08)
- status: superseded
- superseded-by: "USER DECISION — the void-fraction floor eps_min is a division guard, default 0.05, not a packing limit" (2026-10-08)
- quote: |
    eps_min default 0.05 -> 0.25: a physical regularisation (voidage below wide-bidisperse
    RCP can only be interpenetration/deposit artifacts) — the eps-conservative projection
    amplifies interstitial velocity by 1/eps, so artifact eps must never reach the fluid.
    [README:] The older 0.4 floor under-predicted dense-bed drag ~3x; the interim 0.05 guard let
    interpenetration artefacts detonate a bed.
- rejected: the 0.4 floor (clamps real dense-bed voidage ~0.28 and under-predicts the Ergun 1/ε³ drag ~3×, so a coarse dense bidisperse bed would not fluidize); the [0,1]-only clip with a 0.05 division guard (interpenetration/deposit artefacts reach the volume-averaged fluid, whose projection amplifies the interstitial velocity by 1/ε)
- why: real voidage bottoms out near random close packing (~0.36 monodisperse, ~0.25 for wide bidisperse mixes), so a 0.25 floor clamps only unphysical ε; the code default is `CfdDem(eps_min=0.25)` (`python/peclet_coupling/driver.py`) and the same 0.25 is the kernel default of `_coupling.compute_void_fraction`. Fixed-bed tests pass `eps_min=0.05` explicitly (their uniform lattice never clamps).
- supersedes: "Porosity clip changed from a 0.4 floor to [0,1]-only…" (the floor part; its superficial-velocity rule and MFIX smoothing stand) and the eps_min 0.4 of "Model-B drag conversion…"
- note: the 2026-07-10 user directive read "clip porosity to [0,1] only … small physical ε OK, change the drag law if it misbehaves, don't clamp". 0.25 is meant to keep that intent — it clamps only ε no packing can physically reach — but no record of the user explicitly approving the 0.25 floor was found; confirm with the user before treating it as directive-level.

### The July porous CFD-DEM CUDA crash was three real bugs, not a stream race; a genuine cross-module stream race exists and is fenced by HandOff
- area: coupling
- source: memory `archive/porous-cfddem-cuda-two-bugs.md:10-17` (fix record); coupling `7daf324` (HandOff, commit message)
- decided: 2026-07 (bugs fixed); 2026-09-26 (HandOff); recorded 2026-10-08
- status: settled
- quote: |
    The `coupling/doc/porous_cuda_async_race.md` "cross-stream race" diagnosis was wrong. Actual
    defects, found by staged bisection on a synthetic hand-set bed: 1. DEM broadphase pair-buffer OOB
    (illegal-address crash) [dem d4d4093] 2. GraphAMG bottom ∧ domain-BC diverges [flow 6823dc0]
    3. Drag never in the momentum operator on the all-fluid domain-BC path.
    [coupling 7daf324, 2026-09-26:] flow, dem and coupling each statically link their own Kokkos,
    hence their own CUDA/HIP streams, so nothing ordered a coupling kernel against the next flow/dem
    kernel on the same zero-copy arrays. [...] every wrapper that touches arrays shared with flow/dem
    opens with a HandOff guard that calls the global Kokkos::fence() on entry and on exit.
- rejected: the 2026-07-06 reading that the illegal-address crash was a cross-stream race (it was the DEM pair-buffer overflow plus two flow solver defects; "CUDA-only" was the 50-iteration pressure cap truncating a diverging solve at backend-dependent points); leaving coupling kernels unordered against flow/dem kernels on shared zero-copy arrays
- why: the race the July note hypothesised is real but was not what crashed: it surfaced on 2026-09-26 as stale eps ghosts (`update_void_fraction` on coupling's stream, then flow's `exchange_field("eps")` on flow's), failing `mpi_polydisperse_moving` np=4 on CUDA with rel-err up to 4.9e-3 in ~10–30 % of runs. With HandOff: 0/30 failures (max rel-err 3.75e-8); host-openmp bit-identical; CUDA cost 13.37 → 13.49 ms per coupled step.
- supersedes: "The cross-module CUDA porous-CFD-DEM crash was an async stream race, not a GraphAMG bug" (its "NOT graphAMG" was half right — GraphAMG∧BC was one of the three bugs, not the crash)

### USER DECISION — the void-fraction floor eps_min is a division guard, default 0.05, not a packing limit
- area: coupling
- source: user, session 2026-10-08; coupling `043d5e6` (default change), flow `5795fb0` (doc)
- decided: 2026-10-08
- status: settled
- quote: |
    [user:] Where is eps_min = 0.25 used. I hesitate to approve it. Different particle shapes can
    have different minima. Why is it needed?
    [after the analysis:] Lower the floor to a pure division guard of 0.05
- rejected: eps_min = 0.25 as a "physical regularisation at random close packing" (true only for sphere mixtures — ellipsoids pack to ε ≈ 0.26, wide bidisperse mixes lower, space-filling shapes → 0 — so it caps the drag of exactly the dense non-spherical beds dem targets); 0.4 (under-predicted dense-bed drag ~3×)
- why: the floor exists because a trilinear deposit on cells of ~one particle diameter is not a volume filter and can drive a cell's ε towards 0, where the 1/ε³ drag and the 1/ε projection blow up. That is a deposition defect, handled by `smooth_length` (~1.5 d_p), not by a physical bound; the floor only has to keep the 1/ε factors finite. No measured run was found behind the claim that the 0.05 floor "detonated beds" (it first appears in summaries after `dfafc54`, whose message gives only the reasoning; the one recorded blow-up of the period was pure DEM, restitution 0.8 on a resting pile). Matches the 2026-07-10 user directive: clip to [0,1], change the drag law if it misbehaves, don't clamp.
- supersedes: "Void-fraction floor eps_min = 0.25: a physical regularisation at the random-close-packing limit"
