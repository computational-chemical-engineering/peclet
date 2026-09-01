# Exact residual, approximate preconditioner — the suite-wide defect-correction campaign

Written 2026-09-01 (Fable, from the source survey recorded in `VOF_NEXT_SESSION.md` Item 1).
Executed in a separate session — see the prompt in `DEFECT_CORRECTION_PROMPT.md`.

## 0. The rule, and why it is a rule

Every iterative solve in the suite is split into two roles:

> **The residual and the Krylov (or outer) matvec use the exact operator, in double** — matrix-free
> from resident double sources where they exist, exactly-stored double coefficients where they do
> not. **Everything below that line is a preconditioner** — V-cycles, smoothers, AMG bottoms,
> coloured sweeps — and a preconditioner may stay float, because its errors change the
> convergence *rate* and never the fixed point.

Corollary for the discrete identities the methods rely on (`A·1 = 0` for the pressure Poisson,
Galilean invariance for momentum): **write the exact matvec in flux (difference) form**,
`y_i = Σ_f t_f (x_i − x_nbr)`, so the identity holds **bitwise** regardless of coefficient
precision — the diagonal is never formed, so it can never disagree with the faces.

**Correction (2026-09-01, §4 M1 design correction 3).** This plan first stated the momentum
identity as `(A − idiag·I)·1 = 0`. That is **false in general**: `fou_operator`
(`staggered_advection.hpp:113`) is the *conservative* FOU, so its row sum per axis is
`dt·(velp − velm)` — verified directly, since `max(v,0) + min(v,0) = v` — and summed over the three
axes the advective row sum is `ρ_f·div̄_h(u^k)`, the face mean of the cell divergence of the
*advecting* field. The identity therefore holds only when that field is uniform or discretely
divergence-free (WO-M's V2b test carries a uniform field, which is why it measures 8.9e-16). The
flux form still makes each *term* exact; what it annihilates bitwise is the uniform case, and the
general assertion must carry the divergence term. §4's M1 design states the correct form, including
the cut-row version where a static wall legitimately drags a uniform field.

This replaces WO-M's storage policy ("a quantity carrying an exact identity must be stored in the
precision the identity is asserted in"). WO-M asked *which storage to widen*; this campaign asks
*whether the residual and the preconditioner should use the same operator at all*. The answer is
no, and once they do not, the storage question dissolves: the preconditioner's coefficients can
be anything, and the residual's coefficients are already double everywhere that matters (§1).

**What it does not do.** It removes the *float* floor, not `eps_f64·κ`. The κ-law
(`κ ≈ 0.18·N²·contrast`, validated 192³–384³, **failed by 3 orders at 768³**) still bounds what
any rtol can demand; a capped solve is still invalid, not degraded; and S3 (the negative pivot
surviving in a double build) is a separate coefficient-coarsening defect this campaign does not
touch.

**And below the κ-law sits a second, steeper floor that no precision change reaches** (collocated
ladder session, 2026-09-01, closing the 768³ question this plan inherited as unexplained). It is
**intrinsic and cold-start-state-dependent**, not communication and not conditioning:
`PECLET_FLOW_CA=0` is bit-identical and decomposition invariance held to the printed digit (512³
np4-across-2-nodes == np8-2-node; 384³ np1 == np4), yet cold-probe floors run `r/r0 =` 4e-8 / 2.4e-6
/ **3e-4** at bed resolution R = 24/32/48 while *the same 512³ operator* reaches 2e-7 — below its own
cold floor — once the flow state warms. Mechanism: cold ICs leave divergence sources sealed inside
near-isolated pore pockets (chains of α ~ 1e-3 throat faces, multiplying with R); equilibrating them
through those faces is the stalled PCG subspace, and a marched state has already drained them.
Ablated independently against CG variant, precision, MG depth and decomposition (logs:
`flow/doc/data/collocated_campaign/probe*_order2.log`, `dblprobe*_order2.log`). Two consequences are
load-bearing for this campaign's gates — written into P1 gate 3 and §5, not left as background.

**Why defect correction and not "just build in double".** Full fp64 costs +120 B/cell and +12 %
runtime and buys nothing on physical outputs (WO-M §1); the double-diagonal costs +17 B/cell and
gets the identity to `eps_f64`. The exact-residual form costs **0 B/cell** (P1) and gets the
identity bitwise, and it is the *only* form that survives the nonlinear residuals surface tension
and phase change bring, where "widen the storage of A" has no meaning because A is a
linearisation of `r(x)`.

## 1. Inventory — what each solver does today

Measured by source inspection 2026-09-01. "Exact source resident" = the double quantities the
exact matvec needs are already allocated and ghost-valid at solve time.

| solver | file (line) | residual/matvec reads | exact source resident? | outer loop exists? | rung |
|---|---|---|---|---|---|
| **flow staggered cut-cell pressure** `CutcellMG` | `flow/src/mac_cutcell_mg.hpp` — `matvecOverlap` :1715, `solvePCG` :769, flexible PCG :881, `solveBiCGStab` :988 | float bands `AC..AT` (`FPC`), promoted to double at use | **yes**: `Level::ox/oy/oz` are `View<double*>` (:276), ghost-filled + boundary-re-imposed by `setOpenness` (:689), ρ already folded in by the caller (`buildRhoCoeff`, `mac_pressure.hpp:251`); `gf = 1.0` at all 3 call sites (`flow_ibm.hpp:1659,4408,4442`) | **yes** — PCG with one symmetric V-cycle as `precond` | **P1** |
| flow collocated pressure (approximate projection) | `mac_approx_projection.hpp` → same `CutcellMG` | same as above | same | same | **P1** (free) |
| flow collocated **ghost-projection** overlay | `flow/src/ghost_projection.hpp` — `GpOverlay` :81-101, `gpApplyDelta` :254-263 | **float** `rescale, wm_n1, wm_n2` inside the BiCGStab matvec | **WRONG — see §4 handoff**: computed in **float** (`gpOrderWeights`/`GpFace` are `float`, `core/.../scheme/ghost_closure.hpp:84,104`); only the upstream sdf sampling is double, so widening the store buys nothing. `rescale` needs no widening at all (it scales A and b by the same stored `D`). | yes (BiCGStab) | **P2** — merged into A1 |
| flow mode-B **star** overlay | `flow/src/star_elimination.hpp` — `StarOverlay::a` :37, :87, :118-165 | **float** `a[6]` inside the PCG matvec | trivially: `a` is the openness `ox/oy/oz` masked by the sdf sign (:75-80) — matrix-free from resident doubles | yes (PCG) | **P2** |
| flow **momentum** (IBM RB-GS) | `flow/src/flow_ibm.hpp` — `smoothComp` :3885, `velSweepLoop` :3855, `buildAdvStencil` :3709, `buildAdvStencilVar` :3746, `addDragDiagonal` :5726 | float bands `C[c].AC..AT` (`FV = View<MReal*>`, :63); the **sweep is the solver**; stop criterion is the increment `du`, never a residual | partly: `mu_, rho_/dt_` scalars, adv velocities double, drag β double, face props double; **but the IBM overlay `IbmOverlay::K_val/M_val/X_val/Nbc_val/R_val/D_rescale` is float and computed in float** (`cut_cell_ibm.hpp:77-79`, :150-160 `float R`, `float D_axis`) | **no** | **M1, M2** |
| flow `VelocityMG` (domain-BC vel-MG path, single-rank) | `flow/src/mac_velocity_mg.hpp` — `FPV` bands all levels; `vmg_.solve` :3940 used as the solver | float | n/a — becomes a preconditioner under M2 | no | **M2** (absorbed) |
| flow const-coeff periodic MG (FlowReference) | `flow/src/mac_mg.hpp` :101-141 | matrix-free double `(6φ − Σ)/h²` | n/a | plain MG, but the residual is exact ⇒ already defect correction | compliant |
| flow bottom AMG (agglomerated) | `mac_cutcell_mg.hpp` :1411 (diag re-sum precedent) → `core/.../solver/graph_amg*.hpp` | double CSR | inside the preconditioner | — | compliant |
| **core AMR pressure** (`AmrFlow`) | `core/include/peclet/core/amr/fv_op.hpp` (`FvOp` faceW/bcDiag/invVol all double, `applyFv` :114), `pcg.hpp` (double PCG, MG precond), `flow.hpp` (`presPCG_ = true` :2042) | double | yes | yes | **A0** audit only: verify `applyFv` is flux-form; confirm the `setPressurePCG(false)` plain-MG path recomputes the fine residual exactly (then it is defect correction by construction) |
| core AMR **ghost-projection** overlay | `core/.../amr/ghost_projection.hpp` :364-366, :299-307; `ghost_projection_sampled.hpp` :1142-1144 | **float** `rescale, wm_n1, wm_n2` inside the matvec | **WRONG — see §4 handoff**: computed in float in the SHARED `scheme/ghost_closure.hpp`, whose three consumers are flow's gp overlay and both AMR overlays. P2 and A1 are ONE change, in core, and it moves double-build results (trigger 2). | yes | **A1 == P2**, blocked on a Fable ruling |
| core AMR momentum | `core/.../amr/momentum_assembly.hpp` (all `View<double>`), BiCGStab | double | yes | yes | compliant |
| core `DistributedPoissonMG` | `core/.../amr/distributed_poisson.hpp` :200 `vcycle` | double, plain MG | — | check: test-only, or a production solver? | **A0** |
| **voro** mesh-optimizer CG (+GraphAMG precond) | `voro/include/peclet/voro/mesh_optimizer.hpp` :33-41, :396, :691 | double CSR / `View<double>` | yes | CG | compliant — **X** audit: confirm the assembled `Aop` and the wall-Jacobian term are double end-to-end |
| **pnm** `extract_network_flow` | `pnm/src/pore_extraction.hpp` :860-905 | no linear solve — fluxes from a given velocity field, all double | — | — | out of scope |
| **dem** XPBD / coloured PGS / multilevel stabiliser | `dem/src/solver_*.hpp`, `particles.hpp` (`V3 = View<float*[3]>`, λ float) | float **state**, nonlinear complementarity — there is no operator to widen and no double source to correct against | no | no | **D1** — evaluation only, Fable |

Three things the inventory makes plain:

1. **Only three code paths violate the rule**: flow's `CutcellMG` level-0 matvec (P1), the two
   flow overlays (P2), and the core AMR overlay (A1). All three have the double source resident
   or trivially recomputable, and all three already sit inside a Krylov loop. They are
   *switch-the-matvec* changes.
2. **flow momentum is the one solver with no outer loop at all** — the float RB-GS *is* the
   solver, its stop criterion is an increment, and its cut-cell overlay is float at the source.
   That is why WO-M's table shows momentum-side identities 8 orders worse in float (uniform-
   velocity identity 1.3e-7 vs 1e-15; porous drag balance 4.8e-8 vs 2.8e-16). This is the real
   work of the campaign (M1, M2) and the part that needs design, not just a switch.
3. **core AMR, voro, mac_mg are already compliant** — they were written double-first. The
   campaign confirms rather than changes them.

## 2. Rungs

Each rung: default **OFF** behind an env gate until its gates pass; byte-identical with the gate
off; then a deliberate default flip with a regression re-baseline (the fixed point *moves* by
float-rounding amounts, ~1e-7 relative, so "+0.00 %" is the perf gate, not the physics one — the
physics gate is the identity tests and the ladders below). One rung per commit, in an isolated
`git worktree`, `git diff --cached --stat` before every commit, never `git add -A`.

### P1 — `CutcellMG` exact level-0 matvec  [Opus]

**Change.** New `applyCutcellOpExact(y, x, ox, oy, oz, gfx, gfy, gfz, ext, g)` and its box form
(`applyCutcellOpExactBox`, for the distributed interior/shell overlap — same skip-box signature
as `applyCutcellOpBox`, `mac_pressure.hpp:194`), flux form:

```
y_i = ox(i)·gfx·(x_i − x_{i−sx}) + ox(i+sx)·gfx·(x_i − x_{i+sx})
    + oy(i)·gfy·(x_i − x_{i−sy}) + oy(i+sy)·gfy·(x_i − x_{i+sy})
    + oz(i)·gfz·(x_i − x_{i−sz}) + oz(i+sz)·gfz·(x_i − x_{i+sz})
```

Store `gfx/gfy/gfz` as `CutcellMG` members set by `setOpenness` (today they are 1.0 at every call
site — store them anyway). Switch **only** `matvecOverlap` (`:1715`, both the distributed
overlap branch and the single-rank branch) behind `PECLET_FLOW_EXACT_RESIDUAL=1`. Nothing inside
`vcycle` changes: `residualCutcell` at `:1138` (the V-cycle's own fine residual), the smoother,
restriction, CA ring, AMG bottom all keep the float bands — they are the preconditioner.

**Do not** touch the star overlay here: `starApplyDelta` is already a separate additive delta
applied after `matvecOverlap` (`:777-781`); P1 composes with it unchanged. Same for the gp
overlay in BiCGStab.

**Solid cells.** With the bands, a fully-closed cell has `AC = 0` and every face 0, so `A x = 0`
there and the smoother decouples it (`ac < 1e-30`). The flux form gives the same: every `t_f = 0`
⇒ `y_i = 0`. Verify this is bitwise, including cells whose openness is tiny-but-nonzero (there
`AC` is the float-rounded sum; the flux form is exact — that is the point, and it is where the
two disagree).

**Gates.**
1. `A·1 = 0` **bitwise** on `random_spheres` and `hollow_rings` openness at N=32,64 — new ctest in
   `flow/tests/kokkos/test_cutcell.cpp`. With the bands, report the actual `max|A·1|` for the
   record (expected ~1e-7·max|AC|).
2. Gate off ⇒ byte-identical solver output (regression suite, `tests/regression/sdflow_regression.py`).
3. **The ladder** — RCP bed, PCG rtol 1e-8 cap 300, Ng = 48/64/96, harness
   `flow/tests/study/precision_ab.py` (WO-M's): float bands / `PECLET_FLOW_EXACT_RESIDUAL=1` /
   `PECLET_FLOW_MG_DIAGRESUM=1` (needs the `MREAL_DOUBLE` build) / full `MREAL_DOUBLE`. Prediction:
   the exact-residual column reproduces the double column (14/14/28) with the hierarchy still
   float. Report iterations, attained residual, `max|div(open·u)|` (float 4.5e-6 vs double 9.5e-12
   at Ng=48 is the number to move).

   **Two traps, both from the collocated finding in §0 — this ladder is a dense bed and WO-M read
   it cold, exactly the configuration that produces them.**
   - **Agreement across the four columns is NOT evidence that P1 works.** Three of the collocated
     session's R=48 runs agreed *to nine digits* while all were starved on a shared floor. If the
     columns converge on one number, first establish that the number is not the pore-pocket floor:
     march the state and re-probe, or show the attained residual sits at rtol rather than on a
     plateau. A shared floor makes every precision variant look identical — the one way this
     experiment can return a false GO.
   - **A capped exact-residual column at Ng=96 is not automatically a P1 failure.** Judge the
     attained residual against *the run's own state history*, never a cold-start probe: a cold floor
     1000× above rtol coexists with a healthy production march on the same operator. Run the ladder
     **cold and after a short march**, report both, and attribute a cap to precision only if the
     warm leg also caps. WO-M's double column reached 14/14/28 cold, so the discriminator is sound —
     but a *new* cap in the exact column must be separated from the geometry floor before it is read
     as a verdict.
4. MPI: np=1 bitwise vs today with the gate off; np=1/2/4 the same across np as today
   (`tests/kokkos_mpi`, 18 ctests) with the gate on. The box form must be bit-identical to the
   blocking form (reads x, writes y, no aliasing — same argument as `applyCutcellOpBox`).
5. Perf: ms per matvec and ms per step on CUDA and OpenMP before/after, gate on. Expected ≤ 0
   (24 B/cell read instead of 28). A regression here is a finding, not a tuning target.
6. Contrast: V2a's `∂P/∂z` at ratio 1000 and the varRho hydrostatic acid test unchanged
   (`test_vardensity_projection.cpp`) — the ρ-folded coefficient path.

**Then** flip the default ON in a separate commit with the regression re-baseline
(`--update`), recording the per-metric deltas.

### P2 — flow overlays exact  [Opus; Fable reviews the `rescale` semantics]

`StarOverlay::a` (`star_elimination.hpp:37`): replace the float `a[6]` in `starApplyDelta` with
the masked openness recomputed on the fly from `ox/oy/oz` + the sdf sign (the `:75-80` logic),
or store it double — it is 6 values per *cut* cell, either is fine; matrix-free is preferred
because it removes a build step that must otherwise stay consistent with `setOpenness`.

`GpOverlay` (`ghost_projection.hpp:81-101`): `wm_n1, wm_n2, rescale` → double. These are the
*matrix* weights; `th, w_bc, w_n1, w_n2` are RHS/diagnostic closure weights and may stay float
(they enter `b`, not `A` — but note that a float `b` is a *different* problem, not an inexact
solve of the same one; leave them and record it). **The `rescale` question for Fable**: it is a
row scaling `D·A` applied in the matvec; the fixed point of `D A x = D b` is unchanged by the
precision of `D` only if the same `D` scales `b`. Confirm where `b` is scaled and that it is the
same view.

Gates: gate-off byte-identical; the ghost-projection order-2 Z&H tests (`flow-ghost-projection`
memory: directional gp order ~2 on Z&H, mode 9 throat-safe) unchanged to tolerance; the collocated
campaign's fully-periodic reproducer (contrast via `PECLET_FLOW_APERTURE_ORDER=1|2`) iteration
counts before/after.

### P3 — level-0 smoother exact ⇒ drop the level-0 bands  [Opus, optional, perf-gated]

The −28 B/cell saving from `VOF_NEXT_SESSION.md` Item 1's ledger. A flux-form
`cutcellSmoothColorExact` forming `ac = Σ t_f` on the fly (which *is* the double diagonal, for
free) and the `ac < 1e-30` decoupling test on that sum; then level 0 allocates no `AC..AT`.
Also the V-cycle's level-0 `residualCutcell`/`residualCutcellBox` (`:1138-1155`) go exact.
Only worth doing if P1's perf gate showed the matvec is bandwidth-bound and the smoother
dominates the V-cycle on level 0 (it usually does). Gate: byte-identical **is not** expected
(the preconditioner changes) — gate on iteration counts unchanged ±1 and the ladder unchanged.

### A0 — core AMR audit  [Opus]

Read `applyFv` (`fv_op.hpp:114`) and confirm flux form (`Σ w_f (u_j − u_i)`), not
`diag·u_i + Σ w_f u_j`. If not flux form, change it (double already, so the only effect is
`L·1 = 0` bitwise) and gate on the AMR ctests (`core`, 26 ctests, np 1–8) + `amr-testing`
recipes. Determine whether `DistributedPoissonMG::vcycle` and the `setPressurePCG(false)` path
are production or test-only; if production, confirm the fine residual is recomputed exactly per
cycle (then it is defect correction already). Record the verdict in this file's §4.

### A1 — core AMR ghost-projection overlay exact  [Opus]

Same as P2's `GpOverlay` half, in `core/.../amr/ghost_projection.hpp:364-366` and
`ghost_projection_sampled.hpp:1142-1144`: `rescale, wm_n1, wm_n2` → double. Gates: the AMR
ghost-collocated ctests (`amr-ghost-collocated-ns-plan`, mixed-level band np=1 bitwise / np=2,4
3e-7) unchanged with the gate off; iteration counts with it on.

### M1 — flow momentum: an exact residual exists  [design: Fable → implementation: Opus]

Today there is **no function that computes `r(u) = b − A_mom u`** for the momentum system at
all; the sweeps stop on an increment. M1 creates one, matrix-free in double, in flux form for
the diffusion and advection parts:

- diffusion `−μ∇²`: face fluxes from `mu_` (or `VarFaceProps` per-face μ) — double scalars/views;
- time diagonal `idiag = ρ/dt` (or face-density variant) — double;
- FOU advection: `Grid::fou_operator` from `advVelView(0..2)` — double views; write it as the
  upwind flux difference so uniform `u` gives `(A − idiag·I)·1 = 0` bitwise;
- drag diagonal (`addDragDiagonal`, β field double);
- **the cut-cell IBM modification** (`ibmModifyStencil` from `IbmOverlay`): this is the one
  place the source itself is float (`cut_cell_ibm.hpp:77-79`, computed with `float R`,
  `float D_axis`). Widen `IbmOverlayT` to double **for the matrix quantities** (`K_val, M_val,
  X_val, D_rescale`; `Nbc_val/R_val` are RHS-side — same remark as P2's closure weights). It is
  per-cut-cell storage (6·n_cut), not per-cell, so the cost is small. `poly_N_c_sandwich` etc.
  must be evaluated in double. **[SUPERSEDED on two counts — §4 M1 design corrections 2 and (d).
  (i) The overlay is allocated PER CELL (`maxCut = nx·ny·nz`, `flow_ibm.hpp:110`): 156 B/slot × 3
  components = 468 B/cell allocated today; only the *touched* memory is per cut cell. (ii) `Nbc_val`
  is NOT RHS-side — it enters the diagonal through the closure identity `K = D − X − Nbc`, and only
  its `u_bc` half is inhomogeneous. Both verified 2026-09-01. The design's ruling is to store
  nothing and evaluate the rows in double on the fly.]**

**Fable decides first** (before Opus writes a line): (a) whether the exact residual should be
one fused kernel or composed from the existing builders evaluated in double into scratch — the
overlay's row modification is algebraically a rescaled row (`rscale`, `inhom`) and the
composition must reproduce it exactly; (b) how `inhom` (the inhomogeneous wall-velocity term the
overlay moves into `b`) is accounted for so that `r(u)` is the residual of the *same* problem the
sweeps solve; (c) the porous (`ε`-weighted) and varRho variants.

Gates for M1 alone (no solver change yet): `r(u*)` evaluated at the converged RB-GS iterate
`u*` reports the *true* momentum residual for the first time — record it on Poiseuille,
`zh_sphere`, the porous drag balance and the V2b uniform-velocity identity. Expect: the
uniform-velocity identity residual is at 1e-15 with the exact operator applied to a uniform
field (bitwise 0 in flux form), while `|r(u*)|` shows what the float sweeps actually left.

### M2 — flow momentum: outer defect-correction loop  [Fable chooses; Opus implements]

`u ← u + P(r(u))` where `P` = k RB-GS colour pairs (or `VelocityMG` V-cycles on the domain-BC
path) applied to the residual, in float, with the stop criterion on `|r(u)|` (double,
rank-uniform via the same `MPI_Allreduce` pattern as `velSweepLoop`). This subsumes
`velSweepLoop`'s increment test: the increment stop stays as the *inner* control, the residual
stop is the *outer* one.

**Fable's choice**: plain defect correction (Richardson on the preconditioned residual) is the
minimal form and is what the existing structure becomes with one loop around it; if its rate on
the FOU (non-symmetric) operator at large dt is poor, BiCGStab with the same `P` is the next
step — `solveBiCGStab` in `mac_cutcell_mg.hpp:988` is the template, and the momentum operator is
per-component, so scratch is 3× a level-0 field set. Do not reach for FGMRES unless BiCGStab
breaks down (it can on the sliver-rescaled rows; that is a finding).

Gates: the momentum-side rows of WO-M's table in the **float** build reach the double column —
uniform-velocity identity `≤ 1e-14` (was 1.3e-7), porous drag balance `≤ 1e-14` (was 4.8e-8);
Poiseuille, Z&H drag (4.292), RCP k unchanged to 6 digits; total sweep count per step within
+10 % of today on `zh_sphere` N=64 (more is a finding: report it, do not tune it away); MPI np=1
bitwise gate-off, np=1/2/4 identical across np gate-on; `set_ghost_projection` collocated momentum
path exercised.

### D1 — dem: double state, float solve  [Fable, evaluation only]

The methodology's shape for a nonlinear complementarity solve is *state in double, correction
in float*: positions/velocities in double, `Δx`/`Δv` from the float PGS/XPBD sweeps, constraint
residual `C(x)` evaluated in double. Today `V3 = View<float*[3]>` end to end. This is a
memory-bandwidth decision for the whole DEM, not a solver switch, and it must be weighed against
the measured perf curve (`dem-perf-campaign`). Fable writes the a-priori estimate (bytes/particle
today vs proposed; which kernels are bandwidth-bound; what precision the Hertz history and the
persistent-contact ledger need) and a *recommendation*; nothing is implemented this campaign.

### X — audits, record only  [Opus]

voro mesh-optimizer CG: confirm `Aop` assembly and the wall-Jacobian term are double end to end
and the GraphAMG is used only as a preconditioner (it is — `mesh_optimizer.hpp:35-41`). pnm: no
linear solve, out of scope. `mac_mg.hpp`: already exact matrix-free. One paragraph each in §4.

## 3. Order, ownership, and the handoff protocol

**Order**: **M1 + M2 design (Fable) FIRST** → P1 → (P2, A0, A1 in any order) → M1 → M2 → P3
(if perf says so) → D1 (Fable) → X.

The design leads deliberately (user decision, 2026-09-01). Both momentum design sections are
written up front, in one Fable session, before any Opus implementation starts — so that Opus then
has a long uninterrupted run (P1 → P2/A0/A1 → M1 → M2) with no mid-campaign wait for a ruling, and
so that M1's exact-residual design is settled while the inventory that motivated it is fresh. It
costs nothing to front-load: the design is reading and reasoning, no builds, no GPU time.

**P1 remains the go/no-go for *implementation*.** It is the discriminating experiment for the
whole campaign: if its ladder does **not** reproduce the double column, stop and hand off — the
premise is wrong somewhere and nothing further should be built on it, M1/M2 included. Ordering the
design first does not lower that bar; it only means the design is already on paper when P1
answers. If P1 fails, the M1/M2 design sections stay in §4 as unexecuted design, and the handoff
question becomes why the premise failed.

Consequence for Fable's first session: it writes M1 and M2 designs against the *inventory* (§1),
not against P1's measurements, which do not exist yet. Where a design decision genuinely depends
on a number P1 would produce, do not guess — state the dependency explicitly in the design section
(`**Depends on P1:** …`) and give the decision rule rather than the decision, so Opus can resolve
it from P1's numbers without another handoff.

**Ownership**: Opus executes every rung marked [Opus]; Fable owns the design decisions in M1, M2,
the `rescale` semantics in P2, and D1. Opus does not start M1/M2 implementation until the Fable
design section for it exists in §4 of this file — which, under the order above, it will, since the
campaign opens with that Fable session. If an Opus session somehow starts first and §4 is empty,
it may still run P1/P2/A0/A1 (none of them depend on the momentum design) and must leave M1/M2
alone.

**Handoff triggers (Opus → Fable)** — stop, write the handoff, do not push past it:
1. A gate fails and two attempts have not isolated the *mechanism* (not "made it pass").
2. The change needed is to numerics semantics, not precision (a different operator, a different
   stop criterion, a different identity) — anything that would change a double-build result.
3. A measurement contradicts a prediction in this plan (e.g. P1's ladder, P1's perf ≤ 0,
   M2's sweep count).
4. A design fork with more than one defensible option and no measurement that decides it.
5. Anything touching `buildOpenness` / the coefficient path (S3's trap: it feeds both the
   geometric openness and the coefficient path).

**The handoff itself** is a section appended to §4 of this file: `### Handoff → Fable: <one-line
question>` with *what was measured* (numbers, commands, build flags, np), *what was tried*, *what
the mechanism is believed to be* and *the decision needed*. Commit it. The next session (Fable)
starts from `DEFECT_CORRECTION_PROMPT.md`, which says to read §4 first. Fable answers in the
same section (`**Fable ruling (date):**`) and the following Opus session resumes from there.

**Fable → Opus** works the same way in reverse: a design section in §4 ends with
`**Ready for Opus:**` and the concrete change list.

## 4. Status log (append-only; newest at the bottom)

*(The executing sessions append here: one entry per rung with commit hash, gate results as
numbers, and any handoff sections. The two momentum design sections below were written before
any implementation, per §3.)*

### M1 design (Fable, 2026-09-01) — the exact momentum residual

Read-only session: everything below is from the source, nothing was built or run. Line numbers
are flow HEAD as of the umbrella's `flow` pointer on 2026-09-01.

**What the sweeps actually solve.** Per component `c` the RB-GS sweeps solve `A'_c u = b_c` where

- `A'` is the float band `C[c].AC..AT` assembled in this order: `ibmBuildDiffusion` (constant
  path) or `ibmBuildDiffusionVar(VarFaceProps)` (`cut_cell_ibm.hpp:229`, `:257`) → `Grid::fou_operator`
  folded in on the implicit-FOU paths (`flow_ibm.hpp:3709`, `:3746`) → `ibmModifyStencil`
  (`cut_cell_ibm.hpp:291`: row scale `D = D_rescale` + ghost substitution; writes `rscale` and
  `inhom`) → `addDragDiagonal` (`:5726`, β on the diagonal, **not rescaled**) → `applyBackflowStab`
  (`:3800`, outflow slab, **not rescaled**, lagged at the live `u`).
- `b` is `rs·(bracket) − inhom` on the IBM path (`buildRhs*` `:3407`, `:3486`, `:3538`, `:3576`) and
  `rs·(bracket) + brhs` on the const-coeff domain-BC fold path. So the stored `b` already carries
  both the rescale and the inhomogeneous wall-velocity term.
- Solid (masked) rows are pinned to `u = 0` by the smoother (`mac_ibm.hpp`, `solidmask > 0.5`). The
  `|ac| < 1e-30` skip is dead code for momentum: the θ clamp (`cut_cell_ibm.hpp:104`) keeps
  `D ≥ 1e-4·(1+1e-4)`, so every fluid row has `AC ≥ 1e-4·ρ/dt`. The P1 "tiny-but-nonzero openness"
  trap has no momentum analogue — the decoupling test is the mask, not the diagonal.

**Four corrections to §1's inventory, each a design input.**

1. `ibmBuildDiffusion(Var)` and `ibmModifyStencil` live in `cut_cell_ibm.hpp`, not `mac_ibm.hpp`
   (which holds the smoothers and the overlay-build driver). Cosmetic.
2. **The overlay is allocated per cell, not per cut cell**: `maxCut = nx·ny·nz` (`flow_ibm.hpp:109`),
   156 B per slot (`cell_index 4 + num_boundaries 4 + D_rescale 4 + dir_code 24 + K/M/X/Nbc/R 120`)
   × 3 components = **468 B/cell allocated today**; *touched* memory is 156 B per cut cell per
   component. "6·n_cut, cost small" is true of traffic and false of allocation. Widening in place
   would add +156 B/cell (X, Nbc, D only) to +372 B/cell (all five). This settles (d) toward storing
   nothing.
3. **The Galilean identity as stated in §0/§2 does not hold for this operator in general.**
   `fou_operator` (`staggered_advection.hpp:113`) is the *conservative* FOU: per axis its row sum is
   `ρ_f·(velp − velm)`, and summed over the three axes that is `ρ_f·½[div_h(u^k)_i + div_h(u^k)_{i−s_c}]`
   — the face mean of the cell divergence of the *advecting* field, which is exactly the quantity the
   porous path compensates with `divAdv_` (`buildRhs:3398`). Hence
   `(A − idiag·I − β·I − extraDiag)·1 = ρ_f·div̄_h(u^k)`, zero only when the advecting field is
   uniform or discretely divergence-free. WO-M's V2b test carries a uniform velocity, so its
   8.9e-16 measures the identity where it holds; as a general assertion it must carry the
   divergence term. (e) below asserts the correct statement.
4. **Drag × cut cell is a numerics defect, not a precision one.** The drag diagonal is added
   *after* the rescale and is not scaled by `D`, while its RHS target `β·u_p` sits inside the
   rescaled bracket (`rs·(… + fbF …)`). At a cut cell the fixed point is `β·u = D·β·u_p`: the drag
   relaxes towards `D·u_p`, wrong by the row scale. The code documents the `rscale ≠ 1` interaction
   as "untested" (`:5724`). The backflow diagonal has the same shape (harmless in practice —
   outflow-adjacent cells are rarely cut). **Ruling**: M1 reproduces the operator *as the sweeps see
   it* (unscaled β), so `r(u*)` is the residual of the sweeps' problem and the M1 gate stays
   meaningful; the fix is a separate one-line commit after M2 (`AC += rs·bd` in `addDragDiagonal`,
   RHS unchanged) gated on the all-fluid porous drag balance (unaffected, `rs ≡ 1`) plus a new
   cut-cell drag test. It changes double-build results at cut cells, so it gets its own re-baseline.

**The algebra the exact residual must reproduce.** Write the pre-modification row as
`aC0·u_c + Σ_k a_k·u_k` with `aC0 = idiag + Σ_k t_k + advdiag`, `a_k = −t_k + adv_k`, where
`t_k = fp.beta(i, nb_k) ≥ 0` is the face viscosity and `adv_k ≤ 0` the upwind coupling. Reading
`ibmModifyStencil` line by line: for a fluid neighbour `(K, M, X, Nbc) = (0, 1, 0, 0)` gives `D·a_k·u_k`;
for a ghost neighbour `(Nc·R, 0, N_nb·R, 2R)` gives `a_k·(K u_c + X u_opp + Nbc u_bc)`. So the
modified row is **exactly**

```
D·[ aC0·u_c + Σ_fluid a_k u_k + Σ_ghost a_k u_g(k) ] + inhom,
u_g(k) = (K_k u_c + X_k u_opp(k) + Nbc_k u_bc) / D,     inhom = Σ_ghost a_k Nbc_k u_bc
```

i.e. the original row with each ghost value replaced by its quadratic wall extrapolation, then
scaled by `D`. I verified the closure identity `K_k + X_k + Nbc_k = D` in exact arithmetic on both
branches of the fill: single ghost `2(ξ²−1) + ξ(1−ξ) + 2 = ξ(1+ξ)` (`:29-37`), sandwich
`(ξm+1)(ξp−1) + [ξm(1+ξm) + ξp(1−ξp)]/(ξm+ξp) = ξm·ξp` (`:50-56`) — the extrapolation reproduces a
constant. In the float overlay that identity holds only to eps_f32, and **`K_val` is the overlay's
diagonal**: `K + X + Nbc − D ≠ 0` at eps_f32 is the momentum-side "diagonal disagrees with the
faces" defect at cut rows, the one WO-M's `MReal` switch could not reach. Substituting
`K = D − X − Nbc` eliminates `K` and puts the cut row in difference form:

```
(A u)_c = D·{ idiag·u_c + Σ_fluid k  t_k·(u_c − u_k) + ρ_f·FOU(ũ)_c }
        + Σ_ghost k  (t_k − adv_k)·[ X_k·(u_c − u_opp(k)) + Nbc_k·(u_c − u_bc) ]
        + β_f·u_c + extraDiag_c·u_c                                (unscaled, as built)
ũ_k = u_k (fluid neighbour),   ũ_k = u_c (ghost neighbour)
```

Non-cut rows are the same with `D = 1` and no ghost sum. `FOU(ũ)_c` is literally
`Grid::advect_fou(c, …, ũ)` (`staggered_advection.hpp:164`) — the double flux difference
`Σ_fd F(ũ_c, ũ_+, velp) − F(ũ_−, ũ_c, velm)`, `F(L, R, v) = v·(v > 0 ? L : R)`, whose max/min split
*is* `fou_operator`'s diagonal/off-diagonal — the same function the deferred correction already
evaluates on `u^k`. Every non-diagonal term is a coefficient times a difference; `K` and `R` are
never read; nothing is divided by `D_axis` (the `[X(..) + Nbc(..)]` bracket is bounded by `2R ≤ 2`),
so the sliver rows are as well scaled as the Robust-Scaled stored rows.

**(a) One fused matrix-free kernel, not a composition.** (i) A composed form needs seven double
scratch bands (56 B/cell) per component, rebuilt per component per outer iteration because the
three operators differ — more traffic than the residual itself. (ii) Stored bands cannot give any
identity bitwise: the diagonal is stored, and at cut rows the stored `K` carries the closure
defect; the difference form never forms a diagonal. (iii) "Reproduce the row modification
exactly" is meaningful only algebraically, and that is proved above; the composed double form is
its float-free twin and becomes the **test oracle, not the product**: `ibmBuildDiffusion(Var)` and
`ibmModifyStencil` are already templated on the view type, so instantiating them on double
scratch and applying with a stencil apply gives a reference to compare the fused kernel against on
random cut configurations (`test_ibm_overlay.cpp`'s generator), ≤ 1e-13 relative per row. One
kernel, `momResidualExact<Grid>(r, u, b, inhom, VarFaceProps fp, U, V, W, fouw-rule, drag(β view,
faceAvg), extraDiag, uBc, sdf, off, thEx, idMap, mask, e, G)` returning `max|r|` over inner rows
(fused reduction, `r = 0` at masked rows), plus a box variant with the same skip-box signature as
`ibmRbgsStencilColorBox` for the distributed overlap.

**(b) Where `inhom` lives.** Today `inhom = Σ_ghost a_k·Nbc_k·u_bc` is accumulated in
`ibmModifyStencil` from the *float* `orig[k]` and float `Nbc` (double arithmetic on float-rounded
inputs, `:311-318`) and folded into `b`. In the difference form the wall-velocity term is not a
separate vector at all: it is the `Nbc_k·(u_c − u_bc)` half of the ghost sum, formed in double
inside the operator. The kernel therefore needs the *physical* rescaled RHS `rs·bracket`, which it
recovers as `b(i) + inhom(i)` from the two existing `CCField`s — exact when `u_bc ≡ 0` (every
static case: `inhom` is then exactly `0.0`, `(double)Nbc·0.0f·vnb`) and within 2 ulp(|rs·bracket|)
for moving geometry. **The RHS builders are untouched** and the sweeps keep solving the folded
system, so gate-off byte identity holds by construction. Consequence for M2: the inner correction
equation `A_float·δ = r` carries no `inhom` — only the outer residual sees the wall velocity, and
it sees it in double. That is also what removes the ~eps_f32 relative wall-velocity forcing error
the float `inhom` imposes on moving-body runs (ten-cate's regime): worth recording in the M1 gate
as `|r(u*)|` on the cut band of a moving instance.

**(c) One kernel covers constant, varProps, varRho and porous-ε by construction.**
`VarFaceProps` with `haveMu = haveRho = false` *is* the constant path — `makeFaceProps(c)` (`:2282`)
returns exactly that — so the kernel is instantiated once on `VarFaceProps`: `fp.beta(i, nb)` is
the face viscosity (arithmetic or harmonic, the accessor `ibmBuildDiffusionVar` reads) and
`fp.idiag(i)` the face-density time diagonal (`0.5(ρ(i)+ρ(i−s_c))/dt` with `effRhoField()` =
`epsRho_` on the eps-conservative porous path, refreshed by `updateEpsRho()` before the build).
Two rules are copied verbatim from the builders, not re-derived: `fouw = vr ? 0.5·(rf(i) + rf(i −
s_c)) : ρ` (`buildAdvStencilVar:3771`) and `bd = porous_ ? 0.5(β(i)+β(i−s_c)) : β(i)`
(`addDragDiagonal:5750`). No siblings. **What needs care is what is frozen.** The FOU coefficients
were built from `advVelView(0..2)` (`:3266`), which aliases `C[c].u` unless a moving scene supplies
`uwAdv_` — and the sweeps overwrite `C[c].u`. A residual evaluated after the sweeps must use the
advecting field the operator was built from, or it is the residual of a *different* (Picard-updated)
operator. Use `prev_[c]` (already allocated, 0 B) as the frozen `u^k` stash, but: it is copied only
when `outerTol_ > 0` (`:1723`) and *before* the ghost fill at `:1727`, so under the gate copy it
unconditionally and after that fill (its inner values are unchanged, so `outerTol_`'s semantics are
untouched). `applyBackflowStab` likewise reads the live `u`; under the gate it also writes its
increment into a lazily allocated double `backDiag_[c]` (only when `hasOutflow_ && backflowBeta_ >
0`), and the const-coeff fold path's `bcDcorr_[c]` goes into the same `extraDiag` slot. On that fold
path the smoother is already double end to end (`diffSmoothColor` takes double `beta`, `Ac`,
`dcorr`, `mac_stencils.hpp:37`), so the residual there serves only M2's stop criterion.

**(d) The overlay: store nothing; evaluate the rows in double on the fly from the resident double
SDF.** Matrix quantities: `D_rescale` (row scale), `X_val` and `Nbc_val` (both multiply *u* in the
difference form — **`Nbc` is not RHS-side**: it is part of the diagonal through `K = D − X − Nbc`,
and only its `u_bc` half is the inhomogeneity; §2's "Nbc_val/R_val are RHS-side" is wrong for
`Nbc`), and `M_val` only as the is-ghost flag. `K_val` and `R_val` are not needed by the residual.
What the fill must evaluate in double: everything upstream — `θ = sdf_c/(sdf_c − sdf_n)` from the
*double* samples (`ccSampleExt` is double; `buildIbmOverlay` casts to float at `mac_ibm.hpp:58-63`),
the clamps, `poly_D`/`poly_D_sandwich` → `D_axis`, `D_rescale = argmin|D|`, `R = D/D_axis` (`:150-152`),
`poly_N_nb`, `poly_Nbc_*_sw`, the exact crossings from the double `tEx_` arrays; `poly_N_c_sandwich`
and `poly_Nc` are evaluated only by the oracle test (to check `K + X + Nbc = D` to 1e-15). Mechanism:
template `ibmFillEntry` on the real type (`template <int SCHEME, class Real, class OV>`) and add a
per-thread `OverlayRow<Real> { Real D; Real X[6], Nbc[6]; bool ghost[6]; }` target; factor the
7-sample gather (+ `thEx` wrap logic) of `buildIbmOverlay` into a shared inline function so the
build and the residual cannot drift. The float build instantiates `Real = float` into the SoA views
(byte-identical); the residual instantiates `Real = double` at cut cells only. **The cut set is the
float overlay's** (`idMap(i) ≥ 0`, `mask`), never re-decided in double — a sample within eps of zero
must not move between the sets; only the *values* differ. Storage: **0 B**. If widened in place
instead: +52 B per cut cell per component (X, Nbc: 2×6×4; D: 4) = +156 B/cell at today's per-cell
allocation, or ≈ +31 B/cell at a 20 %-cut bed if right-sized to `nCut` in a second pass (+74 B/cell
for all five). Traffic per residual at a cut cell: ~14 SDF reads (two cell values per staggered
sample) + 3 `thEx` ≈ 136 B, against 104 B for stored double X/Nbc/D — same order, so recompute is
not a traffic loss. Decision rule (an M1 measurement, not P1): if ms/residual on `zh_sphere` N=64
exceeds 1.5× the stored-band `residualVarPin` (`mac_velocity_mg.hpp:33`), cache the double rows
right-sized to `nCut` in a second pass after the count; the algebra is unchanged either way.

**(e) The flux form, and what is actually asserted.** Diffusion: `t_k·(u_c − u_k)` from `fp.beta`,
never `Σt` as a diagonal. FOU: `ρ_f·advect_fou(ũ)`, a flux difference with the same max/min
structure as the stored coefficients. Time, drag and extra diagonals: `D·(idiag·u_c)` then
`+ β_f·u_c + extraDiag·u_c`, the same association `buildRhs` uses (`rs·(idiag·un + …)`), so the
uniform case cancels bitwise. Cut rows: the ghost sum above, differences only. Assertion, precisely:
for `u ≡ U`, `u_bc ≡ U`, wall/inflow ghosts filled to `U`, and a **uniform advecting field**,
`r(u) = b − A u` with `b = rs·(idiag·U)` is **`0.0` bitwise at every fluid row, cut or not**: each
non-diagonal term is `c·(x − x) = c·0 = 0` exactly (guarded — `R = 1` when `|D_axis| < 1e-9`, θ
clamped — so no `NaN·0`), sums of exact zeros are exact, and the diagonal terms are formed in the
RHS's order. With a non-uniform advecting field the assertion becomes `r = −rs·ρ_f·div̄_h(u^k)·U`
to 1 ulp — the conservative form's row sum — and the gate must test that expression, not zero. With
static walls (`u_bc = 0`) a uniform `u` is *not* annihilated at cut rows (the wall drags), and the
correct rescaled assertion is `(A u)_c − rs·idiag·U = Σ_ghost (t_k − adv_k)·Nbc_k·U`, the exact wall
drag: that is what "a rescaled row preserves a zero residual but not the raw identity" means here.

**Gates as numbers I predict.**
1. Uniform-velocity identity (V2b `gate_uniform`, ratios 1e1…1e4, all-fluid periodic): `max|r(U)|`
   **≡ 0.0**, bitwise, not `≤ 1e-14`. On `zh_sphere` with `u_bc = U` also `0.0`; with `u_bc = 0`
   equal to the wall-drag expression to 1 ulp.
2. `|r(u*)|/max|b|` at the float sweeps' fixed point: 1e-7…1e-6 on Poiseuille and `zh_sphere`,
   with the **argmax in the cut band** on `zh_sphere` (structural prediction: the closure defect
   `K + X + Nbc − D` at eps_f32 exceeds the all-fluid eps_f32 diagonal rounding). Porous drag
   balance: ≈ 5e-8 — WO-M's 4.768e-8 *is* this fixed-point offset, measured in velocity units.
3. When the increment stop leaves the sweeps unconverged, `|r(u*)|/|r(u^k)|` ≈ `velTol_`, well above
   the eps_f32 floor — the first time the solver can tell the two apart. Report both.
4. Fused kernel vs composed-double oracle on random cut rows: ≤ 1e-13 relative. Fused kernel vs
   the stored-band residual on all-fluid: ≤ 4 ulp_f32·|A||u| per row.
5. Perf: the residual reads ≈ 44–60 B/cell (`u`, `b`, `inhom`, `U/V/W`, `idMap`; μ/ρ fields when
   variable) against 44 B for the band residual → ≤ 1.4× `residualVarPin`, once per outer iteration.
6. Gate off: no code path changes; regression byte-identical. Gate on, np=1/2/4: the max is
   order-free, so the residual maxima are bitwise equal across np.

**Ready for Opus:** change list
1. `cut_cell_ibm.hpp`: template `ibmFillEntry` on `Real`; add `OverlayRow<Real>` and
   `ibmFillRow<SCHEME, Real>` on the same code path as the SoA fill. Extend `test_ibm_overlay.cpp`:
   float SoA vs `OverlayRow<float>` bitwise; `OverlayRow<double>` satisfies `K + X + Nbc = D` ≤ 1e-15.
2. `mac_ibm.hpp`: factor the 7-sample gather (+ `thEx` wrap) of `buildIbmOverlay` into
   `ibmGatherCut<Real>(…)`; `buildIbmOverlay` calls it with `float` — byte-identical.
3. New `mac_momentum_residual.hpp`: `momResidualExact<Grid>` + box variant, as in (a).
4. `flow_ibm.hpp`: env gate `PECLET_FLOW_EXACT_MOMENTUM` (helper like `mgDiagResum()`); under it:
   unconditional `prev_` copy after the `:1727` fill; lazily allocated `backDiag_[c]` written by
   `applyBackflowStab`; `momentumResidual(c)` wrapper choosing the branch's own fill closure
   (`fillVelGhostsTo(u, c, 0)` / `fillVelGhosts(c, 1)` / `fillGhostsFaces` / halo exchange) before the
   kernel; after each `smoothComp(c)` record `max|r(u*)|`, its argmax class (cut / non-cut / fold),
   and `max|b|`, exposed in the stats dict (`momentum_residual_{x,y,z}`, `momentum_rhs_max`).
5. New ctest `test_momentum_residual.cpp` (`tests/kokkos`): gates 1, 4 above, plus the
   divergence-form assertion with a non-uniform advecting field.
6. Then run the M1 gate battery (`precision_ab.py` cases `vof`, `porous`, `zh`; Poiseuille) with
   the gate on and record gate 2/3 numbers here. No solver change in this rung.

### M2 design (Fable, 2026-09-01) — the outer loop

**Choice: plain defect correction (Richardson on the preconditioned residual), with outer
iteration 0 being today's solve verbatim.**

```
iteration 0:  today's smoothComp branch on (C[c].u, C[c].b)             — unchanged code, unchanged bits
r_ref = max|r(u^k)|  (evaluated before iteration 0 when the gate is on)
for it = 1 .. max_outer − 1:
    fill(u);  rmax = max|r(u)|                                           — M1 kernel, double, MPI_Allreduce(MAX)
    if rmax ≤ max(rtol_r · r_ref, atol_r): break
    δ = 0;  same branch on (δ, r) with HOMOGENEOUS boundary data          — P: k RB-GS colour pairs, or vmg.solve
    u += δ
```

Why Richardson and not BiCGStab first: (i) away from the cut band the operator is diagonally
dominant (`idiag = ρ/dt + Σt + FOU-diag`), so RB-GS is a contraction and
`‖I − P·A_exact‖ ≈ ‖I − P·A_float‖ + O(eps_f32)`: each outer iteration multiplies the residual by
≈ `max(velTol_, 1e-7)`, and the outer rate is set by the *inner* solve, not by the float/double
gap; (ii) scratch is one `r` and one `δ` (16 B/cell, reused across components — `setVelocityStreams`
is a no-op, `:566`, so the 3× the plan feared does not arise) against BiCGStab's six extra vectors
(48 B/cell); (iii) Richardson cannot break down — its only failure is a slow rate, which is a
capped and *reported* solve; (iv) gate-off byte identity is by construction (`max_outer = 1` →
iteration 0 only, no residual evaluated). Non-symmetry is irrelevant to Richardson; it is why CG is
not on the list, not an argument for BiCGStab.

**What `P` is on each branch.** bcStencilPath / collocated-BC / periodic-IBM / distributed
(blocking and CA): `velSweepLoop` on `(δ, r)` with the same colour kernels. This is a refactor of
`smoothComp(c)` into `runMomentumBranch(c, x, rhs, homogeneous)`; the legacy call is
`runMomentumBranch(c, C[c].u, C[c].b, false)` with identical kernel arguments. **The `homogeneous`
flag is the trap**: on the correction equation the domain-BC fill must reflect about *zero* (wall
and inflow Dirichlet data → 0, outflow zero-gradient unchanged); `fillVelGhostsTo(δ, c, 0)` as
written would impose the wall velocity on the correction. `applyVelocityBcCompTo` (`:4155`) gets a
`homogeneous` argument (`bcVel_` and profiles → 0). Periodic and halo fills are unchanged. vel-MG
branches (IBM staircase/upwind, `:3960`; domain-BC const-coeff, `:3930`): `vmg_.solve(r, δ,
vmgVcycles_, 2, 2, 8)` with the `bcApplyL0_` hook in its homogeneous form — VelocityMG's own level-0
residual stays the float `residualVarPin`; it is inside `P`. **Distributed**: both vel-MG branches
are disabled under `distributed_` with a notice (`:1296-1301`), so the distributed path always uses
the RB-GS `P`; `VelocityMG::initMpi` exists (ctest `velocitymg_mpi`) but wiring it into the solver is
separate work, not this campaign. Const-coeff fold path: already double end to end; `P` is the same
double sweeps and the outer loop adds only the residual-based stop.

**Stop criterion and rank-uniformity.** Outer: `max|r(u)|` over inner fluid rows, double, one
`MPI_Allreduce(MAX)` per outer iteration (the `velSweepLoop:3867` pattern); the max is order-free,
so np=1/2/4 decide identically and bitwise. Inner: `velSweepLoop`'s increment test is unchanged and
keeps its meaning — `velIters_` is the sweep cap *per inner solve*, `velTol_` the increment
contraction *per inner solve*, `velMinIters_` the inner floor; on the correction equation `du0` is
the first sweep's increment of `δ` from zero, so the relative test behaves as today. The reference
scale is `r_ref = max|r(u^k)|` before iteration 0 — the explicit momentum imbalance, the natural
physical scale (one extra residual per component per Picard iteration, ≈ one sweep's traffic);
`|r|` *after* iteration 0 is the wrong scale, it is already the float floor. `atol_r` covers
`r_ref = 0` (rest state).

**Public API.** `set_velocity_solver_params(iters, rtol, min_iters)` (`flow_bindings.cpp:212`)
keeps its meaning exactly — inner control, no silent change. New
`set_momentum_residual_params(rtol_r, max_outer, atol_r = 0.0)` with default `max_outer = 1`
(byte-identical); the timing/stats dict gains `momentum_outer_iters`, `momentum_residual_ref`,
`momentum_residual_final` (per component max); `momentum_sweeps` keeps counting every sweep,
correction solves included (`lastMomentumSweeps_ += used` already does this). The env gate
`PECLET_FLOW_EXACT_MOMENTUM` enables the M1 diagnostic; the outer loop runs only when
`max_outer > 1`.

**Depends on P1:** whether a Krylov method (BiCGStab with the same `P`) is worth its second
residual per iteration versus more Richardson iterations. P1's perf gate gives the cost ratio
`ρ_x = c_exact / c_band` for the flux-form matvec on CUDA and OpenMP. Decision rule: with `c_r` one
momentum residual (M1 gate 5; predicted ≤ 1.4·c_band from the byte counts) and `c_s` one colour
pair, Richardson costs `c_r + k·c_s` per outer iteration and BiCGStab `2·c_r + 2k·c_s + ~10 vector
ops`. **If `ρ_x ≤ 1.5`** (P1's own prediction is ≤ 1: fewer bytes), then `c_r ≈ c_s` and both
methods are dominated by `k·c_s` per residual evaluation, so the choice is decided by
outer-iteration counts alone: switch to BiCGStab only if Richardson needs more than 2× BiCGStab's
iterations to reach the same `|r|` on `zh_sphere` N=64 at the stiff end (`ρ/dt ≤ 6μ`; at the
CFL-limited dt Richardson converges in 1–2 outer iterations and nothing is gained). **If
`ρ_x > 2`** (a P1 finding contradicting its prediction — handoff trigger 3 fires there first),
residual evaluations are the expensive part, Richardson with larger `k` (fewer residuals) is the
right shape, and BiCGStab is out unless it halves the residual count. Do not decide this without
the P1 number. Middle option if the rule says Richardson is too slow: minimal-residual Richardson
(`ω = (r, A P r)/(A P r, A P r)`; one extra matvec, two dots, monotone in `‖r‖₂`, no breakdown mode)
— one extra vector, not six.

**BiCGStab breakdown on the sliver-rescaled rows, if it is reached.** `solveBiCGStab`
(`mac_cutcell_mg.hpp:988`) guards `|ρ_new| < 1e-300` and `|(r̂, v)| < 1e-300` — absolute, never
tripped in practice. For the momentum operator breakdown looks like `(r̂, A P p)` changing sign or
falling below ~1e-12·‖r̂‖‖v‖ between consecutive iterations while `max|r|` sits on cut-band cells
(M1's argmax diagnostic), and `ω → 0` (`tt` tiny): the preconditioned operator acquiring
eigenvalues with negative real part, which the Robust-Scaled rows can produce — they are not
M-matrix rows (`X_k = ξ(1−ξ)·R > 0` is a positive off-diagonal). Make the guards relative, log the
argmax cell, fall back to Richardson for that solve; FGMRES only if Richardson's rate at large dt is
also unacceptable — both measured, both findings.

**Gates restated as numbers.** Uniform-velocity identity (V2b `gate_uniform`, ratios 1e1…1e4):
iteration 0 leaves the float fixed point at 1.3e-7…1.7e-7; one correction brings it to ≤ 2e-14
(error × ≈ `max(velTol_, 1e-7)`), two to ≤ 3e-16 — so `≤ 1e-14` needs `rtol_r ≤ 1e-13` relative to
`r_ref` and costs one to two inner solves per component. Porous drag balance: 4.768e-8 → ≤ 1e-14
after one correction, ≈ 2.8e-16 after two. Poiseuille, Z&H 4.292, RCP `k`: unchanged to 6 digits
(WO-M: float and double already agree to the 6th digit). **The +10 % sweep gate and the 1e-14
identity gate cannot both be measured at one setting — fix the gate**: at the production default
(`rtol_r = 1e-6` relative to `r_ref`) the float fixed point (`~1e-7·|b| ≲ 1e-6·r_ref` for any
non-trivial step) already satisfies the stop, so the outer loop costs one residual evaluation and
**zero** extra sweeps (+0 % sweeps, ≈ +2 % momentum time for the two residual evaluations) and
certifies each step; at `rtol_r = 1e-13` expect ≈ 3× today's sweeps on `zh_sphere` N=64 (three
inner solves per component) — report it, do not tune. MPI: np=1 bitwise with `max_outer = 1`;
np=1/2/4 identical outer counts and bitwise residual maxima with it on. `set_ghost_projection`
collocated momentum: same kernels through `Grid = Colocated`, exercised by the existing gp ctests
with the gate on.

**Ready for Opus:** change list
1. `flow_ibm.hpp`: `runMomentumBranch(c, x, rhs, homogeneous)` refactor of `smoothComp` (all six
   branches, CA and overlap included); `applyVelocityBcCompTo(…, homogeneous)`; homogeneous
   `bcApplyL0_` hook; `momentumSolve(c)` = iteration 0 + corrections; scratch `momR_`, `momDelta_`
   (two `CCField`s, allocated under the gate); `r_ref` before iteration 0; stats and the
   `set_momentum_residual_params` binding (`flow_bindings.cpp`, beside `set_velocity_solver_params`).
2. Validation order: gate-off regression byte-identical → M1 gates → M2 at `rtol_r = 1e-13` on the
   two identity cases → M2 at the production default on the regression suite (+0 % sweeps
   predicted) → `kokkos_mpi` np=1,2,4 → the default-flip commit with `--update`.
3. After M2 lands: the drag-diagonal rescale commit from M1's ruling (4), with its own re-baseline.
   **Name `coupling` as an affected consumer in that commit message** (collocated session, 2026-09-01):
   drag on cut cells is the porous CFD-DEM coupling campaign's bread and butter, so whichever session
   next touches `peclet-coupling` must re-baseline its drag-balance checks rather than chase a phantom
   regression. The all-fluid porous drag balance is unaffected (`rs ≡ 1`); it is the cut-cell drag that
   moves, and it moves in a *double* build too — this is a numerics fix, not a precision one.


### P1 — `CutcellMG` exact level-0 matvec — **gate-passed, NOT default-flipped 2026-09-01/02**, flow `e9da3e5`

`PECLET_FLOW_EXACT_RESIDUAL=1`, default OFF, byte-identical off. `applyCutcellOpExact` /
`applyCutcellOpExactBox` (`mac_pressure.hpp`) apply `y_i = Σ_f t_f (x_i − x_nbr)`,
`t_f = open_f·gf`, read from the resident double `Level::ox/oy/oz` — the same arrays
`buildCutcellOp` assembles the float bands from, so **0 B/cell** (GPU memory identical to the
byte, measured). `matvecOverlap` branches on the gate in both the distributed-overlap and the
single-rank branch; `setOpenness` retains `gfx_/gfy_/gfz_` (all three call sites pass 1.0 today,
stored anyway). Nothing inside `vcycle` changed.

**Status: the gate stays OFF and the default is NOT flipped.** Gates 1, 2, 3 and 5 passed and the
discriminating experiment (gate 3) passed decisively, but **gate 4 (MPI) is only partially run and
gate 6 is partial** — see below. The plan's "then flip the default ON in a separate commit with
the regression re-baseline" step is **not done** and must not be done until gate 4 closes.

**Gate 1 — `A·1 = 0` bitwise.** New block in `tests/kokkos/test_cutcell.cpp`, on the two
regression beds (`random_spheres` centres lifted from the seed-12345 generator; `hollow_rings`
is deterministic), N = 32 and 64:

| bed | N | `max\|A_exact·1\|` | `max\|A_bands·1\|` | rel. to `max AC` | cut / solid cells |
|---|---|---|---|---|---|
| random_spheres | 32 | **0.000e+00** | 2.980e-07 | 4.97e-08 | 4192 / 5083 |
| random_spheres | 64 | **0.000e+00** | 2.980e-07 | 4.97e-08 | 15990 / 45822 |
| hollow_rings | 32 | **0.000e+00** | 2.980e-07 | 4.97e-08 | 3197 / 2330 |
| hollow_rings | 64 | **0.000e+00** | 2.980e-07 | 4.97e-08 | 12283 / 23004 |

Bitwise zero, as predicted, and the band figure is the expected ~1e-7·`max AC`. Solid cells: 0
in both forms, checked explicitly. Bands vs exact on a random field agree to 2.3e-8…2.5e-8
relative — it is the same operator, not a null-space trick.

**Gate 2 — gate off byte-identical.** Regression suite **+0.00 % on every metric**, identical
`p_iter_tot`, iterations/step, step count and divergence on all 13 grid points of
`zh_sphere` / `random_spheres` / `hollow_rings`. 26/26 `tests/kokkos` ctests pass on nvidia-cuda.

**Gate 3 — the ladder** (RCP bed, PCG rtol 1e-8 cap 300, one RTX 5080):

| Ng | float bands | **EXACT_RESIDUAL** | DIAGRESUM (double build) | full MREAL_DOUBLE |
|---|---|---|---|---|
| 48 | 24 its, div 4.51e-06 | **14, div 9.51e-12** | 14, div 6.19e-10 | 14, div 9.51e-12 |
| 64 | 33 its, div 6.48e-07 | **14, div 9.53e-12** | 14, div 1.24e-09 | 14, div 9.53e-12 |
| 96 | **300 — CAPPED, INVALID**, div 4.36e-06 | **28, div 3.17e-11** | 28, div 2.04e-09 | 28, div 3.17e-11 |

The prediction was that the exact column reproduces the double column (14/14/28) with the
hierarchy still float. It does, **to every printed digit on iterations and on divergence**, and
the float column reproduces WO-M's 24/33/capped and 4.5e-6/6.5e-7/4.4e-6 exactly, so the
instrument is validated against its own prior record.

**One result stronger than the plan predicted: exact beats the double-diagonal by ~2 orders on
divergence** (9.51e-12 vs 6.19e-10 at Ng=48; 3.17e-11 vs 2.04e-09 at Ng=96) while matching it on
iterations. Mechanism: `DIAGRESUM` converges to the *float-face* operator (it rounds the faces and
resums the diagonal), the exact form converges to the true one. This is the bitwise-vs-`eps_f64`
distinction of §0 showing up in a physical output rather than only in an identity — the first
direct measurement that defect correction dominates its own fallback on something the solver ships.

**Attained residual (the gate-3 trap: is this a shared floor?).** No. From
`PECLET_FLOW_MG_DEBUG=2` through `mg_trace_parse.py`:

- float: floor 1.115e-08 at it 14 → **final 8.657e-04, rebound ×7.76e+04**; Ng=96 floor 2.429e-08
  at it 25 → final 3.816e-03, **rebound ×1.57e+05**. The plateau-then-rebound eps_f32 signature.
- exact: **rebound ×1 on every solve**, monotone, stopping at 13–28 its (finals 2.4e-09…9.8e-09),
  far under the 300 cap, having crossed rtol. No plateau.

Three independent reasons this is not the collocated cold-start pore-pocket floor returning a
false GO: (i) the four columns do **not** agree — float is 24/33/CAPPED against 14/14/28, so the
signal is float-vs-rest, not agreement; (ii) the attained residual sits at rtol with rebound ×1,
which is what the trap asks to be shown; (iii) EXACT and DIAGRESUM agree on iterations yet
separate **65×** on divergence while EXACT reproduces full double exactly — a shared floor cannot
produce a 65× separation between two columns while one of them matches a third to every digit.

**Warm leg** (gate 3, second trap — attribute a cap to precision only if the warm leg caps).
`case_contrast` already marches 4 steps and its per-solve counts run *against* a cold-start
reading: at Ng=96 float is `[45, 300, 300, 300]` — the **cold** solve converges in 45 its and the
**warm** ones cap — while exact is `[21, 25, 27, 28]`, stable across the march. Ng=48 is the same
shape (float `[13, 23, 24, 24]`, exact `[13, 13, 14, 14]`). So the float failure *appears as the
state warms*, the opposite of a cold-start artifact, and the exact column is the march-stable one.
The dedicated long-march leg (16 steps, cold vs warm reported separately) was written
(`warm_ladder.py`) but **not run — the session's batteries were interrupted**. It is not needed to
read the result above, because the 4-step data already contains a cold/warm split and it points
the same way; run it if a stronger statement is ever wanted.

**Gate 4 — MPI.** **PARTIAL — not a pass, not a failure.** The gate-off battery (`tests/kokkos_mpi`, 60 ctests on
nvidia-cuda, np 1/2/4) reached **47/60 with zero failures** and was interrupted at test 48
(`vof_twophase_mpi_np4`); the gate-**on** leg was not started. `mpirun` env forwarding was verified
first (`PECLET_FLOW_EXACT_RESIDUAL=1 mpirun -np 1 env` shows the variable), so the gate-on leg will
be meaningful when it runs. **Gate 4 is therefore still open and P1 must not be default-flipped
until it closes.** What can be said structurally: with the gate off the change is a branch not
taken, and the 47 green legs are consistent with the byte-identity gate 2 measured directly; with
the gate on the box form reads `x` and the openness and writes `y` with no aliasing and no
same-colour dependence, which is the same argument that makes `applyCutcellOpBox` bit-identical to
the blocking form — but that is an argument, not a measurement, and it is the measurement gate 4
asks for.

**Gate 5 — perf. This contradicts the plan's prediction and is written up as a handoff below.**
At matched iteration counts (`case_cost`, rtol 1e-6 so neither caps, 3 warm-up + 10 timed steps,
three interleaved off/on repeats):

| Ng | ms/step gate off | ms/step gate on | Δ | GPU MiB off / on |
|---|---|---|---|---|
| 64 | 31.50 | 31.57 | **+0.2 %** | 732 / 732 |
| 96 | 84.90 | 85.23 | **+0.4 %** | 1270 / 1270 |
| 128 | 171.67 | 171.83 | **+0.1 %** | 2532 / 2532 |

Memory identical to the byte — the 0 B/cell claim is confirmed directly. But per *matvec*
(isolated micro-benchmark, 20 warm-up + 200 timed applies on a sphere-packing openness):

| N | bands | exact | ρ_x = c_exact/c_band |
|---|---|---|---|
| 64 | 0.0123 ms | 0.0144 ms | **1.17** |
| 96 | 0.0328 ms | 0.0430 ms | **1.31** |
| 128 | 0.0932 ms | 0.0993 ms | **1.07** |

The plan predicted **≤ 0** ("24 B/cell read instead of 28"). Measured **+7 % to +31 %** on the
kernel. The byte count is right and the inference from it is wrong: the band form is 7 perfectly
coalesced loads all at index `i`; the flux form is 6 loads at `i` **and** `i±sx/sy/sz`, touching
more distinct cache lines than the unique-byte accounting suggests, plus 6 subtractions of extra
arithmetic against 7 FMAs. At step level it disappears into +0.1…+0.4 % because the matvec is one
kernel per PCG iteration against a whole V-cycle — and where it matters the change is a large
*win*: Ng=96 goes 0.40 → 0.10 s/step because 28 valid iterations replace 300 burnt ones.

**This number resolves M2's `Depends on P1` without a handoff.** Fable's decision rule: `ρ_x ≤ 1.5`
⇒ the Richardson-vs-BiCGStab choice is decided by outer-iteration counts alone. Measured
`ρ_x = 1.07…1.31`, so the **`ρ_x ≤ 1.5` branch holds** and the `ρ_x > 2` handoff branch does not
fire. M2 proceeds on iteration counts.

**Gate 6 — contrast / varRho.** **PARTIAL.** `vardensity_projection` (the varRho hydrostatic acid test + uniform-rho reduction)
passes inside the 26/26 `tests/kokkos` run with the gate off. The V2a `∂P/∂z` at ratio 1000 and the
`precision_ab --cases hydro` ratio ladder with the gate **on** were not run (interrupted). Note the
ρ-folded path is structurally the one most likely to be fine: `buildRhoCoeff` hands the full
coefficient `c_f = open_f·rho0/rho_f` to `setOpenness` *as* the openness, so `Level::ox/oy/oz`
already holds exactly what `buildCutcellOp` consumed, and the exact apply reads the same array
(verified: the only writers of `lv.ox/oy/oz` are the allocation, the `setOpenness` deep-copy,
`fillOpenness` and `applyBoundaryOpenness` — nothing mutates them during a solve).

**Two corrections to the plan's premises, both verified against source.**

1. **`matvecOverlap` is not "the single choke point for all three drivers"**
   (`VOF_NEXT_SESSION.md` Item 1, correction 1). `solveBiCGStab` has its own inline matvec
   (`mac_cutcell_mg.hpp:995` and `:1003`) because the gp overlay needs a g=2 staging block; it
   does not route through `matvecOverlap`. P1 as specified therefore covers `solvePCG` and the
   flexible PCG only. Those two `applyCutcellOp` sites are left untouched here and belong with
   **P2**, which owns the gp overlay that is the reason BiCGStab has a separate matvec at all.
2. **This plan's own §5 double-control build recipe was wrong and failed silently — fixed in
   this commit.** `cmake -DPECLET_FLOW_MREAL_DOUBLE=ON` sets an `UNINITIALIZED` cache variable
   that nothing reads and builds **float**; the symbol appears nowhere in flow's `CMakeLists.txt`,
   `CMakePresets.json` or `cmake/`, because it is a *compile define*, not a CMake option. The
   first "double" ladder column here came back byte-identical to the float one because of it —
   a null result that reads like a finding. The working form is
   `-DCMAKE_CXX_FLAGS=-DPECLET_FLOW_MREAL_DOUBLE` (`flow/doc/vof_workorders_v34.md:256` has it
   right, and is how WO-M actually built its control). Corrected at §5 below. **Attribution: the
   bad recipe was only ever in this file (§5:707)** — `suite/CLAUDE.md` never mentioned
   `MREAL_DOUBLE` at all and `flow/CLAUDE.md` mentions it only in prose, so there is nothing to
   fix in either.

### A0 — core AMR audit — **DONE 2026-09-01/02, COMPLIANT, no code change**

Source audit only (`core` at the umbrella pointer, 2026-09-01); nothing built or run, because
nothing needed changing. Four questions, four answers.

1. **Is `applyFv` flux form?** **Yes, and already bitwise.** `applyFv` (`fv_op.hpp:114`) delegates
   per row to `fvApplyRow` (`face_csr.hpp:120-126`):
   ```cpp
   const double ui = u(i); double acc = 0.0;
   for (Index k = op.start(i); k < op.start(i + 1); ++k)
     acc += op.coef(k) * (u(op.nbr(k)) - ui);
   return op.c0 * ui + op.cD * (op.invVol(i) * (acc - op.bcDiag(i) * ui));
   ```
   That is `Σ_f w_f (u_j − u_i)` exactly as §0 requires — the diagonal is never formed, so it
   cannot disagree with the faces. On the periodic/pure-Neumann path (`bcDiag = 0`, `c0 = 0`,
   `cD = 1`) a constant vector gives every difference identically 0 ⇒ `acc = 0` ⇒ `L·1 = 0`
   **bitwise**, with no storage change and nothing to fix. Where `bcDiag ≠ 0` the operator is
   non-singular and `L·1 = −invVol·bcDiag ≠ 0` is correct, so the identity holds exactly where it
   is supposed to. `faceW / bcDiag / invVol` are `View<double>` throughout.
2. **Does the default pressure driver use the exact operator?** Yes. `presPCG_ = true`
   (`flow.hpp:2042`) and the PCG matvec is `applyFv` (`pcg.hpp:219`) — the exact double operator,
   with the MG as preconditioner. **This path is defect correction by construction.**
3. **Does the `setPressurePCG(false)` plain-MG path recompute the fine residual exactly?** Yes —
   `residualFv` (same `fvApplyRow`) at `multigrid.hpp:196` and `:234`, and
   `distributed_flow_mg.hpp:158`. So that path is defect correction by construction too. (Context
   worth carrying: `flow.hpp:1255-1270` records that the un-deflated V-cycle *stalls* at
   `|mean|·√V_fluid` because the aperture RHS is incompatible by a fluid-mean component — the PCG's
   per-iteration fluid-range projection is what makes it valid. That is a compatibility/deflation
   issue, not a precision one, and this campaign does not touch it.)
4. **Is `DistributedPoissonMG::vcycle` production or test-only?** **Test-only — and the name in §1
   does not exist.** `distributed_poisson.hpp` declares `DistributedPoisson` and
   `DistributedMultigrid` (`:142`), the latter a *host* `std::vector<double>` implementation whose
   `vcycle` is reached only from `tests/test_amr_distributed_mg_mpi.cpp` (plus a reference mention
   in `distributed_view.hpp:34`). The **production** distributed pressure MG is a different class,
   `DistributedFlowMultigrid<3, Bits> presMGD_` (`flow.hpp:2126`, `distributed_flow_mg.hpp`), and
   it is used as the *preconditioner* inside `pcg_.solve` (`flow.hpp:1330`). Compliant either way.

**Verdict: core AMR pressure needs no P1-equivalent change.** §1's "compliant — written
double-first" is confirmed, and stronger than it claimed: the operator is not merely double, it is
already in the flux form that makes the identity bitwise. A0's gates (AMR ctests, `amr-testing`
recipes) were not run because no code changed. **§1 correction:** the row should read
`DistributedMultigrid` (test-only) and name `DistributedFlowMultigrid` as the production
distributed path.

### X — audits, record only — **DONE 2026-09-01/02, all three compliant**

Source audit only; nothing built or run.

**voro mesh-optimizer CG — compliant.** The Gauss-Newton Hessian is assembled host-side as
`std::vector<double> Hval, Hdiag` (`mesh_optimizer.hpp:359-360`), the CG matvec is the double CSR
`s += Hval[k]·v[Hcol[k]]` (`:379`), and the CG driver is a plain double CG on that exact operator
(`:441-460`). `GraphAMG` is reached only through `precond` (`amg.apply(r, z)`, `:420`, alongside
the Jacobi and coloured-GS alternatives) — **preconditioner only**, never the matvec, exactly as
§1 recorded. The SDF wall term is double as well: `wallG` is `DV = View<double*>` (`:711`) and the
wall-facet Jacobian `J_wallᵀ` (`:187-191`) is accumulated from the published double facet areas.
Note the matvec is in *stored* form (it sums all CSR entries including the diagonal) rather than
flux form — correct here, because this operator carries **no exact discrete identity**: it is the
Hessian of a volume energy, not a singular Laplacian with a constant null space, so §0's flux-form
corollary does not apply. The precision rule is satisfied end to end.

**pnm — out of scope, confirmed.** `extract_network_flow` (`pore_extraction.hpp:860-905`) has no
linear solve; it forms fluxes from a given velocity field, all double.

**`flow/src/mac_mg.hpp` (FlowReference const-coeff periodic MG) — compliant on precision, with one
honest caveat §1 did not state.** `SField = Kokkos::View<double*>` (`mac_stencils.hpp:21`), and the
operator is matrix-free — there are no stored coefficients at all, so there is no float storage to
correct and it is defect correction by construction. **But its apply is written in stored-diagonal
form, not flux form**: `r(i) = f(i) − (6.0·phi(i) − s)/h2` (`mac_mg.hpp:141`), with
`s = Σ_6 phi(nbr)`. For a constant field `6.0·φ − Σφ` is **not** bitwise zero — the running sum
`((((φ+φ)+φ)+φ)+φ)+φ` rounds at the 3φ and 5φ partials — so `A·1 = 0` holds here only to
`eps_f64`, not bitwise. That is six orders below the eps_f32 defect this campaign exists to remove
and it is a *reference* path, not production, so **no change is proposed**; recording it because
§1's "compliant" row could otherwise be read as "bitwise", which P1 has now made a meaningful
distinction. Making it bitwise is a one-line rewrite to
`((phi(i)−phi(i+sx)) + (phi(i)−phi(i−sx)) + …)/h2` if anyone ever wants it.

### Handoff → Fable: P1's matvec is 7–31 % *slower* per kernel, not ≤ 0 — does P3 survive its own perf gate?

**Trigger 3** (a measurement contradicts a prediction in this plan). P1 itself passes every gate;
this is about what P1's perf number does to **P3**, which is gated on it.

**What was measured.** nvidia-cuda, one RTX 5080, `OMP_NUM_THREADS=8 OMP_PROC_BIND=false`,
worktree `flow-dc` at `e9da3e5` (= flow main `72278d2` + P1 only).

*Isolated matvec* — 20 warm-up + 200 timed applies on a jittered 8-sphere packing openness,
`applyCutcellOp` (float bands) vs `applyCutcellOpExact`, same field, same block:

| N | bands | exact | `ρ_x = c_exact / c_band` |
|---|---|---|---|
| 64 | 0.0123 ms | 0.0144 ms | **1.17** |
| 96 | 0.0328 ms | 0.0430 ms | **1.31** |
| 128 | 0.0932 ms | 0.0993 ms | **1.07** |

*Step level* — `precision_ab.py --cases cost`, rtol 1e-6 so neither variant caps, 3 warm-up + 10
timed steps, three interleaved off/on repeats: **+0.2 % / +0.4 % / +0.1 %** at Ng = 64 / 96 / 128,
GPU memory identical to the byte (732 / 1270 / 2532 MiB both ways — the 0 B/cell claim confirmed
directly).

**What was predicted.** P1 gate 5: "Expected ≤ 0 (24 B/cell read instead of 28)."

**Believed mechanism.** The byte count is right; the inference from it is not. `applyCutcellOp`
issues **7 perfectly coalesced loads, all at index `i`** — seven streams, each one aligned access
per thread. `applyCutcellOpExact` issues **6 loads at `i` and `i±sx / i±sy / i±sz`**: the `±sy`
and `±sz` offsets land on different cache lines from the thread's own `i`, so the kernel touches
more distinct lines than the 24-vs-28 B unique-byte accounting predicts, and adds 6 subtractions
against 7 FMAs. On a kernel that was already line-limited rather than unique-byte-limited, fewer
bytes does not mean fewer transactions.

**What this does NOT threaten.** P1 on its own terms. +0.1…+0.4 % of a step is a pass, and where
the change is load-bearing it is a large win, not a cost: Ng=96 goes **0.40 → 0.10 s/step**
because 28 valid iterations replace 300 burnt ones. The matvec is one kernel per PCG iteration
against an entire V-cycle, which is why a +31 % kernel is +0.4 % of a step.

**What it does threaten: P3.** P3's stated condition is "only worth doing if P1's perf gate showed
the matvec is bandwidth-bound and the smoother dominates the V-cycle on level 0". The first half
is now measured false in the direction P3 needs. P3 would move this access-pattern penalty **into
the smoother**, which runs (pre + post) several times per V-cycle and once per level-0 visit,
rather than once per PCG iteration — so a per-sweep `ρ` of the same order would be multiplied by
the sweep count instead of divided by the V-cycle cost.

**Why it is not simply a no.** The smoother case is *not* the matvec case, and my number does not
settle it: P3 does not trade 7 bands for 3 openness arrays, it **drops the 7 bands entirely**
(−28 B/cell of allocation, a real memory win the matvec change does not have) and forms
`ac = Σ t_f` on the fly, which also yields the exact double diagonal for free. So the access mix
differs and the sign is genuinely open.

**Decision needed.** One of:
1. **Measure then decide** (my recommendation, and cheap): a `cutcellSmoothColorExact` micro-
   benchmark gated on **ms per V-cycle**, not ms per matvec — the peer session's point, and the
   right unit — plus the −28 B/cell against the measured per-sweep penalty. If the V-cycle gets
   slower, stop and record it; P3 was always marked optional and perf-gated.
2. **Drop P3 now** on the strength of `ρ_x > 1` and bank the campaign's remaining rungs.
3. Something the above misses about why the smoother would behave differently.

**Already resolved, for the record: this number does *not* block M2.** M2's `Depends on P1` rule
is `ρ_x ≤ 1.5` ⇒ decide Richardson-vs-BiCGStab on outer-iteration counts alone; `ρ_x > 2` ⇒
handoff. Measured `ρ_x = 1.07…1.31`, so the `≤ 1.5` branch holds and M2 proceeds without a ruling.
Writing the decision rule into the design did exactly what §3 intended it to.


### Handoff → Fable: P2 and A1 are the SAME change, in a shared `core` header — and widening the storage as scoped would buy nothing

**Triggers 4** (a design fork with more than one defensible option and no measurement that decides
it) **and 2** (the change alters a *double-build* result). Found by source inspection while
starting P2; nothing was built or changed. **No P2/A1 code was written — the rung is stopped here.**

**What §1 says.** The two gp overlays are "computed in double (`gpFillRow`, sdf `S` double), stored
float", and the fix is `rescale, wm_n1, wm_n2 → double` — a switch-the-matvec change, P2 in flow
and A1 in core, listed as independent rungs in different repos.

**What the source says.** The matrix weights are **computed in float, not merely stored in float**,
and the computation is one shared template that all three overlays call.

`peclet::core::scheme::gpFillRow` (`core/include/peclet/core/scheme/ghost_closure.hpp:169-232`):
```cpp
struct GpFace { int8_t state; float th, wbc, w1, w2, D; };              // :104-107
PECLET_CORE_GP_HD void gpOrderWeights(int8_t st, float th, int order,
                                      float& wbc, float& w1, float& w2, float& D);  // :84-85
  float wbcM[6], w1M[6], w2M[6];                                        // :197
  float Dm; gpOrderWeights(f.state, f.th, matrixOrder, wbcM[k], w1M[k], w2M[k], Dm);  // :206-207
  if (Dm < rho) rho = Dm;                                               // :208
  ov.rescale(slot)      = rho;                                          // :215
  ov.wm_n1(slot*6 + k)  = w1M[k];                                       // :228
```
So `th` is float, `gpOrderWeights` takes and returns floats, the matrix weights live in float
locals, and the row rescale `rho` is the min of float `Dm`s. Only the *upstream geometry sampling*
is double. **Widening `View<float*> wm_n1/wm_n2` to `View<double*>`, exactly as P2 and A1 specify,
would store an already-float-rounded value in a double and change nothing.** The scoped change does
not achieve its stated goal.

**Consequences that make this a fork rather than a bigger edit.**

1. **P2 and A1 become one change, in `core`, not two changes in two repos.** `ghost_closure.hpp`
   has three consumers: `flow/src/ghost_projection.hpp` (P2), `core/.../amr/ghost_projection.hpp`
   and `core/.../amr/ghost_projection_sampled.hpp` (A1). Fixing the shared closure fixes all three
   at once; fixing them separately is not possible without duplicating the closure.
2. **It alters double-build results — trigger 2.** `th`/`w1M`/`Dm` are hard-typed `float`, *not*
   `MReal`, so a `-DCMAKE_CXX_FLAGS=-DPECLET_FLOW_MREAL_DOUBLE` build carries the same float
   closure. Widening therefore moves the answers of the double build too. That is the campaign's
   *intent* here (the current weights are float-rounded approximations of the exact closure), but
   it means **the gate cannot be byte-identity-on-a-double-build**, and the gp ctests need a
   deliberate re-baseline rather than an unchanged-to-tolerance check. P2's stated gates
   ("gate-off byte-identical; the gp order-2 Z&H tests unchanged to tolerance") are written for the
   storage-only change and do not fit this one.
3. **`rescale` does not need widening at all — settled from source, this is the Fable question P2
   reserved.** `ov.rescale` is read in exactly two places: `gpApplyDelta`
   (`flow/src/ghost_projection.hpp:268`, `y(r) = rho*(y(r) + delta)`) and `gpDivergDelta` (`:322`,
   `d(r) = rescale(s)*dd`) — the **same view, same slot, applied multiplicatively to the whole row
   of A and of b**. So the solved system is `D A x = D b` with one identical stored `D`, whose fixed
   point is that of `A x = b` for any `D ≠ 0` regardless of its precision. Widening `rescale`
   changes rounding and cannot change the answer. **Drop it from P2 and A1.** (`rho` is
   `min(1, min_f D_f) > 0`, and rows with no coupling are zeroed explicitly via `coupled`, so the
   `D ≠ 0` proviso holds.)
4. **`wm_n1/wm_n2` already annihilate constants bitwise.** `gpApplyDelta:263-266` applies
   `sgn*w1*(X(a,mn-1) − X(a,mn))` — difference form already, so `A·1 = 0` for the overlay part
   holds whatever the weights' precision. What float costs here is therefore *not* the identity but
   the operator itself: the Krylov method converges to a float-rounded gp operator. P1 measured
   exactly what that costs on the pressure side — DIAGRESUM matched double on iterations yet sat
   ~65× worse on `max|div(open·u)|`, because it converged to the float-face operator. That is the
   real argument for doing this, and it is a *different* argument from the one §1 gives.

**The fork — three defensible options, no measurement between them.**

- **(a) Widen the shared closure.** `GpFace::th/wbc/w1/w2/D`, `gpOrderWeights`' signature and
  `w1M/w2M/wbcM/Dm` → `double` in `ghost_closure.hpp`. One edit, fixes all three overlays. Cost:
  a `core` header change with a blast radius across flow gp + AMR gp + AMR gp-sampled, and a
  re-baseline of every gp ctest in both repos including the double builds.
- **(b) A gated double overload.** Keep `gpOrderWeights` float, add a `double` twin used only when
  the exact-residual gate is on. Keeps gate-off byte-identical *by construction in both builds* and
  makes the re-baseline opt-in, at the cost of two copies of a closure that must not drift — the
  exact hazard §5 warns about.
- **(c) Template the closure on its real type** (`template <class R> gpOrderWeights(…)`), overlays
  instantiate at `float` today and `double` under the gate. No duplication, but it touches every
  call site's deduction and the `PECLET_CORE_GP_HD` device path.

**My recommendation: (c), falling back to (a).** (c) has (b)'s gate-off safety without duplicating
the closure, and the campaign has already shown that a single exact operator beats a
carefully-maintained approximate twin. But this is a `core`-wide typing decision affecting a second
repo and two other rungs' scope, so it is yours, not mine.

**Decision needed.** Which of (a)/(b)/(c); whether P2 and A1 merge into one core-first rung with
flow and AMR as consumers; and what replaces P2's byte-identity gate given (2) — presumably
"gate-off byte-identical in *both* builds, gate-on re-baselined with the gp order-2 Z&H order and
the mode-9 throat-safety preserved".

**What is NOT blocked by this** and is still open [Opus] work: P1's gate 4 (MPI, 47/60 green and
interrupted) and gate 6; and P2's **star-overlay half**, which is independent of all of the above —
`StarOverlay::a` (`star_elimination.hpp:37`) is a genuine float *store* of a value built from the
double openness (`:75-80`), so widening it does what §1 says it does. One further note for whoever
takes it: `starApplyDelta` (`:115-133`) computes `phibar = Σa·x / Σa` and adds `a_k(x_k − phibar)`,
which is **not** bitwise-annihilating for a constant even in double; the algebraically identical
`(a_k/D)·Σ_j a_j (x_k − x_j)` is, and is the P1 trick applied to the star row.


### P2 (star half) — exact star apertures + flux-form delta — **DONE 2026-09-02**, flow `7fb80e0`

The half of P2 independent of the ghost-closure ruling handed off above. §1 is right about this
one: `StarOverlay::a` really was a float **store** of a double-built value
(`star_elimination.hpp:75-87`, `const double op` → `(float)op`), unlike the gp weights.

**Change**, all behind `PECLET_FLOW_EXACT_RESIDUAL`, which moved to `mac_cutcell.hpp` so the
overlay and `CutcellMG` share **one** definition — the star delta is part of the same level-0
operator, so "the matvec is exact" has to cover it or the composed operator is still the float one.

- `StarOverlay::a`: `View<float*>` → `View<double*>`; the build keeps the double aperture.
- `starAval()` reads it back through `(float)` when the gate is OFF, so the default path sees
  bitwise the value it always saw. (The widening is otherwise unconditional — a runtime gate
  cannot change a view's type.)
- `starApplyDelta` gains a **flux form** under the gate:
  `a_k (x_k − phibar) = (a_k/D)·Σ_j a_j (x_k − x_j)` — algebraically identical, but every term is
  a coefficient times a *difference*, so a constant `x` is annihilated **bitwise**. The `phibar`
  form is not: `phibar = Σ(a·x)/Σa` does not return `x` exactly for constant `x` **even in
  double** (the two sums round independently, then divide). So the star delta was leaking a row
  contribution into `A·1` that P1's exact 7-point apply could not cancel. **The level-0 operator
  is the 7-point part PLUS this delta, and `A·1 = 0` needs both halves exact** — this is the
  composition P1's §2 note ("P1 composes with it unchanged") left open.
- `starCorrectFaces` reads the aperture at the same precision, so the reconstruction matches the
  operator actually solved. Its `phibar` *is* the wanted quantity (the eliminated cell's value),
  not an operator row, so there is no difference form to take there.

**GATE CORRECTION — "gate-off byte-identical" cannot be measured on this path.** Saying so rather
than tuning it (§5). `starApplyDelta` uses `Kokkos::atomic_add`, so the mode-B path is **not
bit-reproducible against itself** on CUDA: three runs of one binary give three different states.
That is pre-existing — the atomics predate this rung — but it makes P2's stated gate unmeasurable
here. Measured (N=32, 6 steps, mode B via `set_fluid_only_constraint(2)` on a jittered 8-sphere
packing; max abs over u/v/w/p; scale `max|state| = 2.127e-01`):

| comparison | max abs diff |
|---|---|
| REF (pre-change, flow `e9da3e5`) run-to-run spread | 1.110e-16 |
| NEW gate-off run-to-run spread | 1.110e-16 |
| **NEW gate-off vs REF** | **8.327e-17 best pairing / 1.110e-16 worst** |
| NEW gate-ON vs REF | 2.239e-09 (rel 1.1e-08 — the eps_f32 scale) |

So gate-off is **indistinguishable from pre-change within the path's own noise floor (~2 ulp)**,
which is the strongest statement this path admits, and the gate-on effect sits **7 orders above
that noise**. Iterations `[13,13,13,13,13,13]`, `max_open_divergence` and `umean` identical to
every printed digit across all three. **The corrected gate for any future work on this path:**
*gate-off matches the reference within the path's measured run-to-run spread, and iterations /
divergence / mean velocity match exactly* — not byte-identity, which is not achievable here.

**Other gates.** Staggered regression **+0.00 %** on all 13 points; collocated gauge-exact
regression **+0.00 %** on all points; **26/26** `tests/kokkos` ctests. Those also confirm the
`exactResidual()` move is inert. Note the two regressions do **not** exercise the star path at all
— mode B is only reachable via `set_fluid_only_constraint(2)` (single-rank periodic collocated,
`flow_ibm.hpp:1414`), which no baseline sets; that is why the dedicated probe above exists, and it
is worth knowing that **the shipped regression suite covers none of mode B**.

**Not done:** the gp/BiCGStab half of P2 (handed off above), and P2's wider mode-B batteries
(`tests/study/collocated_longmarch.py KIND=fluidonly2`) beyond this probe.

## 5. Working practices (inherited; not optional)

- Isolated `git worktree` per session carrying only your own diff; three live sessions share
  these checkouts (three mis-attributed commits last campaign). `git diff --cached --stat` before
  every commit; never `git add -A`; submodule commit → push → umbrella pointer LAST.
- `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` for every test battery (the `nvidia-cuda` prefix has an
  OpenMP host backend; an unbounded pool on the 48-core host is an hour-long trap).
- **A capped solve is invalid, not degraded.** Report iterations *and* attained residual.
- **Judge an achieved residual against the run's own state history, not a cold-start probe.** A cold
  floor 1000× above rtol can coexist with a healthy production march on the same operator (§0).
  Probe cold *and* warm before attributing a floor to anything you changed.
- **Agreement across configurations is not evidence of convergence when they can share a floor.**
  Three R=48 runs agreed to nine digits while all were starved; rate-based stationarity detectors
  freeze into false convergence on a cold-start cap. An A/B that returns "identical" is suspect
  until one leg is shown to be off the floor.
- `rtol = max(1e-8, C·eps·0.18·N²·Δρ/ρ)` is a lower bound on what to demand, not a prediction;
  above ~384³ measure the attainable residual.
- Any multi-rank run on a `MREAL_DOUBLE` build: run the `kokkos_mpi` battery first.
- The np=4 `MPI_ERR_TRUNCATE` race is load-triggered: re-run on an idle machine before believing
  it; never three heavy batteries at once.
- Never tune a gate to pass. If a gate measures the wrong quantity, say so and fix the gate — five
  did last campaign and each time saying so improved the plan.
- Build recipes: `suite/CLAUDE.md` per project (`flow`: `cmake -S . -B build
  -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"`; MPI ctests: `tests/kokkos_mpi` with
  `-DPECLET_FLOW_MPI=ON`; the `host-openmp` prefix for the host gate).
- **The double control is a COMPILE DEFINE, not a CMake option** (corrected 2026-09-01 by P1,
  which lost a ladder column to it). Use
  `cmake -S . -B build_double -DCMAKE_PREFIX_PATH=… -DCMAKE_CXX_FLAGS=-DPECLET_FLOW_MREAL_DOUBLE`.
  This bullet previously said `-DPECLET_FLOW_MREAL_DOUBLE=ON`, which **silently builds float**:
  the symbol appears nowhere in flow's `CMakeLists.txt`, `CMakePresets.json` or `cmake/`, so a
  `-D…=ON` on the cmake line only creates an uninitialized cache entry that nothing reads. The
  failure is silent and looks like a *result* — P1's first "double" column came back byte-identical
  to its float column. Verify a double build before trusting it (`grep CMAKE_CXX_FLAGS
  build_double/CMakeCache.txt`, or check that the RCP ladder at Ng=96 does not cap).
