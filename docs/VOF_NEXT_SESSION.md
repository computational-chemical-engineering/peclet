# VoF campaign — handoff for the next session

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

## Item 1 — Ship the double-diagonal as an **option** (user decision, 2026-08-31)

**Decided**: implement it, default OFF, never make fp64 the default.

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
- **Five gates in this campaign turned out to measure the wrong quantity** (V0's MYC-normal
  order, WO-C's premise, WO-K's uniform-velocity discrimination, WO-J's acid-test velocity half,
  WO-P's falling drop). Every time, an agent isolating the mechanism and saying so improved the
  plan. Preserve that norm in the work-order prompts.
- **The np=4 `MPI_ERR_TRUNCATE` race is load-triggered** (WO-L, unstarted): re-run an affected
  leg on an idle machine before believing it. Do not run three heavy batteries concurrently.
