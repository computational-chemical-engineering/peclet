# Design decisions — flow

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### "Hand the stopping level to GraphAMG" telescoping idea is retired
- area: flow
- source: mg-decomposition-alignment.md:75
- decided: 2026-09-01
- status: settled
- quote: |
    The "hand the stopping level to GraphAMG" idea is retired — it gathers the operator to every rank
    and solves serially, scaling the wrong quantity.
- rejected: handing the MG-telescoping stopping level to GraphAMG
- why: "it gathers the operator to every rank and solves serially, scaling the wrong quantity"

### "Intrinsic ~1% gap, don't chase it" corrected: collocated IBM is first-order at curved walls, staggered is second-order
- area: flow
- source: sdflow-collocated-solver.md:46-56
- decided: 2026-07-04
- status: superseded
- quote: |
    **KEY FINDING — CORRECTED 2026-07-04 (supersedes the old "intrinsic ~1% gap, don't chase it").** The
    collocated solver is **first-order accurate at curved immersed boundaries; the staggered solver is
    second-order**. Both converge to the SAME Z&H limit. The "~1% gap" seen at N≈32 is *first-order boundary
    error*, NOT a resolution-independent floor — it roughly halves each time N doubles.
- rejected: "the old 'intrinsic ~1% gap, don't chase it'" conclusion
- why: "PROVEN by a staggered-vs-collocated Z&H sphere-drag convergence to N=128... collocated +0.60→+0.40→+0.30% at N=64/96/128 (clean local p≈1.0)"

### "No portable GPU wheel" was a policy choice, not a hard limit — single-GPU CUDA wheels are feasible
- area: flow
- source: peclet-cuda-wheel-feasible.md:10-13
- decided: 2026-07-03
- status: superseded
- quote: |
    DEPLOYMENT.md / the umbrella pyproject say GPU peclet is not pip-installable. That's a **policy choice,
    not a hard limit** — the cited blocker (arch × CUDA × MPI-ABI) really only applies to *multi-GPU MPI*.
    For **single-GPU** the Python module links no MPI, so a pip wheel is just a packaging exercise (like
    `cupy-cuda12x` / PyTorch).
- rejected: the DEPLOYMENT.md / umbrella pyproject claim that GPU peclet cannot be pip-installable
- why: the arch x CUDA x MPI-ABI blocker only applies to multi-GPU MPI builds; a single-GPU module links no MPI

### (1,2) mixed closure order is the recommended default going forward
- area: flow
- source: flow-ghost-projection.md:50
- decided: undated
- status: settled
- quote: |
    **(1,2) MIXED is the recommended default going forward**: quadratic RHS = 2nd-order steady
    constraint on the 7-point near-symmetric linear matrix; operator mismatch converges through time
    stepping (measured ρ(I−A_lin⁻¹A_quad)=0.40; vs binary-M lagging 1.087 = divergent). Z&H: all
    three modes identical drag to 3 decimals, order ~1.9; 7-point variants hold FLAT 7 BiCGStab
    iters N=32..128 (13-point grew 11→16).
- rejected: binary-M lagging (divergent, ρ=1.087) and linear-everywhere (1,1) (worse pointwise near the IB)
- why: "operator mismatch converges through time stepping (measured ρ(I−A_lin⁻¹A_quad)=0.40; vs binary-M lagging 1.087 = divergent)"

### (superseded) fp32-floor-explains-everything hypothesis
- area: flow
- source: vof-campaign.md:366-381
- decided: 2026-08-31
- status: superseded
- quote: |
    - **(superseded) fp32 rival hypothesis, first raised (2026-08-31).**
      `mac_cutcell_mg.hpp:51` `using MReal = float;` — **the MG operator storage is fp32** [...]
      **Consequence: do NOT start S3 coefficient-coarsening work before ruling out the
      fp32 floor — a coarsening fix that ignores a precision floor is a wasted campaign.**
- rejected: superseded by "WO-M FINAL... TWO mechanisms" (float floor is depth-independent; S3 indefiniteness deepens with depth — both real, separated)
- why: none stated at time of the original hypothesis; refuted later by the depth-independence discriminator

### (superseded) precision-vs-indefiniteness verdict corrected — S3 indefiniteness is real and separate from the float-storage floor
- area: flow
- source: vof-campaign.md:346-347
- decided: 2026-08-31
- status: superseded
- quote: |
    - (superseded) earlier verdict: "it is precision, not indefiniteness; S3's evidence is
      contaminated" — half right (the float defect is real) but the S3 conclusion did not survive.
- rejected: "it is precision, not indefiniteness; S3's evidence is contaminated"
- why: "WO-M FINAL 2026-08-31: S3 STANDS — the pivot SURVIVES in double" (from the surrounding ★★★ note)

### 1/2-1/2 constraint truncation exonerated as the plateau cause — a previously-published claim was wrong
- area: flow
- source: collocated-second-order-verdict.md:29-34
- decided: undated
- status: superseded
- quote: |
    - The ½/½ CONSTRAINT truncation (and the embed port's "defect (a)" as the cause): a-priori vs
      exact quadrature, signed net defect 1e-5→1e-6 of through-flux, 3 decades under the bias
      (`flow/tests/study/collocated_constraint_consistency.py`). This claim was in CLAUDE.md/the
      example page and is WRONG as an explanation of the plateau.
- rejected: the ½/½ constraint truncation (embed port's "defect (a)") as the cause of the collocated accuracy plateau
- why: measured signed net defect is 3 decades under the observed bias; the claim had been published in CLAUDE.md/the example page and is wrong

### 2nd order finally resolved by ghost-cell projection FD family, not the full Basilisk embed rewrite
- area: flow
- source: sdflow-collocated-solver.md:10-27
- decided: 2026-07-17
- status: superseded
- quote: |
    **✅ 2ND-ORDER PROBLEM RESOLVED (2026-07-17): the collocated GHOST projection** [...] Fix = `set_ghost_projection(True,1,2)` on SolverColocated:
    staggered ghost closures/matrix verbatim on the face-averaged field + NEW `gpCenterGrad`
    directional cell gradient (central / one-sided 2nd-order, never reads decoupled cells) for the
    predictor AND cell correction. [...] The Basilisk-embed conclusion below
    ("needs one shared FV geometry") is thereby SUPERSEDED — a consistent point-based FD family
    works; embed modes 4–7 remain ablations.
- rejected: the earlier conclusion that a full Basilisk-embed FV rewrite was required
- why: "a consistent point-based FD family works" — defaults stay byte-identical, Z&H order restored

### A masked solid cell is not a fluid sample
- area: flow
- source: sdf-scene-campaign.md:44
- decided: undated
- status: settled
- quote: |
    **a masked solid cell is not a fluid sample** (cost a sign-flipped moving-wall force, §7 item 2).
- rejected: none stated
- why: treating a masked solid cell as a fluid sample "cost a sign-flipped moving-wall force"

---

### API/ordering: x-fastest is fixed; PyVista/VTK [x,y,z] + F-contiguous convention
- area: flow
- source: suite-distributed-status.md:177-184
- decided: undated (commits de16af5, c272046)
- status: settled
- quote: |
    **API/ordering decision** (commits de16af5, c272046): dcfd uses the **PyVista/VTK convention** (the leading
    package): get_u/v/w return 3-D arrays indexed **u[x,y,z]**, shape (nx,ny,nz), **F-contiguous → x fastest in
    memory** (ParaView/VTI-compatible, bytes unchanged). set_* accept 3-D [x,y,z] arrays of any order (read via
    strides). To avoid the ravel('F') footgun for VTI export, added **get_u/v/w_flat()** returning the x-fastest
    1-D buffer directly. (The numpy C-vs-F tension is unavoidable: no convention is both [x,y,z]-indexed AND
    default-ravels-to-x-fastest; PyVista resolves it with [x,y,z]+order='F', which dcfd matches.) User: x-fastest
    is FIXED (non-negotiable, ParaView); dislikes order='F' and [z,y,x].
- rejected: order='F' as the user-facing default and [z,y,x] indexing
- why: x-fastest memory layout is required for ParaView/VTI compatibility (non-negotiable per user)

### Agglomerated redundant coarse solve deferred pending multi-rank hardware
- area: flow
- source: suite-distributed-status.md:296-299
- decided: undated (MG Phase 3)
- status: uncertain
- quote: |
    The agglomerated redundant coarse solve (for large-np scaling) is DEFERRED — its benefit needs
    many-rank/multi-GPU hardware (dev box has 1 GPU; the threshold wouldn't even trigger at np≤4, so it'd
    ship untested).
- rejected: shipping the agglomerated coarse solve untested at np<=4
- why: dev box has 1 GPU; the feature's threshold wouldn't trigger at low np

### Agglomerated/"auto" bottom solve default is gated to the singular (mean-removed) path only, not enabled universally
- area: flow
- source: agglomerated-bottom-ibm-fix.md:45
- decided: 2026-08-14
- status: settled
- quote: |
    **DEFAULT FLIPPED 2026-08-14** (flow 3493a89, umbrella 72c29c2): `set_pressure_bottom` default =
    auto, **gated to the SINGULAR path** (`removeMean_`) — the sweep caught a real regression on the
    Dirichlet-anchored/outflow path (div floor 8e-8 → 2e-5 on a 128×32×32 inflow/outflow channel...).
    Anchored operators keep the smoothed bottom byte-identical...
- rejected: enabling "auto" bottom solve on Dirichlet-anchored/outflow operators
- why: "the sweep caught a real regression on the Dirichlet-anchored/outflow path (div floor 8e-8 → 2e-5 ...); inner solve exact AND CSR consistent ... so NOT the fixed bugs; suspected float round-off"

---

### Agreed IBM velocity-MG coarse-op scheme: volume-fraction Helmholtz, coarse-only solid masking, masked volume-weighted transfers
- area: flow
- source: velocity-mg-design.md:37-52
- decided: undated
- status: superseded
- quote: |
    **The agreed scheme (correction scheme, true residual, NO un-scale):**
    1. **Coarse op = clean volume-fraction Helmholtz `A_θ`** (smoothed momentum balance): θ = fluid volume
       fraction from the SDF (smoothed Heaviside, the volumetric analogue of the pressure path's
       `mg_coarsen_open_avg_k` area openness), coarsened 2:1; face β_f = νΔt·min(θ_i,θ_nbr)/h²; **volume-weighted
       diagonal** AC = θ_i + Σβ_f. Symmetric M-matrix. (Plain Galerkin/rediscretized of A_f is wrong — momentum
       is non-conservative across the IBM boundary.)
    2. **Small cells → solid ONLY on the coarse op** (θ<ε ⇒ identity row). Safe because a misclassified coarse
       cell costs convergence RATE only, never accuracy (the fine A_f smoother + true residual fix it). Do NOT
       ε-mask the fine grid — that's exactly the small-cell job D_rescale already does accurately.
    3. **Masked, volume-weighted transfers** (the diagnosed real bias: unmasked transfers move corrections
       ACROSS the wall, polluting the cut-cell skin). Restrict `Σθ_f r_f / Σθ_f` (fluid-side weighted; an
       extensive boundary FORCE coarsens by fluid volume — this is the "apply the clean stencil to the IBM field
       ⇒ residual = wall force" view); prolong masked (no correction into θ<ε cells).
- rejected: plain Galerkin/rediscretized coarse operator of A_f (non-conservative across the IBM boundary); ε-masking the fine grid; unmasked transfers
- why: "momentum is non-conservative across the IBM boundary" for plain Galerkin; unmasked transfers "move corrections ACROSS the wall, polluting the cut-cell skin"
- conflict: this volume-fraction-weighted coarse op design was later replaced by the STAIRCASE (binary θ≥0.5 classification, no volume-fraction coefficients) as the consolidated default — see "STAIRCASE coarse operator is now the ONLY IBM coarse op" entry below

### Agreement across configurations sharing a floor is not proof of convergence
- area: flow
- source: defect-correction-campaign.md:65-70
- decided: 2026-09-01
- status: settled
- quote: |
    **Cold-start floor (collocated session, 2026-09-01) — CAN INVALIDATE P1:** [...] (b) **agreement across
    configs is NOT convergence when they share a floor** — three R=48 runs agreed to 9 digits while all
    starved. P1's four columns agreeing would have read as GO. Gate 3 now needs cold AND warm legs.
- rejected: treating cross-config agreement alone as sufficient evidence of convergence
- why: "three R=48 runs agreed to 9 digits while all starved"

---

### All level-0 partitioning must go through one shared factory; never hand-build a BlockDecomposer for the solver
- area: flow
- source: mg-decomposition-alignment.md:56
- decided: undated
- status: settled
- quote: |
    - The three level-0 partition call sites (`mpi_block`, `IbmSolver::initMpi`, `CutcellMG::initMpi`)
      now share ONE factory `CutcellMG::decomposition()`. Never hand-build a `BlockDecomposer` for the
      solver; they must agree or the block layout diverges silently.
- rejected: hand-building a separate BlockDecomposer at any of the three call sites
- why: "they must agree or the block layout diverges silently"

### Allreduce diet: fuse mean-removal sum+count; 'fine' mean-removal scope as bench/pack default, 'all' stays solver default pending Snellius validation
- area: flow
- source: parallel-scaling-study.md:81-86
- decided: 2026-08-08
- status: settled
- quote: |
    (3) ALLREDUCE DIET:
    mean-removal {sum,count} fused to ONE allreduce (bit-identical, always on) +
    set_pressure_mean_removal('fine') drops interior-level/post-matvec projections → 17.6→5.4
    allreduces/Krylov-iter, iters EXACTLY unchanged (7.5==7.5), KE digit-identical; 'all' stays solver
    default until Snellius validates; bench driver + snellius pack default MEANSCOPE=fine.
- rejected: none stated (interim state, not yet finalized)
- why: fusing sum+count is bit-identical; 'fine' scope needs Snellius validation before becoming the solver default

### Anisotropic MG coarsening order: coarsen axis a iff H_a < 2·min H over coarsenable axes, engaged only under `aniso`
- area: flow
- source: physical-units-phase2-aniso.md:47-51
- decided: 2026-09-06/07
- status: settled
- quote: |
    **Decisions taken (do not reopen):**
    - ⚑A coarsening order (both MGs, one helper `mgChooseRatio`): coarsen axis a iff coarsenable and
      `H_a < 2 * min H` over the coarsenable axes, `H_a = h_a' cfac_a`; ENGAGED ONLY WHEN `aniso` (the
      isotropic table, incl. after telescoping, stays today's — a lagging unblocked axis would otherwise
      change bits at extent=None).
- rejected: applying the anisotropic coarsening rule to the isotropic path (would change isotropic bits)
- why: "a lagging unblocked axis would otherwise change bits at extent=None"

### Anisotropic wall-gradient normal/foot-point convention (⚑B)
- area: flow
- source: physical-units-phase2-aniso.md:52-54
- decided: 2026-09-06/07
- status: settled
- quote: |
    - ⚑B normal: `n_a = (g_a/h_a')/|g/h'|` (physical), `m_a = n_a/h_a'` (index direction); foot point
      `xi - d' m`; image distances physical; dominant axis by |m|; fragment area `sqrt(sum W_a^2 w_a)`;
      slip `s*lambda'/(h_a'|n_a|)`; `ibmVolfrac` = `0.5 + d'|m|` under aniso only.
- rejected: none stated
- why: none stated

### Aperture weighting (A1) is not indicated as a fix for the confined finite-Re deficit
- area: flow
- source: advective-cutwall-flux-plan.md:26
- decided: 2026-08-31
- status: superseded
- quote: |
    **ten-cate did NOT recover** (E1 `0.781/0.777/0.749 → 0.803/0.797/0.766` vs 0.947; E3/E4 still
    above u∞) ⇒ the confined finite-Re deficit is NOT the advective cut-wall flux, and **A1 (aperture
    weighting / D2) is NOT indicated** — nothing in the remaining symptoms implicates it.
- rejected: A1 (aperture weighting / D2) as the fix for the ten-cate deficit
- why: "nothing in the remaining symptoms implicates it"
- conflict: this conclusion is itself later reframed as moot once advective-cutwall-flux-plan.md:49 finds the true (geometric) cause — A1 remains correctly not-indicated, but for a different final reason.

### Area fractions (proper face α, not min(θ)) extend the stable dt ceiling for the (now-removed) area-fraction coarse op
- area: flow
- source: velocity-mg-design.md:118-124
- decided: 2026-06-17
- status: superseded
- quote: |
    Replaced the `min(θ)` face coefficient with proper **AREA fractions** (`ibm_areafrac_k`: α=clamp(0.5+ψ_face,0,1)
    at each control-volume −face; coarsened by averaging via the pressure path's `mg_coarsen_open_avg_k`;
    `mg_build_velocity_op_areafrac_k`: diagonal 1+Σβ_f, β_f=νΔt·α_f/h², θ for the ε-solid test). Mirrors the proven
    rediscretized PRESSURE MG. **Result: extends the stable dt ceiling** — area-frac+exclude is exact & stable to
    **dt=400 at φ=0.216** (was dt=200 with min(θ)); φ=0.5236 stays dt=200. Kept (genuine improvement).
- rejected: min(θ) as the coarse-op face coefficient
- why: measured to extend stable dt ceiling to 400 (from 200)
- conflict: this area-fraction operator was itself removed in the later "staircase is the ONLY IBM coarse op" consolidation

### Body-force ghost policy: Neumann copy, pinned to ρ's policy
- area: flow
- source: vof-campaign.md:145-154
- decided: 2026-08-30
- status: settled
- quote: |
    Ghost policy chosen = Neumann copy, same
      as ρ, because `buildRhsVar` face-averages force and ρ with the SAME mean and the physical
      content is f_f/ρ_f — pin the force's policy to ρ's or the ratio breaks at the boundary.
- rejected: none stated (implicitly, any policy not matching ρ's)
- why: "buildRhsVar face-averages force and ρ with the SAME mean and the physical content is f_f/ρ_f — pin the force's policy to ρ's or the ratio breaks at the boundary"

### Boiling scope addition did not resurrect transported-φ CLSVOF
- area: flow
- source: vof-campaign.md:101-106
- decided: 2026-08-30
- status: settled
- quote: |
    Phase change = Part II of the plan (interfacial ṁ, velocity
      jump/divergence source in the projection, T_sat interface condition); strengthens the band-RDF
      investment (normal-probe gradients). Boiling did NOT resurrect transported-φ CLSVOF pending
      the Part II literature check.
- rejected: transported-φ CLSVOF
- why: none stated (pending Part II literature check)

### Byte-identical gating is unmeasurable for atomic-add paths — gate against the path's own run-to-run spread instead
- area: flow
- source: defect-correction-campaign.md:55-57
- decided: 2026-09-02
- status: settled
- quote: |
    **TRAP — mode B is not bit-reproducible against itself:** `starApplyDelta` uses Kokkos::atomic_add
    (star_elimination.hpp:155,163), so 3 runs of one CUDA binary give 3 states (spread 1.1e-16). A
    "byte-identical" gate is UNMEASURABLE there; gate against the path's own run-to-run spread.
- rejected: a byte-identical regression gate for atomic-add code paths
- why: "3 runs of one CUDA binary give 3 states"

### CA (event-halving) smoothing ships default ON with an env kill switch
- area: flow
- source: comm-scaling-plan.md:23
- decided: undated
- status: settled
- quote: |
    3. **CA smoothing (2.3)** — DONE, flow **b96dd74**: one 2-deep exchange per RB pair, first colour
       redundantly re-smooths the 1-deep ghost ring, second colour needs NO exchange. Env
       `PECLET_FLOW_CA` (default ON, =0 kill switch); engages only where every rank's block extent ≥ 4
       AND the operator is periodic/IBM.
- rejected: none stated
- why: measured 35%→62% weak efficiency gain, "almost entirely 2.3's event halving"

### CSF force is exact; curvature error is the real budget — improve κ, never the force
- area: flow
- source: vof-campaign.md:430-444
- decided: 2026-08-30
- status: settled
- quote: |
    `F_c = σ·κ_f·(C(i)−C(i−s_c))/h` added by a sibling `addCsfRhs` using **the projection's own
      face difference**. **Loud gate: stationary droplet max|u| = 1.93e-17, spurious Ca 1.9e-18**;
      the ablation `set_csf_mode(1)` (arithmetic cell-force interpolation) gives 5.76e-02 /
      Ca 5.8e-03 = **3.0e+15× worse**. [...] **★ Ca ≲ 1e-7 IS NOT REACHABLE, structurally**: with
      EXACT κ the force gives 1.9e-18, so the force is exact [...] **Ca ≈ δκ·h ⇒ the budget is a
      CURVATURE requirement** [...] Improve κ (V5 RDF, ELVIRA/LVIRA on 5³), never the force.
- rejected: arithmetic cell-force interpolation (set_csf_mode(1)); improving the force term to chase lower Ca
- why: "the force is exact" once κ is exact; "the budget is a CURVATURE requirement"

### CUDA wheel dependency name: nvidia-cuda-runtime, not the deprecated -cu13 suffix
- area: flow
- source: peclet-cuda-wheel-feasible.md:28-30
- decided: 2026-07-04
- status: settled
- quote: |
    - `flow/packaging/pyproject-cuda.toml`: name `peclet-flow-cu13`, dep **`nvidia-cuda-runtime`** (NOT
      `-cu13` — NVIDIA dropped the `-cuXX` suffix at CUDA 13; the `-cu13` pkg is a deprecated placeholder;
      real one is 13.3.29, lays libcudart.so.13 at site-packages/nvidia/cu13/lib).
- rejected: depending on the `nvidia-cuda-runtime-cu13` package name
- why: NVIDIA dropped the -cuXX suffix at CUDA 13; that package name is now a deprecated placeholder

---

### Cell-average IBM scheme, not point-value, for Poiseuille validation
- area: flow
- source: cuda-kokkos-migration.md:285-287
- decided: undated
- status: settled
- quote: |
    CRITICAL: use the CELL-AVERAGE scheme
    (ibmFillEntry<1>); point-value <0> is ~10% off at this resolution.
- rejected: point-value scheme (ibmFillEntry<0>)
- why: "point-value <0> is ~10% off at this resolution"

### Channel DNS IC must seed streamwise rolls/streaks in wall units, not cold random noise
- area: flow
- source: channel-dns-isotropic-grid.md:46
- decided: 2026-08-05
- status: settled
- quote: |
    **PRODUCTION LAMINARIZED → TRANSITION FIX (2026-08-05, peclet-examples 9b1c86b):** ... the cold random-noise
    IC failed to trigger the self-sustaining cycle at low Re_tau=180 ... FIX (channel_dns_mpi.py): IC now seeds
    streamwise ROLLS+STREAKS at spanwise wavelength ~110 wall units, perturbation scales in WALL UNITS
    (resolution-independent; old lp() cutoff was cycles/CELL → shrank into viscous range at fine dx).
- rejected: cold random-noise initial condition; perturbation cutoff specified in cycles/cell
- why: "the cold random-noise IC failed to trigger the self-sustaining cycle at low Re_tau=180"; cycles/cell cutoff "shrank into viscous range at fine dx"

### Chebyshev pressure driver's apparent win was a placement artifact, not a real gain
- area: flow
- source: momentum-solve-residual-stop.md:39
- decided: undated
- status: settled
- quote: |
    at 1536 ranks node placement moves the SAME config by 1.5x (single 0.391 vs
    0.256 s) — every top-rung A/B needs a same-allocation control; the Chebyshev pressure driver
    looked like a 36 % win until the control showed parity (and 5x LOSS on the cut-cell bed, 238 vs
    40 iterations).
- rejected: adopting the Chebyshev pressure driver based on the uncontrolled 36% win
- why: "the control showed parity (and 5x LOSS on the cut-cell bed, 238 vs 40 iterations)"

---

### Clean-fluid-interior mask required on both restriction and prolongation for IBM velocity-MG correctness
- area: flow
- source: velocity-mg-design.md:54-64
- decided: 2026-06-16
- status: settled
- quote: |
    ## SOLVED (2026-06-16) — clean-fluid-interior coarse coupling makes the IBM velocity-MG exact + stiff-stable
    Volume-fraction coarse op (`mg_build_velocity_volfrac_op_k`, diagonal **1+Σβ_f**, NOT θ-weighted — θ-weighting
    the I term shrinks the diagonal vs the fine As_[c] O(1) diagonal → overshoot; the backward-Euler op is a POINT
    eq, only the diffusion flux sees θ: β_f=νΔt·min(θ_i,θ_nbr)/h²). The KEY FIX (Frank's diagnosis of the logical
    error): the coarse grid must couple ONLY where its clean operator matches the fine one. So a
    **clean-fluid-interior mask** (`ibm_clean_fluid_mask_k`: 1 only at fluid cells with no solid neighbour; 0 at
    IBM cut cells AND solid cells) is applied to BOTH the restriction (zero the residual there: `mg_mul_mask_k`
    on `lv.res_mask` before restrict) AND the prolongation (`mg_prolong_masked_k`, no correction INTO those cells).
    The fine IBM RB-GS smoother owns the cut-cell band + the stiff 1+6β solid interior; the coarse grid solves the
    clean interior.
- rejected: θ-weighting the diagonal's identity (I) term; coupling the coarse grid at cut/solid cells (masking cut cells only, not solid cells, was tried and still failed — see below)
- why: "θ-weighting the I term shrinks the diagonal vs the fine As_[c] O(1) diagonal → overshoot"; "the coarse grid must couple ONLY where its clean operator matches the fine one"

### Coarse-first decomposition ships opt-in, legacy remains the default
- area: flow
- source: mg-decomposition-alignment.md:22
- decided: 2026-08-11
- status: settled
- quote: |
    **Shipped 2026-08-11 (core c98964a, flow 7e0a3b1, umbrella 8ec5f39, all pushed):** coarse-first
    decomposition, OPT-IN (`flow.set_decomposition_levels(L)` / `PECLET_FLOW_DECOMP_LEVELS`, 0 =
    legacy default).
- rejected: making coarse-first decomposition the default
- why: none stated beyond shipping it opt-in

### Coarse-level solve policy default stays "smoother", not "auto", because auto regresses the cut-cell IBM path
- area: flow
- source: mg-decomposition-alignment.md:28
- decided: 2026-08-11
- status: settled
- quote: |
    coarse-level solve policy `set_pressure_bottom("smoother"|"auto"|"agglomerated")` + `BOTTOM` env
    in the channel driver. **DEFAULT STAYS "smoother"** — `auto` makes the cut-cell `random_spheres`
    N=48 regression WORSE (442→622 iters, +41 %, accuracy bit-identical). An exact coarse solve cannot
    legitimately do that ⇒ the assembled coarse operator is inconsistent with the V-cycle's on the IBM
    path. **That is now open problem #3 and it BLOCKS making auto the default.**
- rejected: making "auto" the default coarse-level solve policy
- why: "auto makes the cut-cell random_spheres N=48 regression WORSE (442→622 iters, +41%, accuracy bit-identical)"

### Collocated pressure coupling is the ABC (MAC) approximate projection, NOT Rhie–Chow
- area: flow
- source: sdflow-collocated-solver.md:37-39
- decided: undated (2026-06-22 build)
- status: settled
- quote: |
    The collocated pressure coupling is the **Almgren–Bell–Colella
    approximate (MAC) projection** (NOT Rhie–Chow): average cell→face (`centerToFace`), make the *face* field
    divergence-free with the SAME `CutcellMG`, then correct cell velocities with a (now openness-aware)
    cell-pressure gradient (`projectCorrectCenter`).
- rejected: Rhie–Chow interpolation as the collocated coupling
- why: none stated (states what it is, not why it isn't R-C)

### Container slab half-extent must equal L/2 + wall thickness, never more (periodic-image rule)
- area: flow
- source: advective-cutwall-flux-plan.md:57
- decided: 2026-09-02
- status: settled
- quote: |
    RULE: container slab half-extent = L/2 + wall thickness, never more.
- rejected: an oversized slab half-extent
- why: an oversized slab lets its periodic images refill the cavity (see the ten-cate root cause above)

### Correction/supersession: plan §9.3 U5 was wrong about VoF spacing
- area: flow
- source: physical-units-plan.md:32
- decided: 2026-09-06
- status: superseded
- quote: |
    2. **The plan's §9.3 U5 is wrong about the VoF spacing.** Under representation (B) the advector runs on
       the unit lattice and `v*dt'` IS `u*dt/h`; passing hRef converts twice. The `1.0`s stay; sigma, kappa
       and every TIME convert at the boundary instead.
- rejected: superseded claim = "§9.3 U5" (passing hRef to convert v*dt' under representation B)
- why: "the advector runs on the unit lattice and v*dt' IS u*dt/h; passing hRef converts twice"

### Correction: the raw field registry hands out internal (unconverted) arrays
- area: flow
- source: physical-units-plan.md:28
- decided: 2026-09-06
- status: settled
- quote: |
    1. **The RAW field registry (`field_view`/`get_field`/`set_field`) hands out INTERNAL arrays**, while
       `get_u`/`get_p` convert. Any driver writing `force_x`/`drag_beta` directly must scale — that is what
       `s.unit_scales` (a dict, `identity` True in cell units) exists for
- rejected: none stated
- why: none stated (documents an internal-vs-converted API split that must be respected)

### Correction: §9.3 U3's setter list was incomplete, causing silent physical errors
- area: flow
- source: physical-units-plan.md:35
- decided: 2026-09-06
- status: superseded
- quote: |
    3. **§9.3 U3's setter list was short by four** — `set_property_model` on rho/mu (the documented
       two-phase spelling), `enable_vof_momentum`, `set_vof_kappa_constant`,
       `set_phase_change_fit_curvature`. Missing them made a two-phase physical run silently wrong by
       `lam^3` in density and `lam^1.5` in the capillary dt.
- rejected: superseded claim = the original (short) §9.3 U3 setter list
- why: "Missing them made a two-phase physical run silently wrong by lam^3 in density and lam^1.5 in the capillary dt"

### Coupling partial/cut+solid cells to the coarse grid fails regardless of coarsening depth — capping depth cannot fix it
- area: flow
- source: velocity-mg-design.md:118-135
- decided: 2026-06-17
- status: settled
- quote: |
    **Couple-partial-cells (drop the exclude mask) — FAILS, and the cap does NOT rescue it (measured):** coupling
    the partial/cut+solid cells to the coarse grid **diverges at dt=200 even with a SINGLE coarsening level (L=2)**.
    So the overshoot is at the very first coarse correction into the row-scaled IBM cut/solid cells, **independent of
    coarsening depth ⇒ a pore-scale cap cannot enable coupling** (capping depth is at best a minor compute saving
    when the exclude mask is already on). The clean-fluid **exclude mask stays REQUIRED + default** (`res_mask=true`).
    **Corrected lever for coupling = Brinkman/Darcy, NOT capping:** coupling overshoots because the clean coarse op
    (even with area fractions) lacks the WALL DRAG the fine IBM imposes on partial cells → no resistance → overshoot.
    A Brinkman drag `−μ/k·u` on partial coarse cells (k from the local geometry) is the physically-motivated way to
    make the coarse op resist like the fine one — the only remaining route to coupling, but speculative (needs a
    permeability model) and unproven.
- rejected: capping coarsening depth as a fix for partial-cell coupling divergence
- why: "the overshoot is at the very first coarse correction into the row-scaled IBM cut/solid cells, independent of coarsening depth"

### Crank-Nicolson ported then reverted; backward-Euler is the right default
- area: flow
- source: suite-distributed-status.md:320-324
- decided: undated
- status: settled
- quote: |
    **Crank-Nicolson: ported then REVERTED** — the
    simple explicit Laplacian is inconsistent with the Robust-Scaled cut-cell IBM (θ=0.5 gave 4% θ-dependent
    *steady* error, a bug); correct CN needs the cut-cell operator in the explicit half (research); no
    steady benefit anyway → backward-Euler is the right default.
- rejected: Crank-Nicolson (θ=0.5) time integration with the plain explicit Laplacian
- why: inconsistent with the Robust-Scaled cut-cell IBM, causing a 4% θ-dependent steady-state error

### Cut-cell C convention: liquid fraction of fluid volume, openness-weighted
- area: flow
- source: vof-campaign.md:98-100
- decided: 2026-08-30
- status: settled
- quote: |
    Cut-cell C convention APPROVED: C = liquid fraction of the *fluid* volume, openness-weighted
      fluxes.
- rejected: none stated
- why: none stated

### Defect-correction proposal: float hierarchy demoted to pure preconditioner, evaluate before double-diagonal
- area: flow
- source: vof-campaign.md:293-306
- decided: 2026-09-01
- status: superseded
- quote: |
    **★★ USER PROPOSAL 2026-09-01 — DEFECT CORRECTION, evaluate BEFORE the double-diagonal.**
      `r = b − A_exact·x` in double, **matrix-free as `r(x)`**; float operator only solves the
      correction `A_float·dx = −(float)r`, `x ← x + (double)dx`. This demotes the float hierarchy
      to a **pure preconditioner** — its errors then affect only the convergence RATE, never the
      fixed point — so `A·1 = 0` breaking inside it becomes IRRELEVANT and the double-diagonal
      becomes unnecessary rather than merely cheaper.
- rejected: shipping the double-diagonal as the fix
- why: "its errors then affect only the convergence RATE, never the fixed point"
- conflict: defect-correction-campaign.md (P1 result formally retires the double-diagonal fallback, confirming this proposal's direction won)

### Deferred correction is not viable as an undamped fallback
- area: flow
- source: flow-ghost-projection.md:29
- decided: undated
- status: settled
- quote: |
    Deferred correction is NOT a viable fallback undamped: measured iteration rate max|1−λ| = 1.087.
- rejected: undamped deferred correction as the C/F / ghost solve fallback
- why: "measured iteration rate max|1−λ| = 1.087" (divergent)

### Design constraints for any collocated-plateau fix
- area: flow
- source: collocated-second-order-verdict.md:51-55
- decided: undated
- status: settled
- quote: |
    **Design constraints for any fix (Frank)**: C1 cells=conserved quantities, faces=volume flux,
    flux = volume-flux × face-interpolated quantity; C2 dt-INDEPENDENT steady states (bars
    Basilisk's dt·a face event AND both embed-note salvages); C3 AMR 2:1 faces; C4 no fragmenting
    graphs, keep CG.
- rejected: Basilisk's dt·a face event and both embed-note salvage approaches (ruled out by C2); any fix that fragments the CG graph (ruled out by C4)
- why: C2 requires dt-independent steady states; C4 requires keeping a non-fragmenting graph compatible with CG

### Distributed cut-cell MG coarse levels must be nested, not independently re-decomposed
- area: flow
- source: channel-dns-isotropic-grid.md:52 (line ~740 in original combined read; per-file line 52 of the "ROOT CAUSE FOUND" bullet)
- decided: 2026-07-31
- status: settled
- quote: |
    **ROOT CAUSE FOUND (2026-07-31): distributed cut-cell MG coarse levels are NOT nested.** `CutcellMG::initMpi`
    (flow/src/mac_cutcell_mg.hpp:228) decomposes EACH MG level with an INDEPENDENT `BlockDecomposer` ORB of
    that level's coarsened global grid (:246) — vs single-rank `init` (:170) which halves in place (nested).
    Independent ORBs don't align across levels ... so `restrictAvg`/`prolongAdd` — which assume coarse-local i
    ↔ fine-local ratio·i — read across the misaligned block boundary → OOB. ... FIX DESIGN: nested coarse
    decomposition — (1) core BlockDecomposer: add split-alignment ... + `coarsened(ratio)` (copy tree w/
    splitValue,origins,sizes scaled by 1/ratio; preserves leaf/rank order); (2) mac_cutcell_mg initMpi: level
    L+1 decomp = level L `.coarsened(ratio)` not independent ORB.
- rejected: independent per-level BlockDecomposer ORB for MG coarse levels
- why: "Independent ORBs don't align across levels ... read across the misaligned block boundary → OOB"

### DistributedNS declared canonical; clean API; periodic BCs only; MPI a true build option
- area: flow
- source: suite-distributed-status.md:247-251
- decided: 2026-06-09
- status: settled
- quote: |
    cfd-gpu shipped TWO implementations of the same
    cut-cell IBM NS physics: production `pnm_backend` (`cfd_solver*.cu`, in-kernel `get_idx` wrap, rich
    `CFDSolver` API) and the extended-block `DistributedNS`/`dcfd`. User wants ONE best code + ONE API + MPI
    optional. **Decided (user): `DistributedNS` is canonical; clean new API (no pnm_backend compat); periodic
    BCs only (future BCs via the cut-cell IBM `u_bc`, not a halo-BC system); MPI a true build option.**
- rejected: keeping pnm_backend API compatibility; a halo-BC system for future boundary conditions
- why: user wants one best code, one API, MPI optional

### DistributedNS solves in physical units (ρ, dynamic μ, force/volume), not kinematic ν
- area: flow
- source: sdflow-dt-divided-convention.md:46-59
- decided: 2026-06
- status: settled
- quote: |
    (2) **DistributedNS now solves in PHYSICAL units** (was kinematic, rho≡1). `init` signature changed to
    `init(res, rank, size, rho, mu, dt, comm)` — density + DYNAMIC viscosity (was a single `nu`). [...] The
    stored variable `p_` is the **physical pressure p** (not a potential, not kinematic) [...] It's an exact
    rescaling (×rho) of the kinematic system -> velocity invariant, physical pressure unchanged
- rejected: the kinematic (ρ≡1, single-ν) formulation as the solved system
- why: none stated beyond the unit-system change itself; validated as an exact rescaling

### DistributedStokes renamed to DistributedNS
- area: flow
- source: suite-distributed-status.md:14-18
- decided: 2026-06-08
- status: settled
- quote: |
    **RENAME (2026-06-08):** cfd-gpu's `DistributedStokes` is now **`DistributedNS`** (it's a full NS
    solver). Everywhere below `DistributedStokes`→`DistributedNS`, `dstokes`→`dns`,
    `src/distributed_stokes.cuh`→`src/distributed_ns.cuh`, `tests/test_distributed_stokes.cu`→
    `test_distributed_ns.cu`.
- rejected: none stated
- why: it's a full NS solver, not just Stokes

### Divergence in mixed-order ghost projection (GPORDER 1,2) is caused by the incremental-rotational pressure accumulation, not the linear solve
- area: flow
- source: ghost-hardening-plan.md:50-59
- decided: 2026-08-17
- status: settled
- quote: |
    **LOCAL FAILING CASE (the phase-B/C testbed)**: `GPORDER=1,2` (matrix_order=1, rhs_order=2 —
    the mixed mode the plan wanted to build C on) DIVERGES on s116, k → 4.5e77, ×1.62/step,
    threshold between 1956 and 7823 spheres and RESOLUTION-INDEPENDENT... Mechanism nailed: trajectory
    identical to 5 digits at PRTOL 1e-4 vs 1e-12 (not the linear solve), growth monotone in
    `set_pressure_underrelax(ω_p)` (stabilises R=3 outright; at R=5 only slows it — a damper, not
    a cure), and 10× smaller dt makes it WORSE ⇒ amplifier = the incremental-rotational
    accumulation `P += (ρ/dt)φ`.
- rejected: attributing the (1,2) divergence to the linear solve tolerance or resolution
- why: trajectory is identical across PRTOL settings (rules out the linear solve); divergence worsens with smaller dt, pointing to the incremental-rotational accumulation as the amplifier

### Divergence uses flux openness (beta); MG uses operator openness (alpha)
- area: flow
- source: cuda-kokkos-migration.md:325-327
- decided: undated (channel WIP session)
- status: settled
- quote: |
    THREE open-BC
    bugs found: (1) FIXED flux-vs-operator openness -- divergence uses FLUX beta (inflow-with-nonzero-normal-vel +
    outflow OPEN; walls + tangential-Dirichlet/lid CLOSED), MG uses OPERATOR alpha (inflow Neumann via setBC); (2)
- rejected: using the same openness definition for both divergence and MG operator
- why: none stated beyond the bug description; the fix separated the two openness definitions

### Do not make the preconditioner rho-aware — harmful, and no compatibility floor exists in practice
- area: flow
- source: ghost-hardening-plan.md:26-37
- decided: 2026-08-17
- status: settled
- quote: |
    - **H1 refuted 3×**: GP_THETA_MIN (1e-4) NEVER fires on any bed (min rho 1e-3); max|w| ≤ 971
      and rho*w is O(1); the worst rows sit at grid/surface INCIDENCE coincidences...
    - **Preconditioner is fine**: spec(M⁻¹A) |λ|min 0.32, λmax 2.15, spread 6.7 on a real bed.
      Making the preconditioner rho-aware is HARMFUL (split radius 1.15 → 15.4). Don't.
    - **No compatibility floor in practice**: rtol sweep 1e-4→1e-10 gives 56→137 iters (linear in
      log rtol) — the solve converges, nothing burns on the stagnation guard.
- rejected: making the preconditioner rho-aware; the H1 hypothesis that GP_THETA_MIN fires and causes the trouble
- why: rho-aware preconditioning measured to worsen the split radius (1.15→15.4); GP_THETA_MIN never fires on any tested bed

### Domain-BC all-fluid velocity must use double diffSmoothColor, not float IBM stencil
- area: flow
- source: cuda-kokkos-migration.md:318-320
- decided: undated (Session-2, 2026-06-19)
- status: settled
- quote: |
    (b) domain-BC all-fluid velocity MUST use the DOUBLE
    diffSmoothColor(+dcorr) (= CUDA diff_k), NOT the float IBM stencil (float gave only 1.5e-7);
- rejected: float IBM stencil for domain-BC all-fluid velocity
- why: "float gave only 1.5e-7" (double needed for accuracy)

### Domain-BC paths stay blocking, following the VelocityMG precedent
- area: flow
- source: comm-scaling-plan.md:22
- decided: undated
- status: settled
- quote: |
    Domain-BC paths stay blocking (VelocityMG precedent).
- rejected: applying halo-compute overlap to domain-BC paths
- why: "VelocityMG precedent" (no further reason stated)

### Drag must be included in bcStencilPath() whenever advection is off
- area: flow
- source: porous-cfddem-cuda-two-bugs.md:14
- decided: undated
- status: settled
- quote: |
    **Drag never in the momentum operator on the all-fluid domain-BC path**: with `advect_=false` (default; the fluidized-bed example never enables advection) and no immersed solid, `bcStencilPath()` was false → `smoothComp` used the CONST-COEFFICIENT fold smoother (`Ac=ρ/dt+6μ` inline) → the drag-loaded band from `rebuildStencils`+`addDragDiagonal` was built every step and never read. [...] Fixed: `bcStencilPath()` includes `hasDrag_`.
- rejected: none stated
- why: "pressure-loop gain = β·dt/ρ (measured 3.84 vs predicted 3.85 — diverges whenever β > ρ/dt)"

### E2 resolved: the aspect coarsening rule alone fixes MG-PCG stall on stretched grids — no auto-FCG/symmetric-V-cycle decision needed
- area: flow
- source: physical-units-phase2-aniso.md:28-31
- decided: 2026-09-07
- status: settled
- quote: |
    C3 LANDED (flow 6cf870b, umbrella cd50c56): E2 RESOLVED by the rule alone — stretched MG-PCG 500-cap
    → 10 (cubic 9-10), pr 0.356 → 0.068 (isotropic ~0.06), level table (1,2,1)(2,2,1)(2,2,2)…; new
    ctest cutcellmg_aniso_mpi (106 MPI tests).
- rejected: needing a separate symmetric-V-cycle-under-aniso or auto-FCG-on-aniso decision
- why: the aspect coarsening rule alone resolved the stall (measured pr 0.356→0.068)

### E3 decided: v3 wall-torque uses the area factor V'/h_b', not h_a'V', correcting the design note's §4.4
- area: flow
- source: physical-units-phase2-aniso.md:34-37
- decided: 2026-09-07
- status: superseded
- quote: |
    E3 DECIDED: the v3 wall-torque traction takes the AREA factor V'/h_b' on the area component
    (F' = mu' A'×Omega'), NOT h_a'V' on the force component — the note's §4.4 sentence was wrong;
    C4b implements it, C5 = docs (flow/CLAUDE.md + umbrella CONVENTIONS §7, PLAN §9.4/§9.8).
- rejected: h_a'V' on the force component (the design note's §4.4 as originally written)
- why: "the note's §4.4 sentence was wrong"

### Earlier "+13-83% above 2024" deviation was a normalization error, not a real discrepancy
- area: flow
- source: ibm-accuracy-sphere-validation.md:79-81
- decided: undated
- status: superseded
- quote: |
    **The "+13–83% above 2024" I reported earlier this session was a NORMALIZATION ERROR**
    (equated raw K with superficial F̄_D, dropped the (1−φ)); raw-K/F̄_D
    tracks 1/(1−φ) exactly (1.26/1.54/1.83 vs 1.25/1.67/2.0). `resconv_vs2024.py` reinterpreted: raw K=5.48 →
    (1−φ)K=4.38 vs 4.67 = −6% (consistent).
- rejected: the earlier "+13-83% above 2024" claim
- why: raw K was equated with superficial F_D, dropping the (1-phi) factor

### Earlier "slow convergence / non-converged" worry was a multiplied-dt float-precision artifact, fixed by the divided-dt engine convention
- area: flow
- source: ringbed-cfd-surrogate.md:63
- decided: 2026-06-18
- status: settled
- quote: |
    The earlier "slow convergence/+19%/non-converged" worry was the OLD multiplied-`dt` float-precision
    artifact at large dt — the divided-`dt` engine ([[sdflow-dt-divided-convention]],
    [[ibm-accuracy-sphere-validation]]) fixed it: grid-convergence is now monotone, order 1.25,
    k_inf=1.195e-3, only **1.4% residual at 14.8 cells/wall**...
- rejected: the multiplied-dt momentum-operator convention
- why: divided-dt fixes the float-precision artifact and restores monotone grid convergence

### Embed momentum + mode-3 projection (mode 5) does not converge — over-drags
- area: flow
- source: embed-port-progress.md:23
- decided: undated
- status: settled
- quote: |
    - mode 5 (embed + mode-3 projection): plateaus ~+0.7%, does NOT converge — mode-3 projection over-drags.
- rejected: mode 5 (embed momentum + mode-3 projection) as a viable configuration
- why: "does NOT converge — mode-3 projection over-drags"

### Escalation rule: a twice-failed gate stops the work order, never gets its numerics tweaked to pass
- area: flow
- source: vof-campaign.md:495-496
- decided: 2026-08-30
- status: settled
- quote: |
    Escalation rule: twice-failed gate = stop + findings log, never tweak
      numerics to pass.
- rejected: tweaking numerics to force a failing gate to pass
- why: none stated

### Exact-crossing openness overrides must be masked to 0 at solid velocity points
- area: flow
- source: flow-ghost-projection.md:61
- decided: undated
- status: settled
- quote: |
    `set_openness_override` (exact apertures,
    MUST be masked to 0 where the face velocity point is solid — the flux DOF is pinned there;
    unmasked exact apertures broke the projected divergence at 1.9e-3).
- rejected: unmasked exact apertures at solid-velocity-point faces
- why: "unmasked exact apertures broke the projected divergence at 1.9e-3"

### FV viscous operator confirmed 2nd-order-consistent — "face-flux placement" hypothesis refuted; barrier is the pressure coupling
- area: flow
- source: sdflow-collocated-solver.md:152-166
- decided: 2026-07-05
- status: settled
- quote: |
    A-priori truncation test [...] proves the FV VISCOUS OPERATOR is clean
    O(h²) (order 1.98-2.00, N=32→128). So the face-centre two-point flux IS 2nd-order-consistent (Basilisk
    right); the "face-flux placement" hypothesis is REFUTED. [...] Tried the spec's wall pressure term
    −p_i·W_c on the momentum force [...] dissipative sign is stable but WORSE (N32 +0.81→+1.04%), opposite
    sign diverges — NOT the fix.
- rejected: the "face-flux placement" hypothesis; the wall-pressure-term-on-momentum-force fix (both signs)
- why: "the FV VISCOUS OPERATOR is clean O(h²)"

### Face-primary uf reconstruction (mode 8) attempted and reverted — incompatible with flow's divided time convention
- area: flow
- source: embed-port-progress.md:33
- decided: undated
- status: settled
- quote: |
    **Face-primary uf attempted (mode 8) and FAILED — reverted.** Basilisk centered.h fix = acceleration event uf=fs*(face_avg(u)+dt*a) so the cut-cell body-force flux o*dt*a enters div(o*uf) as a source. But Basilisk's explicit u+=dt*(a-grad p) correction needs its (I-dt*mu*Lap) convention; flow uses the DIVIDED convention (rho/dt*cs - mu*Lap_embed), whose implicit viscous barely dissipates at large dt → explicit dt*a body force runs away → -75% drag at N=32. **Closing p=2 needs switching the momentum step to the undivided time convention (solver-wide) OR an implicit face-flux body-force source.** NOT clean p=2; mode 0 / Solver remain production.
- rejected: mode 8 (face-primary uf via Basilisk's acceleration-event reconstruction) under flow's current divided momentum-operator convention
- why: flow's divided convention's implicit viscous "barely dissipates at large dt", so the explicit dt*a body force term "runs away → -75% drag at N=32"; production stays mode 0 / Solver

### Falling-drop gate: WO-K's under-resolved-momentum-solve suspicion is refuted
- area: flow
- source: vof-campaign.md:459-464
- decided: 2026-08-31
- status: superseded
- quote: |
    **Falling drop (WO-K's deferred gate): the GATE measured the wrong quantity.** [...]
      **WO-K's suspected under-resolved momentum solve is REFUTED** (60→2649 sweeps swings
      lab-frame 5.7× but relative velocity stays 0.826/0.828/0.828).
- rejected: "WO-K's suspected under-resolved momentum solve"
- why: "A periodic zero-mean body force conserves MOMENTUM, not volume flux"

---

### Final default: momentum residual tolerance follows the pressure solver's rtol, not a fixed constant
- area: flow
- source: momentum-solve-residual-stop.md:53
- decided: 2026-09-02
- status: settled
- quote: |
    **Final default (user decision 2026-09-02, later the same day):** the momentum residual
    tolerance FOLLOWS THE PRESSURE SOLVER'S rtol (`velResTol_ < 0`; the projection consumes u* and
    resolves the divergence the momentum residual leaves to its own tolerance — no free constant).
    Guards: >= 1 sweep/V-cycle always (else the hydrostatic acid test drifts 1e-8), round-off floor
    (r <= 1e-14*scale or no decrease between checks).
- rejected: a fixed residual-stop constant (1e-5), decided earlier the same day
- why: "the projection consumes u* and resolves the divergence the momentum residual leaves to its own tolerance — no free constant"
- conflict: supersedes the same file's earlier same-day decision (see next entry)

### Fine-scope MG-PCG promoted to default after lever ablation
- area: flow
- source: parallel-scaling-study.md:162-164
- decided: 2026-08-09
- status: settled
- quote: |
    LEVER ABLATION @8/16 GPU: fine-scope MG-PCG WINS (default PROMOTED in flow: meanRemovalAll_=false, gates rerun); meanall +5.5%, hoststage +12%
    (GPU-aware halo worth it), Chebyshev 2.6x WORSE (38 vs 12.2 iters — reduction-free loses to
    PCG's convergence), GraphAMG bottom 3-8x worse on GPU.
- rejected: 'all'-scope mean removal as the default; Chebyshev smoother; GraphAMG bottom solve (on GPU)
- why: fine-scope MG-PCG measured fastest; Chebyshev's reduction-free approach loses to PCG's convergence rate; GraphAMG bottom is 3-8x worse on GPU

### Fix: refresh the MG halo before computing the residual, not only before each colour sweep
- area: flow
- source: cpu-fat-rank-optimization.md:14-22
- decided: undated (flow 5d77deb)
- status: settled
- quote: |
    **ROOT CAUSE (lever 1), found by instrumenting, not guessing — flow 5d77deb.** The pressure
    V-cycle's smoother exchanges the halo BEFORE each colour sweep, so on return from the pre-smooth
    the ghosts are ONE COLOUR-UPDATE STALE. The residual (→ restricted coarse rhs) was therefore wrong
    on the whole block-boundary shell... The perturbation scales with
    block SURFACE ⇒ **the V-cycle's convergence rate depended on the decomposition**. Fix = refresh the
    halo before the residual (distributed: exchange overlapped with the interior residual via the new
    `residualCutcellBox`, same interior/shell split the smoother uses; single-rank: periodic wrap copy).
    `PECLET_FLOW_MG_RESFILL=0` restores the old behaviour as an ablation.
- rejected: computing the MG residual from ghosts left stale by the pre-smooth's own halo exchange
- why: "boundary-adjacent cells reported their Gauss–Seidel residual (≈0) instead of the true one, so the coarse grid never saw that error"

### Float MReal operator storage silently breaks A*1=0 at high MG contrast; peer's FCG/S3-indefiniteness fix is refuted for this case
- area: flow
- source: collocated-attractor-campaign.md:56
- decided: 2026-08-31
- status: settled
- quote: |
    **FLOAT-STORAGE ROOT CAUSE 2026-08-31 ...:** the R>=24 order-2-aperture ladder blocker ("high-
    contrast MG degradation", row 55) is ROOT-CAUSED = float MReal operator storage breaks A*1=0 at
    eps_f32; at 3-decade MS contrast the defect ~1e-4 relative on mixed rows shifts the near-null
    vector off the deflated constant -> PCG rebound / FCG floor 2e-6 / Chebyshev cap-burn, ALL drivers
    ... PROOF: -DPECLET_FLOW_MREAL_DOUBLE A/B at 192^3 = clean 1e-8 ...; float path bit-reproduced
    post-refactor. Cross-session: VoF peer (suite-c8) supplied FCG (...) + the indefinite-pivot S3
    model — REFUTED on this case, their dense-probe evidence self-declared contaminated (float-backed
    V-cycle); their VoF rho-ratio-1000 case may independently reproduce (contrast per se).
- rejected: the VoF peer's indefinite-pivot S3 model as the explanation for this case's MG degradation
- why: "their dense-probe evidence self-declared contaminated (float-backed V-cycle)"; float MReal storage A/B (double build clean) is the proven cause

### Fragmentation guard: BFS-isolated pockets are treated as solid for the projection only
- area: flow
- source: flow-ghost-projection.md:81
- decided: 2026-07-16
- status: settled
- quote: |
    the binary
    COUPLED-face graph FRAGMENTS (25/50/83 components at Ng=32/44/56) → per-pocket null vectors →
    BiCGStab breakdown → fields to 1e152. FIXED: host-BFS fragmentation guard in setSolid (pockets
    outside the main component become solid for the projection only).
- rejected: none stated (the unguarded fragmentation caused breakdown)
- why: "per-pocket null vectors → BiCGStab breakdown → fields to 1e152"

### Free-variable fix: pin phi=0 at decoupled cells after the solve
- area: flow
- source: flow-ghost-projection-mpi-plan.md:19
- decided: 2026-07-23
- status: settled
- quote: |
    **KEY BUG found by the np=2 gate (fixed; affects single-rank too):** solid-centered cells + fully-BC_ONLY rows are FREE variables of the binary-openness operator (zero row + zero rhs). The Krylov path left arbitrary decomposition-dependent phi there [...] Fix: pin phi=0 at decoupled cells after the solve (`gp_pin_decoupled` in flow_ibm project()), per the ghost_projection.hpp doc contract. Side effect: staggered gp residual floor 4.3e-8 → 1.4e-13 on separated spheres — the old "compatibility floor" was this pollution leaking through EXPLICIT sliver faces.
- rejected: leaving free variables (solid-centered / BC_ONLY rows) unpinned after the Krylov solve
- why: "the Krylov path left arbitrary decomposition-dependent phi there — invisible to every gp diagnostic, but injected into near-wall fluid u"

### Fresh (newly-uncovered) cells must be seeded with the local wall velocity, not inherit the solid value
- area: flow
- source: sdf-scene-campaign.md:97
- decided: 2026-08-31
- status: settled
- quote: |
    **§7 item 4 (FRESH CELLS) RESOLVED 2026-08-31** flow `1a01769` ... inheriting the solid's value in a
    cell a moving body uncovers costs a **RESOLUTION-INDEPENDENT +2.6..2.9% drag bias** ... Seeding with
    the local wall velocity (`uBc_`, already computed) is now the DEFAULT: bias → −0.04..+0.38%, spurious
    force oscillation 20–50× down ... DECISIVE DIAGNOSTIC: without seeding the oscillation gets WORSE as
    dt is refined — the literature's signature that the source is SPATIAL; with seeding it converges.
- rejected: inheriting the solid's prior value in a freshly-uncovered cell
- why: "a RESOLUTION-INDEPENDENT +2.6..2.9% drag bias"; "without seeding the oscillation gets WORSE as dt is refined"

### GPU binding must let SLURM cgroup-isolate; manual CUDA_VISIBLE_DEVICES remap fights SLURM
- area: flow
- source: channel-dns-isotropic-grid.md:45
- decided: 2026-07-29
- status: settled
- quote: |
    GPU-BINDING GOTCHA: manual CUDA_VISIBLE_DEVICES remap (PECLET_BIND_GPU=1) FOUGHT SLURM → oversubscription
    (N=4 put 3 ranks on GPU0, 4× SLOWER). FIX: `srun --gpus-per-task=1 --gpu-bind=per_task:1` +
    PECLET_BIND_GPU=0 (SLURM cgroup-isolates; driver must NOT remap).
- rejected: PECLET_BIND_GPU=1 manual remap
- why: "manual CUDA_VISIBLE_DEVICES remap ... FOUGHT SLURM → oversubscription ... 4× SLOWER"

### GPU-aware MPI is not the shipped default on Snellius 2024a due to a toolchain conflict
- area: flow
- source: channel-dns-isotropic-grid.md:44
- decided: undated
- status: settled
- quote: |
    **GPU-aware MPI KNOT: Snellius 2023 stack UCX-CUDA is built only for CUDA 12.1.1, but Kokkos 5.1.1 requires
    NVCC≥12.2.0 — mutually exclusive.** GPU-aware DID validate at 12.1.1 ... but you can't build the solver
    there. ... Default shipped = CUDA/12.4.0 + host-staging.
- rejected: building the solver against the GPU-aware-validated CUDA 12.1.1 stack
- why: "you can't build the solver there" (NVCC≥12.2.0 required by Kokkos 5.1.1)

---

### Galilean identity (A−idiag·I)·1=0 is false in general — corrects the plan's inventory
- area: flow
- source: defect-correction-campaign.md:27-28
- decided: 2026-09-01
- status: superseded
- quote: |
    (3) **Galilean
    identity (A-idiag*I)*1=0 is FALSE in general** — fou_operator is conservative, row sum = rho_f*div_h(u^k)
    (per axis dt*(velp-velm), since max(v,0)+min(v,0)=v); holds only for uniform/div-free advecting field
- rejected: the plan's assumption that (A−idiag·I)·1=0 holds generally
- why: "fou_operator is conservative, row sum = rho_f*div_h(u^k)... holds only for uniform/div-free advecting field"

### Geometric const-coeff + masking are the validated defaults; Galerkin/CG is opt-in
- area: flow
- source: suite-distributed-status.md:98-100
- decided: undated (Step 19)
- status: settled
- quote: |
    Geometric const-coeff path + masking remain validated DEFAULTS (galerkin_=false);
    cut-cell+Galerkin+CG+flux-div+no-mask is a self-consistent opt-in.
- rejected: making Galerkin/CG the default
- why: none stated beyond "validated"

### Ghost's rho scalar is not a partial cut-cell transplant — premise correction
- area: flow
- source: ghost-hardening-plan.md:21-25
- decided: 2026-08-17
- status: superseded
- quote: |
    Premise corrections (all measured, don't re-derive):
    - Ghost's one-scalar `rho = min(1, min_f D_f)` is **NOT** a partial transplant of cut-cell's
      D_rescale — for a single-sided closure it is algebraically IDENTICAL to `R = D_rescale/D_axis`
      (ghost divides each face's weights by its own D then scales the row by min D; cut-cell folds
      both into `K = poly_Nc*R`). Frank's and the plan's premise here was wrong.
- rejected: the premise that ghost's rho is only a partial transplant of cut-cell's D_rescale
- why: algebraically it is identical to R = D_rescale/D_axis for a single-sided closure — "Frank's and the plan's premise here was wrong"

### Ghost-plane MASK must be exchanged under motion, not just velocity fields
- area: flow
- source: advective-cutwall-flux-plan.md:75
- decided: 2026-09-02
- status: settled
- quote: |
    **Gate 7 CLOSED 2026-09-02:** np=2 1.45e-7 → 4.1e-16. Mechanism = ghost-plane MASK (ibmSolidMask
    uses the clamping ccSampleExt) deciding which ghost rows get the A0 fill; uBc_ exchange alone
    changed nothing. Fix: exchangeExtRaw(C[c].mask) under hasMotion_ (+ uBc_/uwCell_ exchange).
    Ablation: inner-only or ghost-only fill → 1.4e-3 (both rows classes needed).
- rejected: exchanging only uBc_/velocity without exchanging the mask ("uBc_ exchange alone changed nothing"); inner-only or ghost-only mask fill (both insufficient, 1.4e-3 residual)
- why: the ghost-plane mask, not the velocity field, decides which rows get the A0 wall-velocity fill

---

### Ghost-projection MPI design: gp-row ownership = inner-block cell; BiCGStab stages the iterate on a g=2 block rather than doing a second exchange
- area: flow
- source: flow-ghost-projection-mpi-plan.md:13-16
- decided: 2026-07-23
- status: settled
- quote: |
    gp-row ownership = inner-block cell (buildGpOverlay already iterates exactly the rank's inner cells); all ±2 closure couplings are reads into the exchanged g=2 halo. [...] BiCGStab distributed matvec: the MG block only has g=1 ghosts but the overlay reaches ±2 → stage the iterate on the solver's g=2 block (`gpX2_`), one 2-deep exchange, read the g=1 halo back from the staged copy (no second exchange), `gpApplyDelta` in ghost mode.
- rejected: a second separate exchange to satisfy the ±2 overlay reach
- why: none stated beyond the design itself (avoids a second exchange)

### Gibou-style NS scheme identified as a trap (adopted MAC/staggered for stability, not a collocated precedent)
- area: flow
- source: sdflow-collocated-solver.md:169-174
- decided: 2026-07-05
- status: settled
- quote: |
    keeping ABC does
    NOT block 2nd order — the whole COLLELA SCHOOL (Basilisk embed.h [V-verified collocated approx
    projection], Trebotich-Graves/EBChombo, Johansen-Colella 1998 foundation) reaches 2nd-order curved-wall
    drag WITH an approximate projection. **PRIMARY REC = copy Basilisk embed.h** [...] Gibou path = TRAP
    (a Gibou NS scheme adopted MAC/staggered for stability).
- rejected: the Gibou-path literature precedent for a collocated 2nd-order scheme
- why: "a Gibou NS scheme adopted MAC/staggered for stability"

### GraphAMG re-enabled as porous+drag default after two BC-blind defects fixed
- area: flow
- source: porous-cfddem-cuda-two-bugs.md:27
- decided: 2026-07-06
- status: settled
- quote: |
    **GraphAMG∧domain-BC FIXED** (was gated off): two BC-blind defects in `flow/src/mac_cutcell_mg.hpp` — (a) buildAmg wrapped off-diagonals periodically across ALL boundaries (open Dirichlet outflow face coupled top↔bottom; now boundary-crossing faces on non-periodic axes keep the coefficient diagonal-only); (b) pcgAmg unconditionally mean-projected rhs/z (now gated on removeMean_ = !hasOutflow_). GraphAMG re-enabled as porous+drag default; validated resid 3.9e-11; regression +0.00%.
- rejected: leaving GraphAMG gated off for domain-BC problems
- why: none stated beyond the fix description

### Grid-convergence studies must report dimensionless permeability k* = k/N², not dimensional k
- area: flow
- source: sdflow-regression-suite.md:20-22
- decided: undated
- status: settled
- quote: |
    **Key gotcha:** geometry is self-similar in N (R = r_frac·N), so dimensional permeability k_cells ∝ N²
    (NOT convergence) — must report the dimensionless k* (k/N²) for a real grid-convergence study. Z&H's K is
    already dimensionless. Order is fit as f(N)=f_inf + C·N^-p (grid-search p + linear LS, dependency-free).
- rejected: reporting dimensional k_cells directly as a convergence metric
- why: "geometry is self-similar in N ... so dimensional permeability k_cells ∝ N² (NOT convergence)"

### Grid-dimension convention: MG per-axis coarsening depends on factors of two; always check halvings before proposing a grid
- area: flow
- source: channel-scaling-rebenchmark.md:182-200
- decided: 2026-08-10
- status: settled
- quote: |
    **★★★ THE REAL ROOT CAUSE 2026-08-10 (peclet-examples 9371067): GRID DIMENSIONS' FACTORS OF TWO.**
    MG coarsening rule, read from `flow/src/mac_cutcell_mg.hpp` (NOT guessed):
    - `can(d) = (d%2==0) && (d/2>=2)`, applied **PER AXIS INDEPENDENTLY** → **semi-coarsening is already
      automatic**: the long axis keeps halving after the short ones stop (level dump shows
      `ratio(2,1,1)`). Depth is NOT set by the smallest direction — it is set by **factors of two**.
      **An ODD dimension never coarsens even once.**
    - Hierarchy stops when NO axis can coarsen, or at `nLevels` (MGLEVELS).
    - **MPI ONLY: `evenBlocks(ax)`** — an axis coarsens only if EVERY rank's block origin AND size are
      even on it. So distributed depth is set by the **PER-RANK BLOCK**, not the global grid...
    - **MEASURED, single GPU, 384×128×GNZ, all else identical: GNZ=256 (8 halvings) 5.0 iters/120 ms;
      GNZ=250 (1) 9.8/195 ms; GNZ=255 (0) 16.2/329 ms → ONE ODD NUMBER = 3.2×, no MPI involved.**
    ...
    **ALWAYS check halvings before proposing a grid.**
- rejected: choosing benchmark grid dimensions without checking per-axis halving depth (led to a "WORSE" refine ladder caught before burning GPU hours)
- why: "An ODD dimension never coarsens even once" — measured 3.2x iteration/time penalty from one odd dimension

### Guidance: ghost for resolved/smooth IBM geometry, cutcell aperture for tight-throat porous media
- area: flow
- source: flow-ghost-projection.md:86
- decided: 2026-07-16
- status: settled
- quote: |
    VERDICT: ghost equally
    good on resolved/smooth IBM geometries with fewer iterations; **cutcell remains preferable for
    under-resolved tight-throat porous media**; ghost iterations also rise there (33–42 vs 14).
- rejected: using ghost projection for under-resolved tight-throat porous media
- why: "point-based faces can't throttle sub-cell throats the way apertures do"

### Host-serial-kernel threshold lever kept despite measuring as marginal at the fat-rank size
- area: flow
- source: cpu-fat-rank-optimization.md:43-49
- decided: undated (flow 56bc731)
- status: settled
- quote: |
    **LEVER 2 (serial-below-threshold host kernels) = MARGINAL, kept anyway (flow 56bc731).** ccFor3 +
    the cut-cell RB-GS line sweeps run sequentially below `hostSerialCellCutoff()` (8192 cells,
    `PECLET_FLOW_HOST_SERIAL_CELLS` overrides). Bit-identical; reductions deliberately NOT cut over (FP
    order vs the multi-rank contract). Per-level timer says the win is almost entirely the MG BOTTOM
    level (~24 trivial launches/V-cycle): 64³/rank 0.018→0.007 s per 50 V-cycles ≈ 8% of the V-cycle;
    128³/rank ~1.5%; **256³/rank (the fat-rank size) ~0.2% = noise.** The plan's 15–20% estimate did
    NOT survive measurement. A bigger cutoff back-fires (131072: 64³ projection 16.6→20.6 ms).
- rejected: cutting reductions over to serial-below-threshold execution; a larger serial-cutoff (131072)
- why: reductions kept parallel to preserve "FP order vs the multi-rank contract"; a bigger cutoff measured worse (16.6→20.6 ms)

### How to apply: staggered recommended for accuracy-critical drag/permeability; collocated for structural wins, at the cost of first order at curved walls
- area: flow
- source: sdflow-collocated-solver.md:202-207
- decided: undated
- status: settled
- quote: |
    **How to apply:** recommend staggered when permeability/drag accuracy is the goal (2nd order, lands on Z&H
    at modest N); recommend collocated for its structural wins (cell-centered storage, easy coupling to
    cell-centered scalars/physics) — but it is FIRST-ORDER at curved immersed walls, so it needs finer grids
    there (or the embed-style fix).
- rejected: none stated
- why: none stated beyond the accuracy/structure tradeoff

---

### IBM overlay needs no separate scaling change — linear in the base stencil
- area: flow
- source: sdflow-dt-divided-convention.md:24-26
- decided: 2026-06
- status: settled
- quote: |
    The IBM overlay
    (`ibm_modify_stencil_k`) is LINEAR in the base stencil, so scaling the base by 1/dt scales the whole
    modified row + inhom automatically — no IBM-side change.
- rejected: none stated
- why: linearity of the overlay in the base stencil

---

### IBM velocity-MG must NEVER un-scale the residual by 1/D_rescale
- area: flow
- source: velocity-mg-design.md:24-35
- decided: undated
- status: settled
- quote: |
    ## IBM-path correctness fix — the DECISION (so the wrong fix never resurfaces)
    The IBM (packed-object) **diffusion** vmg with the geometry-blind `setDiffusionCoarse` const-coeff coarse
    has a +2–4% Z&H drag bias at a fixed cycle count. The fix is NOT, and must never become, "un-scale the
    residual by 1/D_rescale". **D_rescale** (`mac_ibm.cuh:105`) is a `min|D|` cut-face factor that →0 for thin
    slivers; it's a pure left row-scale of A and b → exactly RB-GS-invariant. Dividing the restricted residual
    by it AMPLIFIES the near-solid rows where D→0. `mac_ibm.cuh:18` itself says the IBM op is row-based,
    non-conservative across the wall, "NEVER multigridded; D_rescale is GS-invariant but not MG-invariant."

    **Why un-scaling is unnecessary, not just dangerous:** the correction-scheme V-cycle already restricts the
    TRUE residual `b' − A_f x` (level-0 op = the IBM `As_[c]` via `setDiffusionFine`), so the fixed point is the
    exact sharp solution regardless of the coarse op — `r=0 ⇒ correction=0`. The coarse op only sets the RATE.
    So leave the residual scaled; fix the coarse op and the transfers instead.
- rejected: un-scaling the restricted residual by 1/D_rescale to fix the +2-4% Z&H drag bias
- why: "Dividing the restricted residual by it AMPLIFIES the near-solid rows where D→0"; D_rescale is "GS-invariant but not MG-invariant"; the correction-scheme V-cycle already uses the true residual so the coarse op only affects convergence rate, not correctness

### If a pressure method clearly wins at scale, make it the default
- area: flow
- source: parallel-scaling-study.md:11-17
- decided: 2026-08-07
- status: settled
- quote: |
    **The study (user-approved plan 2026-08-07):** ... User decisions: BOTH CaNS and OpenFOAM as references
    ("close to SOTA, much better parallel than OpenFOAM"); 32 GPUs max; keep runs short (budget);
    if a pressure method clearly wins at scale, MAKE IT THE DEFAULT; workstation study FIRST and its
    results reported (workstation-vs-Snellius for small systems).
- rejected: none stated
- why: none stated (user directive)

### Incremental (rotational) pressure now default ON in C++ DistributedNS, matching the Python binding
- area: flow
- source: sdflow-dt-divided-convention.md:40-44
- decided: 2026-06
- status: settled
- quote: |
    (1) `incremental_` rotational pressure is now **default ON** in
    C++ `DistributedNS` (matches the sdflow Python binding, which already defaulted on); the cell-for-cell
    classical-Chorin ctests + the `n_pois=0` (no-projection) ctests opt out with
    `set_incremental_pressure(false)`
- rejected: classical (non-rotational) pressure as the C++ default
- why: to match the existing Python binding default

### Incremental-rotational pressure default ON in sdflow, OFF in DistributedNS
- area: flow
- source: suite-distributed-status.md:325-332
- decided: undated
- status: settled
- quote: |
    **Default OFF in DistributedNS**
    (69 Chorin cell-for-cell tests byte-unchanged), **default ON in the sdflow module**. Validated: steady
    velocity unchanged; **pressure vs pnm_backend 2.36%→0.42% (5.6× closer)**; and **28.6% FASTER**
    (smaller correction → fewer pressure-PCG iters).
- rejected: none stated
- why: keeps DistributedNS's existing cell-for-cell tests byte-unchanged while giving sdflow closer parity to pnm_backend and faster convergence

### Instability fix: a wall-banded rotational-term blend, not the full rotational update everywhere
- area: flow
- source: collocated-attractor-campaign.md:14
- decided: 2026-08-21
- status: settled
- quote: |
    Fixed by Frank's **wall-banded blend** `set_rotational_wall_weight(0.5)`: P += (ρ/dt + w·μ)φ −
    (1−w)μ·div(u*) at solid-adjacent cells only — stable + 11-digit convergence at dt=60/600/**1e20**.
- rejected: the unblended full rotational update on the cell-centered approximate projection (unstable, PM-II instability)
- why: "stable + 11-digit convergence at dt=60/600/1e20"

### Interstitial vs superficial drag normalization: our K is interstitial (Zick-Homsy); literature (vdH/Tenneti/van Wachem) reports superficial F_D=(1-phi)K, not "friction"
- area: flow
- source: ibm-accuracy-sphere-validation.md:45-50
- decided: undated
- status: superseded
- quote: |
    **Convention (DEFINITIVE — see RECENT PAPERS block below):** our `K` (=Zick&Homsy) is **INTERSTITIAL**-
    referenced; the literature (vdH/Tenneti/**van Wachem**) reports the **SUPERFICIAL total drag F̄_D=(1−φ)·K**
    (NOT friction — earlier "friction" label was wrong; the number (1−φ)K was right). Both →1 dilute so the
    dilute limit can't tell them apart — the trap.
- rejected: the earlier "friction" label for (1-phi)K
- why: the dilute limit (both -> 1) hides the convention difference; the earlier label was simply wrong even though the number was right

### Invariant: the ORB must never split the wall-normal axis (y) in wall-bounded flow
- area: flow
- source: channel-scaling-rebenchmark.md:85-88
- decided: undated
- status: settled
- quote: |
    - **The ORB must never split wall-normal y** (an internal y-boundary decouples the halves at the
      centreline — validated bug; the driver hard-aborts). Weak scaling grows GNX only, so the box
      gets more elongated and ORB carves x/z first; y stayed whole to np≈32 on the production grid.
      **32 GPUs is therefore the natural ceiling for this case.**
- rejected: allowing the ORB to split the wall-normal axis
- why: "an internal y-boundary decouples the halves at the centreline — validated bug"

### Keep the staircase velocity-MG despite modest current efficiency win — it is the right operator for future AMR near contact points
- area: flow
- source: velocity-mg-design.md:113-116
- decided: undated
- status: settled
- quote: |
    **Why conserved despite a modest current efficiency win** (RB-GS converges in O(pore-cells) sweeps; pressure
    solve dominates the step at high res): it is the natural coarse operator for a future **AMR with extreme
    refinement near contact points**, where the velocity solve becomes genuinely stiff/multiscale and an
    O(1)-V-cycle exact, unconditionally-stable solver pays off. Keep intact.
- rejected: removing the staircase velocity-MG for lack of current efficiency win
- why: "the natural coarse operator for a future AMR with extreme refinement near contact points"

### Lattice-plane trap: an SDF exactly 0 at a staggered point is invisible to both the fluid mask and the ghost detector
- area: flow
- source: sdf-scene-campaign.md:150
- decided: 2026-09-02
- status: settled
- quote: |
    **Lattice-plane trap ROOT-CAUSED (2026-09-02, §7 item 12):** sdf EXACTLY 0 at a staggered point is fluid
    to `ibmSolidMask` (strict <0) and not a ghost in `ibmFillEntry` (strict <0) → the wall has no row →
    inert. Detector `moving_instance_degenerate_points()` ... First detector version used face apertures —
    WRONG signal (plane cutting parallel faces leaves apertures 0/1); the gate caught it.
- rejected: face-aperture-based detector for the degenerate lattice-plane condition
- why: "plane cutting parallel faces leaves apertures 0/1" — the wrong signal

### Level-0 BC hook must use fold=0 (reflection) for the unfolded stencil
- area: flow
- source: momentum-solve-residual-stop.md:24
- decided: undated
- status: settled
- quote: |
    (2) Level-0 BC hook must use fold=0 (reflection) for the unfolded stencil; fold=1
    diverges.
- rejected: fold=1
- why: "fold=1 diverges"

### M2 chosen as plain Richardson, not BiCGStab
- area: flow
- source: defect-correction-campaign.md:31
- decided: 2026-09-01
- status: settled
- quote: |
    M2 = plain Richardson (not BiCGStab): 16 vs 48 B/cell, no breakdown mode.
- rejected: BiCGStab for M2
- why: "16 vs 48 B/cell, no breakdown mode"

### MG telescoping ships off by default, byte-identical when off
- area: flow
- source: mg-decomposition-alignment.md:79
- decided: 2026-09-02
- status: settled
- quote: |
    **2026-09-02 — telescoping IMPLEMENTED and merged to main** ... `set_pressure_telescope(True)` /
    `PECLET_FLOW_TELESCOPE=1`, off by default, byte-identical off.
- rejected: none stated
- why: none stated

---

### MG-PCG stalls on ρ- and eps/drag-scaled coefficient operators; Chebyshev is the default driver for those paths
- area: flow
- source: multiphysics-framework-plan.md:391
- decided: undated (P5 section)
- status: settled
- quote: |
    **CRITICAL FINDING: MG-PCG STALLS on ρ-scaled coefficient operators (5000 its stuck; openness-tuned
    transfer pair loses CG's SPD structure) — Chebyshev converges in ~20 and is the varRho DEFAULT
    driver** (bounds re-estimated per rebuild); MG-transfer-symmetry fix = follow-up.
- rejected: MG-PCG as the default driver for variable-density (and, per line 379/382, porous+drag) coefficient operators
- why: "5000 its stuck; openness-tuned transfer pair loses CG's SPD structure"

### MG-PCG's relative stopping test never fires on a near-quiescent field; a fixed-iteration cap is the workaround, not a proper fix
- area: flow
- source: flow-thermal-convection-validated.md:20
- decided: undated
- status: settled
- quote: |
    **Two flow pressure-driver pitfalls** (logged in peclet-examples ISSUES.md, open in flow):
    1. MG-PCG's relative stopping test never fires on a near-quiescent field (velocities ~1e-5, e.g.
       near RB onset): runs to max_iter at ANY rtol. Workaround: cap it —
       `set_pressure_pcg(True, 12, 1e-6)` acts as a fixed-work MG solve (div ~1e-12). Proper fix would
       be an absolute/RHS-scaled floor in the criterion.
- rejected: relying on the relative (rtol) stopping criterion alone near a quiescent field
- why: "runs to max_iter at ANY rtol" — the relative test cannot fire when velocities are ~1e-5

### MPI-optional single-source build: default is single-rank with no MPI linked
- area: flow
- source: suite-distributed-status.md:332-345
- decided: undated (Phase 2)
- status: settled
- quote: |
    cfd builds `sdflow` in BOTH modes from one block — **default = single-rank, NO MPI linked**
    (ldd: no libmpi), `-DCFD_BUILD_MPI=ON` = MPI multi-rank + `*_mpi` tests.
- rejected: none stated
- why: none stated

### Marching-squares (order-2) apertures are now the shipped default in both flow and AMR
- area: flow
- source: collocated-attractor-campaign.md:56
- decided: 2026-08-26
- status: settled
- quote: |
    **APERTURE ORDER-2 DEFAULT SHIPPED 2026-08-26 (flow 2b3a6ce, core + umbrella pushed):**
    marching-squares apertures are the DEFAULT in flow (trilinear samples) AND AMR (analytic samples);
    PECLET_FLOW_APERTURE_ORDER=1 reverts. TWO hardening lessons baked in: CENTER GATE (ungated MS opens
    masked-DOF staggered faces -> uncorrectable ~1.6e-4 div floor under plain RB-GS...) and floor 1e-3.
- rejected: order-1 (single-sample) apertures as default; an ungated marching-squares aperture (opens masked-DOF staggered faces)
- why: order-2 "recovers 90%/~100% of the exact-aperture bias at R=8/12"; ungated MS causes "uncorrectable ~1.6e-4 div floor under plain RB-GS"

---

### Masking must exclude BOTH cut cells and solid cells, not cut cells alone
- area: flow
- source: velocity-mg-design.md:64-75
- decided: 2026-06-16
- status: settled
- quote: |
    **Why each exclusion matters (measured, SC sphere, `verify_velocity_mg_volfrac_zh_sdflow.py`):**
    - residual scaled-but-not-unscaled + plain transfers + const coarse: +bias, NaN at dt≥200.
    - volfrac op alone: converges to RB-GS but SLOWER than const, still NaN at dt≥200.
    - zero residual at CUT cells only: helps rate, still NaN at dt≥200.
    - zero residual + mask prolong at CUT cells: better rate, still NaN at dt≥200 (the **solid** rows: fine 1+6β
      live during the cycle vs coarse identity θ<ε → factor-(1+6β) mismatch → overshoot at large β).
    - **zero residual + mask prolong at CUT *and* SOLID cells (clean-fluid mask):** dt=60 **0.000%** (beats const
      0.06%), **dt=200 0.000% and STABLE where const NaNs** (2× the stable steady-state dt), converged not
      under-resolved. dt≥400 (β≥40) still diverges — the practical ceiling.
- rejected: masking cut cells only (without also masking solid cells)
- why: "the solid rows: fine 1+6β live during the cycle vs coarse identity θ<ε → factor-(1+6β) mismatch → overshoot at large β"

### Method verdict: WY-split PLIC (B) chosen; CICSAM (A) rejected; CLSVOF (D) dropped
- area: flow
- source: vof-campaign.md:89-92
- decided: 2026-08-30
- status: settled
- quote: |
    - Method verdict: **B builds** (WY split PLIC + MYC + SZ/Lehmann-Gekle inversion + HF cascade
      + PV paraboloid fallback + balanced-force CSF, momentum-consistent from day one); **C = band
      RDF folded into B** for SDF contact angle (ghost-fraction fill, n_wall=∇sdf, θ rotation);
      **A (CICSAM) rejected** (MTHINC optional fast mode later); **D (CLSVOF) dropped**.
- rejected: CICSAM (A); CLSVOF (D)
- why: none stated beyond the verdict itself

### Mixed ghost widths require CutcellMG::parityOg to correct red-black colour parity
- area: flow
- source: comm-scaling-plan.md:33
- decided: undated
- status: settled
- quote: |
    **KEY TRAP (cost a bug-catch): mixed ghost widths swap red-black colours** — parity uses og+local
    index, so a g=2 level's colours flip vs the g=1 reference (3 axes → parity flips). Fix =
    `CutcellMG::parityOg` (og − g + 1 per axis); `Level::og` itself stays the true global origin
    (buildAmg needs it).
- rejected: none stated
- why: "a g=2 level's colours flip vs the g=1 reference"

---

### Mode 10 (open-centroid quadrature) is dead — worse on Z&H and diverges on RCP slivers
- area: flow
- source: flow-ghost-projection.md:119
- decided: 2026-07-18
- status: settled
- quote: |
    Mode 10 (open-centroid quadrature + good force) = DEAD:
    worse on Z&H, DIVERGES on RCP slivers (mode-3a non-telescoping row-sum runaway; telescoping
    force does NOT cure it) — constraint quadrature is definitively not the lever.
- rejected: mode 10 open-centroid quadrature constraint
- why: "worse on Z&H, DIVERGES on RCP slivers ... telescoping force does NOT cure it"

### Mode 4 (fully-FV via defect correction) implemented and is a negative milestone — not 2nd order
- area: flow
- source: sdflow-collocated-solver.md:133-150
- decided: 2026-07-05
- status: settled
- quote: |
    **RESULT: stable, converges to an ω-independent fixed point, but NOT 2nd-order** — Z&H +0.81/+0.99/
    +0.93% at N=32/48/64 (non-convergent) vs mode0 +1.00/+0.68/+0.60. **ROOT CAUSE (documented in doc
    §"Implementation of the fully-FV route"): only the WALL flux got centroid placement; the o_f open-FACE
    fluxes in L_FV still use the face-CENTRE two-point gradient = the SAME O(h) sub-cell placement error**
- rejected: mode 4 as shipped (face-centre flux placement retained on the 6 axis faces)
- why: "only the WALL flux got centroid placement; the o_f open-FACE fluxes... still use the SAME O(h) sub-cell placement error"

### Mode-10 quadrature, Seo-Mittal pressure-only split, and ghost-as-production are all dead ends
- area: flow
- source: collocated-second-order-verdict.md:40-41
- decided: undated
- status: settled
- quote: |
    Also dead: mode 10 quadrature (breaks D/G adjointness — conservation is the binding
    constraint), Seo–Mittal pressure-only split, ghost as production.
- rejected: mode 10 quadrature; Seo-Mittal pressure-only split; ghost scheme as the production path
- why: mode 10 quadrature breaks D/G adjointness (conservation is the binding constraint)

---

### Momentum solve uses the divided (1/dt-scaled) convention, replacing the dt-multiplied form
- area: flow
- source: sdflow-dt-divided-convention.md:10-16
- decided: 2026-06 (June 2026)
- status: settled
- quote: |
    In cfd-gpu's **sdflow** (`dns::DistributedNS`), the implicit momentum/diffusion equation is scaled by
    **1/dt** ("divided convention"): the operator is `idt*I - nu*Lap (+ FOU advection)` with diagonal
    `Ac = idt + 6*beta`, `beta = nu`, `idt = 1/dt`; the RHS time term carries `idt` [...] This replaced the
    old dt-multiplied form `I - nu*dt*Lap`, `b = u^n + dt*f`. Same converged solution [...] but well-conditioned
    as **dt→∞ / steady state** — the change the user asked for (June 2026)
- rejected: the dt-multiplied form `I - nu*dt*Lap`
- why: "at large dt the multiplied form's I and u^n terms become negligible vs the huge dt-scaled terms (float precision loss)"

### Momentum tolerance-stop: adaptive tolerance instead of a fixed sweep cap
- area: flow
- source: parallel-scaling-study.md:74-77
- decided: 2026-08-08
- status: settled
- quote: |
    (1) momentum TOLERANCE STOP `set_velocity_solver_params(iters, rtol, min_iters)` — fused max-increment
    reduce on the black sweep, rank-uniform MPI stop; rtol=0 default = legacy byte-identical; TGV exits at
    4 sweeps/component vs 20 (user floated "cap 5" — rejected: silently under-converges stiff regimes,
    tolerance adapts instead).
- rejected: a fixed sweep cap of 5 (user's own suggestion)
- why: a fixed low cap silently under-converges stiff regimes; an adaptive tolerance is used instead

### Momentum-advection kernels must use the actual wall velocity field, not maskVelocity's solid zeros
- area: flow
- source: advective-cutwall-flux-plan.md:15
- decided: 2026-09-02 (A0)
- status: settled
- quote: |
    **What A0 was:** the momentum-advection kernels (`sadv::`, geometry-blind) read `maskVelocity`'s
    solid ZEROS; zero is the wall velocity only for a STATIC wall. A0 feeds them scratch views holding
    the rigid-body `u_wall` (reuses `uBc_`), explicit + implicit paths both.
- rejected: reading maskVelocity's solid-zero convention as the wall velocity for a moving wall
- why: "zero is the wall velocity only for a STATIC wall"

### Multiphysics assembly is runtime-dispatched flags on existing kernels, not a Solver<Grid,Props> template
- area: flow
- source: multiphysics-framework-plan.md:403
- decided: undated
- status: settled
- quote: |
    Core design verdicts (argued in the doc):
    - **Runtime-dispatched assembly, NO `Solver<Grid,Props>` template**: hot loops (RB-GS, CutcellMG)
      already run on stored coefficient fields; rho/mu enter only assembly kernels (`ibmBuildDiffusion`
      cut_cell_ibm.hpp:215, buildRhs, pressure update). `varProps_` flag selects sibling `*Var` kernels;
      **existing validated kernels never edited** (bit-exactness is structural). Pressure Poisson is
      already variable-coefficient in openness => variable density = `openness/rho_face` on the same
      CutcellMG rails.
- rejected: a templated Solver<Grid,Props> design
- why: "existing validated kernels never edited (bit-exactness is structural)"

### Must re-mask solid velocity after grad(phi) correction
- area: flow
- source: cuda-kokkos-migration.md:354-355
- decided: undated
- status: settled
- quote: |
    (b) MUST re-mask solid velocity after the grad(phi) correction
    (CUDA apply_mask/mask_k) or decoupled solid velocity accumulates -> blow-up.
- rejected: skipping the re-mask
- why: "decoupled solid velocity accumulates -> blow-up"

### Non-incremental Chorin projection gives wrong steady Z&H drag — incremental-rotational required
- area: flow
- source: embed-port-progress.md:21-22
- decided: undated
- status: settled
- quote: |
    - Z&H drag steady state is dt-independent BUT slow to converge (incremental-rotational pressure accumulation, ~1000-3000 steps; NOT accelerated by larger dt). Non-incremental Chorin gives WRONG steady drag (−40%, splitting-error). Robust protocol: dt=400 + warmstart, run past min_steps floor until |dK| over 200 steps < 5e-5. The warm-detector protocol fires on false plateaus — don't use.
- rejected: non-incremental Chorin projection (−40% error, splitting-error); the warm-detector convergence protocol
- why: Chorin gives "WRONG steady drag (−40%, splitting-error)"; the warm-detector "fires on false plateaus"

### Old "inter-node reduction tax" diagnosis for the channel 8-GPU scaling drop is superseded
- area: flow
- source: channel-scaling-rebenchmark.md:59-61, 137-139
- decided: 2026-08-10/11
- status: superseded
- quote: |
    The published page (2026-08-02) reports 46 M cells/GPU, 1/2/4/8 GPUs =
    **1369/1300/1713/2942 ms/step = 100/105/80/47 % weak efficiency** (33/70/106/124 Mcell/s) and
    attributes the 8-GPU drop to "the inter-node pressure-solve reduction tax". **That diagnosis is
    now believed wrong/stale** — see below.
    ...
    **COMMUNICATION IS NOT THE BOTTLENECK — the old page's "inter-node reduction tax" is dead.**
    Pressure allreduce = 0/1/3/9/14/16 ms of a 2.6–2.8 s step (0.3–0.6 %); 2.3–2.4 % with CFR. Step is
    89–95 % `projection`, and projection tracks the iteration count exactly.
- rejected: "the inter-node pressure-solve reduction tax" as the explanation for weak-scaling loss
- why: measured pressure allreduce time is only 0.3-0.6% of the step; the loss tracks iteration count instead

### Old grid-convergence table retired; Galerkin=True / set_pressure_pcg not for production
- area: flow
- source: suite-distributed-status.md:311-316
- decided: undated (MG Phase 4)
- status: superseded
- quote: |
    **This re-frames my earlier "Galerkin pressure buggy" saga** (the old
    `grid_convergence_sdflow_vs_pnm.py` k/N² 5.700→5.603→5.586→5.33 table): sdflow side used the buggy
    `galerkin=True`; pnm side was MIS-CONFIGURED (time-marched w/ default outer-iters, not pnm's SIMPLE
    800-outer steady solve). BOTH halves broken → retired; Z&H single-sphere supersedes it. (NOT Brinkman —
    that correction still stands, never active.) **OPEN bug → backlog item 7: fix or remove sdflow's
    Galerkin-MG pressure path; until then don't use `galerkin=True`/`set_pressure_pcg` for production.**
- rejected: the old grid_convergence_sdflow_vs_pnm.py comparison table/methodology
- why: both sides of that comparison were misconfigured; Galerkin-MG pressure path has an open bug

### Old single-GPU CFDSolver reference retired; pnm_backend is pore-network extraction only
- area: flow
- source: sdflow-dt-divided-convention.md:29-38
- decided: 2026-06
- status: settled
- quote: |
    **RETIREMENT (June 2026):** the old single-GPU `CFDSolver` reference (cfd_solver*.cu/.cuh) is **deleted**
    (restore tag `pnm_backend-reference`); sdflow was validated bit-identical to it + Zick–Homsy first. [...]
    The **`pnm_backend` Python module is now pore-network extraction ONLY** (SDFReader / extract_pores /
    segment_volume / extract_topology_gpu, in bindings.cpp + pore_extraction.cu) — it no longer has a CFD solver.
- rejected: keeping the CFDSolver single-GPU reference implementation; pnm_backend carrying a CFD solver
- why: "sdflow was validated bit-identical to it + Zick–Homsy first"

### Only upwind/dissipative advection schemes exist — no central/energy-conserving option
- area: flow
- source: channel-dns-isotropic-grid.md:15
- decided: undated
- status: settled
- quote: |
    Only advection schemes are **SOU (scheme 0) and Koren-TVD (1) — both upwind/dissipative. NO
    central/energy-conserving option** (`staggered_advection.hpp`). This is THE scientific risk:
    over-dissipation may relaminarize Re_tau=180 or flatten spectra. Must be measured empirically, not assumed.
- rejected: central/energy-conserving advection scheme (does not exist)
- why: "none stated" (a limitation, not a chosen rejection)

### Owner-boundary attribution fix: remove shared-cell pressure from both sides of cross-owner faces
- area: flow
- source: sdf-scene-campaign.md:82
- decided: 2026-08-31
- status: settled
- quote: |
    **§7 item 10 (OWNER-BOUNDARY ATTRIBUTION) RESOLVED 2026-08-31** flow `1d95260` (v4): per-body
    reaction attribution carried the pressure flux through the owner partition's mid-surfaces — ZERO in
    the total (pairwise), zero for one instance, cancelling for symmetric arrays, and worth a FACTOR
    2.2 on the drag of a sphere in a closed tank ... Fix: remove the shared-cell π from both sides of
    every cross-owner fluid-fluid staggered face (+s convention = visited once = MPI-clean); wall faces
    skipped (their remainder IS the wall pressure force).
- rejected: leaving the shared-cell pressure flux attributed through owner mid-surfaces
- why: "worth a FACTOR 2.2 on the drag of a sphere in a closed tank ... and −44% on a Jeffery orbit period"

### P1 passed: double-diagonal fallback retired as measurably worse, not merely unnecessary
- area: flow
- source: defect-correction-campaign.md:33-38
- decided: 2026-09-01
- status: settled
- quote: |
    **P1 RESULT:** RCP bed rtol 1e-8 cap 300: float 24/33/CAPPED vs exact 14/14/28 == full double, div
    9.51e-12 vs float 4.51e-06. [...] **KEY: exact vs DIAGRESUM agree on iters but separate 65x on
    divergence** -> the double-diagonal converges to the FLOAT-FACE operator, exact to the true one
    => fallback RETIRED as measurably worse, not merely unnecessary.
- rejected: the double-diagonal fallback (converges to the float-face operator, not the true one)
- why: "the double-diagonal converges to the FLOAT-FACE operator, exact to the true one"
- conflict: vof-campaign.md's "USER PROPOSAL 2026-09-01 — DEFECT CORRECTION" (which this note explicitly supersedes)

### PCG selector fixed; Chebyshev stays varRho/porous default (S0/S1 outcome)
- area: flow
- source: vof-campaign.md:172-201
- decided: 2026-08-30
- status: settled
- quote: |
    Working spelling: `set_pressure_chebyshev(False,…)`.
      With PCG genuinely selected the stall reproduces at **CONSTANT density on 3-D wall-bounded
      grids** (200/200, div 1.2e-5 at nz≥8; Chebyshev 13-14) and NEVER on periodic+IBM at any ratio
      — present since the 2026-07-06 build [...] **So S3/S4 are PARKED** (no measurement shows a
      coefficient-coarsening failure: periodic handles 1e4 at parity with ρ≡1). [...]
      Two modes FCG does NOT cure (for WO-H): (a) gravity-driven hydrostatic column [...]
      (b) small ρ₀/ρ_f next to a prescribed-velocity face at ratio ≥1e2. **So Chebyshev stays the
      varRho default** (only driver healthy in all four regimes) and S2's 3× keeps its value.
- rejected: PCG as the varRho/porous default driver
- why: "only driver healthy in all four regimes"

### Pairing lesson: stability needs (G,D) structural match, accuracy needs closure-value consistency — only the ghost architecture has both
- area: flow
- source: collocated-attractor-campaign.md:35
- decided: 2026-08-23
- status: settled
- quote: |
    Adjoint family O(h) (3 rungs); Design A order 1.3; Design B (star) SPD-but-scheme-unstable
    => PAIRING LESSON (stability = (G,D) structural match; accuracy = closure-value consistency; ghost
    architecture = only scheme with both; doc/fluid_only_constraint_plan.md). B+ gates: sym(A_ghost)
    INDEFINITE (dead); star base λmax == binary surrogate (no quick precond win).
- rejected: Design B (star) — "SPD-but-scheme-unstable"; B+ gates ("dead")
- why: "stability = (G,D) structural match; accuracy = closure-value consistency; ghost architecture = only scheme with both"

### Part II phase-change architecture: Robin IHTR, PLIC plane-shift regression, transported-φ CLSVOF stays dead
- area: flow
- source: vof-campaign.md:115-125
- decided: 2026-08-30
- status: settled
- quote: |
    ṁ from pure-cell weighted 5³ one-sided gradients on band-RDF normals; IHTR Robin (not
      hard T_sat — spurious-wave trap, Bureš-Sato); WY advects with band-extended div-free
      liquid velocity; interface regression by PLIC plane shift + clip-and-redistribute (NEVER
      volume-source-in-C — Hardt-Wondra wisp trap); div source shifted into pure GAS cells in
      the Poisson RHS; ρcpT advected with the same geometric fluxes; conjugate solid heat via
      cut-cell SDF diffusion. [...] Confirmed: transported-φ CLSVOF stays dead;
      band RDF sufficient (whole Basilisk/PARIS/NGA phase-change ecosystem is geometric VoF).
- rejected: hard T_sat interface condition; volume-source-in-C interface regression; transported-φ CLSVOF
- why: "spurious-wave trap, Bureš-Sato" (hard T_sat); "Hardt-Wondra wisp trap" (volume-source-in-C)

### Part III bubbly-flow container reuses V0–V4 kernels; Dodd–Ferrante FFT not needed
- area: flow
- source: vof-campaign.md:107-114
- decided: 2026-08-30
- status: settled
- quote: |
    In peclet: blocks = third
      container over the SAME V0–V4 kernels; rungs W0–W5 in plan §10 (W2 gate: TBFsolver's own
      `channel_18` case as cross-code validation; W5 = resolved↔unresolved switching with
      dem/coupling — flagship). TBFsolver's Dodd–Ferrante constant-coeff FFT NOT needed (varRho
      MG projection is stronger).
- rejected: Dodd–Ferrante constant-coefficient FFT pressure solve
- why: "varRho MG projection is stronger"

### Per-kernel space.fence() removed — default-exec-space kernels are stream-ordered
- area: flow
- source: cuda-kokkos-migration.md:534-539
- decided: 2026-06-20
- status: settled
- quote: |
    - FENCE OPTIMISATION (commit 6f6ec32): dropped all 64 redundant per-kernel space.fence() from the cfd Kokkos
      operator headers (default-exec-space kernels are stream-ordered; only host reads -- deep_copy(host)/
      parallel_reduce -- need sync, and those are inherently blocking). BIT-IDENTICAL (full verify suite + RingBed
      + OpenMP + 15 MPI tests all unchanged). HUGE perf win: the velocity RB-GS alone fired ~1e4 host-blocking
      fences/step. => Kokkos sdflow is now FASTER than the hand-tuned CUDA at production res.
- rejected: per-kernel fence() calls
- why: "default-exec-space kernels are stream-ordered; only host reads ... need sync"

### Phase B/C explicitly must not touch GP_THETA_MIN, the sliver branch, or the preconditioner scaling
- area: flow
- source: ghost-hardening-plan.md:60-64
- decided: 2026-08-17
- status: settled
- quote: |
    Phase B re-scoped: B0 = compatibility projector (project on the measured left null vector, not
    the constants) — the only genuine structural gap left; B1 conditioning-driven order reduction
    (τ≈1e-2 on D_f, counter-gated); B2 store ρ·w not w; B3 optional two-sided sandwich flux
    closure. DO NOT touch GP_THETA_MIN, the sliver branch, or the preconditioner scaling.
- rejected: touching GP_THETA_MIN, the sliver branch, or the preconditioner scaling in phases B/C
- why: these were already investigated and ruled out/confirmed fine (see H1-refuted and preconditioner findings above)

### Plain incompressible continuity with ε only in drag is the WRONG constraint for a porous bed; volume-averaged (Model-A) continuity is required
- area: flow
- source: multiphysics-framework-plan.md:379
- decided: 2026-07-05
- status: superseded
- quote: |
    VOLUME-AVERAGED (POROUS) CONTINUITY IMPLEMENTED (2026-07-05, ...) — was the plan's explicitly-
    DEFERRED "Model-A continuity". User (CFD-DEM expert) correctly caught that the coupling solved
    PLAIN incompressible NS (div(open*u)=0, open = cut-cell WALL openness from the SDF, NOT the
    particle porosity) with eps only in the drag — so reporting div(u)->0 as "converged" enforced the
    WRONG constraint (for a bed div(eps u) = -d(eps)/dt != 0). FIX in flow: `set_porous_continuity(True)`
    — divergOpenEps (eps-weighted divergence div(open*eps_f*u)) ...
- rejected: treating div(open*u)=0 (plain incompressible NS with eps only in drag) as the converged/correct constraint for a porous bed
- why: "for a bed div(eps u) = -d(eps)/dt != 0" — the plain constraint is physically wrong for a porous medium
- conflict: this is itself later refined/superseded by the semi-implicit-drag pressure correction (multiphysics-framework-plan.md:381, below).

### Porous pressure correction must use drag-consistent relaxation (SIMPLE/PISO-with-implicit-drag), not a drag-free coefficient
- area: flow
- source: multiphysics-framework-plan.md:381
- decided: 2026-07-05
- status: settled
- quote: |
    SEMI-IMPLICIT-DRAG PRESSURE CORRECTION (2026-07-05, flow `07ea855`, umbrella `1e219c8`): USER
    (expert) identified the ROOT of the high-Re porous divergence: the pressure-correction coefficient
    was open*eps (drag-free), INCONSISTENT with the drag-loaded momentum diagonal A_P=idt+beta ->
    corrector over-shoots predictor -> diverges where drag is stiff. FIX = the standard SIMPLE/PISO-
    with-implicit-drag (OpenFOAM rAU=1/A_p, MFIX): drag-relaxation w_f=idt/(idt+beta_f)...
- rejected: the drag-free pressure-correction coefficient (open*eps) used against a drag-loaded momentum diagonal
- why: "corrector over-shoots predictor -> diverges where drag is stiff"
- conflict: refines/partially supersedes multiphysics-framework-plan.md:379 (the earlier porous-continuity fix) for the high-Re stiff-drag regime.

### Porous projection must run even with no immersed solid — flow now throws, CfdDem auto-installs set_pressure_geometry
- area: flow
- source: porous-cfddem-cuda-two-bugs.md:62
- decided: 2026-07-10
- status: settled
- quote: |
    **THE REAL BUG — FOUND & FIXED (flow `0e19de4`, coupling `78353b3`)**: the porous projection lives ENTIRELY inside `project()`, and step() has `if (cutcellPressure_) project();` — a porous **domain-BC-only box** (no set_solid/set_pressure_geometry — exactly the bidisperse example) ran with **NO projection at all** [...] FIX: (a) flow step() **throws** when porous_&&!cutcellPressure_; (b) new binding `has_cutcell_pressure()`; (c) CfdDem auto-installs `set_pressure_geometry(all-fluid)` when missing.
- rejected: silently running porous mode without any pressure-geometry / projection
- why: "no continuity constraint, gas never accelerated to interstitial U/ε in the bed"

---

### Port production physics onto the distributed solver rather than retrofit MPI into production kernels
- area: flow
- source: suite-distributed-status.md:101-104
- decided: undated (Step 20)
- status: settled
- quote: |
    closes the last capability gap vs production `cfd_solver.cu`. **Decided** (with user): rather than
    retrofit MPI into the production kernels (every one wraps get_idx — unvalidatable on 1 GPU), port the
    production physics onto the already-distributed solver, then eventually replace.
- rejected: retrofit MPI into the production kernels
- why: every production kernel wraps get_idx, which is unvalidatable on 1 GPU

### Pre-fix porous coefficient pair kept for A/B only, never for publishable results
- area: flow
- source: porous-eps-conservative-momentum.md:38-39
- decided: undated
- status: settled
- quote: |
    **Gotchas:** (1) the pre-fix pair (buildPorousCoeffDrag etc.) kept for A/B only — never publish with
    it;
- rejected: publishing results computed with the pre-fix (buildPorousCoeffDrag) pair
- why: it is the known-buggy energy-pumping formulation, retained only for A/B comparison

### Precision policy rule: identity-bearing quantities stored in the precision the identity is asserted; ship double-diagonal, not fp64 default
- area: flow
- source: vof-campaign.md:307-312
- decided: 2026-08-31
- status: settled
- quote: |
    **PRECISION POLICY (as a rule, not a patch)**: *a quantity an algorithm requires to satisfy an
      exact discrete identity must be stored in the precision in which that identity is asserted;
      one carrying only an approximation may stay float.* Identity-bearing = the operator DIAGONAL
      in both operators. `PECLET_FLOW_MG_DIAGRESUM=1` ablation recovers full-double behaviour 48³–160³.
      **Recommend shipping double-diagonal (+17 B/cell) — NOT fp64 default (+120 B/cell, +12% time,
      zero gain on Z&H/permeability/regression).**
- rejected: full fp64 default operator storage
- why: "+120 B/cell, +12% time, zero gain on Z&H/permeability/regression"

### Pressure solve must be PCG (Krylov), not RB-GS, for cut-cell IBM
- area: flow
- source: cuda-kokkos-migration.md:352-358
- decided: undated
- status: settled
- quote: |
    CRITICAL FINDINGS: (a) pressure solve MUST be PCG (Krylov), NOT RB-GS — RB-GS leaves smooth modes
    unresolved -> unstable at N>=32 (stable only small N); CUDA single-rank auto-runs MG-PCG
    (last_pressure_iterations=12 not 20). (b) MUST re-mask solid velocity after the grad(phi) correction
    (CUDA apply_mask/mask_k) or decoupled solid velocity accumulates -> blow-up. (c) use standard incremental
    (Goda) pressure P+=（rho/dt)phi; the rotational variant -mu*div(u*) is UNSTABLE in this cut-cell port
    (descale amplification at thin cut cells) and unneeded (PCG -> div~1e-12).
- rejected: RB-GS for pressure; rotational pressure-update variant
- why: "RB-GS leaves smooth modes unresolved -> unstable at N>=32"; rotational variant "UNSTABLE in this cut-cell port (descale amplification at thin cut cells) and unneeded"

### Public API renames: pressure_potential() → pressure() (returns physical pressure)
- area: flow
- source: sdflow-dt-divided-convention.md:36-38
- decided: 2026-06
- status: settled
- quote: |
    **sdflow renames:** `pot_update_k`→`press_update_k`, `sub_gradpot_k`→`sub_gradp_k`,
    `pscale_k`→`press_from_phi_k`, and the public accessor `pressure_potential()`→**`pressure()`** (returns the
    physical pressure p). `phi()`/`phi_` (projection potential) unchanged.
- rejected: the name pressure_potential() for the physical-pressure accessor
- why: none stated beyond disambiguating potential vs physical pressure

### Random-array drag deviation is a genuine method difference, not finite-size or arrangement effects
- area: flow
- source: ibm-accuracy-sphere-validation.md:57-64
- decided: undated
- status: settled
- quote: |
    **DEVIATION INVESTIGATED (commit `8ee8bab`):** the ~+8–13% (vs vdH) / +16% (vs Tenneti) random-array drag
    deviation is **a systematic METHOD difference**, not finite-size or arrangement: (1) ... mean F_d FLAT across N_p=16→256 ... → NOT finite-size;
    (2) ... MD-equilibrated config (g(σ)=1.78 = Carnahan–Starling 1.758, a proper
    equilibrium ensemble) still F_d=4.54, +8% vs vdH → NOT arrangement.
- rejected: finite-size effects and arrangement/crystallization as explanations for the deviation
- why: mean drag is flat across N_p and unchanged under a proper equilibrium (MD) ensemble

---

### Reaction torque leak fix is a closed-form cut-cell moment; adding the pressure moment term makes it worse
- area: flow
- source: sdf-scene-campaign.md:70
- decided: 2026-08-31
- status: settled
- quote: |
    Fix: mu*r×(n dA×Omega) over cut cells with the
    EXACT apertures — closed form, no reconstruction, zero when nothing rotates, force untouched. Gates
    (`rotation_gate.py`): static −31% → **+3.5/+2.4/+2.2% CONVERGING** ... TRAP: a failed repair is recorded —
    adding the pressure moment Σ r×grad(pi) makes it WORSE (−84%); do not re-try.
- rejected: adding the pressure moment Σ r×grad(pi) to close the torque gap
- why: "makes it WORSE (−84%); do not re-try"

### Repair attempts (modes 1–3b) inside the unidirectional IBM all fail to reach 2nd order
- area: flow
- source: sdflow-collocated-solver.md:79-108
- decided: 2026-07-04
- status: settled
- quote: |
    **STRUCTURAL CONCLUSION (the real lesson):** the unidirectional IBM momentum row is FINITE-DIFFERENCE
    (pressure force wants the point ∇p at the cell center) while the cut-cell constraint is FINITE-VOLUME
    (adjointness wants an o-weighted scatter); at cut cells these conflict and NO axis-only (T, force) pair
    satisfies both. Mode 0's wrong-geometry pair is self-consistent + error-compensating → best of the
    axis-only family. 2nd-order collocated requires momentum + constraint to share ONE finite-volume cut-cell
    geometry = the Basilisk embed route — now justified by an exhaustive ablation, not conjecture.
- rejected: mode 1 (wall-anchored weighted-LSQ), mode 2 (transpose pairing), mode 3a (open-centroid, unstable), mode 3b (o-weighted adjoint, stable but worse constant)
- why: "at cut cells these conflict and NO axis-only (T, force) pair satisfies both"

### Report K normalized by superficial velocity (Zick-Homsy convention), not interstitial
- area: flow
- source: ibm-accuracy-sphere-validation.md:110-112
- decided: undated
- status: settled
- quote: |
    **Normalization is the main pitfall** — report K normalized by SUPERFICIAL velocity (=Z&H, →1 dilute); vdH/Beetstra F is INTERSTITIAL so
    K_vdH=F/(1−φ).
- rejected: reporting an interstitial-normalized K without conversion
- why: none stated beyond avoiding the normalization pitfall

### Resolved: the cell-average velocity scheme was a porting bug, not a real discrepancy — point-value is correct
- area: flow
- source: migration-faithful-port.md:31
- decided: 2026-06-19
- status: settled
- quote: |
    **RESOLVED (2026-06-19):** the task-1 ~1% discrepancy was the cell-average velocity scheme (`buildIbmOverlay<1>`)
    vs CUDA's POINT-VALUE (`ibm_geometry_ext_k<0>`, hardcoded in distributed_ns.cuh:999). The `poly_*` matched;
    the deviation was purely the SCHEME selector. Switching to `<0>` + restoring the rotational pressure update
    -> Kokkos matches CUDA to **~1e-13**
- rejected: the cell-average velocity scheme (buildIbmOverlay<1>) as used in the Kokkos port
- why: "the deviation was purely the SCHEME selector"; switching to point-value matches CUDA to ~1e-13

### Richardson extrapolation is ill-conditioned for this dense-bed data; do not rely on a free-parameter fit
- area: flow
- source: ringbed-cfd-surrogate.md:31
- decided: 2026-06-15
- status: settled
- quote: |
    ... order UNCHANGED (per-grid drop ~0.68×, ~+19% at 12.7 cells/wall, k_inf~1.12e-3 geom;
    **Richardson ILL-CONDITIONED** — free-fit→nonsense 4e-4).
- rejected: relying on an unconstrained Richardson-extrapolation fit for k_inf on this data
- why: "free-fit→nonsense 4e-4"

---

### Ring convergence failure was a solver-tolerance artifact, not a cut-cell/geometry limitation
- area: flow
- source: ibm-accuracy-sphere-validation.md:14-30
- decided: undated
- status: superseded
- quote: |
    **The apparent "IBM breaks for rings" was a SOLVER-TOLERANCE ARTIFACT, not the cut-cell.**
    The convergence study stopped the steady-state TIME-MARCH on a loose `Δ⟨u⟩<3e-4·⟨u⟩` criterion (in
    `ibm_shape_diagnostic.solve_k` AND `run_ring_cfd_sdflow.stokes_permeability`), halting before steady state by
    a shortfall that GROWS with resolution ... **Fix = tight tol 1e-6:** Z&H −0.03% at N=192 (clean 2nd order),
    single sphere flat to 0.5% (was spurious 23% drop); ALL single shapes then converge order 1.3–1.85 ...
    **Ring report "first-order +14%" was substantially this artifact — tight-tol ring bed is order ≈1.5.**
- rejected: the earlier conclusion that ring geometry/thin walls caused first-order (+14%) convergence
- why: the loose 3e-4 steady-state stopping criterion halted the march before steady state, a shortfall that grows with resolution and mimics degraded convergence order

### Ring-bed k convergence slowness is intrinsic dense-packing near-contact Stokes stiffness, not a thin-wall/cut-cell IBM defect
- area: flow
- source: ringbed-cfd-surrogate.md:33
- decided: 2026-06-15
- status: superseded
- quote: |
    **(1) k convergence is SLOW (sub-2nd-order) — but it's NEAR-CONTACTS, not the wall or the cut-cell**
    (CORRECTED 2026-06-15 via [[ibm-accuracy-sphere-validation]] IBM diagnostic). ... **A SINGLE hollow
    cylinder converges FINE (order 1.70, 0.2% at 11.5 cells/wall, volume exact ~1e-4) ⇒ ring-bed
    slowness = dense packing near-contact fluid gaps (intrinsic Stokes stiffness, cf RCP φ0.62), NOT
    thin wall/IBM defect.**
- rejected: the initial hypothesis that slow k convergence was caused by the thin wall or the cut-cell IBM discretization
- why: "A SINGLE hollow cylinder converges FINE ... ⇒ ring-bed slowness = dense packing near-contact fluid gaps"
- conflict: this note's own earlier framing (implicit prior suspicion of wall/IBM defect) is what's being corrected here.

### Root cause of the RB-GS stall: update-criterion (max|du| <= rtol*first-sweep-update) chases noise on a warm-started step
- area: flow
- source: momentum-solve-residual-stop.md:8
- decided: undated
- status: settled
- quote: |
    On the FoxBerry packed bed (domain BCs + IBM, nu dt/dx^2 ~ 4e4) the momentum RB-GS hit its
    600-sweep cap every step = 63 % of the step at 384 ranks. Cause: the stop is max|du| <= rtol *
    FIRST sweep's update, and a warm-started near-steady step's first update is already noise.
    Fix (flow telescope branch d6b3eb5 + 3987e08): `set_velocity_residual_tolerance(rtol)`
    (max|b-Au| <= rtol*max(|b|,|Au|); the inflow forcing enters via the ghost, held face excluded):
    96^3: 468 -> 24 sweeps/step.
- rejected: the update-criterion stop (max|du| <= rtol * first sweep's update)
- why: "a warm-started near-steady step's first update is already noise"

### Rung 3 fix: openness-weighted centered gradient replaces plain ½(g⁻+g⁺) projection correction for embed mode
- area: flow
- source: embed-port-progress.md:24-25
- decided: undated
- status: settled
- quote: |
    - mode 6 pre-Rung-3 (embed + plain projection): converges from below but asymptotically O(h) (−2.27→−1.09→−0.48→−0.37→−0.27 at N=32..128) — plain `projectCorrectCenter` uses ½(g⁻+g⁺) with closed faces zeroed = O(h) under-correction at cut cells (analysis defect b).
    - **Rung 3 fix**: Basilisk `centered_gradient` = openness-WEIGHTED cell gradient `(o⁻g⁻+o⁺g⁺)/(o⁻+o⁺)` — at a cut cell with one closed face it uses the OPEN face gradient at FULL weight (not ½). Added `centerGradOpen`/`projectCorrectCenterOpen`; wired into mode 6 for BOTH the incremental −grad(P^n) predictor AND the correction (adjoint pair).
- rejected: plain projectCorrectCenter's ½(g⁻+g⁺) correction (with closed faces zeroed) for the embed-momentum mode
- why: plain ½/½ correction is "O(h) under-correction at cut cells" (defect b); the open-face-only weighting matches Basilisk's centered_gradient

### S-ladder plan; Dodd–Ferrante splitting rejected for the pressure driver
- area: flow
- source: vof-campaign.md:473-479
- decided: 2026-08-30
- status: settled
- quote: |
    Key risk owned: PCG stalls on ρ-scaled coefficients → **S-ladder in plan §5 (2026-08-30,
      user's main concern)**: S0 measure on static manufactured ρ fields (no VoF needed) → S1
      flexible CG → S2 Chebyshev-bound amortization at capillary dt → S3 series-harmonic
      resistor-network coarsening → S4 Galerkin/BoxMG symmetric transfers. [...] Dodd–Ferrante
      splitting rejected (error ~ σκ = the dominant field at pore scale).
- rejected: Dodd–Ferrante splitting for the pressure driver
- why: "error ~ σκ = the dominant field at pore scale"

### S3 coarsening indefiniteness is real, but coarsenOpenAvg must NOT switch to harmonic
- area: flow
- source: vof-campaign.md:253-260
- decided: 2026-08-31
- status: settled
- quote: |
    Cause: `coarsenOpenAvg`'s **arithmetic** face-coefficient
      average (across a 1000:1 jump the coarse coefficient is ~0.5 where ~2e-3 is right). **TRAP: do
      NOT just switch `coarsenOpenAvg` to harmonic** — that same field is the geometric openness on
      the periodic/IBM path. This is the honest reason Chebyshev stays the varRho/porous default.
- rejected: switching coarsenOpenAvg's face-coefficient averaging to harmonic
- why: "that same field is the geometric openness on the periodic/IBM path"

### SdflowIbm MPI requires constructing each rank with local ORB block dims (ctor refactor, not a gated add-on)
- area: flow
- source: cuda-kokkos-migration.md:558-570
- decided: undated
- status: settled
- quote: |
    SdflowIbm MPI = ARCHITECTURAL REFACTOR (not a clean gated add-on, unlike CutcellMG/VelocityMG): SdflowIbm is
    CONSTRUCTED for the grid it operates on -- e_=nx+2G block, the IBM overlay/openness/masks, and the g2<->g1
    pressure bridge are all sized + built at construction/setSolid from (nx,ny,nz). MPI needs decompose-THEN-
    allocate-local (each rank's block dims come FROM the GridHalo decomposition, chicken-and-egg with the ctor).
    ...
    SdflowIbm MPI DONE (commit 47e52c3) = CFD MPI PORT COMPLETE. The refactor was clean after all: each rank
    CONSTRUCTS SdflowIbm with its LOCAL ORB block dims; initMpi(gnx,gny,gnz,comm) builds the g=2 velocity-block
    halo + records og_=block inner origin (global RB parity) + sets distributed_.
- rejected: none stated (this is the resolved architecture, not a rejected alternative)
- why: "CUDA DistributedNS was MPI-first (ctor takes global, decomposes internally) -- the Kokkos SdflowIbm was single-GPU-first, hence the mismatch."

### Sequencing: "VoF vs multiphysics first" dissolves — VoF is the next multiphysics phase
- area: flow
- source: vof-campaign.md:480-484
- decided: 2026-08-30
- status: settled
- quote: |
    **Sequencing answered 2026-08-30**: multiphysics phases 1–8 are DONE (host-openmp); "VoF
      vs multiphysics first" dissolves — VoF IS the next multiphysics phase. [...] NOT on the path:
      VelocityMG varProps, porous ρε inertia, AMR unification.
- rejected: none stated (a false dichotomy dissolved)
- why: none stated

### Sign convention: closed divergence of the corrected field equals Aφ − b = −residual
- area: flow
- source: flow-ghost-projection.md:43
- decided: undated
- status: settled
- quote: |
    Identity: closed div of the corrected field = **Aφ − b = −residual** (sign!).
- rejected: none stated
- why: none stated (sign convention)

---

### Sliver mask must pin only cells with cs<1e-6, not every cell with sdf(center)<0
- area: flow
- source: embed-port-progress.md:27
- decided: undated
- status: settled
- quote: |
    **SLIVER-MASK breakthrough (Rung 4 core)**: `ibmSolidMask`+`maskVelocity` zero every cell with sdf(center)<0 — INCLUDING solid-centred cut cells (cs>0). Correct for mode 0's IBM (no-slip on fluid rows) but WRONG for embed: a partial-fluid cut cell must hold its reconstructed near-wall velocity (e.g. the below-wall extrapolation U9=-0.152). Masking it to 0 leaves the adjacent fluid cell under-constrained → a UNIFORM +0.15 velocity shift on the flat channel (+7% at N=32). Fix (flow_ibm.hpp setSolid, gated faceInterp_>=5): re-mask from cs — pin ONLY cs<1e-6. Flat-wall N=32 went +7% -> ~0 (profile matches analytic to 0.04%). BUT it flips Z&H mode 6 from under-drag (converging) to over-drag increasing (-0.05,+0.29,+0.42 at N=32/48/64) — the live cut cells expose that the plain 1/2-1/2 constraint over-counts curved-wall flux.
- rejected: the mode-0-style mask (zero every cell with sdf(center)<0, including solid-centred cut cells) for embed mode
- why: masking solid-centred cut cells to 0 leaves the adjacent fluid cell under-constrained, producing a uniform +7% velocity shift on a flat channel at N=32

### SolverColocated is the ABC approximate projection, NOT Rhie–Chow — user correction
- area: flow
- source: vof-campaign.md:485-489
- decided: 2026-08-30
- status: settled
- quote: |
    **USER CORRECTION 2026-08-30**: SolverColocated = **ABC approximate projection** (they
      worked hard on it — [[collocated-attractor-campaign]]), NOT Rhie–Chow; never say R-C for
      it.
- rejected: describing SolverColocated's coupling as Rhie–Chow
- why: none stated beyond the correction itself (user built it as ABC)

### Staggered converges onto Zick & Homsy; collocated is bias-dominated (irreducible ~0.9%)
- area: flow
- source: peclet-examples-gallery.md:165-171
- decided: 2026-07-04
- status: settled
- quote: |
    HEADLINE RESULT (frozen, N=16/24/32/40, ~5min CPU
    render): **staggered converges monotonically ONTO Z&H** (−1.74%→−0.18%, fit K∞+C·N^−p gives
    order p≈1.92, K∞=4.299, +0.16% bias); **collocated is BIAS-DOMINATED** — sits ~+0.9% high
    (+0.78/+1.06/+0.99/+0.73%), non-monotone, NO clean power law, K∞≈4.332 (+0.93%), irreducible
    by refinement — confirms [[sdflow-collocated-solver]]'s intrinsic velocity-placement gap.
- rejected: none stated (measurement result)
- why: confirms an intrinsic velocity-placement gap in the collocated scheme
- conflict: collocated-second-order-verdict.md (later campaign shows the plateau is NOT simply "bias-dominated collocated vs exact staggered" — it is a real non-vanishing wall-sourced plateau present with more nuance and multiple exonerated causes)

### Staircase coarse operator (binary classification, no volume-fraction coefficients) is the DEFAULT for the IBM volfrac path, removing the dt ceiling
- area: flow
- source: velocity-mg-design.md:77-98
- decided: 2026-06-17
- status: settled
- quote: |
    ## STAIRCASE coarse operator (2026-06-17, Frank's idea) — DEFAULT; removes the dt restriction
    Frank's variant, now the DEFAULT for the IBM volfrac path (`set_velocity_mg_volfrac(on, eps, res_mask=True,
    staircase=True)`): keep the fine-level IBM residual exclude (clean-fluid `res_mask`) AND **on the coarse levels
    use the volume fraction ONLY to CLASSIFY** cells — θ≥0.5 fluid, θ<0.5 solid — then build a **plain
    constant-coefficient Helmholtz** (per-axis β, `mg_build_velocity_op_staircase_k`) at fluid cells with the solid
    cells **pinned to 0** (a first-order staircase no-slip). **The volume/area fractions are NOT used as
    coefficients** (that was the area-fraction op; weak partial-cell coupling limited it). ... **Result (SC sphere): exact (== RB-GS, 0.000%) and stable to dt=6400
    (β=640) at φ=0.216 AND φ=0.5236** — vs area-fraction dt≤400, const-coarse dt≤200. Essentially no practical dt
    restriction; V-cycle ρ≈0.23. The const-coarse failure (coupling fluid pockets through thin walls) is fixed by
    the binary classification disconnecting pockets across resolved walls.
- rejected: the volume-fraction-weighted (area-fraction) coarse operator as coefficients; the plain const-coeff coarse op without staircase classification
- why: "weak partial-cell coupling limited" the area-fraction op; binary classification "disconnect[s] pockets across resolved walls" whereas const-coarse coupled fluid pockets through thin walls

### Staircase is consolidated as the ONLY IBM velocity-MG coarse op — const and area-fraction paths removed from the code
- area: flow
- source: velocity-mg-design.md:100-116
- decided: 2026-06-17
- status: settled
- quote: |
    ## CONSOLIDATED (2026-06-17) — staircase is the ONLY IBM coarse op; const + area-fraction REMOVED
    Cleanup commit: the staircase is now the IBM velocity-MG coarse operator, reached directly via
    `set_velocity_multigrid(on, levels, vcycles)` + `set_ibm_solid` (the `set_velocity_mg_volfrac` toggle and the
    `vmg_volfrac_`/`vmg_staircase_`/`vmg_eps_` flags are GONE). Removed: `setDiffusionCoarse` +
    `mg_const_diffusion_op_k` (geometry-blind const-coarse for IBM), `setVelocityVolfracCoarse` +
    `mg_build_velocity_op_areafrac_k` + `ibm_areafrac_k` + the fine area-fraction fields, `mg_restrict_volwt_k` +
    the `vel_mask_xfer_` experiment. KEPT: `setVelocityStaircaseCoarse`, `mg_build_velocity_op_staircase_k`,
    `mg_threshold_mask_k`, `MGLevel::pin` + the smoother/residual `pin` arg, the clean-fluid exclude
    (`ibm_clean_fluid_mask_k`/`mg_mul_mask_k`/`mg_prolong_masked_k`), `vfine_`/`vresmask_`/`vtheta_lvl_`/`vpin_lvl_`.
    Domain-BC const-coeff (cavity/BFS, `setDiffusionConstAllLevels` + `mg_const_diffusion_op_aniso_k`) and the
    upwind-convective (`build_vmg_adv_stencil`) paths are SEPARATE and untouched.
- rejected: geometry-blind const-coarse (setDiffusionCoarse) and area-fraction (setVelocityVolfracCoarse) IBM coarse operators — both deleted from the code
- why: staircase superseded both in accuracy and dt-stability (see prior entries)

### Stale-ghost pressure V-cycle bug invalidated the entire published parallel-scaling page's peclet numbers
- area: flow
- source: parallel-scaling-study.md:206-213
- decided: 2026-08-09
- status: superseded
- quote: |
    **⚠ ALL PECLET NUMBERS ON THE PUBLISHED PAGE ARE NOW STALE (2026-08-09, flow 5d77deb).** The
    pressure V-cycle restricted a residual computed with one-colour-stale ghosts; fixing it made
    pressure iteration counts decomposition-independent AND ~2× lower.
- rejected: the pre-fix pressure iteration counts and all derived peclet-vs-reference ratios on the published page
- why: the V-cycle was restricting a residual computed with stale (one-colour-old) ghost values

---

### Star half fix: phibar mean was not bitwise-annihilating even in double — replaced by flux form
- area: flow
- source: defect-correction-campaign.md:52-54
- decided: 2026-09-02
- status: settled
- quote: |
    Star half LANDED (flow 7fb80e0):
    **`phibar = Sum(a*x)/Sum(a)` was NOT bitwise-annihilating even in double** — the two sums round
    independently — so the star delta leaked into A*1 regardless of aperture precision, INDEPENDENT of P1;
    fixed by the flux form `(a_k/D)*Sum_j a_j (x_k - x_j)`.
- rejected: the phibar=Sum(a*x)/Sum(a) formulation
- why: "the two sums round independently — so the star delta leaked into A*1"

### Strict staggered bit-identical guard must be held through every change; AMR must work for both velocity placements or be explicitly scoped
- area: flow
- source: sdflow-octree-amr-next.md:19-20
- decided: undated
- status: settled
- quote: |
    Two velocity placements via the `GridLayout` policy (`src/grid_layout.hpp`): staggered MAC vs collocated —
    see [[sdflow-collocated-solver]]. Any AMR must work for both (or be scoped to one and keep the other
    bit-identical — the project has held a strict staggered bit-identical guard through every change).
- rejected: none stated
- why: the project has held a strict staggered bit-identical guard through every change; a design that can't work for both must not break it

---

### Success criterion for any A·1=0 repair: match the full-double floor, never demand rtol 1e-8
- area: flow
- source: vof-campaign.md:413-427
- decided: 2026-08-31
- status: superseded
- quote: |
    **Consequences: (1)** the honest success criterion for double-diagonal/any A·1=0 repair is
      "floor ≤ the full-double floor at MATCHED config", never "reaches rtol 1e-8" — evaluating
      against 1e-8 would REJECT A CORRECT FIX (I had written exactly that wrong criterion into
      WO-M and corrected it mid-flight).
- rejected: judging a precision fix by whether it reaches rtol 1e-8
- why: "a full-double hierarchy still floors at r/r0 ≈ 3–4e-8... the classical CG attainable-accuracy limit"

### Superseded same-day decision: residual stop default was fixed at 1e-5
- area: flow
- source: momentum-solve-residual-stop.md:32
- decided: 2026-09-02
- status: superseded
- quote: |
    **Decided 2026-09-02 (user):** residual stop is the DEFAULT (1e-5; regression suite passes,
    metrics +0.00 %, steady-state runs need 5-20 % more steps); the const-coeff domain-BC smoother
    got its residual (`diffResidual`); AUTO velocity MG under MPI below
    PECLET_FLOW_VMG_AUTO_CELLS=65536 cells/rank and np>1 (flow telescope branch c600d79/500a9d8).
- rejected: none stated (this decision was itself superseded later the same day by the rtol-following default)
- why: "regression suite passes, metrics +0.00 %, steady-state runs need 5-20 % more steps"

### TRAP: -DPECLET_FLOW_MREAL_DOUBLE=ON on the cmake command line silently builds float
- area: flow
- source: defect-correction-campaign.md:45-46
- decided: 2026-09-01
- status: settled
- quote: |
    **TRAP:** `-DPECLET_FLOW_MREAL_DOUBLE=ON` on the cmake line SILENTLY BUILDS FLOAT (symbol is in no
    CMakeLists/preset -> uninitialized cache var). Correct form: `-DCMAKE_CXX_FLAGS=-DPECLET_FLOW_MREAL_DOUBLE`.
- rejected: passing -DPECLET_FLOW_MREAL_DOUBLE=ON as a normal cmake cache variable
- why: "symbol is in no CMakeLists/preset -> uninitialized cache var"

### Telescoping is default on for the pressure MG since 2026-09-02; the velocity solve does not need it
- area: flow
- source: momentum-solve-residual-stop.md:18
- decided: 2026-09-02
- status: settled
- quote: |
    **Why:** the user asked to "improve the velocity solve" and whether it needs telescoping. It
    does NOT: 2/3/5 levels identical (pore-confined problem). Telescoping is DEFAULT ON for the
    pressure MG since 2026-09-02.
- rejected: telescoping the velocity solve
- why: "2/3/5 levels identical (pore-confined problem)"

### Ten-Cate periodic-image bug: periodic images are a union, not independent slabs
- area: flow
- source: sdf-scene-campaign.md:131
- decided: 2026-09-02
- status: settled
- quote: |
    **2026-09-02 — ten-cate CLOSED, §7 item 11 (periodic images are a UNION):** the whole "creeping-valued
    confined drag / sharpest open defect" story was a CSG slab wider than the periodic box refilling its own
    cavity (tank 30% narrow). Corrected: E1 −2.6%, E4 +1.8% at d/h=8.
- rejected: the earlier CSG-slab-per-image geometry construction (implicitly non-union)
- why: "a CSG slab wider than the periodic box refilling its own cavity (tank 30% narrow)"

### The 47%-at-8-GPU "reduction tax" diagnosis is stale, superseded by 2026-08 solver fixes
- area: flow
- source: snellius-parallel-benchmark-campaign.md:25-27
- decided: 2026-08-10
- status: superseded
- quote: |
    **SUPERSEDED IN PART (2026-08-10):** the measured baseline below predates the 2026-08 solver fixes
    (esp. the stale-ghost MG residual, which made V-cycle convergence decomposition-dependent) — the
    47%@8-GPU "reduction tax" diagnosis is stale. Re-benchmark planned: see [[channel-scaling-rebenchmark]].
- rejected: the "inter-node pressure-solve reduction tax" explanation for the 47% weak efficiency at 8 GPU
- why: the baseline predates the stale-ghost MG residual fix, which made V-cycle convergence decomposition-dependent

### The agglomerated-bottom MG anomaly required a per-fluid-component null-space projector, a double row-sum, and a looser inner tolerance
- area: flow
- source: agglomerated-bottom-ibm-fix.md:15
- decided: 2026-08-13
- status: settled
- quote: |
    **Root causes, in order of severity (all measured, not guessed):**
    1. `pcgAmg::meanZero` projected the ALL-cell mean; the true null space is one constant per connected
       FLUID component (solid cells are identity rows)... Fix: [per-component projector].
    2. MG level coefficients are float (`MReal`) → assembled double CSR had fluid row sums ~5e-8
       relative instead of 0 → near-null vector off the assumed constant... Fix: on the singular path
       (removeMean_) resum each fluid diagonal in double = −Σ off-diags (exact by construction...).
    3. Inner tol 1e-10 is at/below the double floor of the projected solve; parity already held at
       1e-5. Now 1e-8, cap 100 (~7 median iters).
- rejected: projecting the all-cell mean (rather than per-connected-fluid-component); leaving MG coefficients in single-precision row sums uncorrected; an inner tolerance of 1e-10
- why: all three measured directly (per-iteration trace signature, row-sum defect measurement, floor comparison)

### The defect-correction rule: Krylov matvec/residual must be the exact double operator in flux form; preconditioners below may stay float
- area: flow
- source: defect-correction-campaign.md:14-17
- decided: 2026-09-01
- status: settled
- quote: |
    **The rule:** Krylov matvec + residual = exact double operator in FLUX form (A·1=0 bitwise); V-cycles/
    smoothers/AMG below are preconditioners and may stay float. User's proposal; Fable's evaluation found
    no outer loop is needed — PCG already separates `matvec`/`precond` lambdas, only `matvecOverlap`
    (`mac_cutcell_mg.hpp:1715`) reads the float bands
- rejected: none stated (this is the adopted rule)
- why: "PCG already separates matvec/precond lambdas"

### The earlier "staircase not suited for packed materials" caveat is retracted
- area: flow
- source: velocity-mg-design.md:90-98
- decided: undated
- status: superseded
- quote: |
    **PACKED-BED VALIDATED** (`scripts/verify_velocity_mg_staircase_packing_sdflow.py`, random periodic sphere
    packings): on a moderate bed (21 sph, φ=0.245, N=64) staircase is exact (0.000%) and stable at dt=800 where
    const (0.19% biased→NaN) and area-fraction (NaN) both fail; on a DENSE thin-neck bed (53 sph, φ=0.29, ~1-cell
    necks, N=128) staircase is exact (0.000–0.010% vs RB-GS) and stable to **dt=3200 (β=320)** with 16 V-cycles
    (the ceiling rises with V-cycle count; thin necks lower it vs the SC sphere's dt=6400). Exact across coarsening
    levels 2–6 (the answer is correct regardless of depth — fine smoother + exclude mask own the boundary; deep
    coarsening only affects rate, so the `levels` cap is a tuning knob, not a correctness requirement). **⇒ the
    earlier "not for packed materials" caveat is RETRACTED: the staircase velocity-MG handles packed beds, exact
    and stable to very large dt.**
- rejected: the earlier belief that staircase velocity-MG doesn't suit packed materials
- why: measured exact + stable results on moderate and dense thin-neck packed beds

### The rotational (Timmermans) pressure update must be restored, not the non-rotational Goda form substituted
- area: flow
- source: migration-faithful-port.md:61
- decided: undated
- status: settled
- quote: |
    **Concrete violation to undo (task 1, cut-cell pressure, commit 290f8a4):** I changed the incremental
    pressure update from CUDA's ROTATIONAL form (`P += (rho/dt)*phi - mu*div(u*)`, Timmermans) to the
    non-rotational Goda form (`P += (rho/dt)*phi`), and substituted a diagonal-preconditioned CG for CUDA's
    geometric MULTIGRID / MG-PCG pressure solve, and stored the pressure operator in double instead of CUDA's
    float `mreal`. Result: k_Kokkos=5.798 vs k_CUDA=5.836 (~0.65%, stable under heavy convergence -> a genuine
    method difference). MUST re-port faithfully: CUDA's mac_multigrid.cuh MGPoisson ... + the rotational
    pressure update.
- rejected: non-rotational Goda pressure update form; diagonal-preconditioned CG in place of geometric MG/MG-PCG; double-precision pressure operator storage
- why: "Result: k_Kokkos=5.798 vs k_CUDA=5.836 (~0.65%, stable under heavy convergence -> a genuine method difference)"

---

### The standalone V-cycle pressure driver does not honor set_pressure_solver_params(n) and is ~30x slower at small grids
- area: flow
- source: flow-thermal-convection-validated.md:25
- decided: undated
- status: settled
- quote: |
    2. The standalone V-cycle driver (no PCG/Chebyshev) is ~30× slower than capped PCG at small grids
       and `set_pressure_solver_params(n)` doesn't change its work — n_pois appears not honoured on
       that path.
- rejected: none (this documents a bug/limitation, not a chosen alternative)
- why: none stated beyond the observed behavior (n_pois not honoured on that driver path)

---

### The ten-cate confined-flow deficit was a geometry (oversized periodic slab) bug, not a solver/advection defect
- area: flow
- source: advective-cutwall-flux-plan.md:49
- decided: 2026-09-02
- status: superseded
- quote: |
    **CLOSED 2026-09-02 — the deficit was GEOMETRY:** the ten-cate tank slab (`NX*0.7`) was wider than
    the periodic box; the scene query takes the MIN OVER 27 IMAGES (union), so the slab's images
    refilled the cavity: 38-cell duct instead of 53 (d/W 0.21 vs 0.15 → Faxén K≈1.67 = exactly the
    measured effective K). Corrected tank at d/h=8: E1 0.922 vs 0.947, E4 0.972 vs 0.955, physical
    falls.
- rejected: the hypothesis that the deficit was caused by the advective cut-wall flux / aperture weighting (A1), or by precision/momentum-convergence issues
- why: "the slab's images refilled the cavity ... d/W 0.21 vs 0.15 → Faxén K≈1.67 = exactly the measured effective K"
- conflict: supersedes the earlier framing in this same note ("ten-cate did NOT recover", advective-cutwall-flux-plan.md:26) that treated it as an open solver-physics deficit.

### The ~0.3% collocated accuracy "plateau" is not a truncation ceiling — it is an instability + an invisible pressure-subspace attractor family
- area: flow
- source: collocated-attractor-campaign.md:11
- decided: 2026-08-21
- status: superseded
- quote: |
    **State 2026-08-21** (supersedes [[collocated-second-order-verdict]] — the ~0.3% "plateau" is NOT
    a truncation ceiling): two-layer mechanism found and measured. (1) Guy–Fogelson PM-II instability
    of the rotational update on the cell-centered approximate projection ... (2) ROOT CAUSE of the
    residual bias: **invisible pressure subspace** — gpCenterGrad never reads solid-centered P but the
    aperture operator couples those DOFs (α>0 faces), so u-stationarity only needs the P-increment ∈
    ker(G) ⇒ an affine FAMILY of steady states...
- rejected: the earlier "collocated-second-order-verdict" conclusion that ~0.3% was a truncation-order ceiling
- why: measured two-layer mechanism (PM-II instability + invisible pressure subspace / attractor family) fully explains the residual bias
- conflict: collocated-second-order-verdict.md (explicitly named as superseded; not in this slice)

### UCX_RNDV_THRESH tuning is falsified as an explanation for the np8 anomaly — leave UCX defaults
- area: flow
- source: comm-scaling-plan.md:57
- decided: 2026-08-18
- status: settled
- quote: |
    UCX_RNDV_THRESH=256k = 2x WORSE (36.1)
    -> threshold hypothesis FALSIFIED, leave UCX defaults.
- rejected: tuning UCX_RNDV_THRESH=256k
- why: "2x WORSE (36.1)"

### User decision: port Basilisk embed.h, not Trebotich–Graves, for 2nd-order collocated walls
- area: flow
- source: sdflow-collocated-solver.md:186-191
- decided: 2026-07-05
- status: settled
- quote: |
    USER DECISION 2026-07-05: copy Basilisk (not Trebotich–Graves — same core reconstruction, far more
    extractable, its flux-redistribution rigor targets an explicit small-cell-CFL problem we don't have in
    the Stokes regime; T–G kept only as a pore-scale-validation reference + a later add-on if we need strict
    discrete conservation through pores).
- rejected: Trebotich–Graves/EBChombo as the primary port target
- why: "far more extractable, its flux-redistribution rigor targets an explicit small-cell-CFL problem we don't have in the Stokes regime"

### User directive: ghost-cell IBM must become production-grade (it generalizes to AMR better than cut-cell)
- area: flow
- source: ghost-hardening-plan.md:11-14
- decided: 2026-08-17
- status: settled
- quote: |
    Frank's directive (2026-08-17): ghost-cell IBM must become production-grade — it generalizes
    to AMR better than cut-cell (its closure cascade is ALREADY lifted into
    `peclet::core::scheme::ghost_closure`, shared verbatim with core's octree AMR band). Plan:
    `flow/doc/ghost_hardening_plan.md` (flow 31a4675).
- rejected: none stated (cut-cell is the implicit alternative, not rejected outright, but ghost is directed to be hardened)
- why: ghost-cell IBM "generalizes to AMR better than cut-cell"

### V-cycle stale-ghost bug made MG convergence decomposition-dependent; fixed, now iteration count is decomposition-independent
- area: flow
- source: channel-scaling-rebenchmark.md:67-73
- decided: undated (commit 5d77deb)
- status: settled
- quote: |
    **`5d77deb` the decisive one: the V-cycle residual read STALE ghosts, so the coarse-grid rhs was
    wrong on the whole block-boundary shell → the V-cycle's convergence rate DEPENDED ON THE
    DECOMPOSITION.** Post-fix, iteration counts are decomposition-independent and ~2× lower. Any
    weak-scaling curve measured before this is contaminated: what looked like a communication tax
    was partly the iteration count creeping up with rank count.
- rejected: reading stale ghosts in the V-cycle residual
- why: caused convergence rate to depend on decomposition, contaminating prior weak-scaling measurements

### Variable-viscosity rotational correction stays incremental (constant-μ) under varProps, not full pointwise
- area: flow
- source: multiphysics-framework-plan.md:397
- decided: undated (P4)
- status: settled
- quote: |
    **Incremental-rotational KEPT under varProps** (user requirement: large-dt/steady-Stokes; dt=100
    conv@200): Timmermans −μ∇·u* is homogeneous-μ-only (Deteix & Yakoubi AML 2018 / arXiv:1902.05643) →
    rotational coeff defaults to constant χ·μ_min (stable by domination, exact uniform-μ fallback);
    `set_variable_rotational('min'|'full'|'off',chi)`; 'full' pointwise diverges at 10× contrast; full
    shear-rate projection ... = deferred upgrade.
- rejected: 'full' pointwise variable-μ rotational correction
- why: "'full' pointwise diverges at 10× contrast"; user requirement for large-dt/steady-Stokes stability

---

### Velocity domain BCs must be applied before divergence in project()
- area: flow
- source: cuda-kokkos-migration.md:332-335
- decided: undated (channel WIP session)
- status: settled
- quote: |
    CHANNEL DONE (2370f27, verify_channel.py: max|du|/maxu=8.9e-16 vs CUDA, outlet u_max/U_mean=1.4948): the 3rd
    open-BC bug was that the velocity domain BCs (outflow zero-gradient) must be applied BEFORE the divergence in
    project()/maxOpenDivergence() (CUDA apply_velocity_bc before diverg_open_k) -- else div(u*) mis-counts the
    outflow and the rotational -mu*div pumps the outflow-wall corner. Fixed via fillVelGhosts(c,0) before divOpen.
- rejected: applying divergence before the velocity domain BCs
- why: "else div(u*) mis-counts the outflow and the rotational -mu*div pumps the outflow-wall corner"

### Velocity masking must be OFF with the cut-cell pressure operator
- area: flow
- source: suite-distributed-status.md:94-95
- decided: undated (Step 19, commit 30df260)
- status: settled
- quote: |
    **velocity masking must be OFF** with the cut-cell operator
    (masking zeros partially-open solid faces post-projection → reintroduces divergence).
- rejected: masking velocity with the cut-cell operator active
- why: masking zeros partially-open solid faces post-projection, reintroducing divergence

### Velocity-diffusion MG rediscretization diverges; velocity RB-GS is the exact default
- area: flow
- source: suite-distributed-status.md:291-296
- decided: undated (MG Phase 2)
- status: settled
- quote: |
    **MG Phase 2 (commit d0e6928):** ... Velocity-diffusion MG rediscretization ATTEMPTED and DIVERGES (the
    Robust-Scaled fine stencil is row-scaled by D_rescale → inconsistent with a clean I-βL coarse op under
    geometric transfers; staggered velocity geom ≠ cell-face openness) → reverted to const-coeff coarse;
    **velocity RB-GS is exact and the default** (velocity is the easy non-singular operator; proper velocity
    MG = deferred research).
- rejected: rediscretized velocity-diffusion multigrid coarse operator
- why: the Robust-Scaled fine stencil's row scaling is inconsistent with a clean coarse operator under geometric transfers

### Viscous term left plain (not epsilon-weighted) — a deliberate, documented scope choice
- area: flow
- source: porous-eps-conservative-momentum.md:31
- decided: 2026-07-12/13
- status: settled
- quote: |
    - Viscous term left plain μ∇²u (ε-weighting is next-order for a thin gas; documented).
- rejected: epsilon-weighting the viscous term
- why: it is next-order for a thin gas

### VoF execution model: no new submodule, kernels live in flow/src/vof/
- area: flow
- source: vof-campaign.md:491-496
- decided: 2026-08-30
- status: settled
- quote: |
    **Execution model (2026-08-30, plan §11)**: NO new submodule — VoF in `flow/src/vof/`
      (extraction trigger: kernels → core if AMR/others consume). [...] Escalation rule: twice-failed
      gate = stop + findings log, never tweak numerics to pass.
- rejected: a new submodule for VoF
- why: none stated (extraction to core is conditional on future multi-consumer need)

### WO-H fix: CutcellMG::applyNeumannGhost; PCG selector now throws (MG-PCG is the terminal fallback)
- area: flow
- source: vof-campaign.md:236-251
- decided: 2026-08-31
- status: settled
- quote: |
    Fix
      `CutcellMG::applyNeumannGhost` (:601), ablation `PECLET_FLOW_MG_BCGHOST=0`. [...] Selector fixed too; `set_pressure_pcg(False)`
      now throws (MG-PCG is the terminal fallback).
- rejected: none stated
- why: "Proof of intent: **`VelocityMG` always did both halves**... the pressure MG only ever got the Dirichlet half"

### WY advection CFL default corrected to Weymouth's proven 3D bound 0.25
- area: flow
- source: vof-campaign.md:128-130
- decided: 2026-08-30
- status: settled
- quote: |
    Fable corrections on top: WY CFL default → Weymouth's PROVEN 3D bound 0.25 (the famous
      "CFL<0.5" is his 2D value, thesis eq. A.33), inclusive comparison (flow af8d6f1).
- rejected: CFL<0.5 (Weymouth's 2D value, mistakenly applied to 3D)
- why: "the famous 'CFL<0.5' is his 2D value, thesis eq. A.33"

### Wall-band "1/h amplitude growth" was a unit artifact, not a real localization signal
- area: flow
- source: collocated-second-order-verdict.md:36-39
- decided: undated
- status: superseded
- quote: |
    - Wall-band localisation: test failed 3 ways — the "1/h amplitude growth" was a UNIT ARTIFACT
      (cell-unit runs have ⟨u⟩∝R²; normalised, near-wall diff DECAYS ~h^0.5–1; Frank caught it);
      band share crosses a zero of ⟨ΔFlux⟩ at R≈16; elliptic smearing means response-localisation
      ≠ cause-localisation anyway.
- rejected: the "1/h amplitude growth" reading as evidence of wall-band localization
- why: it was a unit artifact of cell-unit runs (⟨u⟩∝R²); properly normalised, the near-wall difference decays

### Weak efficiency must be computed from per-GPU throughput, not raw step time
- area: flow
- source: channel-scaling-rebenchmark.md:208-209
- decided: undated
- status: settled
- quote: |
    - cells/GPU can't be constant (3-D power-of-2 refinement moves cells in 8× steps) → ±8 % →
      **weak efficiency computed from PER-GPU THROUGHPUT**, which corrects it exactly.
- rejected: computing weak efficiency directly from step time when cells/GPU varies ±8%
- why: 3-D power-of-2 refinement can't hold cells/GPU exactly constant

### Weak-scaling ladder must refine a fixed physical box, not grow box length at fixed cross-section (methodology correction)
- area: flow
- source: channel-scaling-rebenchmark.md:156-168
- decided: 2026-08-10
- status: superseded
- quote: |
    **★★ ROOT CAUSE FOUND 2026-08-10 (user's question: "how do the settings compare to the example?") —
    MY WEAK LADDER WAS THE WRONG ONE. `refine` mode is the fix (peclet-examples 70a0704).**
    - The production script `examples/wall-bounded-turbulence/snellius_gpu.slurm` scales the DNS by
      **REFINING A FIXED PHYSICAL BOX** 4πH×2H×(4/3)πH: `GNX=round(2π·GNY)`, `GNZ=round(2π/3·GNY)`,
      Δ+=360/GNY. Its presets: GNY=240 (Δ+1.5, 182 M) 1 node, 288 (314 M) 2 nodes, 360 (614 M) 3 nodes.
      **More GPUs buy a FINER DNS of the same channel — never a longer one.**
    - My sweep froze the cross-section and grew GNX only → aspect x/y went **1.6 → 51** vs the physical
      **6.3**; at np1 the box was a QUARTER of the MKM length, at np32 EIGHT TIMES it (Lx+ 18432).
      Pressure iters track the elongation, not the rank count...
- rejected: growing GNX only at a fixed cross-section to weak-scale the channel (my original sweep)
- why: elongation (aspect 1.6→51 vs physical 6.3) made pressure iterations track box elongation, not rank count — an invalid weak-scaling measurement

### What was disproved in the agglomerated-bottom investigation
- area: flow
- source: agglomerated-bottom-ibm-fix.md:29
- decided: 2026-08-13
- status: settled
- quote: |
    **What was disproved:** solid-rhs deposits from restriction (measured exactly 0 — fine solid
    residuals are identically 0 and every child of the bottom's solid cells was solid); sliver rows
    from the `dc != 0.0` vs `ac < 1e-30` threshold mismatch (no tiny diags in practice — but the
    mismatch still exists in code); multi-component pockets on random_spheres (1 component; the
    per-component projector matters for other geometries/coarser bottoms).
- rejected: solid-rhs deposit contamination, sliver-row threshold mismatch, and multi-component pockets as causes for THIS case
- why: each measured directly and found not to be the (or a significant) contributor on random_spheres

### bcStencilPath() and implicitAdv() must agree with the actual solver in use
- area: flow
- source: momentum-solve-residual-stop.md:21
- decided: undated
- status: settled
- quote: |
    (1) `bcStencilPath()` and `implicitAdv()` decide RHS treatment AND
    the advection scheme — they must agree with the solver used; turning the MG on used to flip
    advection to explicit (two 1e-11-converged solves 3e-4 apart = different equation, not a
    solver bug).
- rejected: none stated
- why: "two 1e-11-converged solves 3e-4 apart = different equation, not a solver bug"

### cylinder-vortex-street dropped from the gallery; confirmed flow bug pins the fix location
- area: flow
- source: peclet-examples-gallery.md:106-118
- decided: undated
- status: settled
- quote: |
    `cylinder-vortex-street`
    DROPPED — CONFIRMED peclet.flow bug: immersed solid + inflow/outflow broken 3 ways:
    (a) `set_pressure_geometry()` after `set_solid()` SILENTLY WIPES the solid (order-
    dependent, →uniform flow no wake); (b) `cutcell_pressure=False` leaks no-slip (|u|~0.6
    inside solid); (c) `cutcell_pressure=True`+inflow/outflow → NaN. ... **NEXT session: (a) fix inflow/outflow+solid in peclet.flow (localized
    to setSolid openness composition, flow_ibm.hpp ~340-377); (b) ship cylinder wake via
    periodic body-force on GPU (D~30-40, probe wake FFT for St); (c) render BFS on GPU.**
- rejected: shipping a sub-resolution "steady" wake result (would misrepresent physics)
- why: three concrete bugs in immersed-solid + inflow/outflow composition; a low-res wake would misrepresent physics (real cylinder sheds by Re47)

### fillPorousEpsGhosts: mirror-around-1 at inflow/outflow, zero-gradient at walls — one policy for RHS/coeffs/residual
- area: flow
- source: porous-cfddem-cuda-two-bugs.md:36
- decided: 2026-07-09
- status: settled
- quote: |
    FIX: `fillPorousEpsGhosts()` = ONE policy for RHS/coeffs/residual: mirror-around-1 at inflow/outflow (face-mean eps == 1: prescribed inflow velocity IS the superficial velocity — Kuipers/MFIX distributor contract), zero-gradient at walls; called BEFORE divergOpenEps in project() + in maxPorousResidual.
- rejected: reading eps ghosts in three different states across RHS/coeffs/residual
- why: "prescribed inflow velocity IS the superficial velocity — Kuipers/MFIX distributor contract"

### flow's grid is isotropic unit spacing with no wall-normal stretching
- area: flow
- source: channel-dns-isotropic-grid.md:14
- decided: undated
- status: settled
- quote: |
    `flow` uses **isotropic unit spacing dx=dy=dz=1**, NO stretching (`flow_bindings.cpp:472` `get_spacing`
    "always unit on this grid"; RB example line 117 "Grid units: dx=1"). Physical scale enters only via ν,
    f, dt and cell counts. So you CANNOT coarsen wall-parallel independently of wall-normal → channel grid
    is isotropic in wall units.
- rejected: wall-normal grid stretching
- why: "none stated" (stated as a hard solver constraint)

### get_ox/oy/oz are openness fields, not origin aliases — NAMING.md correction
- area: flow
- source: suite-quality-plan-1-0-0.md:101-102
- decided: 2026-09-08
- status: superseded
- quote: |
    **Traps found:** flow `get_ox/oy/oz` are OPENNESS FIELDS, not origin aliases (NAMING had it
    wrong; gallery uses them as arrays).
- rejected: NAMING.md's earlier classification of get_ox/oy/oz as origin aliases
- why: "gallery uses them as arrays"

### poiseuille-ibm reframed: flat-wall cut-cell IBM is pointwise exact, not a 2.8% error case
- area: flow
- source: peclet-examples-gallery.md:48-50
- decided: undated
- status: superseded
- quote: |
    1. `poiseuille-ibm` — flat-wall cut-cell IBM is POINTWISE EXACT (~1e-7, both meshes);
       the old "2.8% error" was a metric artifact (u.max vs continuum peak; walls at
       half-integer put the centre between nodes). Reframed as an exactness demo.
- rejected: the old "2.8% error" framing of flat-wall cut-cell IBM accuracy
- why: it was a metric artifact (comparing u.max vs continuum peak, with walls at half-integer nodes)

### rtol rule: max(1e-8, C·eps·0.18N²·Δρ/ρ) — later re-stated as a lower bound, not an achievability guarantee
- area: flow
- source: vof-campaign.md:289-292, 319-327
- decided: 2026-08-31 / 2026-09-01
- status: superseded
- quote: |
    **κ(A) ≈ 0.18·N²·contrast** (×4 wall-bounded), exactly linear in contrast, quadratic in N.
      ⇒ ratio 1000 @256³: κ≈1.2e7, fp64 limit ~1e-9, so **a fixed rtol 1e-8 is already near the
      arithmetic limit and impossible at 512³ or ratio 1e4**. Use
      `rtol = max(1e-8, C·eps·0.18N²·Δρ/ρ)`.
    ---
    **⚠ κ CLOSURE HAS A VALIDITY BOUNDARY (2026-09-01): holds 192³–384³, BREAKS BY 768³.** [...]
      **CONSEQUENCE FOR US: our `rtol = max(1e-8, C·eps·0.18N²·Δρ/ρ)` rule inherits this — it is a
      lower bound on what to DEMAND, not a prediction of what is ACHIEVABLE. Above ~384³ measure
      the attainable residual; never use the law to dismiss a measured floor.**
- rejected: treating the κ formula as a prediction of achievable residual at all N
- why: "their 768³ probe floored at 3e-4 = 3 orders above the eps·κ prediction"

### sdflow accuracy resolved; default cut-cell RB-GS path matches Zick & Homsy; velocity-MG (not pressure) was the drift source
- area: flow
- source: suite-distributed-status.md:268-283
- decided: 2026-06-11
- status: superseded
- quote: |
    **(c) Accuracy: RESOLVED (2026-06-11) — both codes are CORRECT.** ... **sdflow's DEFAULT path (`galerkin=False`, direct cut-cell RB-GS pressure) matches Z&H
    to <0.05% at N=128 across φ=0.064–0.343, clean grid convergence, agreeing with pnm to 4 digits.**
    sdflow's cut-cell IBM is correct & grid-convergent. **CORRECTION (2026-06-11, later same day): the
    "+4% drift at N=128" is the VELOCITY-diffusion multigrid, NOT the pressure.** I first blamed the
    Galerkin *pressure* path, but it was a confound — every drifting run also had `set_velocity_multigrid`
    on. Isolating one solver at a time on the SC sphere at N=128 (Z&H K=4.292): velocity RB-GS +
    pressure-{RB-GS, const-MG, Galerkin-MG, rediscretized-MG} **ALL give 4.292** ... but
    **velocity-MG + pressure-RB-GS gives 4.4415 (+3.5%)**.
- rejected: the earlier attribution of the +4% drift to the Galerkin pressure path
- why: isolating solvers showed the pressure coarse operator only changes iteration count; the defect was in `setDiffusionCoarse`'s geometry-blind const-coeff velocity coarse operator

### sdflow-vs-pnm_backend "efficiency gains" correction — internal only, not a real speed gap
- area: flow
- source: suite-distributed-status.md:264-269
- decided: 2026-06-11
- status: superseded
- quote: |
    **sdflow vs pnm_backend reality-check (2026-06-11, doc `cfd-gpu/doc/sdflow_pnm_parity.md`).** IMPORTANT
    corrections: (a) the big "efficiency gains" reported during sdflow development (reductions ~96×, etc.)
    were **sdflow-internal**, NEVER vs pnm_backend — don't imply sdflow beats production from those. (b)
    **Speed is NOT a real gap:** with the SAME numerics (simple RB-GS, no MG/PCG) sdflow ≈ pnm_backend
    (16.1 vs 15.4 ms/step); the 1.5–3× "slowdown" I'd shown was sdflow's over-engineered defaults
    (Galerkin MG + PCG to rtol=1e-9 *every* step — absurd for a steady march).
- rejected: implying sdflow's internal speedups meant it beat production pnm_backend
- why: the 1.5-3x apparent slowdown was sdflow's own over-engineered defaults, not a real numerics gap
- conflict: none

### set_exact_crossings and set_openness_override remain single-rank-guarded (v1 scope exclusions unchanged)
- area: flow
- source: flow-ghost-projection-mpi-plan.md:17
- decided: 2026-07-23
- status: settled
- quote: |
    Still single-rank-guarded (inner-sized wrap-access study inputs): `set_exact_crossings`, `set_openness_override`. v1 exclusions unchanged (porous/varRho/domain-BC/Chebyshev).
- rejected: extending this MPI landing to cover set_exact_crossings/set_openness_override or the v1-excluded modes
- why: none stated

---

### set_face_interp(9) hybrid (aperture projection + gpCenterGrad) is the throat-safe collocated scheme
- area: flow
- source: flow-ghost-projection.md:115
- decided: 2026-07-18
- status: settled
- quote: |
    THE throat-safe collocated scheme =
    **set_face_interp(9)** "cutcell-ghost hybrid": mode-0 aperture projection verbatim (throttles,
    symmetric MG-PCG, no guard) + gpCenterGrad for predictor/cell-correction only. RCP monotone
    −13.0/−8.6/−6.2% at Ng=32/44/56 toward the stag-cutcell reference; Z&H −0.04..−0.10% band (NOT
    clean 2nd order ...) but 7-20× below mode-0.
- rejected: pure collocated ghost projection (mode-0 with gpCenterGrad only) for tight-throat porous media — it inherits the throat defect
- why: "collocated ghost DOES inherit the throat defect ... its raw RCP numbers look deceptively good ... CANCELLATION of throat inflation against the collocated under-shoot, don't trust it on tight throats"

### set_ghost_projection(True) must be called before set_solid
- area: flow
- source: flow-ghost-projection.md:33
- decided: undated
- status: settled
- quote: |
    API: `set_ghost_projection(True)` BEFORE `set_solid`; guards throw for porous/varRho/domain-BC/
    Chebyshev/collocated-nonzero-face-interp
- rejected: none stated
- why: none stated (API contract)

### set_pressure_warmstart(True) diverges on the steady Stokes march; bench default is WARMSTART=0
- area: flow
- source: porous-scaling-benchmark.md:106-109
- decided: undated
- status: settled
- quote: |
    **OPEN BUG found**: `set_pressure_warmstart(True)` DIVERGES on the steady Stokes march (192³ bed,
    k → -1.7e+120 by step 400; warmstart=0 converges in 115 steps). Bench defaults WARMSTART=0.
    Not investigated — flagged to Frank.
- rejected: set_pressure_warmstart(True) as a benchmark default
- why: it diverges on the steady Stokes march

---

### ⚠️ UNRESOLVED — interstitial vs superficial drag normalisation
- area: flow
- source: ibm-accuracy-sphere-validation.md:45-50 and :110-112
- decided: undated
- status: uncertain
- quote: |
    l.45  "our `K` (=Zick&Homsy) is **INTERSTITIAL**-referenced; the literature (vdH/Tenneti/van
          Wachem) reports the **SUPERFICIAL total drag F̄_D=(1−φ)·K**"
    l.110 "report K normalized by SUPERFICIAL velocity (=Z&H, →1 dilute); vdH/Beetstra F is
          INTERSTITIAL so K_vdH=F/(1−φ)"
- rejected: nothing — these two statements in the SAME note assign Zick-Homsy and vdH to OPPOSITE
  conventions. Both observe that the dilute limit hides the difference ("the trap").
- why: unresolved. Decides a (1−φ) factor on published permeabilities (porous-scaling study,
  RingBed, gallery pages). Found during the 2026-09-10 harvest. **Do not rely on either reading
  until settled.**

### Published parallel-scaling iteration count is 4.0, not the earlier 12.2
- area: flow
- source: parallel-scaling-study.md:119 vs :158 — resolved against peclet-examples d359a00
- decided: 2026-08-10
- status: settled
- quote: |
    The note carries TWO blocks each marked "FINAL PAGE PUBLISHED": e861010 (2026-08-09) reporting
    "iters pinned 12.2", and d359a00 (2026-08-10) reporting "decomp iters FLAT 4.0 at every rank".
    Resolved 2026-09-10 against the published page itself: peclet-examples commit d359a00
    ("final page — all results re-measured on the current solver") reports 4.0 at every rank count
    in the results table and in the prose.
- rejected: the e861010 figures (12.2), which predate the stale-ghost V-cycle residual fix
  (flow 5d77deb) that lowered iteration counts and made them decomposition-independent
- why: the later block was re-measured after the decisive fix and matches the published page

### Double operator storage is the DEFAULT (SCALING_ISSUES #1 closed by decision)
- area: flow
- source: flow/CMakeLists.txt:48-72 — maintainer decision 2026-09-11
- decided: 2026-09-11
- status: settled
- quote: |
    `PECLET_FLOW_OPERATOR_DOUBLE` defaults to ON. Float operator storage silently breaks A*1 = 0 at
    high multigrid contrast — it fails with no error, and the porous path's default MG-PCG was
    reporting a non-finite preconditioner on 2 of 5 steps, deterministically (QUALITY_PLAN.md:371).
    P1 (2026-09-01) measured the cost of being wrong: RCP bed at rtol 1e-8 — float 24/33/CAPPED
    iterations, div 4.51e-06; double 14/14/28, div 9.51e-12. ~12% step time is the price of a
    default that cannot silently invalidate a dense-bed run. Opt out with
    -DPECLET_FLOW_OPERATOR_DOUBLE=OFF, which now emits a CMake WARNING.
- rejected: (a) leaving float as the default and documenting the limitation — rejected because the
  failure is SILENT, so documentation does not protect a user who never sees it; (b) the
  double-DIAGONAL fallback, which remains retired — it converges to the float-face operator rather
  than the true one and separated 65x on divergence (P1, DIAGRESUM vs exact)
- why: a clean-break 1.0.0 must not ship a default configuration that can silently produce wrong
  dense-bed results
- consequence: this changes numerics in the default build. Regression state hashes and
  `perf_baseline.json` must be re-blessed, per the standing rule that changing a numerics-affecting
  default re-blesses bed references and is itself a decision.
