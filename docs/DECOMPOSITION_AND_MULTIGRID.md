# Decomposition, load balance, and the pressure multigrid

How the MPI domain decomposition and the geometric multigrid constrain each other in `flow`, what has
been measured, and what is still open. Written 2026-08-11 as the starting point for further work on
this interaction; the measurements are the reason to trust (or distrust) the design rules that follow.

Companion reading: [`ARCHITECTURE.md`](ARCHITECTURE.md) for the layering, `core/CLAUDE.md` for
`BlockDecomposer`, `flow/CLAUDE.md` for the solver-side options.

---

## 1. The mechanism

### 1.1 Coarsening is per axis, and it is about factors of two

`flow/src/mac_cutcell_mg.hpp` halves an axis while

```cpp
can(d) = (d % 2 == 0) && (d / 2 >= 2)
```

applied to **each axis independently**. Three consequences, none of them obvious from the outside:

- **Semi-coarsening is automatic.** The long axis keeps halving after the short ones stop; the level
  table shows `ratio(2,1,1)`. Nothing needs enabling, and the depth is *not* set by the direction
  with the fewest cells.
- **An axis's usable depth is its number of factors of two**, not its size. 503 cells coarsen zero
  times; 512 cells coarsen eight.
- **An odd dimension never coarsens at all**, so every level carries that axis at full resolution and
  no coarse grid ever sees an error mode along it.

The hierarchy stops at `nLevels` (`set_pressure_multigrid(on, levels)`) or when no axis can coarsen.

### 1.2 Under MPI, the per-rank block sets the depth

A second gate applies (`initMpi`): an axis coarsens only if **every rank's block origin and size are
even on it** (`evenBlocks`). Coarse levels are the fine decomposition `coarsened()` in place, which is
what keeps restrict/prolong purely local — coarse-local `i` ↔ fine-local `2i`, no added communication.
An independent ORB per level would not nest, and transfers would read out of bounds.

So **the achievable depth is a property of the per-rank block, not the global grid.** Under weak
scaling the blocks stay roughly constant, so the coarsest *global* grid grows with the rank count no
matter how many levels are requested. That is a structural limit of a block-local geometric
hierarchy, and the reason an agglomerated bottom solve exists.

### 1.3 Two ways to build a partition that survives coarsening

| mode | how | selected by |
|---|---|---|
| **aligned ORB** (default) | choose the split on the fine grid, then snap it to a multiple of `align[k] = 2^halvings`, capped at 16 | `set_decomposition_levels(0)` |
| **coarse-first** | decompose the grid coarsened `L-1` times, then `refined()` the partition upward | `set_decomposition_levels(L>=2)` |

Coarse-first makes blocks multiples of the coarsening factor *by construction*, so the hierarchy nests
for the full requested depth. It also balances better: snapping picks a split and then rounds it, and
rounding can turn a balanced split into an unbalanced one, whereas on the coarse grid one cell *is*
the quantum.

Both routes go through one factory, `CutcellMG::decomposition(numBlocks, gnx, gny, gnz)`, which the
three call sites that build the level-0 partition all use — `mpi_block()`, `IbmSolver::initMpi`,
`CutcellMG::initMpi`. They must agree on the block layout, so **never build a `BlockDecomposer` for
the solver by hand.** The mode must be set before `mpi_block()` and `init_mpi()`, since both derive
from it.

Because depth and balance trade off, the factory builds each candidate depth and **measures** its
imbalance, taking the deepest within `PECLET_FLOW_DECOMP_MAX_IMBALANCE` (default 1.05). The search is
a pure function of `(ranks, grid, levels)`, so every rank reaches the same answer without
communicating — do not make it depend on anything rank-local.

---

## 2. What has been measured

Keep these; they are what makes the rules below more than taste.

### 2.1 One odd dimension costs 3.2× — with no MPI involved

Single GPU, 384×128×GNZ, everything else identical:

| GNZ | halvings | pressure iters/step | ms/step |
|---|---|---|---|
| 256 | 8 | **5.0** | 120 |
| 250 | 1 | 9.8 | 195 |
| 255 | **0** | **16.2** | **329** |

### 2.2 The channel's production grid is built the wrong way

`GNX = round(2π·GNY)`, `GNZ = round(2π/3·GNY)` gives 1508×240×503 — x halves twice, y four times, z
never. The 5-level hierarchy bottoms out at 377×15×503 = 2.8 M cells, a "coarse" grid holding 1/64 of
the fine one. Rounding to nearby nice numbers is worse: 2406×383×802 gets **two levels** and a
185 M-cell bottom. Grid dimensions must be chosen for their factors of two, not for arithmetic
convenience.

### 2.3 The rank count does not need to be a power of two

480×80×160 (30×5×10 atoms of 16³), 8 levels requested, aligned ORB:

| np | 1 | 2 | **3** | 4 | **5** | **6** | 7 | 8 | 12 | 16 | 24 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| imbalance | 1.00 | 1.00 | **1.00** | 1.14 | **1.00** | **1.00** | 1.13 | 1.14 | 1.33 | 1.33 | 1.50 |
| levels | 6 | 6 | **6** | 6 | **6** | **6** | 5 | 5 | 5 | 5 | 5 |

Odd np = 3, 5 are perfect; powers of two 4, 8, 16 are not. 30 atoms divide by 3, 5, 6 and not by 4, 7,
12. Same np=24 on a grid whose atom count fits: 480×80×160 → 1.50 and 5 levels; **768×128×256
(48×8×16 atoms) → 1.000 and 8 levels.**

### 2.4 Coarse-first, same grid, 6 levels requested

| np | 3 | 4 | 5 | 7 | 12 | 16 | 24 |
|---|---|---|---|---|---|---|---|
| aligned | 1.000 | 1.143 | 1.000 | 1.125 | 1.333 | 1.333 | 1.500 |
| **coarse-first** | 1.000 | **1.000** | 1.000 | **1.029** | **1.038** | **1.000** | **1.000** |

Equal or better everywhere at equal or better depth. On 96×48×64 at np=6 the partitions differ
substantially (aligned imbalance **2.000** vs 1.048) and the solution still matches single-rank to
3.3e-12 — the MG-PCG reduction-order floor for a different decomposition, not bit-exactness, which
only holds when the reduction order is identical.

### 2.5 Over-aligning is not free

Uncapped natural-max alignment over-constrains the ORB: 192³ at np=24 snapped a balanced 96|96 into
128|64, cascading 2:1 — **27 pressure iterations/step against 9, and 3.4× the step time** (fixed by
capping at 16, `flow 10872a7`). Any change to the alignment must be re-checked against this case.

### 2.6 Domain shape limits the rank count when a direction cannot be split

A channel's wall-normal `y` must not be decomposed (a no-slip wall plus an internal `y` boundary
decouples the halves at the centreline; the driver aborts). That leaves the ORB only the x–z plane, so
a 12H×2H×4H box is exhausted at **16 ranks** — at 32 the blocks are cube-like and the last bisection
takes `y`. Reaching 32 needs a longer box (16H), i.e. a different physics problem.

### 2.7 The coarse level decides whether a V-cycle is domain-independent

A V-cycle converges at a rate independent of the domain only if its **coarsest level is effectively
solved**. A geometric hierarchy cannot always get there — §1.1 and §1.2 both put floors on the depth —
and under MPI the floor is roughly **one cell per rank**, so at fixed cells/rank the coarsest *global*
grid grows with the rank count no matter how many levels are requested.

Single GPU, 2048 × 64 × 64 channel, everything else held:

| levels | smoothed bottom | agglomerated (exact) bottom |
|---|---|---|
| 4 | 13.5 iters, 167 ms | **4.0 iters, 112 ms** |
| 6 | 6.0 iters, 91 ms | **4.0 iters, 69.5 ms** |
| 8 | 4.4 iters, 75.5 ms | **4.0 iters, 72.2 ms** |
| 12 (full depth) | 4.4 iters, 77.2 ms | 4.4 iters, 77.1 ms |

Two things follow. **An exact agglomerated bottom is depth-independent** — 4.0 iterations at 4 levels
and at 8. And it is *faster than full geometric depth*, because the extra levels cost more than the
coarse solve they replace; the best configuration is a shallow hierarchy over an exact bottom.

Independently: with enough depth the multigrid is **domain-length-independent**. Lengthening a
256 × 64 × 64 box by 8× at full depth holds 4.0 iterations, while at 4 levels it climbs 4.0 → 13.5.
So iteration growth in a weak-scaling curve is a coarse-level artefact, not physics.

**The criterion is the coarsest grid's largest EXTENT, not its cell count.** What smoothing cannot fix
is a mode spanning many cells along an axis (Gauss–Seidel needs O(L²) sweeps for a wavelength of L
cells). A 64 × 2 × 2 bottom is only 256 cells and still costs 6.0 iterations against 4.0.

`set_pressure_bottom("auto")` agglomerates whenever the coarsest global grid exceeds
`PECLET_FLOW_AGGLOM_EXTENT` (4) cells on any axis; `"smoother"` is the legacy cheap bottom,
`"agglomerated"` forces it. The agglomerated bottom is decomposition-independent by construction (the
gathered operator is keyed by global cell id) and measures as such: np=6 against np=1 agrees to
**4.5e-16**.

**`"smoother"` is still the default, and that is a deliberate hold.** On the cut-cell sphere-packing
regression (`random_spheres`, N=48) switching to the agglomerated bottom makes the OUTER iteration
count *worse* — 442 → 622 total, +41 % — at bit-identical accuracy. An exact coarse solve cannot
legitimately slow the outer iteration down, so the assembled coarse operator is evidently not
consistent with the V-cycle's on the IBM path (prime suspects: the identity rows given to solid
cells, or the null-space/mean handling when cut cells are present). Until that is understood, `auto`
is opt-in. It is unambiguously right on the all-fluid domain-BC path, which is what the channel uses.

## 3. Design rules

1. **Choose grid dimensions for their factors of two.** `2^k · small` in every direction. Never let a
   dimension come out odd. Check with the tool in §5 before committing to a grid.
2. **Choose the rank count to divide the atom grid**, where an atom is `2^(L-1)` cells — not to be a
   power of two. Think of the domain as a grid of atoms and decompose *that*.
3. **Multigrid depth is a resolution setting, not a constant.** Across a refinement ladder hold the
   *coarsest grid* fixed, not the level count.
4. **Prefer coarse-first when the rank count is awkward**, and let the imbalance budget pick the depth.
5. **When cells/rank cannot be held exactly constant** (3-D power-of-two refinement moves the cell
   count in 8× steps), compute weak efficiency from **per-GPU throughput**, which corrects for it.
6. **Watch `last_pressure_iterations()`, not just ms/step.** A clamped iteration count (equal to
   `PMAXIT` every step) means the solve never converged and the timing measures the cap, not the work.

---

## 4. Open problems

Roughly in order of expected value.

1. **Derive the alignment cap from the requested depth.** It is hard-coded at 16 (five levels) in
   `coarsenAlignment`. It should follow `MGLEVELS` bounded by a load-balance budget, the way
   coarse-first already does. §2.5 is the regression to protect.
2. **Graceful degradation instead of skipping the snap.** The aligned ORB abandons alignment entirely
   once a sub-box drops below `2*align` (`initImpl`), which silently costs a level — visible as np=7,
   12, 16, 24 dropping from 6 levels to 5 in §2.3. Snapping to the largest power of two that still
   fits would keep the depth.
3. **Why the agglomerated bottom hurts the IBM path** (§2.7). This blocks making `auto` the default,
   and the default is what most runs get. Reproduce with
   `tests/regression/sdflow_regression.py` (random_spheres N=48) against
   `PECLET_FLOW_AGGLOM_EXTENT=1000000`. Look first at the identity rows `buildAmg` gives solid cells
   and at `pcgAmg`'s mean projection when cut cells make the operator's null space differ from the
   pure all-Neumann case.
4. **A direct solve at the bottom.** The agglomerated bottom already converges (AMG-preconditioned CG
   to 1e-10), so this buys cost rather than iterations: it replaces ~20 CG iterations of serial host
   code per V-cycle with two triangular solves. For a few-hundred-to-few-thousand-DOF coarse grid a
   DENSE Cholesky is the pragmatic choice — ~100 lines, no new dependency, factor once per operator
   build (the existing `amg_.reset()` on operator change is the hook). Sparse direct (SuiteSparse /
   MUMPS) is not worth a dependency at this size. Note the all-Neumann operator is singular: pin one
   DOF or factor a regularised operator, then project the mean out (`pcgAmg`'s `meanZero`).
   Beware the porous / variable-ρ paths, which rebuild coefficients every step and so would
   refactorise every step.
5. **Cost of the redundant gather.** Today every rank receives the whole coarse problem
   (`Allgatherv`) and solves it with serial HOST code — a device→host→device round trip inside a GPU
   solve, once per V-cycle. Fine at an 800-cell bottom; measure at 32 GPUs before assuming. If it
   bites: agglomerate onto a subset of ranks, keep the factorisation on device, or agglomerate one
   level earlier (§2.7 shows a shallower hierarchy over an exact bottom is *faster*).
6. **Agglomeration for the other multigrids.** The block-local hierarchy cannot get coarser than
   one cell per rank, so under weak scaling the coarsest global grid grows with the rank count. The
   agglomerated `GraphAMG` bottom (`set_pressure_graph_amg`) addresses this algebraically; a geometric
   redistribute-onto-fewer-ranks variant does not exist. This is the main structural lever at scale,
   and the TGV ablation that rejected GraphAMG was run where iterations were already 4 — i.e. where
   there was nothing to fix. Re-test it where the hierarchy is actually starved.
7. **Padding to friendly sizes with masked cells.** `flow` already carries openness/masking, so
   503 → 512 with 9 solid layers costs 1.8 % more cells and buys 8 levels of coarsening. Probably the
   cheapest large win available, and it needs no new numerics — but it does need the padding to be
   invisible to diagnostics and to the physical box definition.
8. **Coarse-first vs the weighted ORB.** Weighted decomposition (load balancing, CFD-DEM
   co-decomposition) and nested coarse levels are currently incompatible beyond `levels=1`: a weighted
   level-0 has no reason to be alignable. Coarse-first offers a way out — weight the *coarse* grid and
   refine upward — which would make dynamic load balancing and multigrid coexist. Not attempted.
9. **Wall-normal decomposition.** Would lift the ceiling in §2.6. Needs the pressure solve and the
   velocity BC handling to tolerate an internal boundary in the wall-normal direction.
10. **Line relaxation for anisotropic levels.** Once only one axis is still coarsening, the coarse
   operator is strongly anisotropic and a point Red-Black Gauss-Seidel smoother is a poor smoother for
   it. Line relaxation in the strong direction is the textbook remedy, and would make deep
   semi-coarsened hierarchies actually pay off.
11. **Odd-grid coarsening.** Allowing `n → (n+1)/2` with matched transfer operators removes the
   divisibility constraint at the root. Larger change; padding (4) buys most of the benefit first.
12. **Should coarse-first become the default?** It is opt-in today. It changes the partition for every
   existing MPI run, so this needs a bit-exactness and performance sweep across the suite first.

---

## 5. Tooling

`flow/scripts/check_decomposition.py` answers all of the above for a given grid and rank count
**without a GPU and without a job** — it needs only an MPI-enabled `flow` build (the OpenMP one is
fine) and runs oversubscribed, since nothing is timed.

```bash
export PYTHONPATH=$PWD/build_mpi_omp        # any MPI-enabled flow build
python scripts/check_decomposition.py --grid 480,80,160 --levels 6 --np 4,7,24 --mode 0,coarse
python scripts/check_decomposition.py --grid 3072,512,1024 --np 16,32 --orb-only   # any size
python scripts/check_decomposition.py --grid 1508,240,503 --levels 5 --np 4 --walls --verbose
```

It reports per-axis halvings, the block, the imbalance, which directions were split, the level count
actually achieved, and (with `--verbose`) the per-level dimensions and ratios. `--orb-only` skips
constructing a Solver so it works on grids far too large to allocate on a host.

**Validate any new grid or ladder with this before spending GPU hours.** It caught a proposed
weak-scaling ladder whose 16-GPU rung would have run with two multigrid levels.

The underlying knob is `PECLET_FLOW_MG_DEBUG=1`, which makes the solver print its level table and the
decomposition it chose; useful inside a real job too.
