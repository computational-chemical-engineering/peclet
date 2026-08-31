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

**V1 — WY advection on prescribed velocity fields. ✅ DONE 2026-08-30** (flow `0440c08`;
`src/vof/advect_wy.hpp` + `tests/kokkos/test_vof_advect.cpp` + `tests/kokkos_mpi/
test_vof_advect_mpi.cpp`, ctests green on host-openmp AND CUDA, np 1/2/4 **bitwise**).
Own g=3 halo, 6-permutation sweep cycling, `parallel_scan` worklist (bitwise neutral,
0/54 872). Measured: planar slab under uniform flow transported **exactly** (Linf and drift
0.0 over 1024 steps); sphere-translation L1 order **2.23**; Zalesak L1/V **2.81e-2** at 100²
(published spread on the identical metric: THINC-scaling 1.55e-2 … THINC/QQ 3.22e-2);
LeVeque T=3 reversal L1(vol) 7.75e-3 / 2.68e-3 / **5.98e-4** at 32/64/128³, order 1.53 then
**2.16** — the published PLIC behaviour; volume drift ≤ 5.7e-14 against a measured discrete
face divergence ≤ 1.2e-15. Clipping OFF; wisp census recorded. Three things to carry
(details in `flow/doc/vof_workorders.md`):
- **The trap is now a number, not folklore**: `debugRecomputeDilation` ships default-off and
  gate G measures it — frozen flag **2.3e-15** vs recomputed per sweep **1.5e-2**.
- **§6's "hard CFL < 0.5" is the *2D* bound.** Weymouth's own thesis (Appendix A, eq. A.33 —
  the JCP paper's proof, and the primary source used, since the paper is paywalled) gives
  `|u|Δt/h < 1/(2(N−1))`, i.e. **1/4 in 3D**. Shipped at 0.5 per the WO, settable per
  instance, and conservation is provably *independent* of boundedness. A measured sweep to
  CFL 0.48 on LeVeque never left `0 ≤ C ≤ 1`, so the bound is sufficient, not tight.
- **The velocity must be discretely, not analytically, solenoidal.** The dilation term adds
  `H(C−½)·div·Δt/h` to *every* cell including interior full ones, so pointwise sampling pins
  the conservation floor at O(h²). Test fields are sampled as the discrete curl of an edge
  vector potential. For V2 the relevant number is the projection's own divergence residual.

**V2 — Two-phase NS, no surface tension (staggered).** Split into **V2a** (wiring, WO-J) and
**V2b** (momentum-consistent transport, WO-K) — `flow/doc/vof_workorders_v2.md`.

**V2a — C → closures → varRho projection. ✅ DONE 2026-08-31** (flow `45c3bd5`;
`src/vof/colour_field.hpp` + the VoF section of `flow_ibm.hpp` + harmonic-ρ_f siblings in
`mac_pressure.hpp` + `interfaceLocalCfl` in `advect_wy.hpp`; `tests/kokkos/test_vof_twophase.cpp`
and `tests/kokkos_mpi/test_vof_twophase_mpi.cpp`, 23/23 ctests on host-openmp AND CUDA, MPI
np 1/2/4 on both, single-phase regression +0.00 % with identical iteration counts). `"C"` is an
ordinary G=2 registered field (so ρ(C)/μ(C) are the existing `LinearMix` closures verbatim) and
the g=3 working block with its own `GridHaloTopology` belongs to the advector — flow's `G = 2`
untouched. Measured: hydrostatic ∂P/∂z = −ρ_f·g to **1.1e-15** through the C chain at ratio 1000,
and with the interface frozen the steady max|u| is **bitwise equal** to the hand-set-ρ reference
(`2.1760599219479075e-17`); colour volume drift a bounded **5.6e-13** over 1000 coupled steps;
C ≡ const bitwise inert and bitwise equal to the hand-set uniform-ρ varRho path; sharp-interface
Rayleigh–Taylor ×13.5 at **0.77×**√(Agk) against the diffuse record's ×13.0 at 0.75×; harmonic ρ_f
shipped default OFF and measured (it breaks hydrostatic balance to 0.34 relative — arithmetic ρ_f
is the harmonic mean of the mobility 1/ρ and the consistency requirement). Four findings in the
WO-J entry, three of them corrections to gates as written:
- **the two codes index a staggered face differently by one cell** (flow: low face; `WyAdvector`:
  high face). Omitting the shift is invisible in a uniform flow, in each axis' own divergence, and
  in `max|div(open·u)|` — and cost **35 % of the colour volume** over 1000 steps, because the
  advector sums the three axes AT ONE CELL. The shipped gate drives the solver and a standalone
  advector with the same physical LeVeque field.
- **the acid test's velocity half cannot be at machine zero with a FREE interface**: the colour
  field is an extra degree of freedom with loop gain g·Δρ·dt/ρ_g (= 100 at ratio 1000, g = 0.1,
  dt = 1), measured to scale with exactly that gain. Frozen-interface bitwise is the sharp gate.
- **the conservation gate is a gate on the pressure solver** — WO-E finding 2 said so in advance;
  the floor is `max|div(open·u)|` (1e-12…1e-11 here), not the advection.
- **a mixed-cell-only CFL band is empty on a grid-aligned sharp interface**; the band predicate is
  a colour *difference*. Measured over-throttle avoided: **22×**.

**V2b — momentum-consistent transport. ✅ DONE 2026-08-31** (flow `7d1a1f0`;
`src/vof/momentum_advect.hpp` + `plicBoxVolume` + `enable_vof_momentum`/`buildRhsVarMom`;
`tests/kokkos/test_vof_momentum.cpp`, `tests/kokkos_mpi/test_vof_momentum_mpi.cpp`,
`tests/study/vof_momentum_consistency.py`; green host-openmp AND CUDA, MPI np 1/2/4 on both,
single-phase regression +0.00 %). `ρ^c u_c` is advected on the half-shifted MAC control volumes by
the SAME PLIC planes, the same sweep order and one frozen dilation state as that step's colour
advection — the momentum sweeps are INTERLEAVED with the colour sweeps, because the planes are
overwritten every sweep. **The decisive gate is bitwise**: an arbitrary sharp C carried by a uniform
velocity comes out exactly uniform at ratios 1e1…1e4 on a slab, a tilted plane and a sphere, on one
rank and at np 1/2/4, with no tolerance. Five findings in the WO-K entry:
- **the uniform-velocity gate does NOT discriminate against the V2a baseline on this solver.**
  flow's momentum advection is in ADVECTIVE (non-conservative) form and the discrete advection of a
  constant by a divergence-free field is exactly zero, so a uniform velocity is a fixed point of the
  inconsistent scheme too. The `O(Δρ)` failure the test targets belongs to codes that advect ρu
  conservatively with a non-VoF mass flux. The gate is still the sharpest instrument in the rung —
  it caught three separate defects at 1.5e+06, 1.2e-13 and 2.2e-10 — but the CONTRAST has to come
  from a case where momentum actually transports.
- **the geometric flux must be clamped into Weymouth's own admissible interval on the shifted
  volume's colour.** It is bounded by what the CURRENT cell planes see in the donor, not by the
  ADVECTED `C^c`; the O(a²) gap drives ρ^c to −255 at ratio 1e4 (ablation: divergence at step 2).
- **the dilation COEFFICIENT ρ̂·u must be frozen across the three sweeps**, exactly as WY freeze
  H(C^n−½): per-step momentum drift **1.4e-7 → 2.2e-13**. General rule to carry — *every coefficient
  multiplying the divergence in a WY sweep must be a constant of the step.*
- **a MUSCL slope in the momentum flux is a density-ratio amplifier** on a control volume a sweep
  empties (gain Δρ·F/ρ^c); donor-cell upwind is the default (2.2e-10 → 6.7e-16 at ratio 1e4).
- **algebraic exactness is not enough for a 1e-15 gate** — two floating-point conditioning defects
  each degraded it *linearly in the ratio*, i.e. each mimicked the defect the rung removes. Storing
  ρ^c u loses the cancellation on a volume a sweep fills and the next empties; the shipped form
  evolves `u_new = u_old + dev/ρ_new`, in which every term is a velocity DIFFERENCE.
- **ESCALATED**: the coupled-loop residual is floored at 1.2e-7 by the solver's FLOAT
  momentum-operator storage (`Solver::FV`), not by VoF — a `-DPECLET_FLOW_MREAL_DOUBLE` A/B puts the
  same measurement at 1.2e-15, flat across four decades. V2b is honestly rated to ratio ~1e3 on the
  shipped build. Same float storage the S-rung has independently root-caused on the pressure
  operator; the fix belongs there.
- the Arrufat raindrop gate **cannot be run before V4** (it is held together by surface tension);
  the substitute is a viscous Stokes drop at the same ratio and 15 cells/diameter.
V2a is explicitly **valid only at modest density ratios for cases with motion** (no momentum
consistency), staggered only, and refuses an immersed solid.

**V2b — momentum-consistent transport** (half-shifted fractions, WO-K). Gates: the
uniform-velocity consistency test exact at 1e-15 across ratios 10…10⁴; falling raindrop at
ratio ~800 stable and accurate at ~15 cells/diameter (Arrufat criterion); the V2a battery re-run.

**V3 — Curvature. ✅ DONE 2026-08-31** (`src/vof/curvature.hpp` — container-free, the V4
promotion target — + `src/vof/curvature_field.hpp` + `compute_vof_curvature()` registering
`"kappa"`/`"kappa_branch"`; `tests/kokkos/test_vof_curvature.cpp` and
`tests/kokkos_mpi/test_vof_curvature_mpi.cpp`, green on host-openmp AND CUDA, MPI np 1/2/4
**bitwise** on both, single-phase regression +0.00 %). The Popinet cascade as specified: HF on
7-cell column sums over a 3×3 patch → the same in the other two directions → the **PV**
PLIC-volumetric paraboloid fit (Jibben 2019 / Han, Evrard & Desjardins IJMF 2024) on a 5³
Wendland-weighted stencil. κ = 2H in 1/h, positive for a liquid blob; plane, cylinder and sphere
all gated so the mean-curvature factor is measured. **No new halo** — the whole cascade reaches
exactly ±3, which is what the colour field's g = 3 already gives, and it contains no reduction at
all, hence the bitwise MPI. Measured: exact-fraction sphere 16³→32³→64³ **order 2.26 (L1) / 1.86
(max)**; the PV branch alone 1.96–1.99; plane 1.5e-14. Findings in
`flow/doc/vof_workorders_v34.md` (WO-O):
- **the fallback rate is ~19 % at D/Δ = 48, not Han's 2-D 0.9 %, and that is geometry.** In 3D the
  corner column of a 3×3 patch must span √2·s where the preferred-direction slope reaches √2 on the
  octant diagonal — 2.5 cells, exactly a 7-column's capacity — so the failing fraction is
  *resolution-independent*. Han et al. use NH = 11 in 3D for this reason; NH = 11 needs g = 5. **The
  one place a wider halo would buy something**, and it is not needed: PV serves those cells at
  order ~2.
- **the advection-realistic plateau sets in between CΔ ≈ 0.16 and 0.08** (max error 1.60e-1 →
  1.53e-1, order 0.07, while the exact-fraction control on the same geometry keeps converging at
  2.16). Consequence for V4: at pore-scale resolutions the curvature error is set by the transport,
  so the spurious-current budget is spent on the balanced-force identity, not on a fancier κ.
- **tier 2b (the mixed height-position fit) ships OFF, measured.** It takes over the 19.5–59.6 % of
  cells tier 1 cannot serve and destroys the max-error convergence (order 0.00 vs 1.86) for every
  Wendland width from 1.5 to 6.0 cells, because its data set is the columns that CLOSED — a
  slope-selected, asymmetric subset whose lever-arm bias is scale invariant. PV is immune because a
  PLIC polygon exists at every slope. Caught by the WO's own "report max and L1 separately" gate.
- **a sign error in Han et al.'s published eq. (14f)**, found and corrected (the `∫y'²dA` edge
  factor); the second such defect this campaign has found in a published listing, both caught by a
  hand-computable case that the randomized batteries miss.

**V4 — Balanced-force CSF + capillary time step. ✅ DONE 2026-08-31** (flow `cd507ba` /
`f2fea3f`; `src/vof/surface_tension.hpp` + `Solver::addCsfRhs`, ctest `vof_surface_tension`,
`vof_surface_tension_mpi_np{1,2,4}`, `tests/study/vof_surface_tension.py`; WO-P in
`flow/doc/vof_workorders_v34.md`). The face force is `σ·κ_f·(C(i) − C(i−s_c))/h` with the
**projection's own difference operator** — deliberately NOT through the per-cell force field,
whose face rule is an arithmetic interpolation (right for `ρg`, wrong for `σκ∇C`); the
interpolated variant ships as the ablation `set_csf_mode(1)`.
- **The stationary-droplet gate is at machine zero**: max|u| **3.6e-17 / 1.9e-17 / 2.4e-17** at
  16³/32³/48³ and **9.4e-17 … 4.3e-18** over μ = 1e-3…1. The ablation reads **5.8e-2 (Ca 5.8e-3),
  3.0e+15×** — the literature's "naive CSF ~1e-2" as a switch. Young–Laplace exact to 2.2e-16 and
  `P = σκC + const` to 2.6e-15 field-wide.
- **Ca ≲ 1e-7 is NOT reached with a computed curvature and cannot be**: measured **2.5e-4 / 5.9e-5 /
  2.6e-5 / 1.4e-5** at D/Δ = 8/16/24/32, order 2.1. `Ca ≈ δκ·h`, so the budget is a *curvature*
  requirement, and V3 measured curvature error to stop converging with advection-realistic
  fractions. The force discretization is exact; the estimator is the ceiling.
- **Hysing both cases within 3 %** (case 1 +3.3 % / −0.02 %, case 2 +2.9 % / −2.6 %), and
  **momentum consistency is worth 14 % of that at ratio 10** — the discriminating case V2b never
  had. Capillary wave vs the dispersion relation −2.1…−3.7 %; Lamb mode-2 **−6.3…−7.0 %**, an
  open measured deviation with amplitude, dt, initialisation, confinement and resolution all
  ruled out by ablation.
- **The capillary Δt binds everywhere at pore scale** — 18 of 18 sweep combinations, by factors 6
  to 5.9e4, and *more* under refinement (`dt_σ ~ h^{3/2}` vs `dt_CFL ~ h`). Cost: 1e6–1e7 steps
  per pore volume at Ca ~ 1e-6. That is the number implicit surface tension would have to beat.
- **The rung found a V3 defect**: WY round-off colour residue makes ~5300 extra cells "interfacial"
  at 64³, for which the cascade returns |κ| up to **2.9e+11**; under a force that destroys the run.
  Fixed by `VofCurvature::interfaceEps` (default 0 = V3 unchanged; `set_surface_tension` sets 1e-8).
  This is §6's "clipping is unavoidable once surface tension is on", in its cheapest form.
- **And it corrected the V2b falling-drop gate**: a periodic zero-mean body force conserves
  *momentum*, not volume flux, so the lab-frame drop velocity is a near-cancellation; the relative
  velocity reaches 0.79/0.83/0.87 of Hadamard–Rybczynski at D/h = 10/15/20 and is insensitive to
  the momentum-sweep count, refuting V2b's suspected mechanism.

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

**⚠ V4's measurements change V7's premises — read before scoping the pore-scale campaign.**
1. **The Ca ≲ 1e-7 spurious-current budget is NOT reachable, and the reason is structural.**
   With an *exact* κ the balanced force gives spurious Ca = **1.9e-18** (max|u| 1.93e-17) —
   the force itself is exact. With the *computed* κ, Ca = 2.5e-4 / 5.9e-5 / 2.6e-5 / 1.4e-5
   at D/Δ = 8/16/24/32 (order 2.10). Since Ca ≈ δκ·h, the budget is a **curvature**
   requirement, and V3 measured curvature error to stop converging with advection-realistic
   fractions. So the 1e-7 figure quoted from the literature in §2 is a target for the
   *estimator*, not something the force discretisation can deliver — plan capillary-dominated
   cases around the achievable Ca at the resolution you can afford, or improve κ (V5's RDF,
   or ELVIRA/LVIRA on 5³), not the force.
2. **The capillary time step binds everywhere at pore scale, and worsens under refinement.**
   Measured over 18 combinations (50/200 µm pores × 16/32/64 cells/diameter × Ca 1e-6…1e-2):
   it binds **18 of 18**, by factors 6 to 5.9e4, and increasingly so as `dt_σ ~ h^{3/2}`
   against `dt_CFL ~ h`. **Cost: 3.8e6–3.0e7 steps per pore volume at Ca ~ 1e-6.** That is the
   dominant feasibility constraint on V7 and it is arithmetic, not tuning. Consequences to
   decide before committing to the campaign: pick the largest Ca that still answers the
   physics question; budget wall-clock from a measured ms/step; and note this **reopens the
   implicit-surface-tension question** the plan parked on Popinet (2018)'s advice — his "not
   yet worth the complexity" was written for cases where the capillary limit is not 4 orders
   inside the advective one. Hysing confirms the crossover is real and not universal: case 1
   is capillary-bound 204/204 steps, case 2 (ratio 1000, σ 12.5× smaller) is CFL-bound
   108/113.

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
  - ~~**S0 — measure before investing**~~ — **DONE 2026-08-30 (WO-B)**, and it **refutes the
    diagnosis this ladder was built on**. `flow/tests/study/vardensity_solver_probe.py`, 406
    configurations × 20 steps, CUDA + host; full numbers in `flow/doc/vof_workorders.md`
    (WO-B findings) and the superseding note in `flow/doc/variable_density_projection.md` §2.
    (a) `set_pressure_pcg(True, …)` **ignores its flag** — it never clears `useChebyshev_` — so
    §2's "PCG" control, and every later varRho PCG measurement, actually ran Chebyshev.
    (b) With PCG really selected the stall reproduces (2000/2000 its on the literal §2 column),
    but it is **not a ρ effect**: the identical stall occurs at **constant density** on any 3-D
    wall-bounded (domain-BC) grid — 200/200 with max|div(open·u)| ≈ 1.2e-05 once the third axis
    reaches 8 cells, Chebyshev 13–14 on the same operator — and does **not** occur on a periodic
    + IBM problem at any ratio (periodic cylinder, real PCG: 7–10 its at ratio 1 … 10⁴). Present
    in the 2026-07-06 release build; invisible so far only because every shipped domain-BC
    verification is quasi-2D (nz = 4).
    (c) Chebyshev is **flat in the ratio** on every well-resolved geometry (11–18 its, 1.00–1.09×
    from ρ≡1 to 10⁴; smooth vs sharp is not a significant axis, and the *smooth* edge is the
    marginally worse one). The only hard geometry is the real `packing_ring.vti` bed — but there
    **MG-PCG needs 16 its at ratio 10⁴ where Chebyshev needs 155**, so that is a Chebyshev
    spectrum-bound weakness, not a coefficient-coarsening problem.
    **Consequence for the rungs below: S3/S4 are NOT indicated by any measurement** and should
    stay parked; the actionable items are the two escalations (the `set_pressure_pcg` no-op and
    the domain-BC PCG stall — each needs its own WO), then S1 (FCG), which is exactly the remedy
    for the non-SPD-preconditioner failure that was measured, gated on this battery. S2 is worth
    **3×** on the varRho pressure stage for as long as Chebyshev is the default: the per-step
    bound re-estimation is 30 extra V-cycles, measured at 21.2 ms of a 31.6 ms projection (67 %).
  - ~~**S1 — flexible CG (FCG/IPCG)**~~ — **DONE 2026-08-30 (WO-C)**, and it **settles the
    diagnosis**. `set_pressure_fcg` / `CutcellMG::solveFCG` (Polak–Ribière β, +1 vector,
    +1 dot/iteration, 2 % projection-time overhead, default off, single-phase regression
    +0.00 %). Full numbers: `flow/doc/vof_workorders.md`, WO-C findings; reproduce with
    `vardensity_solver_probe.py --drivers pcg,fcg`.
    (a) **The V-cycle preconditioner is NOT symmetric w.r.t. the fine operator, and the
    asymmetry comes from the domain BCs at the FIRST coarse level.** FCG converges on **93
    of the 130** battery configurations where MG-PCG fails, with **0** regressions — e.g.
    constant-density lid box 32³, PCG 200/200 (div/u 1e-5) vs FCG 20 (div/u 8e-14). The
    contamination term FCG removes, `pr = |rᵀz_k|/|rᵀz_{k+1}|` (exactly 0 for a symmetric
    preconditioner, printed under `PECLET_FLOW_MG_DEBUG=2`), measures **0.062 median**
    periodic + IBM against **0.43–0.48** wall-bounded on the SAME geometry, and it is
    already full-size at `levels=2` (`levels=1` solves in 1 iteration). ⇒ WO-H should
    target `applyBoundaryOpenness`'s per-level re-imposition and the non-periodic
    prolongation ghosts as an adjoint pair.
    (b) Where PCG is healthy the two βs coincide algebraically and the drivers agree
    exactly: periodic cylinder 7/7, 3-ring bed 10/10, `packing_ring` 64³ 14/14; at ratio
    10⁴ FCG 16 vs Chebyshev 155. **FCG is a strictly-safer drop-in for MG-PCG on the
    production pore-scale path.**
    (c) **Two residual modes FCG does NOT cover**, both new and both for WO-H: the
    gravity-driven hydrostatic column with a *global* stratification (`hydro` × slab/tilt,
    all 36 configurations — the residual *freezes* at `r/r0 = 6.98` with `pr` locked at
    0.500, a stationary iteration, while Chebyshev returns the machine-exact rest state),
    and a small coefficient ρ₀/ρ_f adjacent to a *prescribed-velocity* face (ratio ≥ 10²;
    all-wall configurations are healthy at every ratio). **Chebyshev stays the varRho
    default** — it is the only driver healthy on all four regimes — so S2 keeps its 3×.
  - **S2 — bound amortization for moving interfaces**: at capillary-limited dt the
    interface crosses a cell over many steps → coefficients drift slowly; freeze Chebyshev
    bounds for N steps (safety-inflated, residual-guarded re-estimate on violation) +
    φ warm start. Turns the per-step re-estimation cost into noise.
  - **S3 — coefficient-aware coarsening, structure-preserving**: keep the 7-band
    rediscretized hierarchy but coarsen coefficients as a resistor network (parallel:
    sub-face conductances add — the current `coarsenOpenAvg` is already correct here;
    series: add the two half-cell resistances through the coarse cell along the normal —
    the missing "half-harmonic" step, cf. Alcouffe et al. 1981). Cheap, no stencil growth.
    **✅ RESOLVED 2026-08-31 by WO-M: S3 STANDS — there are TWO mechanisms, not one.** The
    dense-preconditioner probe was rebuilt as a committed instrument
    (`flow/tests/study/mg_precond/`) and run on default vs `-DPECLET_FLOW_MREAL_DOUBLE`
    builds with nothing else different: **the negative pivot survives in double, unchanged
    to 3–4 significant figures at every contrast** (first real negative eigenvalue of
    `sym(M)` at ratio ~1e3 wall-bounded, ~1e4 periodic, in *both* precisions; at 16³/4
    levels the periodic 1e3 case grows to two negatives, so the defect deepens with depth).
    So WO-H's coefficient-coarsening evidence was **not** contaminated by float storage, and
    the "strike S3" prediction below was **wrong**. Two method corrections that strengthen
    WO-H: `sym(M)` is singular by construction, so its "1 negative pivot (−1.1e-12) at ratio
    1e2" was sign noise (it flips between builds), and the unpivoted LDL breaks down near
    the transition — **the mean-free restricted spectrum is the reliable read-out**.
    The float `A·1 ≠ 0` defect is separately real and contrast-amplified as claimed (up to
    4.6e-2 relative to the small couplings at ratio 1e6, vs 5e-11 in double) — but it does
    **not** move `M`'s spectrum. **Two loci, two mechanisms, two signatures**: the float
    floor is resolution- and depth-independent (a fine-level storage defect); S3's
    indefiniteness deepens with depth (a coarsening defect).

    **Resolution-aware tolerance — adopt this in every gate.** WO-M measured
    **κ(A) ≈ 0.18·N²·contrast** (×4 wall-bounded), exactly linear in contrast and quadratic
    in N. At ratio 1000 on 256³ that is κ ≈ 1.2e7, so the fp64 attainable limit is ~1e-9
    before the O(1)–O(10) constant: **a fixed rtol of 1e-8 is already within a small factor
    of the arithmetic limit there, and unreachable at 512³ or ratio 1e4.** Use
    `rtol = max(1e-8, C·eps·0.18·N²·Δρ/ρ)` — the analogue of the collocated campaign's
    `PRTOL = 2e-7`. Gates must not demand what the arithmetic cannot deliver.

    **Precision policy (WO-M, stated as a rule rather than a patch)**: *a quantity an
    algorithm requires to satisfy an exact discrete identity must be stored in the precision
    in which that identity is asserted; a quantity carrying only an approximation may stay
    float.* Here the identity-bearing quantity is the operator **diagonal** in both
    operators; the six face couplings are the approximation. Tested directly by the
    `PECLET_FLOW_MG_DIAGRESUM=1` ablation (bit-for-bit double-diagonal arithmetic), judged
    against a **matched full-double control**: it recovers full-double behaviour at every
    grid from 48³ to 160³. **Recommendation: ship the double-diagonal in both operators**
    (+17 B/cell against a measured +120 B/cell and +12 % time for full fp64) as a follow-on
    work order — it is view-type surgery through smoother/residual/matvec/CA-ring/AMG, not a
    line edit. **Do not make fp64 the default**: it buys nothing on Z&H drag, permeability or
    the regression suite. Keep `-DPECLET_FLOW_MREAL_DOUBLE` documented as the validated
    escape hatch for high-contrast beds.

    **Next unexamined locus, correctly scoped (2026-08-31):** the cut-cell IBM geometry is
    still float — `IbmOverlayT` carries `View<float*>` for `D_rescale`, `K_val`, `M_val`,
    `X_val`, `Nbc_val`, `R_val` (`cut_cell_ibm.hpp:74`) — and `MReal` does not reach it. But
    this is **velocity-side only**: the *pressure* operator's geometry is the openness, and
    `CCField = View<double*>` (`mac_cutcell.hpp:22`), so float geometry **cannot** set a
    pressure-solve floor. It is a momentum-side accuracy audit item, not a candidate
    explanation for a pressure residual floor. (I first proposed it as the latter; the
    collocated campaign corrected it and the types confirm them.)

    **And that floor now has a closed explanation, with no locus left to chase.** The
    collocated campaign checked WO-M's κ formula against their own data: `eps_f64·κ` at
    contrast 1e3 gives ~1.5e-9 at 192³ (below their rtol 1e-8, which is why their local
    float/double A/B converged cleanly) and ~4e-8 at 384³ — *exactly* their measured
    full-double floor, and why the same build cap-burned there. One formula, both
    observations, no free parameters beyond an O(1) constant; it further predicts ~2.4e-8 at
    768³, giving their `PRTOL = 2e-7` about 8× margin by derivation rather than by taste.
    Their floor is **attainable accuracy**, full stop.

    **Earlier note, now corrected — "the mechanism is PRECISION and S3's evidence is
    contaminated" (this prediction did not survive measurement).** The collocated-paper campaign
    made `MReal` compile-switchable (`-DPECLET_FLOW_MREAL_DOUBLE`, smoothers/matvec
    templated on the coefficient view type, default float untouched) and ran the same
    192³ high-contrast bed both ways: **float** — PCG reaches 8e-7 then *rebounds* to
    3.8e-5 and burns its 300 cap, FCG floors at 2e-6, Chebyshev cap-burns; **double** —
    clean monotone convergence to rtol 1e-8 in ~86 iterations/step, no floor, no rebound.
    Same geometry, same hierarchy, same drivers; only the operator storage changed.
    Mechanism: float rounding breaks `A·1 = 0` per row at eps_f32, and under ~3 decades of
    contrast the defect on rows mixing large and tiny couplings is ~1e-4 *relative to the
    tiny coupling*, shifting the near-null vector off the constant that mean-removal
    deflates — i.e. the `:1411` agglomerated-bottom failure generalised to **every level**.
    **Consequence for S3: WO-H's negative LDLᵀ pivot was measured on a V-cycle assembled
    from this same float-backed hierarchy, so a float-perturbed near-singular operator is a
    sufficient explanation and we have no result separating the two.** Rerun the WO-H dense
    probe on a `-DPECLET_FLOW_MREAL_DOUBLE` build *before* investing in coefficient
    coarsening: pivot disappears in double ⇒ S3 loses its evidence and the real work item is
    **precision policy**; pivot survives ⇒ S3 stands and there are two independent
    mechanisms. Best-targeted candidate fix (theirs, and better than resistor-network
    coarsening): a **double-diagonal** variant — keep the six face coefficients in float,
    store and resum the diagonal in double so `A·1 = 0` holds exactly, +4 B/cell against
    +28 B for a full fp64 hierarchy. Data: `flow/doc/data/collocated_campaign/`. Build note:
    CUDA 12.x nvcc ICEs on the pre-fix code; their templating cures it, or use CUDA 13.
    **This plausibly reaches VoF directly** — two-phase at ratio 1000 puts ~3 decades of
    contrast into the pressure operator by a different route (a smooth density jump, no cut
    cells), so V2b's ratio sweep doubles as an independent reproducer.

    **Earlier note, now subsumed — rule out an fp32 floor FIRST.** The MG operator
    storage is **single precision** (`mac_cutcell_mg.hpp:51`, `using MReal = float`,
    "Operator stored single-precision + double iterate, exactly as CUDA"), and `:1411`
    already documents a float-induced failure in this same hierarchy: float storage
    "breaks that identity at ~5e-8 relative … measured as the inner CG flooring at ~1e-5
    and burning its full iteration cap every call", cured there by a targeted
    **double-precision resum**, not by an fp64 hierarchy. The collocated-paper campaign
    independently measured a high-contrast stall flooring at |r|∞ ≈ 3e-8 — right at that
    number — with `pr` starting at 1e-15 and growing only as the residual falls to ~1e-6,
    which is the signature of a fixed-*absolute* perturbation becoming relatively
    dominant, **not** of an indefinite preconditioner (a negative eigenvalue is present
    from iteration 1). WO-H's negative pivot was found in the *assembled* preconditioner
    and so is independent of residual level: **the dense-LDLᵀ negative-pivot probe
    discriminates the two mechanisms directly** and runs in seconds at 48³ on the
    collocated campaign's reproducer (fully periodic, no domain BCs, no VoF, no varRho,
    analytic SDF bed, contrast tunable by `PECLET_FLOW_APERTURE_ORDER=1|2`). A
    coefficient-coarsening fix that ignores a precision floor is a wasted campaign — so
    S3 starts with that probe, on that reproducer, not with `coarsenOpenAvg`. Note also
    that `buildOpenness` feeds both the geometric openness and the coefficient path, in
    this code and in theirs: any change there has two consumers.
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
- ~~**MPI + CUDA validation of the varRho/varMu paths**~~ — **DONE 2026-08-30 (rung V-1 /
  WO-A)**: `tests/kokkos_mpi/test_{vardensity,varmu}_mpi.cpp`, np 1/2/4 on host-openmp AND
  nvidia-cuda (np=1 bitwise, np>1 at the MPI reduction-order floor, ≤3e-19…6e-17 on u);
  hydrostatic max|u| 2.75e-17 at ratio 1000 on CUDA; RT reproduces the host record
  digit-for-digit; single-phase regression +0.00%. **The Chebyshev bounds path IS
  decomposition-independent** — on a non-degenerate solve the V-cycle count is identical at
  np=1/2/4 (and across thread counts). Two OPEN gaps escalated out of it, both in the
  DOMAIN-BC machinery rather than the variable-property path — per-face domain BCs have no
  rank-ownership test, and `fillPropGhosts`/`fillPorousEpsGhosts` skip their domain-face
  override under MPI. **Both must be fixed before any wall-bounded two-phase MPI case**
  (V2+ with walls, and the boiling/porous work of Part II). See
  `flow/doc/variable_density_projection.md` §3.1/§4 and the WO-A findings log.
- **`bcCorrectOutflow` lacks the 1/ρ_f factor** (known gap, variable_density doc §4) —
  needed before any two-phase outflow case.
- **Ghost-projection / porous-ε paths throw under varRho** (`flow_ibm.hpp:3486,:3516`).
  Two-phase-in-porous-ε (volume-averaged two-phase) is explicitly out of scope here; the
  gates stay.

## 6. Traps (from the literature, pre-loaded)

- WY boundedness is a **hard CFL cap of 1/(2(N−1)) — 1/2 in 2D but 1/4 in 3D** (Weymouth
  thesis eq. A.33; MEASURED 2026-08-30, and this plan's own §2 quoted the 2D value). The
  shipped default is the proven 3D bound, inclusive. The dilation coefficient is frozen
  *once per step* across all three sweeps — recompute it per sweep and exact conservation
  silently dies (measured: drift 2.3e-15 → 1.5e-2, a factor 6e12).
- **A global CFL max over-throttles**: on Zalesak the domain-corner faces run at 0.314
  while the interface never exceeds 0.157. Weymouth's bound is per-flux, so **V2's dt
  limiter must take its CFL over interface-adjacent cells**, not the whole domain, or
  quiescent far-field corners will shrink the step for nothing.
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
