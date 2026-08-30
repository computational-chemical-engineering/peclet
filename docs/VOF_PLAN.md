# VoF plan — sharp-interface two-phase flow for the peclet suite

Status: **APPROVED 2026-08-30** (Part I, rungs V0–V11; §7's open questions resolved — see
§8). Scope extended on approval: **boiling (bubbles + boiling inside porous media) and
droplet evaporation** are wanted → Part II (§9, phase change); **advancing/receding contact
angles (hysteresis)** confirmed in scope → carried by V6. Companion to
`MULTIPHYSICS_PLAN.md`, whose Phases 1–8 built exactly the substrate this plan stands on and
whose §"Explicitly deferred" lists VoF + surface tension as this document's scope.

---

## 0. Verdict on the candidate matrix

The four candidates under consideration were:

| | transport | geometry | verdict |
|---|---|---|---|
| A | CICSAM (algebraic) | ∇C-based | **Reject as primary; THINC-class optional "fast mode" later.** Algebraic capture is ~an order of magnitude less accurate than geometric VoF and Courant-limited (Mirjalili 2017); isoAdvector even beat MULES on *speed* (3–9×, Roenby 2016), killing the "algebraic is cheaper" argument; ∇C curvature gives spurious Ca ~1e-2 vs the ≲1e-7 budget of pore-scale flow; and algebraic advection provably transports the contact line incorrectly (Fricke, Marić & Bothe 2020) — disqualifying for a wetting-first code. If a morphology-independent-load fallback is ever wanted (the FluTAS/CaNS-Fizzy argument), implement MTHINC, not CICSAM. |
| B | **PLIC (WY split)** | **height functions + fit fallback** | **The workhorse. Build this.** The converged production design (Basilisk, PARIS, AMR-Wind): Weymouth–Yue directionally-split conservative advection + MYC normals + Scardovelli–Zaleski analytic inversion + Popinet-style HF cascade with paraboloid-fit fallback + balanced-force CSF. |
| C | PLIC | **reconstructed φ (band RDF)** | **Build — but as a component, not a rival method.** RDF *curvature* does not converge (Cummins 2005); RDF's proven roles are 2nd-order normal/position refinement (plicRDF, Scheufler & Roenby 2019) and — decisive here — the **SDF contact-angle machinery**: a band-local signed distance lets the wetting BC be imposed by ghost filling with `n_wall = ∇sdf` and the cos θ condition. C is rungs V5–V6 of method B, not an alternative. |
| D | PLIC | transported φ (CLSVOF) | **Don't build (deprioritize indefinitely).** Production consensus moved away — NGA's own group abandoned conservative LS for geometric VoF; none of Basilisk/PARIS/NGA2/interFoam-family carry CLSVOF; coupling an LS does not fix force balance (spurious currents persist, i-CLSVoF 2022); redistancing is the GPU-awkward part (FMM sequential; sweeping = many halo-synced passes). Everything CLSVOF buys (smooth normals near solids, wetting BC) the band RDF of row C buys cheaper, without a second advected field or global redistancing. Revisit only if pore-scale evidence shows the HF+fit cascade failing under violent topology change. |

So: **one geometric method (B), with C folded in as its near-solid geometry engine, A' (THINC)
as an optional cheap mode later, D dropped.** "Multiple methods" is still honored — the
architecture keeps transport (flux provider) and geometry (curvature provider) as separate
seams, so THINC transport or a fit-only curvature mode drop in later without replumbing.

## 1. What already exists (the head start is large)

Multiphysics Phases 1–8 shipped the hard non-VoF half of a two-phase solver:

- **Variable-density projection, validated at ρ-ratio 1000**: `buildRhoCoeff`
  (`flow/src/mac_pressure.hpp:251`, face coeff `open_f·ρ₀/ρ_f`) + exact-adjoint
  `projectCorrectVar` (`:231`); machine-exact hydrostatic balance. Coefficients ride the
  openness rails through `CutcellMG` with zero MG changes.
- **Variable viscosity** with harmonic face means (`flow/src/face_props.hpp:65`,
  `ibmBuildDiffusionVar`, validated 0.0006% on 10× μ-jump Couette).
- **Cell-centred conservative scalar transport** (Koren TVD, openness-weighted flux form,
  `flow/src/scalar_transport.hpp`) driven by **discretely divergence-free face velocities on
  both grids** — staggered `C[c].u`, collocated `uf_/vf_/wf_` corrected by `projectCorrect`
  (`flow/src/flow_ibm.hpp:3742`), uniform seam `get_face_velocity(c)` (`:1663`).
- **Property closures** `ρ(c)`, `μ(c)`, per-cell force fields face-interpolated in
  `buildRhsVar` — the exact mechanism a CSF force uses verbatim.
- **Cut-cell geometry**: marching-squares face apertures (`ccFaceOpenMS`,
  `flow/src/mac_cutcell.hpp:123`), subsampled cell fluid fractions (`buildCellFraction`),
  SDF + ∇sdf per cell, and a Basilisk-grade true-normal wall-gradient primitive
  (`embedDirichletGradient`, `flow/src/mac_approx_projection.hpp:383`) — the contact-angle
  primitive already in the tree.
- **Runtime-width halos**: `GridHaloTopology::buildTopology(..., ghostWidth, ...)` takes any
  width; the FieldSet supports per-field ghost widths. flow's global `G = 2` need not move.
- **AMR**: `AmrFlow` (`core/include/peclet/core/amr/flow.hpp`) advects with projected face
  velocities; conservative sub-face flux matching; Löhner indicator; conservative
  `transferField` remap; cut band already contractually at the finest level.
- Working diffuse two-phase chain to extend: `flow/tests/study/rayleigh_taylor.py`.

Greenfield: PLIC reconstruction, geometric advection, HF curvature, balanced-force CSF,
contact angle. (`voro`'s "multiphase" is a Lagrangian facet-area energy — unrelated.)

## 2. Method selection — literature grounding (condensed)

- **Transport: Weymouth & Yue 2010 split scheme.** Volume conserved to machine precision
  (dilation correction with `c = H(Cⁿ−½)` frozen across the three sweeps, telescoping against
  discrete `∇·u = 0`); hard cap **CFL < 0.5**, sweep order alternated by step parity.
  Kernel shape is the GPU argument: gather-only, no atomics, three 1D-sweep `parallel_for`s.
  Unsplit geometric flux methods (Owkes–Desjardins) are branch-heavy, have no published
  production GPU implementation, and their CFL≈1 advantage is void when WY's cap binds
  anyway (it doesn't — the capillary CFL binds, §4/V4). AMR-Wind chose split WY on GPUs for
  exactly this reason.
- **Reconstruction: MYC normals + Scardovelli–Zaleski 2000 analytic inversion** in the
  branch-reduced GPU form of Lehmann & Gekle 2022. MYC is non-iterative, near-2nd-order, and
  the de facto standard (Gerris/Basilisk/PARIS/AMR-Wind). 3D ELVIRA needs 5³ for 2nd order
  and is the 3D cost bottleneck — skip. MOF (stencil-1, best halo/AMR story, multi-material)
  is the noted future option if multi-material ever matters.
- **Curvature: Popinet 2009 HF cascade** — standard HF where monotone columns exist → mixed
  HF → **PLIC-volumetric paraboloid fit on a 5³ Wendland-weighted stencil** (the best
  cost/accuracy fallback per Han, Evrard & Desjardins 2024). Two hard facts from Han 2024 to
  respect: HF *always* needs the fallback somewhere below ~4–5 cells/diameter (i.e. in every
  under-resolved pore throat), and with advection-realistic volume fractions **curvature error
  stops converging below CΔ ≈ 1e-2 for every method** — so don't chase curvature order,
  chase transport fidelity. Skip ML curvature (no demonstrated mesh convergence).
- **Force: balanced-force CSF** (Francois 2006; Popinet 2009/2018): `σκ∇C` evaluated at face
  centers with the **identical discrete gradient operator as ∇p** → discrete equilibrium at
  machine precision; residual spurious currents then scale purely with curvature error. On
  the staggered MAC grid this is natural; on collocated it is strictly harder (same
  force/pressure-mismatch class as the collocated-attractor pathology) — hence staggered
  first (§4, V8).
- **Momentum consistency from day one** (Rudman 1998; Arrufat 2021): at ratio 1000, mass and
  momentum must be advected with the *same* geometric fluxes on the momentum control volumes
  (half-shifted fractions on MAC; Favre-averaged upwind face states on collocated per
  AMR-Wind). Payoff is quantified: accurate raindrop at 15 cells/diameter vs ~200 without.
  Not bolt-on-able later.
- **Contact angle on SDF solids** (the differentiator; no GPU cut-cell balanced-force VoF
  pore-scale code exists): geometric imposition where the fluid–fluid PLIC meets the cut-cell
  solid — rotate the interface normal about `n_wall = ∇sdf` by θ and fill solid-side ghost
  fractions / band RDF so the *unmodified* HF/fit stencils see a θ-consistent interface
  (Basilisk `contact-embed.h`; Tavares et al. 2024; Huang et al. 2025/2026 for cut-cell mass
  conservation + hysteresis; Shahmardi 2021 for the SDF-ghost pattern). Flat-wall limit must
  reduce to the Afkhami–Bussmann HF contact-angle BC. Dynamic angle via grid-scale Cox–Voinov
  with the **slip length an explicit exposed parameter** (Afkhami 2009; Legendre & Maglio
  2015; capillary-rise dynamics depend leadingly on it, Gründing 2020); GNBC (Fullana et al.
  2026) as the eventual clean formulation.
- **Scale context**: with an FFT Poisson solver VoF is ~11% of a GPU step (FluTAS); with
  variable-coefficient MG the *pressure solve* dominates (up to 90% — matching our own M0
  profile). VoF cost is a minority concern; the ρ-jump pressure solve is where step time
  goes, which is why §5's solver workstream runs in parallel.

## 3. Architecture

New files, all header-only Kokkos under `flow/src/` (device-first; host oracle mirrors per
suite directive), one new binding surface on the existing `Solver<Grid>`:

```
flow/src/vof/plic.hpp          # SZ2000 forward/inverse (Lehmann–Gekle), MYC + Youngs normals,
                               #   plane↔volume, cell/face clipping helpers   [V0]
flow/src/vof/advect_wy.hpp     # WY split sweeps, dilation term, sweep parity, wisp clipping [V1]
flow/src/vof/curvature.hpp     # HF columns + cascade + PV paraboloid fit                    [V3]
flow/src/vof/rdf.hpp           # band RDF from PLIC (2–3 cells), normals refinement          [V5]
flow/src/vof/wetting.hpp       # SDF ghost-fraction fill, θ rotation, dynamic-angle model    [V5–V6]
flow/src/vof/momentum.hpp      # half-shifted fractions / consistent momentum fluxes         [V2]
```

Design rules:

1. **`C` gets its own g=3 halo.** Keep the global `G = 2` untouched (194 use sites; every
   bit-exact baseline). The colour field is adopted into the FieldSet with its own
   `GridHaloTopology` at width 3 (HF columns are 7 cells; MYC needs 3³). PARIS's
   partial-column-sum trick (halo 2 + a small custom reduction) is the *later* optimization
   (V9), not the starting design.
2. **`C` is the liquid fraction of the *fluid* volume** in cut cells (C ∈ [0,1] regardless of
   solid fraction). Advective fluxes are openness-weighted, exactly like
   `scalarBuildRhs`; the WY dilation telescopes against the openness-weighted discrete
   divergence, which the projection already zeroes — so exact conservation survives cut
   cells. Follow Huang 2025/2026 for the solid-clipped flux-polygon details.
3. **Transport and geometry are seams**, mirroring `GridLayout`: the advector consumes
   `get_face_velocity`-style face fluxes (works verbatim on staggered and collocated); the
   curvature provider consumes C + normals and emits a cell κ field. THINC transport or an
   alternative curvature provider plug in without touching the solver.
4. **Interface-cell worklist compaction**: geometric work lives only in mixed cells
   (O(N^{2/3})); build a compacted index list per step (`parallel_scan`) and launch
   reconstruction/curvature over it. Nobody in the literature has published this on GPU; it
   is the cheap divergence win. The same counts feed the weighted ORB (V9).
5. **Two-phase mode uses explicit conservative momentum advection near the interface.** The
   current implicit-FOU momentum path is incompatible with VoF-flux momentum consistency; at
   pore-scale Ca the capillary CFL (V4) is the binding step limit anyway, so explicit
   advection is free. Single-phase paths are untouched (bit-exact regression is a hard gate).
6. **Properties from C via the existing closures** (`LinearMix` ρ(C), μ(C) with the harmonic
   μ option); `set_density_mode("variable")` and the Chebyshev pressure driver as-is.

## 4. Phase ladder

Every rung gates on: single-phase `sdflow_regression.py` **bit-exact (+0.00%, identical
iteration counts)**; MPI np 1/2/4 bit-exact vs single-rank; device≡host-oracle agreement.

**V0 — PLIC toolbox (no NS). ✅ DONE 2026-08-30** (flow `c1fcf8f`, umbrella `79a13c1`;
`src/vof/plic.hpp` + `tests/kokkos/test_vof_plic.cpp`, 20/20 ctests on host-openmp AND
CUDA). Measured: forward vs an independent inclusion-exclusion oracle 1.2e-15; **10⁵-sample
round-trip 6.7e-15**; `faceFluxVolume(f=1)` bitwise equal to `plicVolume`; MYC on exact
planes max 1.02° / mean 0.10° (Youngs 3.67° / 1.21°); sphere reconstruction order **1.98**.
Two findings, both in `flow/doc/vof_workorders.md`:
- **A boundary defect in Lehmann & Gekle's published Listing 1, found and fixed.** Their
  hoisted case-(5) guard `min(n1+n2,n3) <= d <= n3` fires at the single point `d == n3`
  when `n3 < n1+n2`, where case (3) is correct — `plicVolume(⅓,⅓,⅓, ⅓)` returned 0 instead
  of ⅙. Caught by the hand-computed tetrahedron, *not* by the randomized battery (the
  defect has measure zero). Keep the hand-computed cases in every future port.
- **MYC normal-*angle* error does not converge (order 0.83); reconstruction error does
  (1.98).** Mechanism isolated: MYC is not exact on planes (fails Pilliod–Puckett) and
  ~28% of mixed cells take the Youngs fallback, whose normal error is flat. This
  reproduces Aulisa et al.'s own published behaviour (their reconstruction order degrades
  2.22→1.37 likewise), so the shipped gate is the reconstruction slope with the normal
  angle recorded as a tripwire. **This is a first-principles confirmation of §0's verdict
  against candidate A** (∇C-based geometry): a normal estimator of this class cannot carry
  curvature, which is exactly why V3 takes curvature from height functions (column sums of
  C, independent of the MYC normal) rather than from ∇C. Consequence to carry: if 2nd-order
  *normals* are ever needed, the routes are ELVIRA/LVIRA on a 5³ stencil (3³ is provably
  insufficient in 3D — Boniou 2022) or plicRDF iterative refinement at V5 — never a tune
  of MYC.

**V1 — WY advection on prescribed velocity fields.** Own g=3 halo, sweep parity, worklist.
Gates: translation/rotation shape errors vs published (Zalesak disk, 3D LeVeque deformation
field with reversal); volume conserved to ~1e-15 per step; CFL<0.5 asserted; np 1/2/4
bit-exact. Wisp census recorded (clipping OFF at this rung — conservation must be exact).

**V2 — Two-phase NS, no surface tension (staggered).** C → closures → varRho projection;
**momentum-consistent transport** (half-shifted fractions). Gates: two-layer hydrostatic
acid test machine-exact at ratio 1000 (the varRho acid-test pattern); sharp-interface
Rayleigh–Taylor growth rate vs linear theory (extend `rayleigh_taylor.py`); falling raindrop
at ratio ~800 stable and accurate at ~15 cells/diameter (Arrufat criterion); harmonic ρ_f
face-mean option added to `buildRhoCoeff` (the flagged >10²–10³ coarsening trap).

**V3 — Curvature.** HF cascade + PV 5³ fit; κ as a registered field.
Gates: Han-style static convergence (exact fractions → 2nd order; sphere sweep incl.
D/Δ < 5 where the fallback must engage, no NaN/zero-κ cells); curvature of a translating
droplet (transport-noise floor visible, documented).

**V4 — Balanced-force CSF + capillary time step.** Face `σκ∂C` with the projection's own
gradient; Brackbill/Denner capillary Δt exposed and folded into the step limiter.
Gates: **stationary droplet spurious currents at machine zero** (the direct analogue of the
hydrostatic acid test — fails loudly on any force/coefficient face inconsistency);
capillary wave vs Prosperetti; oscillating droplet vs Lamb; Hysing rising-bubble benchmark
(both cases) vs reference; spurious Ca ≲ 1e-7 on a resolved static droplet.

**V5 — Static contact angle on SDF solids.** Band RDF; ghost-fraction fill with
`n_wall = ∇sdf` + θ rotation; cut-cell-conserving fluxes (C never leaks into solid).
Gates: drop-on-flat-wall equilibrium angle sweep (θ = 30°…150°, measured vs imposed,
matching Afkhami–Bussmann in the grid-aligned limit); **drop-on-sphere equilibrium**
(Asghar/Fricke wetting suite — public data); volume conservation against curved solids;
near-solid spurious currents quantified.

**V6 — Dynamic contact angle.** Grid-scale Cox–Voinov apparent-angle model, slip length as
an explicit parameter; hysteresis (advancing/receding θ) per Huang 2026.
Gates: capillary rise vs the Gründing 2020 benchmark (rise dynamics + corrected stationary
height, slip-length sensitivity reproduced); spreading drop vs Cox–Voinov.

**V7 — Pore-scale campaign.** Pore doublet drainage/imbibition; imbibition in an SDF sphere
packing (the existing packed-bed scenes); a Zhao-2019-style micromodel with wettability
sweep. Lesson to design against: **corner films decide imbibition fidelity** — the
micromodel benchmark defeated nearly every 2019-era code on strong imbibition. Cross-checks
against `pnm` invasion metrics where applicable.

**V8 — Collocated.** The collocated path is the **ABC approximate projection**
(wall-aware center-to-face interpolation → exact face projection `divergOpen(uf)=0` →
separate cell correction), NOT Rhie–Chow momentum interpolation — corrected 2026-08-30.
Consequences: (a) the *transport* half is already right — the ABC face field is exactly
divergence-free, which is precisely what WY's conservation proof needs (and
`advanceScalars` already consumes `uf_`); (b) the balanced-force recipe has a direct
published precedent in this exact framework: **Basilisk is a collocated ABC-style code**
(cell-centered u, auxiliary face field, approximate projection) and achieves machine-zero
spurious currents by applying σκ∂C at faces with the same discrete gradient as ∂φ before
the face projection — so V8's force placement follows the V4 rule on the face path, plus
the *consistent cell-side counterpart* through the same averaging operator as
`projectCorrectCenter`. Requires: collocated varRho projection (currently throws — 1/ρ_f
in the face correction and its cell-averaged adjoint), face CSF as above, Favre face
states for momentum consistency (AMR-Wind pattern; their non-Favre variants blew up).
Specific ABC risk to gate: the approximate projection leaves a filtered remnant of any
face/cell inconsistency in the *cell* velocities — a stiff localized σκδ_Γ force is
exactly the kind of input that could re-excite the invisible-subspace/attractor family
the collocated campaign just tamed (`flow/doc/collocated_invisible_subspace.md`); the
hydrostatic and static-droplet acid tests on the collocated path are the canaries, run
with the wall-blend settings from that campaign. Gate: same V2/V4 battery; staggered
stays the reference. Sequenced after V7 deliberately — porous-media results don't wait
on it (but V8 is the gateway to AMR two-phase, §11).

**V9 — Performance & scale.** Interface-weighted ORB rebalancing (the weighted
`BlockDecomposer` is the published remedy for VoF's O(N^{2/3}) imbalance); PARIS
partial-column-sum halo-2 optimization; Snellius multi-GPU scaling ladder (a Kokkos
geometric VoF would be the first performance-portable one in the literature — FluTAS/
CaNS-Fizzy data say the obstacle is engineering, not algorithm).

**V10 — AMR (separate campaign, sketch only).** Interface band pinned to the finest level
(as everyone but Basilisk does; the cut band already carries the same contract) →
`fraction_refine`-style PLIC-subdivision prolongation (never interpolate C), AMR-Wind
per-substep fine→coarse flux averaging ("pre-reflux" — preserves both conservation and WY
boundedness where deferred refluxing would not), local solenoidal face refinement on adapt.
Blocked behind varRho-on-AMR, which does not exist; scope it when V7 results justify it.

Optional **V11 — MTHINC fast mode** behind the transport seam, for morphology-independent
load at extreme scale.

## 5. Parallel workstreams (not on the ladder's critical path)

- **Pressure solver under sharp ρ jumps — the S-ladder** (elevated 2026-08-30; user's main
  concern). Diagnosis (`flow/doc/variable_density_projection.md` §2): the V-cycle
  preconditioner's transfer pair is not symmetric w.r.t. the coefficient-weighted inner
  product once level fields are ρ-scaled → CG's orthogonality collapses and it stalls;
  Chebyshev needs only real spectrum bounds and is immune (≤32 its at ratio 10³). Two
  reframes before any deep work: (a) the fine-level face mean is *already right* — the
  arithmetic-ρ face mean equals the harmonic mean of the coefficient β=1/ρ, which is the
  homogenization-correct series choice AND the hydrostatic-exactness requirement; the
  flagged degradation lives in the *coarse hierarchy* (arithmetic sub-face averaging +
  rediscretization is fine for openness, unproven for 10³ coefficient jumps); (b)
  **Chebyshev is not a stopgap** — it is the only driver with zero global reductions per
  iteration, i.e. exactly the all-reduce-free pressure driver the comm-scaling campaign
  wants (`core/docs/comm_avoiding_pressure_driver.md`). The ladder, cheap → deep, each
  rung gated on measurement (first-principles directive):
  - **S0 — measure before investing**: a-priori battery with *static manufactured* ρ
    fields (sphere / film / meniscus-shaped jumps inside the ring + packing cut-cell
    geometries; ratio sweep 10²–10⁴): Chebyshev its, PCG stall reproduction, per-level
    residual decomposition. Needs NO VoF — can run today.
  - **S1 — flexible CG (FCG/IPCG)**: Polak–Ribière β tolerates a nonsymmetric/variable
    preconditioner; a ~one-vector change to the existing driver. If FCG with the current
    V-cycle beats Chebyshev, the "stall" is closed at trivial cost.
  - **S2 — bound amortization for moving interfaces**: at capillary-limited dt the
    interface crosses a cell over many steps → coefficients drift slowly; freeze Chebyshev
    bounds for N steps (safety-inflated, residual-guarded re-estimate on violation) +
    φ warm start. Turns the per-step re-estimation cost into noise.
  - **S3 — coefficient-aware coarsening, structure-preserving**: keep the 7-band
    rediscretized hierarchy but coarsen coefficients as a resistor network (parallel:
    sub-face conductances add — the current `coarsenOpenAvg` is already correct here;
    series: add the two half-cell resistances through the coarse cell along the normal —
    the missing "half-harmonic" step, cf. Alcouffe et al. 1981). Cheap, no stencil growth.
  - **S4 — symmetric transfers / Galerkin (RAP) or operator-dependent (BoxMG/Dendy 1982)
    transfers**: the provably-SPD fix that makes MG-PCG legal for arbitrary positive
    coefficients (`MULTIPHYSICS_PLAN.md:495`). Real work (RAP grows 7-band → 27-point on
    cut cells); only climb to it if S0–S3 measurements say Chebyshev/FCG iteration counts
    actually hurt on pore geometries.
  - **Rejected as primary**: Dodd–Ferrante constant-coefficient splitting — its splitting
    error scales with the pressure jump σκ, which is the *dominant* field in
    capillary-controlled pore flow, and it forfeits the exact-adjoint hydrostatic/
    balanced-force structure the whole Part-I acid-test chain is built on. Legitimate as a
    bubbly-channel fast mode at most (it is what TBFsolver uses).
- **MPI + CUDA validation of the varRho/varMu paths** — the multiphysics phases were
  validated on host-openmp only (`variable_density_projection.md` §4: "MPI/CUDA validation
  deferred"). This IS on V2's critical path: promote to a pre-V0 hardening rung (**V-1**)
  — varRho hydrostatic + RT on CUDA, np 1/2/4 bit-exact ctests for varRho/varMu/scalar
  paths, Chebyshev-bounds behavior under np>1.
- **`bcCorrectOutflow` lacks the 1/ρ_f factor** (known gap, variable_density doc §4) —
  needed before any two-phase outflow case.
- **Ghost-projection / porous-ε paths throw under varRho** (`flow_ibm.hpp:3486,:3516`).
  Two-phase-in-porous-ε (volume-averaged two-phase) is explicitly out of scope here; the
  gates stay.

## 6. Traps (from the literature, pre-loaded)

- WY boundedness is a **hard CFL < 0.5**, and the dilation coefficient is frozen *once per
  step* across all three sweeps — recompute it per sweep and exact conservation silently dies.
- **Wisp clipping (ε=1e-8) erodes exact conservation** unless clipped volume is
  redistributed; with surface tension clipping is unavoidable (Arrufat). Ship clipping with
  redistribution, and keep the V1 conservation gate running with clipping on.
- **Curvature is transport-noise-limited below CΔ≈1e-2** (Han 2024): a plateauing curvature
  error on fine grids is expected physics of the method, not a bug to fix with a fancier
  estimator.
- **Contact-line mobility is grid-dependent by construction** (numerical slip ∝ Δx): without
  the explicit slip/Cox–Voinov model, spreading results silently change under refinement.
  Never report a dynamic-wetting result without the slip parameter stated.
- Basilisk's own `contact-embed.h` still flags parts of the 3D normal rotation as fixme —
  budget real derivation time in V5, don't transcribe.
- Arithmetic ρ_f coarsening degrades past ~10²–10³ (already flagged in
  `MULTIPHYSICS_PLAN.md:474`) — harmonic option lands in V2, not when it bites.
- Momentum consistency can excite near-Nyquist growth on under-resolved shear layers
  (Arrufat KH caveat) — keep the RT/KH gates at more than one resolution.

## 7. Open questions — RESOLVED 2026-08-30

1. Cut-cell C convention (§3.2, liquid-per-fluid-volume): **approved**.
2. Collocated (V8) after the pore-scale campaign (V7): **approved**.
3. CLSVOF: **boiling and evaporation ARE wanted** (bubbles, boiling inside porous media,
   droplet evaporation). Per §9, this still does not resurrect a *transported* φ: the modern
   geometric-VoF phase-change codes run on band-local distance/normal probes, which our band
   RDF (V5) already provides — the phase-change requirement *upgrades the RDF from a wetting
   convenience to first-class infrastructure* (normal-probe temperature gradients, field
   extrapolation), reinforcing the §0 architecture rather than changing it.
4. Dynamic contact angle: **wanted, including advancing/receding hysteresis** — V6 stays on
   the critical path for the pore-scale campaign (imbibition/drainage without hysteresis is
   not the physics of interest), with the Huang-2026-style advancing/receding pair as the
   shipped model and slip length always explicit.

## 8. Decisions log

- 2026-08-30 — Part I approved as drafted (user). Scope extended: boiling (incl. in porous
  media), droplet evaporation, contact-angle hysteresis. Part II (§9) added in response.
- 2026-08-30 — Bubbly flow added to scope (user), resolved **and** unresolved (CFD-DEM
  style); `~/Codes/TBFsolver` reviewed as the reference design → Part III (§10).

## 9. Part II — phase change (boiling, evaporation)

Literature verdict (2026-08-30 memo): the last five years settled the LS-vs-VoF question
for phase change — **pure geometric VoF with band-local distance information is
sufficient**. Flash-X is level-set-based because LS hands over signed distance, smooth
normals, and GFM jumps for free; but the entire modern Basilisk phase-change ecosystem
(Gennari 2022, Boyd & Ling 2023, Cipriano 2024, Long 2025), PARIS (Malan 2021), NGA
(Palmore & Desjardins 2019) and FluTAS-lineage (Scapin 2020, who builds an RDF from VoF
precisely to reuse LS machinery) are geometric VoF. This **confirms the §0 verdict on D**
and promotes the band RDF (V5) to first-class infrastructure. Notable gaps we can own:
**no published Kokkos/multi-GPU geometric-VoF phase-change code exists, and no
geometric-VoF boiling-in-porous-media DNS exists at all** (that field is pseudopotential
LBM + Prat-school pore-network models).

Architecture (the Boyd-Ling/Malan pattern + Scapin band RDF — maximum reuse of Part I):

1. **ṁ from one-sided pure-cell gradients**: weighted 5³ gather stencils over *pure-phase
   cells only* on each side (Malan's collinearity weighting / Boyd-Ling's ξ‖d‖²), with
   normals + distances from the band RDF. Halo 2, one gather per band cell — ideal Kokkos
   kernel, no iteration. Aslam PDE extrapolation (~15 band-local sweeps) is the accuracy
   upgrade if Scriven demands it (Tanguy 2014: quadratic extrapolation is what makes
   thermally-controlled growth accurate).
2. **IHTR from day one**: a Schrage-derived interfacial heat-transfer resistance (Robin
   condition T_Γ = T_sat + ṁR_int) instead of hard Dirichlet T_sat — Bureš & Sato 2021
   show pure T_sat triggers spurious interfacial waves at fine resolution; Long 2025
   credits IHTR with part of a 1000× cost improvement. Costs nothing.
3. **WY advection untouched**: advect C with a **band-extended divergence-free liquid
   velocity** (constant Aslam extension of u_l + a small band-local Helmholtz projection,
   Palmore-Desjardins Eq. 61 — reuse the MG-PCG machinery on the band system), preserving
   WY's conservation proof.
4. **Interface regression by PLIC plane shift**: Δd = −(ṁ/ρ_l)Δt with Malan's
   clip-and-redistribute — exact conservation, no wisp accumulation. Never use a volume
   source in the C equation (the Hardt-Wondra smeared-source route leaves unresolvable
   liquid residue and breaks WY bounds).
5. **Divergence source shifted into pure gas cells** (Boyd-Ling/Gennari): the volumetric
   source ṁ(1/ρ_g − 1/ρ_l)A_Γ/V goes into the Poisson RHS conservatively distributed over
   a compact pure-gas layer behind the interface, so interfacial-cell velocities stay valid
   for VoF advection. One extra compatible RHS array through the existing deflated
   pressure solve — no solver changes. (Closed domains: net vapor production must exit via
   an outflow — depends on the `bcCorrectOutflow` 1/ρ_f fix, §5.)
6. **Consistent energy transport**: advect ρc_pT with the *same geometric fluxes* as C,
   face heat capacities reconstructed per sweep (Malan) — the WY sweep structure gives
   this almost free; avoids artificial heating at high ρc_p ratio.
7. **Conjugate solid heat transfer** on the SDF: cut-cell diffusion solve with
   harmonic-mean k at the boundary — the "embed + CHT" item Basilisk lists as future work;
   required for nucleate boiling on walls and for porous matrices.
8. **Micro-region/microlayer**: pore-scale is favorable — pores of 10–100 µm sit near
   microlayer scales, so resolved contact-region evaporation is more attainable than in
   flat-plate boiling; the Stephan-Busse micro-region closure (coupled rigorously in
   Torres 2024) is the sub-grid fallback at the V6 contact line.

**Rung ladder (Part II, after V4; P5+ after V5):**
- **P0** fixed-flux planar interface (regression + div source, no thermal solve).
- **P1** 1D Stefan problem — gate: <0.5% interface position at N=256 (Malan: 0.23%).
- **P2** 1D sucking interface (Welch & Wilson) — gate: observed order ≥1.4 (Boyd-Ling).
- **P3** 3D Scriven bubble growth, Ja = 0.5–10 — gate: <1% radius at 256³; if the
  pure-cell stencil falls short, add Aslam quadratic extrapolation (the known lever).
- **P4** droplet evaporation: D²-law + wet-bulb check — gate: order ~2 on D² (Scapin,
  Palmore-Desjardins); multicomponent later (Cipriano) if wanted.
- **P5** 2D/3D film boiling vs Berenson/Klimenko — ±5% Nusselt (correlation scatter ±25%,
  treat as qualitative); grid-converged interface shapes.
- **P6** film boiling around a superheated **SDF sphere** in subcooled liquid (IJHMT 2024
  reference) — first solids-coupled case.
- **P7** evaporation/boiling in an SDF sphere packing vs pore-network drying curves
  (Prat-school references) — the first-of-kind target; nucleate boiling on structured SDF
  surfaces with CHT as the companion case.

## 10. Part III — bubbly flow: multiple-marker block VoF (the TBFsolver pattern)

Reference code reviewed 2026-08-30: `~/Codes/TBFsolver` (Cifani et al., *Computers &
Fluids* 2018 — DNS of turbulent bubble-laden channel flow; MPI+OpenMP Fortran, pencil
decomposition). Its VoF is exactly the "VoF per bubble on a bounding box" pattern:

**How TBFsolver works** (`src/VOF/vofBlocks.f90`, `src/VOF/VOF.f90`):
- Each bubble owns a **`vofBlock`**: a moving bounding box (bubble extent + a **3-cell
  offset** — independently matching our g=3 choice) carrying its own local mesh arrays and
  dense sub-fields `c, c0, k, st*, u*, n*, isMixed/isFull` (`vofBlocks.f90:60–86`).
- Each block has a **master rank**, assigned independently of the spatial decomposition and
  **redistributed periodically for load balance** (`reInitBlockDistribution`,
  `measureBlocksDistr`). Per step: gather `u` from the ranks overlapping the box to the
  master (`grid_2_boxes_u`, neighbor lists via `excLists`/`s_gbList`); the master runs the
  whole VoF pipeline on the small dense block — PLIC reconstruction, 3 alternating
  direction-split sweeps (implicit-in-sweep + correction fluxes, *not* WY),
  fragment/satellite culling, HF curvature with parabolic-fit fallback
  (`hfColumn`/`parabFittedCurvature` — the same cascade family as our V3), block CSF —
  then scatter back: `c` with **UNPACK_MAX** (union of markers), face surface tension with
  **UNPACK_SUM** (`solveVOF`, `VOF.f90:348`; `computeSurfaceTension:1872`).
- One-fluid coupling: union `c` → vertex-smoothed `cs` → arithmetic ρ(cs), μ(cs)
  (`updateMaterialProps:197`); pressure via **constant-coefficient FFT Poisson with the
  Dodd–Ferrante splitting** (ρ0 = min ρ, correction terms `1 − ρ0/ρ_f`,
  `poissonEqn.f90:234–239`).
- Contact angle: a hardcoded flat-channel-wall normal correction only
  (`correctContantAngle:1803`) — no general solids at all.

**Why the pattern is right for peclet.** The multiple markers make **numerical coalescence
impossible by construction** — colliding bubbles' blocks overlap in space but never merge,
which is the physically correct default for bubbly flows (film drainage is sub-grid; a
single global C field would merge every near-contact pair spuriously). Coalescence becomes
an explicit *model decision* instead of a numerical accident. Bonuses: VoF work confined to
small dense blocks (the block is a stronger form of the §3.4 worklist), **bubble-work load
balancing decoupled from the flow decomposition**, and per-bubble Lagrangian statistics for
free. Lineage: multiple-marker VoF/CLSVOF also in Coyajee & Boersma (JCP 2009) and
Balcázar et al. (multiple-marker conservative LS, IJHFF 2015) — TBFsolver is the
scalable-implementation reference.

**Fit** — the blocks are a *container/orchestration layer over the same V0–V4 kernels*, not
a second method. Everything TBFsolver hand-rolled exists in the suite already, stronger:

| TBFsolver | peclet counterpart |
|---|---|
| box↔pencil gather/scatter lists | `core` NBX / `ParticleMigrator::gatherGhosts` motif; dem coupling's grid↔particle exchange |
| master-rank redistribution | weighted-ORB `BlockDecomposer` + `rebalance` (block count/size as weights) |
| OpenMP loop over blocks | flattened block arena (bubble-major SoA + CSR offsets), Kokkos team-per-block — thousands of bubbles = GPU occupancy; **no published GPU multiple-marker VoF exists** |
| constant-coefficient FFT + Dodd–Ferrante splitting | the validated varRho cut-cell MG projection (strictly stronger: SDF solids, porous, no splitting error at high ρ-ratio/σ) |
| flat-wall-only contact angle | V5/V6 SDF wetting applies per block unchanged (block kernels are the same cut-cell-aware kernels) |
| fixed max box size (abort on overflow) | block re-allocation on growth; breakup → split block via in-block connected components |

**Rung ladder (Part III, after V4; independent of V5–V7):**
- **W0 — block container.** Block arena + init from seeds; gather/scatter over `core` NBX;
  V0/V1 kernels running per block. Gate: one bubble in the V1 vortex **bitwise identical**
  to the global-field result (same kernels, different container); np 1/2/4 bit-exact.
- **W1 — many bubbles + redistribution.** Master assignment via weighted ORB; periodic
  redistribution; Lagrangian per-bubble outputs (position, velocity, volume, deformation).
  Gate: measured balance vs static assignment; volume of every marker conserved.
- **W2 — NS coupling.** Union-C → closures → varRho projection; per-block curvature + CSF
  scattered UNPACK_SUM. Gates: single rising bubble vs Grace-diagram terminal
  velocity/shape regimes + Duineveld; **two-bubble head-on approach with no numerical
  coalescence**; `channel_18` — TBFsolver ships this 18-bubble minimal-channel case, a
  direct cross-code validation target.
- **W3 — turbulent bubbly channel** at TBFsolver's published operating point; cross-code
  statistics comparison (void-fraction profiles, liquid velocity statistics).
- **W4 — coalescence/breakup as models.** Pairwise merge criterion (film-drainage time /
  collision Weber) → deliberate block union; in-block breakup → connected-component split
  into new blocks; satellite policy explicit.
- **W5 — resolved ↔ unresolved bridge (with `dem`/`coupling`).** Unresolved bubbles =
  point particles in the existing CFD-DEM machinery (the porous-ε formulation already
  handles displaced volume — the porous=True directive) with bubble closures added
  (Tomiyama drag/lift, added mass, wall lubrication). Then two-way switching: a point
  bubble entering a resolved region **inflates into a VoF block** (seed sphere of its
  volume); a block advected below ~4–5 cells/diameter (the curvature-resolvability floor,
  Han 2024) **collapses back to a point bubble**. No production code does this cleanly;
  the dem coupling + block container make it a natural peclet flagship.

Note for §0: this also retroactively strengthens the "transport/geometry as seams" rule —
the block container is the third consumer of the same kernel toolbox (global field, AMR,
blocks).

## 11. Execution: repo location, ownership, Opus-readiness

**Repo decision (2026-08-30): no new submodule — VoF lives in `flow` (`flow/src/vof/`).**
Rationale: every rung past V1 couples to `Solver<Grid>` internals (projection, closures,
cut-cell overlay, ghost machinery); a repo boundary would force premature API design and
split the bit-exact regression gates from the code they gate. The suite precedent is to
split when a component acquires its own users/package (the `pnm` split), which git makes
cheap *later* with history preserved.

**Three-layer structure w.r.t. the AMR future** (clarified 2026-08-30 — AMR VoF is wanted,
not hypothetical, so the promotion is *scheduled*, not conditional):
- **L1 — container-free math kernels**: SZ forward/inverse, MYC/Youngs normals on a
  supplied 3³ array, slab clipping, HF column arithmetic on supplied column sums,
  paraboloid LSq fit on supplied points, wetting ghost-fill math. Written from day one as
  pure `KOKKOS_INLINE_FUNCTION`s of scalars/small local arrays — **no grid views, no
  indexing, no halo types in their signatures** (WO-D already mandates this). One copy,
  shared by all three containers (structured field, AMR leaves, bubble blocks).
  **Scheduled promotion: at the V4 freeze** (kernels are frozen math once their gates
  pass) the L1 headers move to `core/` as `peclet::core::vof`, before V10 starts.
- **L2 — stencil gathering**: "give me the 3³ of C / the 7-column / the 5³" —
  container-specific by nature. Trivial on the structured grid; on the octree it is the
  virtual-cell machinery (rescaled extraction from a coarser neighbor's PLIC plane, valid
  under 2:1 balance — the Basilisk pattern) and is the *bulk of the genuine V10 work*,
  together with per-substep flux averaging, PLIC-subdivision prolongation, and solenoidal
  face refinement.
- **L3 — drivers**: sweep loops, halo choreography, adapt hooks — per container, exactly
  as the suite already duplicates NS orchestration between `flow`'s structured solver and
  `core`'s `AmrFlow` (with kernel *bodies* shared, the MORTON_HD consolidation pattern).

So AMR does not "split the implementation" beyond the split the suite already has for the
flow solver itself; VoF adds shared L1 + thin per-container L2/L3. Note the AMR path's
other prerequisite: `AmrFlow` is collocated, so AMR VoF inherits the V8 collocated
variable-density/balanced-force work in addition to V10's machinery; the interface-band-
at-finest-level contract coincides with the existing cut-band-at-finest contract.
Part III's block container stays in flow regardless.

**Ownership model** (the AMR-campaign pattern: Opus executes rungs specified as
work orders with deterministic gates; Fable does design-heavy derivation and writes the
work orders). Detailed phase-0 work orders: `flow/doc/vof_workorders.md`.

| rung | owner | notes |
|---|---|---|
| V-1 MPI/CUDA hardening | **Opus** | WO-A written — pattern-copy MPI ctests, bitwise gates |
| S0 solver battery | **Opus** | WO-B written — measurement only |
| S1 flexible CG | **Opus** | WO-C written — one-formula change, inert-by-default gate |
| S2 bound amortization | **Opus** | spec after S0 numbers |
| S3 series-harmonic coarsening | Fable spec → Opus | touches CutcellMG internals |
| S4 Galerkin/BoxMG transfers | **Fable** | only if S0–S3 say so |
| V0 PLIC toolbox | **Opus** | WO-D written — self-checking gates (round-trip 1e-13) |
| V1 WY advection | **Opus** | WO-E written — traps pre-loaded, conservation gate |
| V2a closures/projection wiring | **Opus** | hydrostatic acid test is the loud gate |
| V2b momentum-consistent transport | **Fable** design → Opus | half-shifted fractions; the subtle rung |
| V3 HF cascade | **Opus** (detailed WO to come) | Popinet 2009 is a precise spec |
| V3 PV paraboloid fallback | Fable spec → Opus | LSq fit + weighting choices |
| V4 balanced CSF + capillary dt | **Opus** | one-rule force placement; machine-zero droplet gate |
| V5 SDF wetting | **Fable** (+ Opus harness) | research-grade; reference impl has known fixmes |
| V6 dynamic θ / hysteresis | Fable design → Opus | model implementation after the derivation |
| V7 pore-scale campaign | **Opus** runs, Fable/user interpret | scripts + sweeps |
| V8 collocated | **Fable** | attractor-campaign territory |
| V9 scale-out | mixed | probes Opus; lever selection Fable |
| V10 AMR | **Fable** | separate campaign |
| P0–P2 phase-change basics | **Opus** after Part-II kernel specs | Stefan/sucking are deterministic gates |
| P3+ | Fable design → Opus | extrapolation quality is the crux |
| W0 block container | Fable exchange design → Opus arena | core-NBX gather/scatter is the design part |
| W1–W3 bubbly rungs | mostly **Opus** | channel_18 cross-code gate |
| W4–W5 coalescence models / dem bridge | **Fable** | modeling decisions |

Net: **roughly two-thirds of the rung-work is Opus-executable** once specified at WO
grain, because the plan's gate style (bitwise, analytic, loud acid tests) makes
correctness machine-checkable — an Opus agent cannot silently pass a wrong PLIC inverse
through a 10⁵-sample 1e-13 round-trip gate. The reserved third is derivation (wetting,
momentum consistency, MG transfers) and campaign interpretation.

**Start order**: WO-A ∥ WO-D (independent), then WO-B → WO-C, then WO-E (needs WO-D).
Escalation rule in every WO: a twice-failed gate stops the run and is written into the
findings log — numerics are never tweaked to make a gate pass.

## Key references

Weymouth & Yue JCP 2010 · Scardovelli & Zaleski JCP 2000 · Lehmann & Gekle Computation 2022 ·
Aulisa et al. (MYC) JCP 2007 · Popinet JCP 2009 + Annu. Rev. Fluid Mech. 2018 · Francois et
al. JCP 2006 · Han, Evrard & Desjardins IJMF 2024 (arXiv:2304.08643) · Cummins, Francois &
Kothe C&S 2005 · Afkhami & Bussmann IJNMF 2008/2009 · Afkhami, Zaleski & Bussmann JCP 2009 ·
Legendre & Maglio C&F 2015 · Fullana et al. JFM 2026 (GNBC, arXiv:2411.10762) · Fricke,
Marić & Bothe JCP 2020 · Tavares et al. JCP 2024 (arXiv:2402.10185) + Basilisk
`contact-embed.h` · Huang et al. JCP 2025 / arXiv:2603.10045 · Shahmardi et al. JCP 2021 ·
Scheufler & Roenby JCP 2019 · Rudman IJNMF 1998 · Arrufat et al. C&F 2021 · Kuhn, Deskos &
Sprague C&F 2023 (AMR-Wind) · Raeini, Blunt & Bijeljic JCP 2012 · Shams et al. JCP 2018 ·
Zhao et al. PNAS 2019 · Gründing et al. AMM 2020 · Asghar et al. 2023 (arXiv:2302.02629) ·
Denner & van Wachem JCP 2015 · Crialesi-Esposito et al. CPC 2023 (FluTAS) · Lupo et al. 2025
(CaNS-Fizzy) · Roenby et al. RSOS 2016 · Mirjalili, Jain & Dodd CTR 2017 · Boniou, Schmitt
& Vié JCP 2022 · Cifani et al. C&F 2018 (TBFsolver) · Dodd & Ferrante JCP 2014 · Coyajee &
Boersma JCP 2009 · Balcázar et al. IJHFF 2015.

Part II (phase change): Hardt & Wondra JCP 2008 · Sato & Ničeno JCP 2013 · Palmore &
Desjardins JCP 2019 · Malan et al. JCP 2021 · Boyd & Ling C&F 2023 (arXiv:2211.16628) ·
Scapin, Costa & Brandt JCP 2020 · Gennari et al. CES 2022 · Cipriano et al. JCP 2024 ·
Tanguy et al. JCP 2014 · Aslam JCP 2004 · Bureš & Sato IJHMT 2021 + JFM 2021/2022 · Long
et al. JFM 2025 (arXiv:2503.12171) · Torres et al. JCP 2024 · Urbano et al. IJHMT 2018 ·
Kunkelmann & Stephan NHT-A 2009 · Dhruv et al. IJMF 2019 + Flash-X SoftwareX 2022 ·
Welch & Wilson JCP 2000 · Scriven CES 1959 · Berenson 1961 / Klimenko 1981.
