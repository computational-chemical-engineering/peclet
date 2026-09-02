# VoF campaign — handoff for the next session

**Status 2026-09-02 (Fable, finishing campaign started).** Items 1–4 below are the 2026-08-31
handoff; their state now:

- **Item 1 — precision:** RESOLVED by the defect-correction campaign (P1 passed, double-diagonal
  retired; `DEFECT_CORRECTION_PLAN.md`). Open for VoF: whether `enable_vof` should switch the
  exact residual on (WO-R item 6 measures Hysing case 2 both ways).
- **Item 2 — Lamb mode-2:** TRACED IN PART. (a) *Cheapest hypothesis first, as instructed*: the
  capillary WAVE deviation is 100 % the inviscid reference. The exact normal-mode relation for an
  interface between two semi-infinite fluids of equal ρ and ν is
  `s² + ω₀²(1 − k/√(k² + s/ν)) = 0` (derived from the even-ŵ solution `A e^{−kz} + B e^{−mz}`,
  `m² = k² + s/ν`, continuity of ŵ, ŵ′, ŵ″ and the normal-stress jump `μ[ŵ‴] = −σk⁴ŵ(0)/s`; first
  order: `Δω/ω₀ = −γ/ω₀ = −k√(ν/ω₀)/(2√2)`). With the finite-depth `coth(kH)` factor the
  measured ω agree to **−0.03 %, −0.23 %, +0.52 %** (WO-P's −2.20 / −2.07 / −3.64 % against the
  inviscid formula), and the measured decay is within 5–24 % of `−Re s` (a two-extremum fit).
  The reference `2νk²` WO-P used is the *free-surface* rate; the two-fluid rate is the O(√ν)
  boundary-layer term, 3–4× larger. (b) The DROP is different: a viscosity sweep μ = 0.02 →
  0.00125 at 32³/R = 8 leaves the frequency deficit flat at **−6.95 → −6.3 %** while the damping
  scales as √ν as it should, so the deficit is **inviscid**; and a static test of the cascade's κ
  on the initial prolate spheroid puts the P2 component within **+2.6 / +1.0 / +0.55 %** of the
  analytic value at R = 8/12/16, so it is **not a static curvature bias** either. Confinement
  accounts for ~0.6 % (−6.27 % at 32³ → −5.63 % at 48³, same R = 8). Remaining candidates under
  test: the moment-based frequency measurement (a damped-sinusoid fit on saved series), the
  dynamic (advected-fraction) curvature, and a resolution ladder at fixed confinement
  (R = 8/12/16). The quasi-2D cylinder mode-2 case gave erratic deficits (−4.7 / −8.9 / −3.9 % at
  R = 8/12/16), which points at the measurement. Findings will be appended here.

  **Addendum (same day, all at ν = 0.0025 unless stated; scratch scripts `lamb_*.py`,
  `drop_modes.py`, `dispersion.py`, `fit_series.py` in the session scratchpad):**
  - *Measurement is sound*: a damped-sinusoid fit of the saved P2-moment series returns the
    zero-crossing frequency to 0.01 %; the polar half-height and the equatorial half-width give
    −5.7 / −5.0 % against the moment's −5.6 % (48³, R = 8); volume drift 2e-14.
  - *Exact viscous drop modes computed* (unsteady Stokes, equal ρ and ν, potential + poloidal
    vortical parts, 4×4 determinant): Δω/ω₀ = −0.885·√(ν/(ω₀R²)) to first order — **−5.0 % at
    ν = 0.02, −1.8 % at ν = 0.0025** (R = 8). The simulation captures only part of it (its
    damping is 25–43 % below the exact −Re s) because the interfacial boundary layer
    √(ν/ω₀) is 0.1–0.45 cells; a resolved-viscous Lamb test needs R ≳ 32.
  - *Inviscid residual after subtracting the exact viscous shift*: **−3.9 / −3.4 / −3.9 %** at
    R = 8/12/16 (48³/72³/96³, φ = 1.9 %) — resolution-independent. The quasi-2D cylinder
    (mode 2, `ω² = 6σ/(2ρR³)`) shows ≈ −2.5 % after the same subtraction.
  - *Not the estimator*: with the curvature FROZEN to the exact curvature of the moment-fitted
    spheroid every step (`set_vof_kappa_frozen` + `set_field("kappa")`), the deficit is
    **larger**, −9.0 % (ν = 0.0025) / −9.5 % (0.02); the cascade's κ carries a +3 % P2
    over-estimate that partly compensates. Dynamic (advected-fraction) P2 content of the
    cascade's κ stays within +2…+5 % of the fitted spheroid's over the whole oscillation.
  - *One-step impulse test* (spheroid at rest, one CSF step, projected velocity along the axis
    against the exact potential-flow impulse response with `η₂ = εR`, `δκ₂ = 4η₂/R²`):
    0.94 inside / 0.98 outside, resolution- and κ-source-independent. BUT the planar standing
    wave gives 0.956 by the same instrument while its *frequency* is exact to 0.03 %, so a
    weak first impulse does not by itself set the frequency — the instrument is not decisive
    and the analysis needs the full linearized discrete loop.
  - **Where it stands**: a ~3.5–4 % inviscid, resolution-independent mode-2 frequency deficit
    specific to curved interfaces (2-D cylinder ~2.5 %, 3-D sphere ~4 %), not attributable to
    the reference, viscosity, confinement, amplitude, time step, the measurement or the
    curvature estimator. The untested link is the **transport**: whether WY advection of a
    curved interface by the mode's velocity field moves the P2 moment at the exact rate — a
    kinematic test with the prescribed potential-flow field, runnable once WO-Q's
    `advect_vof(dt)` exists. Recorded as an open measured deviation; the example page states it
    as such (Basilisk's own `oscillation.c` reports a few % at comparable resolution, so it is
    not exotic, but ours does not shrink with resolution and theirs does).
- **Item 3 — V3 curvature issues:** carried into WO-S/WO-U as measurements (branch census on
  every page); no change to the cascade planned before the examples exist.
- **Item 4 — V5–V7 scope:** V5 is split into V5a (transport in cut cells, WO-Q) and V5b (the
  θ-fill, WO-S), a new V-BC rung (WO-R) covers open boundaries, V8 is pulled forward in minimal
  form (WO-T) because the examples must run on the collocated grid too. See `VOF_PLAN.md` §12.

---

Written 2026-08-31 at the end of the session that built V0–V4. **Read this first**, then
`VOF_PLAN.md` (the campaign plan, now carrying measured results), then the findings logs in
`flow/doc/vof_workorders*.md`. Everything below is *decided and unstarted* — the user
authorized these four items and deferred them to a later session because budget was low.

## Where the campaign stands

**Part I rungs V0–V4 are complete**, gated on host-openmp and nvidia-cuda, np 1/2/4 bitwise,
single-phase regression +0.00% throughout. 26/26 kernel ctests, 60/60 MPI ctests.

| rung | what shipped | headline number |
|---|---|---|
| V0 | `src/vof/plic.hpp` — SZ/Lehmann–Gekle plane↔volume, MYC normals, slab flux | round-trip 6.7e-15 over 1e5 samples |
| V1 | `src/vof/advect_wy.hpp` — Weymouth–Yue split advection, own g=3 halo | volume drift 2.1e-16 over 1024 steps |
| V2a | `src/vof/colour_field.hpp` — C in the solver, closures, interface-local CFL | ∂P/∂z to 1.1e-15 at ratio 1000 |
| V2b | `src/vof/momentum_advect.hpp` — momentum-consistent transport | uniform-velocity identity bitwise on advection |
| V3 | `src/vof/curvature.hpp` — HF cascade + paraboloid fallback | sphere order 2.26 (L1) / 1.86 (max) |
| V4 | `src/vof/surface_tension.hpp` — balanced-force CSF + capillary dt | stationary droplet max\|u\| 1.93e-17, Ca 1.9e-18 |

Four pre-existing production defects were found and fixed en route (rank-unaware domain BCs
across 12 sites, body-force ghosts, `drag_beta` ghosts, the MG prolongation ghost), plus two
published-algorithm errors corrected (Lehmann & Gekle's Listing 1 case boundary; Han et al.
eq. 14f sign).

---

## Item 1 — Precision: evaluate defect correction FIRST, then the double-diagonal

**⚠ EVALUATE THIS BEFORE IMPLEMENTING ANYTHING (user proposal, 2026-09-01).** The user
proposed the scheme WO-M never considered, and it may make the double-diagonal unnecessary:

> 1. Compute `r = b − A_exact·x` with `b`, `A_exact`, `x` all in double — **matrix-free**, as
>    `r(x)`, which also generalises to a nonlinear residual.
> 2. Solve the correction approximately in float: `A_float·dx = −(float)r`, then
>    `x ← x + (double)dx`.

**Why this is stronger than the double-diagonal**: it makes the float operator's errors
*irrelevant* rather than smaller. Once the residual and matvec use the true operator, the float
hierarchy is a **pure preconditioner**, and a preconditioner's errors affect only the
convergence rate, never the fixed point — so `A·1 = 0` breaking inside it stops mattering. The
double-diagonal instead patches the operator so it can keep serving as both the problem
definition and the preconditioner; defect correction removes that double duty.

**Why it is cheap here**: `buildCutcellOp(OpV AC, …, CCConst ox, CCConst oy, CCConst oz, …)`
(`mac_pressure.hpp:24`) assembles the bands from the **openness, which is already double**
(`CCField = View<double*>`, `mac_cutcell.hpp:22`), and the coefficient is a local function of
openness and the ρ face mean. So the fine-level matvec can be **matrix-free in double with no
new storage** — and the fine-level float bands could be *dropped*, saving ~28 B/cell instead of
adding 17. On a bandwidth-bound kernel that trades flops for traffic in the favourable
direction. Coarse levels stay float; they only live inside the preconditioner.

**Caveats to check**: the optional star overlay (fluid-only constraint, `star_elimination.hpp`,
used by the collocated ghost path) applies extra couplings as a separate delta, so a
matrix-free fine matvec must carry it or be restricted to the standard path. And the
conditioning ceiling does not move — this removes the *float* floor, not `eps_f64·κ`.

### Verdict of the evaluation (2026-09-01, by source inspection — no run yet)

**Go.** Every premise holds, the change is *smaller* than the proposal assumed, and on the one
identity that matters it is strictly stronger than the double-diagonal. Three corrections to the
framing above, in descending order of importance.

**RESULT (2026-09-01): P1 PASSED, and it retires the double-diagonal rather than deferring it.**
Measured on the RCP bed, PCG rtol 1e-8 cap 300, nvidia-cuda (P1 session, plan §4 carries the full
table and traces):

| Ng | float bands | exact residual | DIAGRESUM | full double |
|---|---|---|---|---|
| 48 | 24, div 4.51e-06 | **14, div 9.51e-12** | 14, div 6.19e-10 | 14, div 9.51e-12 |
| 64 | 33, div 6.48e-07 | **14, div 9.53e-12** | 14, div 1.24e-09 | 14, div 9.53e-12 |
| 96 | **300 CAPPED (invalid)**, div 4.36e-06 | **28, div 3.17e-11** | 28, div 2.04e-09 | 28, div 3.17e-11 |

Not a shared floor (the trap the collocated finding warned of): the columns do *not* all agree —
float separates sharply — and the residual traces show float plateauing then rebounding (floor
1.115e-08 at it 14, final 8.657e-04, **rebound ×7.8e4**; Ng=96 ×1.6e5) while every exact solve is
monotone, rebound ×1, crossing rtol far under the cap. The warm leg inverts the worry outright:
Ng=96 float is [45, 300, 300, 300] across a 4-step march — the *cold* solve converges and the
*warm* ones cap — against exact [21, 25, 27, 28], march-stable.

**The decisive number is the one this evaluation did not predict.** Exact and DIAGRESUM agree on
iteration counts but separate **65×** on flux divergence (9.51e-12 vs 6.19e-10 at Ng=48; 3.17e-11 vs
2.04e-09 at Ng=96), while exact matches full double to every printed digit. The double-diagonal
converges to the *float-face* operator's solution; the exact residual converges to the true one.
So the bitwise-vs-`eps_f64` distinction argued below is not academic — it shows up in a physical
output, and the fallback is **measurably worse, not merely unnecessary**. The double-diagonal is
retired as an option, not held in reserve.

**Correction to point 1 below (found by the P1 session, verified here).** `matvecOverlap` is NOT
the single choke point for all three drivers: `solveBiCGStab` has its own inline `matvec` lambda
(`mac_cutcell_mg.hpp:995` distributed-g2 branch, `:1003` single-rank) calling `applyCutcellOp` with
the float bands directly, because the g=2 gp staging needs it. P1 therefore covers `solvePCG` and
the flexible PCG only; the two BiCGStab sites belong with **P2**, which owns the gp overlay that is
the reason BiCGStab has a separate matvec at all.

**Correction to the cost claim (P1 measurement).** Per-matvec the exact form is **slower**, not
free: +6.5 % (N=128) / +16.8 % (64) / +31.2 % (96). The byte count was right (24 vs 28 B/cell, 0 B
new storage confirmed) and the *access pattern* was not — the bands are 7 perfectly coalesced loads
all at index `i`, while the flux form loads at `i` and `i ± sx/sy/sz`, touching more distinct cache
lines. At step level it is +0.1…+0.4 %, because the matvec is a small part of the step. This is
P3's go/no-go input, not P1's: P3 moves that penalty into the **smoother**, which runs many times
per V-cycle instead of once per PCG iteration.

**1. No outer defect-correction loop is needed — the structure is already there.** `solvePCG`
(`src/mac_cutcell_mg.hpp:769`) already separates the two roles: a `matvec` lambda and a `precond`
lambda that runs one symmetric V-cycle. The float hierarchy is *already* only a preconditioner
everywhere except that the level-0 `matvec` and the initial residual read the float bands. Make
the level-0 apply exact and the Krylov fixed point becomes `A_exact` by construction; the
proposal's steps 1 and 2 are then just what PCG already does. The work is one kernel plus a
switch at `matvecOverlap` (`:1715`), the choke point for `solvePCG` and the flexible PCG at
`:881`. **[Corrected 2026-09-01 — `solveBiCGStab` at `:988` does NOT route through it: it has its
own inline matvec at `:995`/`:1003` for the g=2 gp staging, and belongs to P2. See the correction
block above.]**

**2. The float bands are the *whole* error — the arithmetic is already double.**
`applyCutcellOp` (`mac_pressure.hpp:178`) and `residualCutcell` (`:109`) both promote to double
before accumulating (`(double)AC(i)*x(i) + …`). So nothing is lost in the summation; the entire
defect is the fp32 *rounding of the stored coefficients*, i.e. precisely the quantity the
double-diagonal targets. This confirms the diagnosis and means storage is the only lever.

**3. The flux form gives `A·1 = 0` BITWISE — the double-diagonal only gets it to `eps_f64`.**
Writing the matrix-free apply in difference form,
`y_i = t_w(x_i − x_{i-1}) + t_e(x_i − x_{i+1}) + …`, annihilates the constant vector *exactly*,
whatever the precision of `t_f`, because each difference vanishes identically. A stored double
diagonal satisfies the identity only to double round-off. Defect correction therefore dominates
its own fallback on the very identity the fallback exists to protect — this is the strongest
argument for it and it was not in the proposal.

**What the caveats turned out to be:**

- **Star overlay: already resolved, no work.** `starApplyDelta` is applied *after* `matvecOverlap`
  as a separate additive delta (`:777-781`), and the gp overlay follows the same pattern in
  BiCGStab. A matrix-free 7-point level-0 apply composes with both unchanged.
- **Variable density: nothing special.** The caller pre-folds ρ into the coefficient
  (`buildRhoCoeff`, `mac_pressure.hpp:251` — "the coefficient rides the openness rails") and passes
  it *as* the openness (`flow_ibm.hpp:4408,4442`). The double array on level 0 is already the full
  `c_f`, ρ included.
- **`gf` plumbing: trivial.** All three `setOpenness` call sites pass `idx2=idy2=idz2=1.0`
  (`flow_ibm.hpp:1659,4408,4442`) — grid units. Store them as members anyway rather than assume it.
- **The coefficients are already resident and already double.** `Level::ox/oy/oz` are
  `CCField = View<double*>` (`:276`), ghost-filled and boundary-re-imposed by `setOpenness`
  (`:693-698`) and retained for the coarsening. The matrix-free apply needs **no new storage**.

**Correction to the cost claim — the −28 B/cell saving is not free.** The proposal assumed the
level-0 float bands could simply be dropped. They cannot: the V-cycle *smooths on level 0*, and
`cutcellSmoothColor` divides by `AC(i)` and uses `ac < 1e-30` to detect decoupled solid cells. So
the honest ledger is:

| variant | Δ bytes/cell | `A·1 = 0` |
|---|---|---|
| double-diagonal (fallback) | **+17** | to `eps_f64` |
| matrix-free level-0 matvec, bands kept for the smoother | **0** | **bitwise** |
|  + matrix-free level-0 smoother too | **−28** | bitwise |

The middle row is the honest first step: zero new storage, still strictly better than the
fallback. The bottom row is a *follow-on* — and note it comes with the double diagonal for free,
since a matrix-free smoother must form the diagonal on the fly as the exact sum of six double face
terms. Traffic on the matvec itself does drop either way (3 doubles = 24 B read instead of 7
floats = 28 B), in the favourable direction on a bandwidth-bound kernel.

**Unchanged:** the conditioning ceiling `eps_f64·κ` (as stated), the AMG bottom and all coarse
levels (inside the preconditioner, stay float), `applyOutflowGhost` and the CA ghost ring (they
act on the vector, not the operator).

**Promoted to a suite-wide campaign (2026-09-01)**: the plan is `DEFECT_CORRECTION_PLAN.md`
(rule, per-solver inventory, rungs P1/P2/P3/A0/A1/M1/M2/D1/X, Opus↔Fable handoff protocol) and the
executing session's prompt is `DEFECT_CORRECTION_PROMPT.md`. This item is now that campaign's P1.

**The discriminating experiment**, when this is implemented behind an env gate: the RCP bed at
rtol 1e-8, Ng = 48/64/96 — the ladder where float took 24/33/**capped-at-300 (invalid)** against
14/14/28 in double. Matrix-free level-0 should reproduce the double column while the hierarchy
stays float. `PECLET_FLOW_MG_DIAGRESUM=1` gives the matched double-diagonal control on the same
ladder, so the three variants are directly comparable in one battery. Run it in an isolated
worktree (working practices, below), and not concurrently with other heavy batteries (WO-L race).

**Why this generalises where storage-widening does not**: with surface tension (V4) and later
phase change (Part II), the quantity driven to zero is genuinely not a fixed linear system —
the operator is a linearisation of a residual depending on curvature, colour and interfacial
mass flux. Defect correction on a matrix-free `r(x)` is the formulation that survives that.

**Honest note on the gap**: WO-M framed the question as *which storage do we widen*, never as
*should the residual and the preconditioner use different operators*. Given that framing, the
double-diagonal is the right answer — to the narrower question. Neither campaign raised this
alternative.

### The double-diagonal (user decision 2026-08-31, still valid as the fallback)

**Decided**: if defect correction does not pan out, implement this, default OFF, never make
fp64 the default.

**Why it is worth having despite buying little today** (the user asked this directly, and the
honest answer has two halves):
- On physical outputs it buys **nothing**: Z&H drag identical to the 6th digit, RCP
  permeability negligible, regression +0.00% either way, hydrostatic already 3e-17 in float.
- On **robustness at tighter tolerance and higher resolution** it is the difference between a
  result and a non-result: RCP bed at rtol 1e-8 took 24/33 iterations at Ng=48/64 in float
  and then **capped at 300 (invalid) at Ng=96**, against 14/14/28 in double. WO-M's measured
  **κ(A) ≈ 0.18·N²·contrast** makes that boundary predictable, not mysterious.

**What exists already**: `PECLET_FLOW_MG_DIAGRESUM=1` (WO-M) is an *ablation* — it rounds
stored faces back to float and recomputes the diagonal as their exact double sum, which is
bit-for-bit the double-diagonal arithmetic. It refuses to run in a float build, so it proves
the numerics without being shippable. Judged against a matched full-double control it
**recovers full-double behaviour at every grid from 48³ to 160³**.

**What the work is**: view-type surgery carrying a double diagonal through smoother, residual,
matvec, the CA ghost ring and the AMG bottom — not a line edit, which is precisely why WO-M
proved the numerics first. Cost ≈ +17 B/cell (against +120 B/cell and +12% runtime for full
fp64).

**The rule it implements** (WO-M's policy, stated deliberately as a rule rather than a patch):
> A quantity an algorithm requires to satisfy an exact discrete identity must be stored in the
> precision in which that identity is asserted. A quantity carrying only an approximation may
> stay float.

Here the identity-bearing quantity is the operator **diagonal** in both the pressure and
momentum operators (`A·1 = 0`); the six face couplings are the approximation. The same root
cause has now surfaced in three unrelated places — pressure hierarchy, momentum stencil, and
the bottom AMG (already cured targetedly at `mac_cutcell_mg.hpp:1411` and holding since
2026-08-13, which is the precedent for cheap-and-specific over blanket fp64).

**Do not repeat these**: the `MReal` switch was incomplete until WO-M completed it — four
families of hard `(float)` casts kept their operator fp32 even in a double build
(`buildAdvStencil`/`buildAdvStencilVar`, `addDragDiagonal`, `applyBackflowStab`, five sites in
`mac_velocity_mg.hpp`). Any pre-WO-M "double" momentum result is suspect.

---

## Item 2 — Trace the Lamb mode-2 discrepancy  [Fable]

**The observation** (WO-P): the oscillating-droplet frequency is **6.3–7.0 % below** Lamb's
analytical mode-2 result, consistently. Recorded as an open measured deviation, explicitly
**not** a pass.

**Already ablated, none of which explains it**: amplitude, time step, initialisation,
confinement (domain fraction φ swept 6.5 % → 0.8 %), and resolution. That the deviation is
*insensitive to all five* is itself the strongest clue — it points at something systematic in
the physics or the discretisation rather than a setup artifact.

**Where I would start, in order:**
1. **Check the reference, not just the code.** Lamb's formula is for an *inviscid, isolated*
   droplet. Confirm which variant WO-P compared against: viscous damping shifts the observed
   frequency (Prosperetti's viscous correction), and an ambient fluid of finite density shifts
   it again (the two-density mode-2 result differs from the single-density one). A 6–7 % offset
   is the right order for using the inviscid single-density formula on a viscous two-density
   simulation. **This is the cheapest hypothesis and it should be eliminated first.**
2. **Cross-check against the capillary-wave result**, which came out at −2.1…−3.7 % against
   its own dispersion relation on the same machinery. Two independent surface-tension
   benchmarks both landing low, by different amounts, suggests a shared cause of partial size
   — or that one of the two references is being misapplied. Compare what differs: the capillary
   wave is planar (curvature from one direction), the droplet is spherical (the cascade's
   mixed-direction and fallback branches engage).
3. **Only then suspect curvature.** V3 measured κ error to plateau with advection-realistic
   fractions, and V4 showed spurious Ca is curvature-limited. A systematic κ bias would shift
   an oscillation frequency systematically (ω ∝ √σκ-ish scaling), so measure the *mean* κ over
   the droplet surface during oscillation against 2/R — a bias, not a scatter, is what would
   do this.
4. Instrument rather than guess: the branch census field `"kappa_branch"` already exists, so
   the fraction of the surface served by each cascade branch during the oscillation is
   directly observable.

**Do not** tune anything to close the gap. If the reference turns out to be misapplied, fix the
comparison and the "deviation" evaporates; if it survives a correct reference, it is a real
finding about the method and is worth writing up.

---

## Item 3 — The V3 curvature issues  [Fable]

These now matter **more than when V3 shipped**, because V4 proved the spurious-current budget
is set by curvature, not by the force (see Item 4 and `VOF_PLAN.md` §4 V7 preamble).

1. **The paraboloid fallback fires on ~19–20 % of interfacial cells at every resolution**, and
   WO-O showed this is geometry, not a defect: in 3D the corner column of a 3×3 patch must span
   √2·s, and s reaches √2 on the octant diagonal — 2.5 cells, exactly a 7-column's capacity.
   (Han et al.'s oft-quoted 0.9 % is a **2-D** droplet, where the patch is 1×3.) Han use
   **NH = 11** in 3D for this reason, which would need **ghost width g = 5**. WO-O judged the
   fallback good enough (its branch converges at 1.96–1.99) and declined to widen the halo.
   **Open question worth revisiting now**: given that κ accuracy is the binding constraint on
   pore-scale Ca, is g=5 + NH=11 worth the halo cost? Measure before deciding.
2. **Tier 2b (Popinet's generalised mixed-height fit) ships OFF because it destroyed max-error
   convergence** (order 0.00 vs 1.86), across every fit width tested. WO-O isolated the
   mechanism: its data set is the columns that *closed* — a slope-selected, asymmetric subset
   whose lever-arm bias is scale-invariant; the paraboloid fit is immune because a PLIC polygon
   exists at every slope. It is retained as a re-measurable instrument with a ctest that
   regenerates the numbers. **Worth revisiting whether this is fundamental or an implementation
   artifact**, since Basilisk ships this tier in production — if our implementation differs
   from theirs in the selection criterion, that difference is the finding.
3. **`interfaceEps` defaults to 0** so V3 stayed byte-identical, but WO-P found that advection
   round-off leaves ~5300 cells looking "interfacial" at 64³ where the cascade returns
   **|κ| up to 2.9e+11** — harmless in V3, fatal once a force consumes it. **Decide the
   production default**, and note the general lesson: a rung's latent defect can be invisible
   until the next rung consumes it.
4. **The advection-realistic plateau** sets in at CΔ ≈ 0.16–0.08 while the exact-fraction
   control keeps converging at 2.16. This is the literature-expected behaviour (Han 2024), but
   it is now the thing standing between us and pore-scale capillary fidelity, so it deserves a
   deliberate decision rather than acceptance: improve the fractions (V5's RDF), improve the
   estimator (ELVIRA/LVIRA on 5³ — note 3D ELVIRA needs 5³ for 2nd order per Boniou 2022), or
   accept and design the campaign around the achievable Ca.

---

## Item 4 — Scope V5–V7  [Fable]

**V5 (SDF wetting / band RDF) has gained a second motivation.** It was scoped for the contact
angle; it is now also the most promising route to better curvature (plicRDF gives 2nd-order
normals/positions — Scheufler & Roenby 2019) and it is the substrate Part II's phase change
needs for normal-probe temperature gradients. Three consumers, one construction — scope it
accordingly rather than as a wetting-only rung.

**V7's premises changed under V4's measurements** (recorded in `VOF_PLAN.md` §4 before V7):
- **Spurious Ca ≲ 1e-7 is unreachable and the reason is structural.** With exact κ the force
  gives Ca = 1.9e-18; with computed κ it is 2.5e-4 … 1.4e-5 at D/Δ = 8 … 32. Ca ≈ δκ·h, so the
  budget is a curvature requirement. Improve κ, never the force.
- **The capillary time step binds 18 of 18 pore-scale combinations**, by factors 6 to 5.9e4, and
  worsens under refinement (dt_σ ~ h^{3/2} vs dt_CFL ~ h). **3.8e6–3.0e7 steps per pore volume
  at Ca ~ 1e-6.** This is the dominant feasibility constraint and it is arithmetic.
- Therefore: pick the largest Ca that still answers the physics question; budget wall-clock
  from a measured ms/step before committing; and **reconsider implicit surface tension**, which
  the plan parked on Popinet (2018)'s advice — advice written for cases where the capillary
  limit is not four orders inside the advective one. Hysing confirms the crossover is real and
  case-dependent: case 1 capillary-bound 204/204 steps, case 2 CFL-bound 108/113.

**Also unresolved and worth folding into the scoping**: S3 (coefficient-aware coarsening) is
*real* — WO-M confirmed the negative pivot survives in a double build, deepening with
hierarchy depth, distinct from the float-storage defect. It is unstarted. The collocated-paper
campaign has a far cleaner reproducer than ours (fully periodic, no domain BCs, no VoF, no
varRho, contrast tunable by `PECLET_FLOW_APERTURE_ORDER=1|2`), and the trap when fixing it is
that `buildOpenness` feeds both the geometric openness and the coefficient path.

---

## Working practices this campaign learned the hard way

- **Run attributable measurements in an isolated `git worktree`** carrying only your own diff.
  Three live sessions share this checkout; a shared index caused **three** mis-attributed
  commits. A "+0.00 % regression" claim only means something if the tree held your changes and
  nobody else's. (Now rule 6 of the work-order preamble.)
- **Never `git add -A`, and run `git diff --cached --stat` before every commit** — staging named
  paths is *not* sufficient, because `git commit` also commits what was already in the index.
- **A capped pressure solve makes a run invalid, not degraded** (rule 3b). MG-PCG can report
  convergence per its own bookkeeping while the true residual sits ~100× above rtol.
- **Gates must not demand what the arithmetic cannot deliver**: use
  `rtol = max(1e-8, C·eps·0.18·N²·Δρ/ρ)`. At ratio 1000 on 256³, κ ≈ 1.2e7 and a fixed 1e-8 is
  already near the limit; at 512³ or ratio 1e4 it is unreachable.
  **But treat this as a lower bound on what to demand, not a prediction of what is
  achievable.** The κ law behind it is validated only **192³–384³**: the collocated campaign's
  768³ probe floored at 3e-4, *three orders worse* than the law predicts, invalidating three of
  their rung values (they had agreed to nine digits across cap settings — floor-limited, not
  converged). Cause under investigation: those were their only 2-node runs, so it is either an
  inter-node comm defect in the pressure path or a superlinear correction to the N² scaling.
  **Above ~384³, measure the attainable residual; never use a prediction from this law to
  dismiss a measured floor.**
- **If anything ever runs multi-rank on a `MREAL_DOUBLE` build, run the `kokkos_mpi` battery
  first.** The collocated campaign's double build never exercised it — its np4 path is
  vindicated only indirectly (one rung matching the float np4 result digit-for-digit).
- **Five gates in this campaign turned out to measure the wrong quantity** (V0's MYC-normal
  order, WO-C's premise, WO-K's uniform-velocity discrimination, WO-J's acid-test velocity half,
  WO-P's falling drop). Every time, an agent isolating the mechanism and saying so improved the
  plan. Preserve that norm in the work-order prompts.
- **The np=4 `MPI_ERR_TRUNCATE` race is load-triggered** (WO-L, unstarted): re-run an affected
  leg on an idle machine before believing it. Do not run three heavy batteries concurrently.
