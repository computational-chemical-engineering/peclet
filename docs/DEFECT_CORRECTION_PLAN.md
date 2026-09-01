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
Galilean invariance `(A − idiag·I)·1 = 0` for momentum): **write the exact matvec in flux
(difference) form**, `y_i = Σ_f t_f (x_i − x_nbr)`, so the identity holds **bitwise** regardless of
coefficient precision — the diagonal is never formed, so it can never disagree with the faces.

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
  must be evaluated in double.

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

**Order**: P1 → (P2, A0, A1 in any order) → M1 design (Fable) → M1 → M2 design (Fable) → M2 → P3
(if perf says so) → D1 (Fable) → X. P1 is the discriminating experiment for the whole campaign;
if its ladder does **not** reproduce the double column, stop and hand off — the premise is wrong
somewhere and the rest should not be built on it.

**Ownership**: Opus executes every rung marked [Opus]; Fable owns the design decisions in M1, M2,
the `rescale` semantics in P2, and D1. Opus does not start M1/M2 implementation until the Fable
design section for it exists in §4 of this file.

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

*(empty — the executing session appends here: one entry per rung with commit hash, gate
results as numbers, and any handoff sections.)*

## 5. Working practices (inherited; not optional)

- Isolated `git worktree` per session carrying only your own diff; three live sessions share
  these checkouts (three mis-attributed commits last campaign). `git diff --cached --stat` before
  every commit; never `git add -A`; submodule commit → push → umbrella pointer LAST.
- `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` for every test battery (the `nvidia-cuda` prefix has an
  OpenMP host backend; an unbounded pool on the 48-core host is an hour-long trap).
- **A capped solve is invalid, not degraded.** Report iterations *and* attained residual.
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
