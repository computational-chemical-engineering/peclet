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

### Model-B drag conversion: β_B = β_A/ε; CfdDem defaults changed (advection=True, eps_min 0.4)
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:25-26
- decided: 2026-07-06
- status: settled
- quote: |
    **Model-B drag conversion**: drag.hpp closures are literature Model-A forms; porous mode now divides the per-particle force by local eps in the kernels (`model_b` flag, driver passes `porous`) — β_B=β_A/ε. [...] **CfdDem defaults**: `advection=True` (driver sets flow.set_advection+set_implicit_advection — implicit FOU + deferred TVD, stable at coupled dt); `eps_min` 0.2→**0.4** (≈ RCP voidage; at 0.3 the porous bed diverges — Ergun β with 1/ε powers explodes below a physical packing; 0.4 stable).
- rejected: eps_min=0.2 or 0.3
- why: "at 0.3 the porous bed diverges — Ergun β with 1/ε powers explodes below a physical packing"
- conflict: eps_min later changed again to 0.05 with smoothing (session 2026-07-10), see below

### Porosity clip changed from a 0.4 floor to [0,1]-only, per user directive; MFIX-faithful smoothing/drag law added instead
- area: coupling
- source: porous-cfddem-cuda-two-bugs.md:59-62
- decided: 2026-07-10
- status: settled
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
- status: settled
- quote: |
    Layer 4 = resolved
    CFD-DEM; **the coupling force is `hydro_force_torque_reaction` (route b)** — the discrete
    reaction, R_i = rho/dt(u−uⁿ) − f_c − Σ_fluid-nbrs mu(u*_nb − u*_i) summed per owner, pressure
    never read (it telescopes inside owner regions). Identity ΣF = f·N_fluid gated to **−8.8e-15**;
    the traction integral (`hydro_force_torque`) is a DIAGNOSTIC only (29% low, resolution
    independent).
- rejected: hydro_force_torque (the traction integral) as the production coupling force
- why: "the traction integral (hydro_force_torque) is a DIAGNOSTIC only (29% low, resolution independent)"

### The cross-module CUDA porous-CFD-DEM crash was an async stream race, not a GraphAMG bug
- area: coupling
- source: multiphysics-framework-plan.md:382
- decided: 2026-07-06
- status: settled
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
