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
| flow collocated **ghost-projection** overlay | `flow/src/ghost_projection.hpp` — `GpOverlay` :81-101, `gpApplyDelta` :254-263 | **float** `rescale, wm_n1, wm_n2` inside the BiCGStab matvec | computed in double (`gpFillRow`, sdf `S` double), stored float; n = cut cells only | yes (BiCGStab) | **P2** |
| flow mode-B **star** overlay | `flow/src/star_elimination.hpp` — `StarOverlay::a` :37, :87, :118-165 | **float** `a[6]` inside the PCG matvec | trivially: `a` is the openness `ox/oy/oz` masked by the sdf sign (:75-80) — matrix-free from resident doubles | yes (PCG) | **P2** |
| flow **momentum** (IBM RB-GS) | `flow/src/flow_ibm.hpp` — `smoothComp` :3885, `velSweepLoop` :3855, `buildAdvStencil` :3709, `buildAdvStencilVar` :3746, `addDragDiagonal` :5726 | float bands `C[c].AC..AT` (`FV = View<MReal*>`, :63); the **sweep is the solver**; stop criterion is the increment `du`, never a residual | partly: `mu_, rho_/dt_` scalars, adv velocities double, drag β double, face props double; **but the IBM overlay `IbmOverlay::K_val/M_val/X_val/Nbc_val/R_val/D_rescale` is float and computed in float** (`cut_cell_ibm.hpp:77-79`, :150-160 `float R`, `float D_axis`) | **no** | **M1, M2** |
| flow `VelocityMG` (domain-BC vel-MG path, single-rank) | `flow/src/mac_velocity_mg.hpp` — `FPV` bands all levels; `vmg_.solve` :3940 used as the solver | float | n/a — becomes a preconditioner under M2 | no | **M2** (absorbed) |
| flow const-coeff periodic MG (FlowReference) | `flow/src/mac_mg.hpp` :101-141 | matrix-free double `(6φ − Σ)/h²` | n/a | plain MG, but the residual is exact ⇒ already defect correction | compliant |
| flow bottom AMG (agglomerated) | `mac_cutcell_mg.hpp` :1411 (diag re-sum precedent) → `core/.../solver/graph_amg*.hpp` | double CSR | inside the preconditioner | — | compliant |
| **core AMR pressure** (`AmrFlow`) | `core/include/peclet/core/amr/fv_op.hpp` (`FvOp` faceW/bcDiag/invVol all double, `applyFv` :114), `pcg.hpp` (double PCG, MG precond), `flow.hpp` (`presPCG_ = true` :2042) | double | yes | yes | **A0** audit only: verify `applyFv` is flux-form; confirm the `setPressurePCG(false)` plain-MG path recomputes the fine residual exactly (then it is defect correction by construction) |
| core AMR **ghost-projection** overlay | `core/.../amr/ghost_projection.hpp` :364-366, :299-307; `ghost_projection_sampled.hpp` :1142-1144 | **float** `rescale, wm_n1, wm_n2` inside the matvec | computed in double, stored float | yes | **A1** (same pattern as P2) |
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
  -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"`; add `-DPECLET_FLOW_MREAL_DOUBLE=ON`
  for the double control; MPI ctests: `tests/kokkos_mpi` with `-DPECLET_FLOW_MPI=ON`; the
  `host-openmp` prefix for the host gate).
