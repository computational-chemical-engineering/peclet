# Design decisions — amr

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### AMR NS advection keeps the fluid-fluid scheme unchanged; uf stays the face-averaged form
- area: amr
- source: amr-ghost-collocated-ns-plan.md:83
- decided: 2026-07-24
- status: settled
- quote: |
    **Step 4 DONE (2026-07-24; core `50cfa80`, umbrella `b7d64b2`, NOT pushed).** NS advection
    under the ghost projection: advection scheme UNCHANGED (fluid-fluid gates, raw-area fluxes);
    uf stays ½(ui+uj)−∇φ (div-free bulk, residual-small band, = face avg at steady).
- rejected: none stated
- why: "= face avg at steady" (keeps the existing discretization consistent at the fixed point)

### AMR gets its own separate Python binding module (tpx_amr), not folded into tpx_mpi
- area: amr
- source: amr-python-bindings-next.md:14-17, 199-202
- decided: 2026-06-25
- status: settled
- quote: |
    Milestones 1–4 DONE + a stubs/example capstone — the entire NEW AMR binding surface. New module
    `python/tpx_amr.cpp` (separate from tpx_mpi; CMake builds it ONLY when the morton sibling is present,
    defining TPX_HAVE_MORTON + C++20 — opt-in, CI stays morton-free).
    ...
    - **Morton guard**: AMR is `#ifdef TPX_HAVE_MORTON`. The python build needs `-DCMAKE_PREFIX_PATH`/include
      pointing at the `morton` sibling so `TPX_HAVE_MORTON` is set. CI builds transport-core WITHOUT morton
      (private repo) ⇒ an AMR python module won't be CI-built; keep it a local/opt-in target (like the
      Kokkos halo). Decide: extend `tpx_mpi` (would force morton on it) vs a separate `tpx_amr` module.
- rejected: extending tpx_mpi to include AMR bindings
- why: would force the morton dependency onto tpx_mpi, breaking morton-free CI

### AMR keeps ORB block decomposition, not a global SFC partition
- area: amr
- source: amr-octree-status.md:12-15
- decided: undated
- status: settled
- quote: |
    Design contract: keep the ORB **block** decomposition (one local octree per block, codes relative
    to block origin) rather than one global SFC partitioned by index range (p4est/Dendro style). A
    uniform/unrefined octree is bit-identical to the existing structured block grid. Builds on
    `morton` (already an optional dep via `TPX_HAVE_MORTON`) + the owner-based `GridHalo`/`NbxEngine`.
- rejected: one global SFC partitioned by index range (p4est/Dendro style)
- why: "A uniform/unrefined octree is bit-identical to the existing structured block grid."

### AMR pressure "near-nullspace" stall under advection was an un-deflated incompatible RHS mean plus a stale PCG gate — not an SPD or coarsest-level defect
- area: amr
- source: amr-aperture-advection-resolved.md:11
- decided: 2026-08-19
- status: settled
- quote: |
    **Diagnosis (all three candidates measured, N=32 Z&H NS, RTX 5080):**
    - SPD refuted: the pressure operator is geometry-only (`advect_` never enters assembly); measured
      `<y,Lx>_D` vs `<x,Ly>_D` asymmetry 8.8e-15, Rayleigh quotients strictly negative.
    - Coarsest level refuted (the session's TOP hypothesis, borrowed from flow's agglomerated bottom):
      `AmrMultigrid::build` coarsens to a SINGLE leaf — the bottom is exact by construction.
    - CONFIRMED: the divergence RHS is zeroed at solid-centered cells with partially-open faces
      (operator DOF!), breaking telescoping ⇒ nonzero fluid-mean that GROWS with the developed flow...
- rejected: an SPD violation as the cause; the coarsest-MG-level as the cause (both explicitly refuted by measurement)
- why: measured asymmetry ~machine-epsilon rules out SPD; single-leaf coarsest bottom is exact by construction, ruling out that hypothesis; the RHS-mean incompatibility mechanism was confirmed to predict the measured stall floor to 3 digits

### AMR rebalance weight grid is defined over root cells, not fine cells
- area: amr
- source: dynamic-load-balancing.md:67
- decided: undated
- status: settled
- quote: |
    - For AMR the weight grid is over ROOT cells (globalRootSize), not fine cells.
- rejected: weighting over fine cells
- why: none stated

---

### All world-coordinate evaluation must use the global frame, never per-rank local coordinates
- area: amr
- source: amr-distributed-flow-campaign.md:22
- decided: 2026-07-26
- status: settled
- quote: |
    ALL world-coord evaluation in the GLOBAL frame (origin global + integer
    frameShift) — float non-associativity otherwise breaks α/ξ symmetry across ranks.
- rejected: per-rank local-frame world-coordinate evaluation
- why: "float non-associativity otherwise breaks α/ξ symmetry across ranks"

### Bind host AMR classes before the Kokkos device path
- area: amr
- source: amr-python-bindings-next.md:203-204
- decided: undated
- status: settled
- quote: |
    - **Host vs device**: bind the host AMR classes first (BlockOctree/AmrPoisson/AmrFlow/adapt are plain
      C++); the Kokkos device path (`*_kokkos`, `DeviceMultigrid`) needs Kokkos in the python build — defer.
- rejected: binding the Kokkos device AMR classes first
- why: "needs Kokkos in the python build" — deferred as a separate, heavier binding effort

### C/F scheme pressure matrix/MG/PCG stays standard order — placement is (1,2)
- area: amr
- source: amr-ghost-collocated-ns-plan.md:71
- decided: 2026-07-24
- status: settled
- quote: |
    Pressure matrix/MG/PCG/ghost-BiCGStab stay standard (φ→0 at the fixed point ⇒ matrix C/F order can't
    move steady — (1,2) placement).
- rejected: moving the matrix itself to quadratic C/F order
- why: "φ→0 at the fixed point ⇒ matrix C/F order can't move steady"

### C/F-consistent flow operators fix graded-mesh drag (supersedes the "momentum only" attempt)
- area: amr
- source: amr-octree-status.md:947-958
- decided: undated
- status: settled
- quote: |
    **C/F-consistent flow operators (DONE) ⇒ graded drag works.** Made the flow path C/F-consistent:
    (1) AmrCutCell momentum diffusion: regular fluid cells now use idiag·u−μ∇² via an internal
    C/F-aware AmrPoisson `lap_` (coeff(si,sj) at 2:1), cut cells keep ξ-overlay (finest/same-level),
    solid=identity; (2) AmrFlow divergence + ABC gradient use new `AmrPoisson::forEachFaceFull`
    (same 2:1 sub-face enumeration+openness as the operator), and project() uses the STANDARD openness
    vcycle (not solveQuad) so D,G,L are consistent ⇒ stable projection. KEY: graded flow DIVERGED
    before (Umean→1e27) due to div/grad C/F-inconsistency (NOT the momentum alone — momentum-only fix
    still diverged); the consistent div/grad fixed it.
- rejected: solveQuad projection (quadratic coarse-fine flux) for the graded flow's pressure solve; momentum-only C/F fix
- why: "the consistent div/grad fixed it" — D, G, L must all be built from the same 2:1 sub-face enumeration to be consistent

### Cell-count savings did not reduce march time — the saving is a spent, not lost, quantity
- area: amr
- source: amr-mixed-level-cut-band-plan.md:238
- decided: undated
- status: settled
- quote: |
    *M1 VERDICT (core `1c9517d`, umbrella `bb3bf91`) — H-band + H-launch; H-iters and H-mg REFUTED.*
    P3c's "1.62× fewer cells, ~0% step time" is a SPENT saving, not a lost one. On a uniform band every
    one of a row's 15 chain slots is an IDENTITY slot (1 CSR entry); on a mixed-level band every slot
    crossing a 2:1 boundary becomes a degree-2 LS cloud of **95–162 entries**, so the overlay CSR GROWS
    as the mesh coarsens
- rejected: H-iters and H-mg as explanations for the flat step time (both REFUTED)
- why: "on a mixed-level band every slot crossing a 2:1 boundary becomes a degree-2 LS cloud of 95–162 entries, so the overlay CSR GROWS as the mesh coarsens"

---

### Changing a default that affects numerics re-blesses bed references — treat as a decision, not a tuning knob
- area: amr
- source: amr-march-distributed-campaign.md:18-23
- decided: 2026-09-04
- status: uncertain
- quote: |
    1. **M2b — pick the production LS-cloud size. A [FABLE] DECISION, data already in hand**
    (plan §M2a results). Clean variants: `rho 1.8`, `rho 1.5`, `N ≤ 32` (all gates). `N ≤ 32` takes
    the depth-8 overlay CSR from 4.33× the uniform arm's to 1.65×, which is exactly where M1's
    +210 ms/step penalty lives. Knobs are already on main and INERT at their defaults
    (`PECLET_CORE_GPS_RHO`, `PECLET_CORE_GPS_MAXN`); changing a default is a numerics change that
    re-blesses the bed references.
- rejected: none stated (decision left open, pending)
- why: changing the LS-cloud size default changes numerics and therefore requires re-blessing reference beds

---

### Cloud-economy variant selection: bed permeability alone is the wrong discriminator
- area: amr
- source: amr-mixed-level-cut-band-plan.md:382
- decided: 2026-08-30
- status: settled
- quote: |
    **THE M2a FINDING (the reason M2b must read the table, not the offsets): bed permeability alone
    picks the WRONG variant.** N≤24 halves the d7 CSR and reads +0.210% vs the shipped +0.247% (i.e.
    CLOSER to the uniform control) yet FAILS the seam gate "LS2 matrix perturbation decays"; N≤16
    fails 3/4 gates and DIVERGES at step 40. Clean variants: rho 1.8, rho 1.5, N≤32 (4/4 gates) —
    N≤32 takes the d8 overlay CSR from 4.33× the uniform arm's to 1.65×.
- rejected: N≤24 and N≤16 cloud-economy variants (look better on permeability alone but fail seam/stability gates)
- why: "N≤24 ... FAILS the seam gate; N≤16 fails 3/4 gates and DIVERGES at step 40"

### Coarsening/covering construction must use c.find(f.code(i)) suite-wide, not ancestor(level+1)
- area: amr
- source: amr-distributed-flow-campaign.md:32
- decided: undated
- status: settled
- quote: |
    PLUS the **measured c2p fix**: ancestor(level+1)+find mis-parented root-level rows in
    mixed-depth ladders (49/56 on a probe) + block-alignment-dependent → covering construction
    c.find(f.code(i)) suite-wide (Multigrid/MomentumMG/AmrMultigrid).
- rejected: ancestor(level+1)+find for covering construction
- why: "mis-parented root-level rows in mixed-depth ladders (49/56 on a probe) + block-alignment-dependent"

### Collocated pressure coupling is ABC (Almgren-Bell-Colella), never Rhie-Chow
- area: amr
- source: amr-octree-status.md:56-68
- decided: undated
- status: settled
- quote: |
    **P6** collocated Stokes momentum+pressure step: `tpx/amr/flow.hpp` `AmrFlow<Bits>` wires both
    halves — momentum = per-component implicit BE viscous solve w/ AmrCutCell Dirichlet IBM
    ((ρ/dt)I−μ∇²); pressure = the **Almgren–Bell–Colella (ABC) approximate projection** (sdflow's
    collocated coupling, `sdflow/src/mac_approx_projection.hpp`): average cell→face MAC divergence,
    solve AmrPoisson openness ∇²φ=∇·u*, then correct cell velocities by **½(g⁻+g⁺)** of the two
    adjacent FACE φ-gradients with a CLOSED/solid face contributing a ZERO gradient (== sdflow
    `projectCorrectCenter`; `gradPhi` in flow.hpp). Face field exactly div-free, cell field
    approximately. Stokes only (advection deferred). Test: Poiseuille between immersed walls =
    analytic parabola to ~round-off; ABC projection cuts a pure-gradient field's div+|u| ~20×+.
    ⚠️ **NEVER propose Rhie–Chow for the collocated projection.** The residual cell divergence is
    INTRINSIC to cell-centered velocity placement (and the ~1% permeability gap is in the momentum
    solve, not the projection) — see [[sdflow-collocated-solver]]. The chosen method IS ABC; do not
    "upgrade" it to Rhie–Chow. (I repeatedly suggested Rhie–Chow by mistake — stop.)
- rejected: Rhie-Chow interpolation for the collocated pressure-velocity coupling
- why: "The residual cell divergence is INTRINSIC to cell-centered velocity placement (and the ~1% permeability gap is in the momentum solve, not the projection)"

### Compat-RHS repair works but is rejected for production in favor of deflation, due to a resolution-independent bias
- area: amr
- source: amr-aperture-advection-resolved.md:49
- decided: 2026-08-19
- status: settled
- quote: |
    the compat-RHS repair was TRIED AND MEASURED 2026-08-19 on branch `dev/aperture-compat-rhs`
    (core 94a069d, not merged): computing div on ALL operator DOF makes the RHS exactly compatible
    ... and ELIMINATES the V-cycle stall ..., with PCG cost unchanged (15–16 iters) — but it introduces
    a RESOLUTION-INDEPENDENT Stokes bias ~−0.09% ... VERDICT: deflation (main) is strictly better for
    production; the branch is the reference if a stall-free stationary V-cycle is ever needed.
- rejected: the compat-RHS repair (computing divergence on all operator DOF) as the production fix
- why: "it introduces a RESOLUTION-INDEPENDENT Stokes bias ~−0.09%"; deflation achieves the same iteration count without the bias

---

### Cut-cell openness α must be evaluated at the finer neighbour's actual lower corner, not the probe point
- area: amr
- source: amr-octree-status.md:871-874
- decided: undated
- status: settled
- quote: |
    BUG FIXED: sub-face α must use the finer neighbour's ACTUAL lower corner (lo−sj), NOT the probe point
    (lo−1 for a −face) used to find it — coeff is position-independent (openness-free test missed it) but α
    isn't. Added fineLoGlobal() helper (computes the fine sub-neighbour's global lo analytically, periodic-
    wrapped) used for the sub α in both in-block and remote branches.
- rejected: using the probe point's lower corner for computing sub-face α
- why: "coeff is position-independent (openness-free test missed it) but α isn't"

### D1' host parallelism is pure Kokkos over an OpenMP host space, not OpenMP pragmas
- area: amr
- source: amr-mixed-level-cut-band-plan.md:152
- decided: 2026-08-30
- status: settled
- quote: |
    THE PLAN = `core/docs/amr_setup_parallel_plan.md` (core b1c93d9): **D1′ PURE KOKKOS over an OpenMP host
    space — USER DECISION 2026-08-30 overriding my first-draft OpenMP-pragma route** (one parallel
    model; pragmas were a dead end for device assembly and untested by the ctest nets).
- rejected: "my first-draft OpenMP-pragma route"
- why: "one parallel model; pragmas were a dead end for device assembly and untested by the ctest nets"

### Distributed MG deadlock fixed by padding the hierarchy to the global-max level count
- area: amr
- source: amr-testing-benchmarking-resume.md:31-49
- decided: 2026-06-27
- status: settled
- quote: |
    **FIXED + PUSHED 2026-06-27 [...] It was NOT environmental: a REAL distributed deadlock.** Fix = pad the MG hierarchy to the
    global-max level count (`MPI_Allreduce` MAX) with identity root-brick levels, in
    `GradedDistributedMultigrid::buildImpl` [...] **Root cause**: the MG
    hierarchy is built by coarsening the **LOCAL** block until `coarse.numLeaves()==before`, so
    `levels_.size()` is **per-rank-local**. [...] Then `op.init` calls `coverLevels` — a **collective NBX**
    [...] once per level ⇒ mismatched collective count ⇒ the deeper rank's extra `coverLevels` deadlocks.
- rejected: per-rank-local level counts driving a collective loop
- why: "mismatched collective count ⇒ the deeper rank's extra coverLevels deadlocks"

### Distributed fragmentation guard design: halo label-propagation + Allreduce, not rank-local BFS
- area: amr
- source: amr-distributed-flow-campaign.md:67
- decided: undated
- status: settled
- quote: |
    (b) distributed fragmentation guard (rank-local BFS would mislabel cross-rank pockets → skipped
    multi-rank; label-propagation over the halo + Allreduce is the design).
- rejected: rank-local BFS for the distributed fragmentation guard
- why: "rank-local BFS would mislabel cross-rank pockets"

---

### Distributed momentum preconditioner is rank-local Galerkin MG, not Jacobi
- area: amr
- source: amr-distributed-flow-campaign.md:40
- decided: 2026-07-27
- status: settled
- quote: |
    **Momentum preconditioner = RANK-LOCAL
    Galerkin MG (exact local rows, ghost columns dropped): np=1 drops nothing ⇒ whole step
    BIT-IDENTICAL to single-rank (the np=1 gate CAUGHT the Jacobi fallback); np>1 additive
    Schwarz.**
- rejected: a Jacobi fallback preconditioner
- why: "the np=1 gate CAUGHT the Jacobi fallback" (it broke bit-identity to single-rank)

### Extend core's AmrFlow rather than build octree AMR into flow itself
- area: amr
- source: amr-ghost-collocated-ns-plan.md:134
- decided: 2026-07-23
- status: settled
- quote: |
    **FIRST: one scoping question to ask the user (in prose, per
    [[prefers-conversational-clarification]]).** There are two candidate homes: (a) extend
    **`peclet::core::amr::AmrFlow`** — the suite ALREADY has a collocated AMR NS solver in `core/`
    ... — vs (b) build octree AMR into `flow` itself (the old intent in
    [[sdflow-octree-amr-next]]). RECOMMEND (a): AmrFlow is exactly the collocated mode-0 analog, the
    octree/MG/2:1 machinery is done and tested there, and `flow` stays the uniform production solver.
- rejected: "build octree AMR into flow itself"
- why: "AmrFlow is exactly the collocated mode-0 analog, the octree/MG/2:1 machinery is done and tested there, and flow stays the uniform production solver"

### Fix: remove the stale presPCG_ && !advect_ gate — the PCG's per-iteration deflation already handles the incompatible RHS
- area: amr
- source: amr-aperture-advection-resolved.md:28
- decided: 2026-08-19
- status: settled
- quote: |
    **Fix** = remove the stale `presPCG_ && !advect_` gate (predates maskSolid): the PCG's
    per-iteration fluid-range projection (maskSolid + fluid-mean removal) deflates exactly the
    incompatible component. Flat 15–16 iters/step (tol 1e-10) through the whole impulsive transient;
    steady K identical to the V-cycle path to 4+ digits.
- rejected: keeping the presPCG_ && !advect_ gate that forced the (unconverging) V-cycle path under advection
- why: "the PCG's per-iteration fluid-range projection ... deflates exactly the incompatible component"

### Fragmentation guard: pocket cells pinned and excluded from the mean and gradients, not zero-forced
- area: amr
- source: amr-ghost-collocated-ns-plan.md:112
- decided: 2026-07-25
- status: settled
- quote: |
    (2) Fragmentation guard: findPocketCells BFS on the
    binary graph; pockets pinned+excluded from mean+hidden from directional gradients
    (sealed-shell ctest: 1208 pocket cells, healthy solve, pocket creep = viscous-limited ~f·L²/μ
    — NOT zero, don't gate it as zero).
- rejected: gating pocket creep as exactly zero
- why: "pocket creep = viscous-limited ~f·L²/μ — NOT zero, don't gate it as zero"

### G.2 decision changed: the whole core/amr tree becomes its own package peclet-amr, depending on core alone
- area: amr
- source: suite-quality-plan-1-0-0.md:68-80
- decided: 2026-09-10
- status: superseded
- quote: |
    **G.2 DECISION CHANGED 2026-09-10 (user asked, audit done):** the whole `core/amr/` tree — solver AND
    octree — becomes its own eighth package **`peclet-amr`** (`peclet.amr`) depending on `peclet-core`
    ALONE, not folded into flow and NOT depending on peclet-flow. Evidence: flow includes no AMR header;
    the only outside includer of the octree is core's own `amr_bindings.cpp`; voro needs one function
    (`greedyColoring` → `core/solver/coloring.hpp`); the Lagrangian rebalance is in `halo/`, not the
    octree. [...] One
    solver over a mesh policy (the pnm G.3 pattern) is a SEPARATE project, not implied.
- rejected: folding AMR into flow; making peclet-amr depend on peclet-flow; generalizing the pnm-G.3 mesh-policy pattern to AMR
- why: "flow includes no AMR header; the only outside includer of the octree is core's own amr_bindings.cpp... The two solvers have different data models"
- conflict: this is itself the earlier plan text's implicit assumption of relocating AMR "to flow or a dev/amr-flow branch" (suite-quality-plan-1-0-0.md:15-21) — the D1–D9 language allowed flow as a destination, this note settles it as a new standalone package instead

### GOTCHA/invariant: detect non-finite explicitly — max|u| via std::max(0,NaN) hides blowup
- area: amr
- source: amr-octree-status.md:781-782
- decided: undated
- status: settled
- quote: |
    GOTCHA: explicit blowup hides as max|u| via std::max(0,NaN)=0 ("looks stable") — must detect non-finite.
- rejected: relying on max|u| alone to detect solver blowup
- why: std::max(0,NaN) evaluates to 0, masking the blowup

### Gap-floor policy default n=4 is the calibrated floor, not sharper
- area: amr
- source: amr-mixed-level-cut-band-plan.md:102
- decided: undated
- status: settled
- quote: |
    **n IS CALIBRATED: the plan's default n=4 is SUPPORTED**
    (4–8 cells across the throat, 0.1–1.3% policy error, 18–30× fewer cells; error is −4.5..−9% at
    1–2 cells, ~1% at 4, sub-1% at 8 — but the sub-1% rows are NON-MONOTONE, so n=4 is a sound floor
    and nothing sharper).
- rejected: n=8 or sharper (non-monotone, not a reliable improvement)
- why: "the sub-1% rows are NON-MONOTONE, so n=4 is a sound floor and nothing sharper"

### Geometric octree-walk kernels kept as an independent oracle alongside the shared-CSR kernels
- area: amr
- source: amr-host-device-kernel-consolidation.md:31-32
- decided: 2026-06-27
- status: settled
- quote: |
    Geometric octree-walk
    versions kept as `*Geometric` = the INDEPENDENT oracle.
- rejected: deleting the geometric octree-walk implementations once the shared CSR body existed
- why: none stated beyond "the point" of the anti-drift lock (cross-checking shared-CSR vs geometric to 5.6e-16/0.0)

### Ghost metadata must be re-installed into builders at the top of every discovery round
- area: amr
- source: amr-distributed-flow-campaign.md:77
- decided: undated
- status: settled
- quote: |
    - Ghost metadata must be RE-INSTALLED into builders at the top of EVERY discovery round
      (same-round registry hits read levelOf → OOB otherwise; segfault at np≥2).
- rejected: none stated
- why: "same-round registry hits read levelOf → OOB otherwise; segfault at np≥2"

### Ghost projection is retired suite-wide; ghost_closure has no production consumer
- area: amr
- source: amr-aperture-advection-resolved.md:36
- decided: 2026-08-19
- status: settled
- quote: |
    **Retirement**: `setGhostProjection` AUTO→plain OFF (tri-state gone, device + oracle lockstep;
    explicit `true` still works, band violations always throw), `amr/ghost_projection.hpp` +
    `scheme/ghost_closure.hpp` carry quarantine headers — **`peclet::core::scheme::ghost_closure` has
    no production consumer anywhere in the suite** (flow quarantined 08-18, AMR 08-19).
- rejected: AUTO-selecting ghost projection as a production scheme
- why: it has no production consumer anywhere in the suite (superseded by the aperture+deflation fix above); note this predates the later collocated-attractor-campaign default flip back to AUTO ghost (collocated-attractor-campaign.md:53) for the *collocated* solver specifically — different subsystem/decision.

### Ghost-closure pure functions are lifted into core, not duplicated
- area: amr
- source: amr-ghost-collocated-ns-plan.md:36
- decided: 2026-07-24
- status: settled
- quote: |
    **Step 2 DONE (2026-07-24, core `c2c08a3`, flow `5811b72` + `43bfe6d` core scheme lift,
    umbrella `e909dfe`).** User chose LIFT: pure closures now in
    `core/include/peclet/core/scheme/ghost_closure.hpp` (float-verbatim; flow consumes via
    using-declarations — validated numerical no-op vs unmodified HEAD; NOTE: next flow wheel
    needs PECLET_TPX_TAG bumped past the next core release).
- rejected: duplicating the pure closure functions in flow and core separately
- why: "User chose LIFT"

### Graded-mesh flow requires ALL flow operators (momentum, divergence/gradient, advection) to be C/F-consistent — momentum-only fix insufficient
- area: amr
- source: amr-octree-status.md:947-958
- decided: undated
- status: superseded
- quote: |
    (superseded) GRADED drag earlier finding: was BROKEN — on a graded mesh (finest band + coarse far field) the flow
    COLLAPSES (Umean≈0, K≈0). Only AmrPoisson (pressure) is C/F-aware; the rest of the flow path —
    AmrCutCell momentum diffusion, the collocated divergence/gradient (divergence/gradOf in flow.hpp),
    AND the ±2 Koren advection stencil — all assume same-level neighbours and break at 2:1. So a
    genuinely graded drag needs ALL THREE flow operators made C/F-consistent (next chunk).
- rejected: fixing only the momentum operator for C/F-consistency
- why: "momentum-only fix still diverged"
- conflict: superseded by the same file's later "C/F-consistent flow operators (DONE)" entry below

### Host AMR must stay Kokkos-free; consolidation done via shared MORTON_HD kernel bodies over a templated accessor
- area: amr
- source: amr-host-device-kernel-consolidation.md:14-19
- decided: 2026-06-27
- status: settled
- quote: |
    the host AMR must stay **Kokkos-free** (firm constraint: there's a no-Kokkos default `build/` with
    `test_amr_poisson`/`cut_cell`/`transfer`/`adapt`). So the consolidation = **shared per-row kernel BODIES
    as `MORTON_HD inline` functions over a templated accessor**, called by a plain serial loop on the host
    (MORTON_HD is empty without Kokkos ⇒ Kokkos-free) and inside `Kokkos::parallel_for` on the device. ONE
    body, two dispatchers.
- rejected: making the host AMR reference depend on Kokkos
- why: "there's a no-Kokkos default build/ with test_amr_poisson/cut_cell/transfer/adapt"

### Host pressure runtime deliberately kept geometric (not switched to shared CSR kernels) for performance reasons
- area: amr
- source: amr-host-device-kernel-consolidation.md:33-36
- decided: 2026-06-27
- status: settled
- quote: |
    Host
    pressure *runtime* stays geometric (MG is perf-sensitive to per-call assembly; momentum already
    reassembles per step, so it was switched; pressure was not).
- rejected: switching the host pressure runtime to the shared assembled-CSR kernel
- why: "MG is perf-sensitive to per-call assembly"

### Implicit-FOU deferred correction defaults ON for AmrFlow advection
- area: amr
- source: amr-octree-status.md:777-782
- decided: undated
- status: settled
- quote: |
    **AmrFlow implicit-FOU deferred correction (DONE)** `setImplicitAdvection` (default ON):
    AmrCutCell::buildAdvectionFou builds the FOU operator from lagged uⁿ (advDiag_/advOff_, same-level
    nb_, wall faces vel=0), added implicitly in applyOp/gaussSeidel; explicit RHS term = ρ(SOU−FOU)/h0
    (advect−advectFou) which cancels at steady ⇒ unconditionally stable for the FOU part.
- rejected: pure explicit advection (default before this change)
- why: explicit blows up (CFL≈6.4 implicit bounded, explicit→NaN)

### Incremental rotational pressure projection replaces non-incremental Chorin (removes dt-dependent error)
- area: amr
- source: amr-octree-status.md:763-767
- decided: undated
- status: settled
- quote: |
    (b) The DOMINANT error was the PROJECTION SCHEME: a
    plain non-incremental Chorin projection has an O(dt) splitting-error boundary layer (≈−11% drag at
    N=32,dt=60, and the earlier "1st-order convergence" was really this dt-error masking it). The
    **incremental ROTATIONAL** update `p += (ρ/dt)φ − μ∇·u*` (predictor carries −∇p^n) removes it →
    dt-independent. AmrFlow now: rotational projection, ccFractionCore openness, AmrMultigrid (presMG_)
    pressure.
- rejected: plain non-incremental Chorin projection
- why: "a plain non-incremental Chorin projection has an O(dt) splitting-error boundary layer"

### Invariant: faceNeighborGather slot layout is [+x,-x,+y,-y,+z,-z]
- area: amr
- source: amr-python-bindings-next.md:34-35
- decided: undated
- status: settled
- quote: |
    GOTCHAS HIT: faceNeighborGather slot layout is 2*axis+(dir>0?0:1) = [+x,-x,+y,-y,+z,-z] (NOT
    [-x,+x,…]).
- rejected: a [-x,+x,-y,+y,-z,+z] slot ordering
- why: none stated beyond the actual implemented layout

### Island-corner C/F stencils sample a finer tangential neighbour by child-volume average
- area: amr
- source: amr-ghost-collocated-ns-plan.md:109
- decided: 2026-07-25
- status: settled
- quote: |
    (1) Island-corner C/F stencils: cfAppendStencil samples a FINER
    tangential neighbour by the 2^Dim-child volume average (fallback O(1/h) at corner rows →
    bounded; corners only exist on CURVED fine regions — convex test meshes have none, which is
    why earlier a-priori was corner-free).
- rejected: none stated
- why: bounds an otherwise O(1/h) fallback at corner rows

---

### M2/D3 verdicts: H-launch accepted as a small-mesh tax; np>1 ~3e-7 residual class accepted
- area: amr
- source: amr-mixed-level-cut-band-plan.md:357
- decided: 2026-08-30
- status: settled
- quote: |
    **M2 VERDICT + D3 RULINGS ISSUED 2026-08-30 (Fable, core `bc2b117`, umbrella bumped, pushed) —
    THE OPUS QUEUE IS SETTLED.** M2: H-launch ACCEPTED (small-mesh tax; fixes → device-assembly
    campaign); H-band attacked via cloud economy (clouds ~10× oversampled: deg-2 LS needs 12 pts,
    rho=2.2·max(h,H) gathers 95–162). D3(a): the ~3e-7 np>1 class ACCEPTED (build bitwise, residual
    contracts, identity band same mechanism; reopen only on growth-with-steps or steady-k
    np-dependence).
- rejected: reworking H-launch cost immediately (deferred instead to device-assembly campaign)
- why: "build bitwise, residual contracts, identity band same mechanism"

### MG hierarchy must share one h0 (level already encodes width)
- area: amr
- source: amr-octree-status.md:34-35
- decided: undated
- status: settled
- quote: |
    **Bug fixed:** MG hierarchy must share one h0 — the octree `level` already encodes width (don't double h0 per level).
- rejected: doubling h0 per level
- why: octree level already encodes width

### MG-as-solver + Picard outer loop: project ONCE per step, not inside the loop
- area: amr
- source: amr-gpu-smoother-flow-port.md:56-67
- decided: 2026-06-27
- status: settled
- quote: |
    `setOuterIterations(n, tol)`: Picard outer loop over the LAGGED ADVECTION only — re-lag +
    re-solve momentum, **project ONCE per step** (sdflow structure; mass term + warm start anchored at uⁿ
    via new u0_ snapshot, −∇pⁿ hoisted). KEY DESIGN FIX: projecting INSIDE the loop wrongly couples extra
    pressure iterations (Stokes stopped being a no-op, 1.3e-3 drift); project-once makes advection-off a
    true no-op that early-stops at 2 (test_picard_outer).
- rejected: projecting inside the Picard outer loop
- why: "projecting INSIDE the loop wrongly couples extra pressure iterations (Stokes stopped being a no-op, 1.3e-3 drift)"

### Minimum-image period for cloud membership is fineExt·h0, an off-by-one fix not a convention change
- area: amr
- source: amr-mixed-level-cut-band-plan.md:281
- decided: 2026-08-30
- status: settled
- quote: |
    **F2 RESOLVED 2026-08-30 (Fable, core `dfe8065`, umbrella `6421d4e`, pushed): the true-period
    fix is on main.** The decision needed no weighing — the minimum-image period of a periodic domain
    is `fineExt·h0` (what probeSlot/LeafHalo::wrap already use); the short value was an off-by-one
    (inclusive `bounds()`) through a truncating divide, not a convention. Landed as a MINIMAL change
    inside the OLD bin-search code (`nbx = max(fineExt)/4`, byte-for-byte the parked branch's
    expression), so the numerics fix and the D0 enumeration refactor never share a diff.
- rejected: "none stated" (bug fix, not an alternative choice)
- why: "an off-by-one (inclusive bounds()) through a truncating divide, not a convention"

### Mixed-level cut-band overlay CSR growth spends the cell savings, not lost — H-iters/H-mg refuted
- area: amr
- source: amr-march-distributed-campaign.md:30-37
- decided: 2026-09-04
- status: settled
- quote: |
    **The one result worth carrying in the head.** M1 attributed P3c's "1.62× fewer cells, ~0% step
    time" to **H-band, in a sharper form than pre-registered**: the graded band has FEWER rows, but on
    a uniform band every chain slot is an identity slot (1 CSR entry) while a mixed-level band turns
    every 2:1-crossing slot into a degree-2 LS cloud of 95–162 entries. So the overlay CSR GROWS as
    the mesh coarsens (9.38× at d7 n=2 for 1.59× fewer cells; 4.50× at d8), and the coarser mesh hands
    back more in overlay matvec (+210 ms/step) than it saves in the MG preconditioner (−164 ms). The
    cell saving is SPENT, not lost. H-launch is real but second-order (a ~178 ms/step mesh-independent
    floor, 20% of a d7 step); H-iters and H-mg are refuted.
- rejected: the pre-registered H-iters and H-mg hypotheses for where the mixed-level band's speed benefit comes from
- why: measured overlay CSR growth (up to 9.38x) at 2:1-crossing slots outweighs the MG preconditioner savings; only H-launch (a mesh-independent floor) is real

### Multicolor-GS smoother: symmetrize the adjacency before coloring; sweep must be symmetric (SGS), undamped
- area: amr
- source: amr-gpu-smoother-flow-port.md:40-55
- decided: 2026-06-27
- status: settled
- quote: |
    **TWO non-obvious correctness fixes (don't repeat):**
    (1) **symmetrise the adjacency before colouring** — the assembled cut-cell CSR is structurally
    ASYMMETRIC [...] so colouring only outgoing edges leaves two face-neighbours the same colour = a data race.
    (2) the GS sweep MUST BE SYMMETRIC (forward colours 0..C-1 THEN reverse C-1..0 = SGS), because the momentum MG
    is a BiCGStab PRECONDITIONER: a forward-only GS V-cycle is non-symmetric/non-normal and BREAKS
    BiCGStab's recurrence on the larger non-symmetric 64³ operator (false convergence → NaN; Galerkin+GS
    blew to 1e74 at 64³ while Galerkin+Jacobi was fine). [...] GS smooths UNDAMPED (omega=1.0; the V-cycle's 0.7 is Jacobi's damping limit
    & needlessly weakens GS).
- rejected: forward-only (non-symmetric) GS colouring/sweep as a BiCGStab preconditioner; damped GS (omega=0.7)
- why: "a forward-only GS V-cycle is non-symmetric/non-normal and BREAKS BiCGStab's recurrence"

### Mutex-on-miss fix: guard only the pre-freeze emplace, not the wider candidate fixes
- area: amr
- source: amr-mixed-level-cut-band-plan.md:135
- decided: 2026-08-30
- status: settled
- quote: |
    **F1 RESOLVED 2026-08-30 (Fable, core 33fd58f, pushed): mutex-on-miss.** Neither candidate
    fix was needed — two structural facts shrink the race to one statement: `misses_` is a
    coord-KEYED std::map (sorted iteration ⇒ ghost numbering depends only on the miss SET, thread
    interleaving canonicalizes bitwise), and `resolve()` checks `frozen_` BEFORE the emplace
    (post-freeze builders were never at risk). Fix = unique_ptr<mutex> in LeafHalo guarding only
    the pre-freeze emplace; cut_cell's serial dist-gate removed; prepareDistributed's discovery
    loop host-parallel.
- rejected: "Neither candidate fix was needed" (the two originally-proposed candidate fixes for the race)
- why: "misses_ is a coord-KEYED std::map ... thread interleaving canonicalizes bitwise, and resolve() checks frozen_ BEFORE the emplace"

### OpenMP backend is the bit-exact determinism reference; GPU is tolerance-based only
- area: amr
- source: amr-gpu-smoother-flow-port.md:142-146
- decided: undated
- status: settled
- quote: |
    **GPU is NOT host-bit-exact** (FMA contraction: nvcc fuses a*b+c, host doesn't). The existing
    `test_amr_device_multigrid_kokkos` ASSERTS device==host bit-exact and FAILS on the RTX 5080 [...]
    PRE-EXISTING, not a regression (the memory's "bit-exact on CUDA/HIP" was over-optimistic / OpenMP-only).
    All MY tests are convergence/tolerance based ⇒ pass on both. The OpenMP backend IS bit-exact (carries
    the determinism bar).
- rejected: the earlier belief that CUDA/HIP were bit-exact to host
- why: "FMA contraction: nvcc fuses a*b+c, host doesn't"

---

### Poisson operator sign convention unified suite-wide: L=∇² (negative-definite)
- area: amr
- source: amr-octree-status.md:861-865
- decided: undated
- status: settled
- quote: |
    **SIGN CONVENTION UNIFIED (DONE)**: suite-wide the operator IS L=∇² (negative-definite, matches
    AmrPoisson::applyLaplacian). Flipped DistributedPoisson + deviceJacobiSweep from A=−∇² to L=∇²
    (apply returns +inv·s; jacobi point-update u+=ω(Lu−b)/diag, diag=2D/h²=−L_ii). Killed the confusing
    inner.vcycle(e,−res) in the graded-MG bottom solve → now inner.vcycle(e,res). MG correction scheme is
    sign-agnostic so behaviour identical; all tests still pass.
- rejected: A=−∇² convention (used previously in DistributedPoisson/deviceJacobiSweep)
- why: to match AmrPoisson::applyLaplacian and remove the confusing double-negation in the graded-MG bottom solve

### Pressure smoother chosen: MG-PCG, NOT multicolor-GS; Chebyshev not pursued for pressure
- area: amr
- source: amr-gpu-smoother-flow-port.md:128-133
- decided: undated
- status: settled
- quote: |
    - **(a) smoother**: went MG-PCG (huge reuse: CG over existing matvec+V-cycle), NOT multicolor-GS
      (would lose determinism + need recolor-on-adapt). Kept the Jacobi V-cycle untouched (determinism
      tests intact). Did NOT do Chebyshev (pressure already scales perfectly with PCG ⇒ marginal here).
    - **(b) flow port sequencing**: pressure→DeviceMultigrid (already done) → momentum operator as CSR →
      projection kernels → wire DeviceAmrFlow. Stokes first (the Z&H drag benchmark is Stokes).
- rejected: multicolor-GS for the pressure smoother; a Chebyshev pressure driver
- why: "multicolor-GS would lose determinism + need recolor-on-adapt"; "pressure already scales perfectly with PCG ⇒ marginal here"

### Projection, MG transfers and V-cycle orchestration deliberately NOT consolidated onto a shared body
- area: amr
- source: amr-host-device-kernel-consolidation.md:47-52
- decided: 2026-06-27
- status: settled
- quote: |
    The projection (divergence/gradient over the face-geometry CSR), the MG
    restrict/prolong transfers, and the V-cycle orchestration were NOT folded onto a shared body: stable,
    already locked by the device-flow host-vs-device comparison, and would need a full host `FaceGeom`
    assembler for low marginal anti-drift value.
- rejected: consolidating the projection/MG-transfer/V-cycle code onto a shared body
- why: "would need a full host FaceGeom assembler for low marginal anti-drift value"

---

### Rediscretized coarse momentum operators fail — must coarsen the exact assembled operator (Galerkin)
- area: amr
- source: amr-gpu-smoother-flow-port.md:153-159
- decided: undated
- status: settled
- quote: |
    **Two REDISCRETISED momentum-MG attempts FAILED** (don't repeat): (a) openness/Neumann Helmholtz
    `idiag·I−μL_open` — at large dt a fully-solid cell's diag≈idiag amplifies its residual ~1e6 →
    BiCGStab DIVERGES; (b) added `max(idiag,μ/L²)` shift floor (fixes divergence) + immersed-wall
    Dirichlet diagonal — still no better than Jacobi [...] LESSON: a rediscretised coarse op can't match
    the cut-cell operator; must coarsen the EXACT operator ⇒ **Galerkin** (DeviceMomentumMG above) WORKS.
- rejected: rediscretized openness/Neumann Helmholtz coarse operator (with and without the shift-floor fix)
- why: "a rediscretised coarse op can't match the cut-cell operator"

### SOU (second-order-upwind) is the default advection flux; Koren TVD becomes an option
- area: amr
- source: amr-octree-status.md:770-776
- decided: undated
- status: settled
- quote: |
    **SOU advection (all impls)**: added second-order-upwind (SOU, unlimited 1.5L−0.5LL) as the
    default high-order advection flux, Koren TVD now an option. (a) sdflow: `sadv::sou`/`advect_sou`,
    `cadv::advect_sou`, `advect_sou` in both GridLayout policies, `advScheme_` (0=SOU default,1=TVD) +
    `set_advection_scheme` binding; FOU deferred-correction base unchanged; advection off by default so
    only advection-on runs change; full tests/kokkos (14) green incl. TG NS. Branch **sdflow/sou-advection**
    (pushed). (b) transport-core AmrFlow: `sou`/`hoFlux`, `setAdvectionScheme`; SOU op ~2nd order
    (ratio>3.3) vs TVD ~2.8.
- rejected: Koren TVD as the default (now opt-in)
- why: SOU measured ~2nd order (ratio>3.3) vs TVD ~2.8

### Sign convention: the AMR ghost operator is +L (negative-definite)
- area: amr
- source: amr-ghost-collocated-ns-plan.md:44
- decided: undated
- status: settled
- quote: |
    SIGN GOTCHA: AMR operator is +L (negative-definite) ⇒ the matrix delta is the NEGATIVE of
    flow's gpApplyDelta expression; divergence delta keeps flow's orientation; both invh-scaled.
- rejected: none stated
- why: none stated (a fixed sign-convention fact)

### Staircase velocity-MG fixed by the clean-fluid exclude mask; Galerkin stays the robust default
- area: amr
- source: amr-gpu-smoother-flow-port.md:29-38
- decided: 2026-06-27
- status: settled
- quote: |
    **Staircase initially
    diverged → user corrected me: the fix (sdflow velocity_mg_plan.md Phase 3) is the CLEAN-FLUID
    EXCLUDE MASK** — zero the cut+solid residuals out of the coarse defect (deviceZeroMasked before
    restrict) + masked prolong [...] RESULT: staircase VIABLE, BEATS
    Galerkin at 16³/32³ [...] **Galerkin stays DEFAULT (more robust + deeper at scale, no
    cap); staircase a validated opt-in**
- rejected: none stated (staircase kept as opt-in, not swapped in as default)
- why: "Galerkin ... more robust + deeper at scale, no cap"

### Volume-weighted superficial velocity is required on graded meshes
- area: amr
- source: amr-ghost-collocated-ns-plan.md:57
- decided: 2026-07-24
- status: settled
- quote: |
    MEASURED FINDING (band sweep + dilute attribution,
    tests/study/amr_zh_graded.py + amr_zh_dilute.py — volume-weighted superficial velocity is
    REQUIRED on graded meshes; dilute needs dt=1e6, the box is diffusion-limited at dt=60)
- rejected: non-volume-weighted superficial velocity on graded meshes
- why: "none stated beyond 'REQUIRED'" — implied: needed for the aperture scheme to show the same offset as the ghost scheme rather than diverge

### Zero pressure after finish_adapt rather than carry the accumulated pressure through coarsening
- area: amr
- source: amr-ghost-collocated-ns-plan.md:121
- decided: 2026-07-25
- status: settled
- quote: |
    KEY MEASURED LESSON:
    at steady dt the transferred accumulated p under COARSENING can be worse than p=0 (mid-cycle
    collapse K 1.28→4.5, recovery ≫ cold start); policy = zero p after finish_adapt
    (Flow.set_pressure binding) and re-accumulate — collapse gone.
- rejected: carrying the transferred/accumulated pressure through a coarsening adapt event
- why: "the transferred accumulated p under COARSENING can be worse than p=0 (mid-cycle collapse K 1.28→4.5, recovery ≫ cold start)"

### cf=1 (quadratic C/F flux) is not optional on graded meshes
- area: amr
- source: amr-mixed-level-cut-band-plan.md:113
- decided: undated
- status: settled
- quote: |
    cf=1 is NOT optional (P2b: the standard flux cannot converge on graded meshes), so the porous
    payoff is blocked until that stencil gets a stability condition or is rebuilt — a DESIGN FORK.
- rejected: standard (cf=0) two-point C/F flux on graded/throat meshes
- why: "the standard flux cannot converge on graded meshes"

### cfDiv/cfGrad row gate must be rowRegular, not rowFluid
- area: amr
- source: amr-mixed-level-cut-band-plan.md:70
- decided: 2026-08-27
- status: settled
- quote: |
    Real carrier = **cfDiv (the C/F divergence delta) firing at CUT rows**
    (row gate was rowFluid under the dead assumption "cut rows are finest-band"); per-path bisect:
    only disabling cfDiv restores stability. Mechanism = C2 violation (overlay owns cut-row
    constraint+gradient; cfDiv adds constraint velocity reads the gradient never sees). FIX =
    rowFluid→rowRegular for cfDiv_/cfGrad_ in flow.hpp + flow_oracle.hpp (the split cfMom_ always
    had) — inert BY GEOMETRY on finest bands (measured bit-identical vs pre-fix module).
- rejected: rowFluid gate under the assumption "cut rows are finest-band"
- why: "C2 violation (overlay owns cut-row constraint+gradient; cfDiv adds constraint velocity reads the gradient never sees)"

### mpi4py rule: never call a collective inside a rank-0-only block
- area: amr
- source: amr-distributed-flow-campaign.md:84
- decided: undated
- status: settled
- quote: |
    - mpi4py RULE: never call a collective inside a rank-0-only block (gleaves-in-print
      deadlocked np=4 once: rank 0 in allreduce, rest spinning in a halo Waitall, GPU 0%
      — gdb backtrace is the diagnostic).
- rejected: none stated
- why: "deadlocked np=4 once: rank 0 in allreduce, rest spinning in a halo Waitall"

### np=1 bit-exactness is the gate for every distributed default
- area: amr
- source: amr-distributed-flow-campaign.md:75
- decided: undated
- status: settled
- quote: |
    - The np=1 bit-exact gate is the workhorse: it caught the Jacobi-vs-MG preconditioner gap AND
      forces every distributed default to reproduce single-rank arithmetic exactly.
- rejected: none stated
- why: "it caught the Jacobi-vs-MG preconditioner gap AND forces every distributed default to reproduce single-rank arithmetic exactly"

### setGhostProjection default is AUTO (tri-state), not always-on or always-off
- area: amr
- source: amr-ghost-collocated-ns-plan.md:98
- decided: 2026-07-25
- status: settled
- quote: |
    **NS DEFAULT + STEP 5 DONE (2026-07-25; core `1306084`, umbrella `cc08472`, NOT pushed).**
    (1) setGhostProjection now TRI-STATE: default AUTO = ghost when advection on at setSolid
    (auto falls back to aperture + stderr warning on thin band; explicit ghost throws; Stokes
    keeps aperture default; aperture-intent tests now explicit setGhostProjection(false); auto
    arm BIT-IDENTICAL to explicit ghost on CUDA+OpenMP).
- rejected: none stated (Stokes explicitly keeps aperture as its own default)
- why: "auto falls back to aperture + stderr warning on thin band"

### setSolid bottleneck diagnosed as SDF evaluation cost, not builder logic
- area: amr
- source: performance-sota-yardstick.md:21-28
- decided: 2026-08-28
- status: settled
- quote: |
    DIAGNOSED 2026-08-28 (suite docs/AMR_GEOMETRY_SETUP_REQUIREMENTS.md, doubling-confirmed): **94%
    of that is SDF evaluation** (101 evals/leaf × 1.18 µs for the 180-sphere brute-force union);
    builder logic is only ~8 µs/leaf, and device-assembly phases are already ~free. The fix is the
    SDF agent's Layer-2 scene (candidate lists + BATCHED device eval — a scalar std::function API
    locks in serial host eval forever)
- rejected: a scalar std::function SDF evaluation API (locks in serial host evaluation forever)
- why: 94% of setSolid's cost is SDF evaluation, not builder logic; a scalar API cannot be batched/parallelized

---

### transferField prolongation gradients must be halo-completed, not block-local
- area: amr
- source: amr-distributed-flow-campaign.md:47
- decided: undated
- status: settled
- quote: |
    **transferGradients fix**: transferField's minmod prolongation
    gradients were BLOCK-LOCAL (faceNeighbor -1 at block edges → zeroed at interior boundaries →
    measured 4.7% post-adapt divergence); now halo-completed via coverValues/coverLevels with
    DOMAIN-crossing probes missing (the single-rank convention) ⇒ np=1 bit-exact, np>1 clean.
- rejected: block-local prolongation gradients
- why: "measured 4.7% post-adapt divergence"

### κ-restrict re-tested on Dirichlet: floor gone but still no win over plain — plain stays default
- area: amr
- source: amr-octree-status.md:899-910
- decided: undated
- status: settled
- quote: |
    Re-ran κ A/B on the NON-SINGULAR Dirichlet op (test_amr_kappa_dirichlet_kokkos): plain→2.6e-10
    (0.36/cyc), κ→6.7e-7 (0.47/cyc) — κ FLOOR GONE (both round-off), confirming the periodic NULLSPACE caused
    the earlier floor; but κ still doesn't BEAT plain (slightly slower, likely because prolongation stays plain
    PC = unmatched transfer pair). NET: plain volume-average stays default everywhere; κ safe on non-singular
    but no win.
- rejected: κ-weighted restriction as default (confirmed again)
- why: "κ still doesn't BEAT plain (slightly slower ... unmatched transfer pair)"

### κ-weighted MG restriction evaluated and rejected as default; plain volume-average stays default
- area: amr
- source: amr-octree-status.md:888-898
- decided: undated
- status: settled
- quote: |
    **κ-weighted restriction EVALUATED → kept opt-in, NOT default (DONE)**: added optional Galerkin-style
    κ-weighted restriction to DeviceMultigrid (setKappaRestrict(true); default off). Coarse res =
    Σκ_c·res_c/Σκ_c, κ=per-cell mean face aperture ... EXPERIMENT
    test_amr_kappa_restrict_kokkos A/Bs on a STRONG cut: plain → 5e-7 (0.49/cyc), κ-weighted → only 2e-3
    (0.64/cyc) — κ is WORSE. Root cause: κ-weighting breaks the EXACT conservation of the volume-average,
    so on the SINGULAR (periodic, constant-nullspace) problem the restricted residual is no longer ⊥ the
    nullspace ⇒ slower + residual FLOOR. CONCLUSION: plain volume-average stays default everywhere; κ-restrict
    is a documented opt-in only for non-singular/Dirichlet configs. (Lesson: for singular Poisson MG, the
    restriction MUST preserve the volume-integral; any reweighting that breaks conservation reintroduces a
    nullspace floor — don't "improve" the restriction without preserving Σ V·res.)
- rejected: κ-weighted restriction as the default MG restriction operator
- why: "κ-weighting breaks the EXACT conservation of the volume-average, so on the SINGULAR (periodic, constant-nullspace) problem the restricted residual is no longer ⊥ the nullspace ⇒ slower + residual FLOOR"
