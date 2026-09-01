# Coarse-level telescoping for the pressure multigrid — design + implementation plan

Written 2026-09-01, answering open problem 1 of
[`DECOMPOSITION_AND_MULTIGRID.md`](DECOMPOSITION_AND_MULTIGRID.md) and issue 2 of
[`SCALING_ISSUES.md`](SCALING_ISSUES.md): the multigrid hierarchy stops coarsening when a per-rank
block hits an odd extent, which costs a third of the strong-scaling efficiency at 1536 ranks and,
on a dense bed, costs convergence outright.

> **Revised the same day after a second read against the code** (three corrections, all in §4 —
> the first draft had the transfer ordering backwards, which would not have worked on the blocked
> axis; it under-specified the trigger in a way that could merge along the wrong axis; and it
> missed that a *far* cheaper first rung falls straight out of machinery that already exists. The
> staging in §6 now leads with that rung.)

**Conclusion up front.** Do geometric telescoping on the ORB tree: when in-place coarsening is
blocked, merge sibling ORB blocks onto half (or a quarter, or an eighth) as many ranks, move the
level's data with one gather per group, and carry on halving. This is PETSc `PCTELESCOPE`'s
structure, and peclet is unusually well set up for it — three of the four primitives it needs
already exist. The two alternatives the current doc floats (hand the stopping level to `GraphAMG`;
pad the grid) do **not** address this constraint, for reasons given in §3.

---

## 1. What the constraint actually is

`CutcellMG::initMpi` builds level `L+1` as `curDec.coarsened(ratio)` — the *same* ORB tree with
origins, sizes and split values divided by `ratio`. That is what makes the transfer operators purely
local: coarse-local `i` ↔ fine-local `ratio*i` on the same rank, so `restrictAvg` and `prolongAdd`
are single-rank kernels with no communication. The price is the gate

```cpp
can(gs[ax]) && evenBlocks(ax)     // every rank's block ORIGIN and SIZE even on that axis
```

and a `break` when no axis passes — note the gate is **per axis**, so an axis freezes individually
while others may keep halving. **The stopping criterion is a property of the smallest block, not of
the grid.** At 384³ on 1536 ranks the level-0 block is 24×48×32 — even on every axis, nicely
factored, imbalance 1.000 — and §2.8 records it stopping at a block of 3×6×4. The robust consequence,
independent of exactly how far `y` and `z` limp on afterwards, is that **`x` freezes at a global
extent of 48** the moment its block is 3 wide. Per §2.7 the figure that decides whether a V-cycle is
domain-independent is the coarsest grid's **largest extent**, and 48 is far too large: a 64×2×2
bottom is only 256 cells and still costs 6.0 iterations against 4.0. (The exact coarsest grid at each
rank count is what P2's tool should report; it is not worth deriving by hand, and this plan
deliberately does not.)

Two consequences worth separating, because they have different fixes:

- **The hierarchy is too short.** Iterations rise 16.6 → 38.7 from 24 to 1536 ranks while time *per
  iteration* improves super-linearly (156 % efficiency). The entire wall-clock loss is the iteration
  count. This is what telescoping fixes.
- **The bottom is then solved badly, and the two FoxBerry cases fail differently.** The single-phase
  case has an inlet/outlet, so the operator is non-singular, `removeMean_` is false, and
  `agglomerateBottom()` returns false — it runs a *smoother* on a grid 48 cells across. The
  packed-periodic case is singular, so `auto` engages and gathers the whole coarsest operator — tens
  of thousands of cells at this rank count — to **every one of 1536 ranks**, every V-cycle, solved by
  serial host code. Same depth cap, two different failure modes downstream of it.

That second point generates two cheap probes that must run before any code is written (§6, P0),
because either could re-order this plan.

## 2. What the libraries do

| library | mechanism | keyed on |
|---|---|---|
| PETSc | `PCTELESCOPE` — redistribute the problem onto a sub-communicator, recurse (May, Sanan, Rupp, Knepley & Smith, *Extreme-Scale Multigrid Components within PETSc*, PASC '16) | explicit reduction factor, or `-telescope_ranks` |
| Trilinos MueLu | `RepartitionFactory` + `RebalanceTransferFactory` (Zoltan2) | minimum rows per rank |
| hypre BoomerAMG | redundant/replicated coarse solve; agglomeration on coarse levels (Baker, Falgout, Kolev & Yang, *Scaling hypre's Multigrid Solvers to 100,000 Cores*) | coarse-grid size threshold |
| DUNE-ISTL AMG | *accumulation* onto fewer processes | coarse-grid size |
| textbook | processor agglomeration, idle processors on coarse grids | Trottenberg, Oosterlee & Schüller, *Multigrid*, ch. 6 |

They differ in how the coarse partition is **chosen**. MueLu and hypre must re-partition an
*algebraic* graph, so they need a partitioner (Zoltan2) and a general, irregular redistribution.
PETSc's telescope is closer to what we want but is generic over `DM`s.

**peclet's ORB makes this strictly easier than any of them**, and that is the design insight:

- `BlockDecomposer` stores the recursive-bisection tree explicitly (`tree_`, heap layout, children at
  `2i+1`/`2i+2`, leaves carrying the block index), plus `flattenTree()`.
- Every internal node of that tree *is* a box, and its box is exactly the union of its subtree's
  leaf boxes — reconstructible by a downward walk from `(0, globalSize)` splitting at each
  `splitDim/splitValue`.
- Therefore **merging sibling blocks = truncating the tree**, and the merged partition tiles the
  domain exactly, nests with the fine one by construction, and needs no partitioner and no graph.

So where MueLu needs Zoltan2 and an irregular redistribution, peclet needs a tree truncation and a
gather within disjoint groups. The agglomeration hierarchy is already in the data structure; nobody
has walked up it yet.

## 3. Why not the alternatives

**Hand the stopping level to `GraphAMG` (open problem 1's "cheapest to measure first", and open
problem 7).** Retire this suggestion. `GraphAMG`'s agglomerated path gathers the assembled operator
to *every* rank (`MPI_Allgatherv`) and solves it with serial host code — a device→host→device round
trip per V-cycle. Handing it the stopping level means doing that to an operator of tens of thousands
of cells at np=1536 instead of the few hundred a telescoped hierarchy would leave, every V-cycle, on
1536 ranks. It replaces a depth problem with a communication-and-serial-work problem. It would be the right answer if `GraphAMG` were distributed,
but it is not (open problem 7 says so), and making it distributed — parallel aggregation, distributed
Galerkin triple products — is a far larger project than §4. **The algebraic route is more work and
less suited; the geometric route is a tree walk.**

**Padding to friendly sizes (open problem 8).** Orthogonal, and it does not touch this. The
constraint is the per-rank block; at np=1536 the *global* grid 384³ = 2⁷·3 is already excellent and
the block 24×48×32 is already even everywhere. Padding cannot help a hierarchy that dies because
1536 blocks have become 3 cells wide. Padding fixes §2.2-style badly-factored grids, a different
disease.

**Odd-grid coarsening (open problem 12).** Would relax the parity gate, but only defers the wall — a
block of 1 cell cannot coarsen however clever the transfer operator — and it changes the numerics of
every level. Telescoping removes the pressure to do it at all, which the doc already notes.

## 4. Design

### 4.0 Two rungs on one primitive

Both rungs need the same thing: **move a distributed level, at its own resolution, onto fewer
ranks, and continue the geometric hierarchy there.** They differ only in *how many* fewer.

| | rung 1 — redundant gather | rung 2 — sub-communicator telescoping |
|---|---|---|
| where the level goes | to **every** rank (Allgatherv), each continues the hierarchy alone | to a **subset** (ORB tree truncation), continues on a sub-communicator |
| new decomposition code | none | `BlockDecomposer::agglomerated()` + group comms |
| below the telescope point | the existing **single-rank** `CutcellMG` path, unchanged | the existing distributed path on the sub-comm |
| scatter back | none — each rank extracts its own block | one scatter per group |
| per-V-cycle traffic | one Allgatherv of the level's residual, N_L doubles to every rank | one gather + one scatter within groups |
| scales to | N_L that one rank can hold and solve in ~ms: this campaign's whole ladder | arbitrary N_L (large weak-scaling runs) |
| effort | days | weeks |

Rung 1 is exactly the design pattern the existing agglomerated bottom already uses — it gathers
the bottom **rhs** redundantly every V-cycle and the operator once, "so the assembled coarse
problem is bit-identical on all ranks and each solves it locally with no rank-0 bottleneck and no
result broadcast". Rung 1 applies that pattern one or more levels *earlier* and, instead of handing
the gathered level to `GraphAMG`, hands it to the single-rank geometric hierarchy — which already
exists, already goes to full depth, already carries every BC path and the exact bottom, and is
already tested. Rung 2 is rung 1's general form, for when N_L is too large to replicate.

The rest of §4 describes the shared mechanism; where the rungs differ it says so.

### 4.1 Where the redistribution happens — at the fine level's resolution

This is the correction to the first draft. Restriction cannot be done first and gathered second,
because restriction on the parent partition is *precisely what is blocked*: a block 3 cells wide
has no in-place half. The order is therefore

```
[all ranks at L]   move lv.res (resolution L) onto the merged partition   -> T.res
[merged ranks]     restrictAvg(cs.rhs, T.res, ...)     // legal: merged blocks are even
[merged ranks]     zero cs.x; vcycle(L+1)              // the hierarchy continues from cs
[merged ranks]     fill/BC ghosts on cs.x; zero T.x; prolongAdd(T.x, cs.x, ...)
[all ranks at L]   move T.x back and ADD into lv.x     // prolongAdd is additive
                   smooth(lv, post)
```

`T` is the *telescope stage*: level L's grid on the merged partition. What moves per V-cycle is two
resolution-L fields, the residual down and the correction up. `restrictAvg` and `prolongAdd` are
untouched.

**T needs no halo topology.** `restrictAvg` reads fine *inner* cells only (`fx = ratio*icx+dx+gf`,
always inside the inner box), and `prolongAdd` writes fine *inner* cells only — the coarse ghosts it
reads are `cs`'s own, filled by `cs`'s existing halo and BC ghost policies. So `T` is two buffers
with the fine extent, nothing more. (The first draft's "staging level on `dec_L.coarsened(ratio)`"
is gone; that partition does not exist, which was the whole problem.)

### 4.2 The level model (rung 2)

A `Level` already carries per-level `og`, `gdim`, ghost width `g` (1 or 2 by CA eligibility) and its
own `GridHaloTopology` built as `buildTopology(dec, rank, v.g, per, comm)` — parameterized by
decomposition, rank and communicator. A telescoped level passes different values for all three and
needs no new halo machinery. `Level` gains `dec`, `comm`, `active`, and the transition into it
gains a `T` stage. Under rung 1 the "merged partition" is one block on every rank and `cs` onward is
a nested single-rank `CutcellMG` driven through its existing entry points
(`init(nx,ny,nz,levels)`, `setBoundaryConditions(bc)`, `setOpenness(ox,oy,oz,…)`).

### 4.3 The trigger — and what actually binds

The gate is `can(gs[ax]) && evenBlocks(ax)`, and `evenBlocks` demands even **origins** as well as
even sizes. Origins are what bind in practice: after three halvings of a level-0 partition whose
splits sit at multiples of 24, the split values are multiples of 3 and every other block starts at
an odd cell. Merging two ORB siblings restores parity because the merged block's origin is the
*parent's* split value, one tree level up — a multiple of 6 in that example. This is why sibling
merging is the right primitive and not merely a convenient one.

The rule, a pure function of `(tree, gs)` replicated on every rank with no communication:

```
telescope(dec, gs):
  if every axis with can(gs[ax]) already passes evenBlocks -> no telescope
  rung 1: merge to ONE block (tree depth 0)      -- trivially passes for every axis
  rung 2: for d = depth-1 down to 1:
             cand = dec.agglomerated(d)
             if EVERY axis with can(gs[ax]) passes evenBlocks(cand, ax): return cand
          return dec.agglomerated(0)
```

**"Every coarsenable axis", not "any axis"** — the first draft had "any", and that can merge along
`z`, unblock `z`, and leave `x` frozen at 48 cells, which is the extent that matters (§2.7). The
"every" rule may merge more than strictly necessary — the ORB alternates split axes, so reaching
an `x`-split can cost two `y`/`z` merges on the way — but it restores full-depth coarsening on all
axes, and P2's tool makes the cost visible. Prefer the largest `d` (fewest merges).

A second, *economic* trigger — telescope before the block is so small that ghosts dominate, the
analogue of MueLu's minimum-rows-per-rank — belongs behind `PECLET_FLOW_TELESCOPE_MIN_EXTENT` and
should not ship until measured. Under rung 1 it also has a memory meaning: every rank then holds the
whole level, so telescoping *early* multiplies memory by the rank count.

### 4.4 Communicators and idle ranks (rung 2)

`MPI_Comm_split(parent, color = isGroupRoot ? 0 : MPI_UNDEFINED, key = groupIndex)` gives the
coarse level a communicator in which **sub-rank == block index**. Ranks that receive
`MPI_COMM_NULL` are inactive on that level and below: they take part in the gather and the scatter
(which run on the *parent* comm, where everyone is present) and skip the recursion. The collectives
currently hard-wired to `comm_` — `allreduce`, `allreduceSum2` (used by `removeMean`), and the
bottom's `gatherv` — must become per-level. Under rung 1 nothing is inactive and no sub-comm exists.

### 4.5 The data movement

Rung 1: one `Allgatherv` of the resolution-L inner cells keyed by global id — the same call and the
same keying `graphAmgSolveBottom` already uses for the bottom rhs. Each rank then holds the full
level and extracts its own block from the correction; no scatter.

Rung 2: because sibling-merge is nested, each merged block is exactly the union of a *contiguous*
run of fine blocks (the ORB assigns leaf indices in order — `initImpl` pushes the right child first
so the left is popped first), so the movement is a gather within disjoint groups: one `MPI_Gatherv`
per group communicator, deterministic, no handshake. core's
`decomp::grid_redistribute.hpp::redistributeGridFields` (general A→B, NBX, bit-exact) is more than
is needed; keep it as the **debug oracle** — `PECLET_FLOW_TELESCOPE_CHECK=1` performs the movement
both ways and compares. Host-staged on GPU at first (buffers are small), device-resident later, as
`GridHalo` did it.

### 4.6 Setup

The coarse operator is built once. Move `ox, oy, oz` at resolution L through the same gather, then
run the existing `coarsenOpenAvg` on the merged partition — a per-coarse-cell average of the same
fine cells, so bitwise identical to what the in-place path would have computed had it been legal.
`applyBoundaryOpenness` and `touchesGlobalFace(lv, f)` key off `og`/`gdim`, which a merged level
carries correctly, so the domain-BC path needs nothing special. Under rung 1, `setOpenness` on the
nested instance does all of this.

### 4.7 What stays bitwise, what does not

Restriction and prolongation are per-cell operations over the same cells with the same arithmetic
regardless of which rank executes them; Red-Black Gauss–Seidel updates each colour as a parallel
per-cell operation, so it is partition-independent once ghosts are correct. Both are bitwise
identical under telescoping. `removeMean` sums in a different order on a different partition, so
results move at the reduction-order floor — the same class as coarse-first vs aligned (3.3e-12,
§2.4). Contract: telescoping **off ⇒ byte-identical**; on ⇒ equal within solver tolerance.

## 5. What changes where

| where | change | rung | size |
|---|---|---|---|
| `flow/src/mac_cutcell_mg.hpp` | bottom mode `"geometric"`: at the blocked level, Allgatherv `res` (and `ox/oy/oz` once) by global id, drive a nested single-rank `CutcellMG` on the full level, extract own block, add | 1 | ~150 lines |
| `flow/scripts/check_decomposition.py` | print the telescoped ladder (rank count and block per level) — rung 1 and rung 2 forms | 1 | ~40 lines |
| `core/decomp/block_decomposer.hpp` | `agglomerated(int depth)` → truncated-tree `BlockDecomposer` + group map; boxes from a downward walk; asserts exact tiling. Reusable by dem/voro/AMR | 2 | ~80 lines |
| `core` (new or in `grid_redistribute.hpp`) | `gatherGroups` / `scatterGroups` on a group comm | 2 | ~120 lines |
| `flow/src/mac_cutcell_mg.hpp` | `Level` gains `dec/comm/active`; `T` stage; `initMpi` hook at the `break`; V-cycle bracketing; per-level comm in the three collectives | 2 | ~250 lines |
| `flow/tests/kokkos_mpi/` | new ctests (§6) | 1, 2 | ~200 lines |

`restrictAvg`, `prolongAdd`, the smoother, `GridHalo` and `GridHaloTopology` are untouched by
either rung.

## 6. Staging

**P0 — two probes before any code (hours).** Either could re-order everything.
  - *Is the single-phase loss the depth, or the anchored bottom?* That case runs a **smoother** on a
    48-across coarsest grid because `auto` is gated to the singular path. Force it:
    `set_pressure_bottom("agglomerated")` at np=384 and 1536, single-phase. **Record `max|div|`
    alongside the iteration count** — §2.7 already measured that the exact bottom *lowers the
    attainable floor* on the anchored path (8e-8 → 2e-5 on the inflow/outflow channel), so a run
    that "converges in fewer iterations" to a worse divergence is not a win, and the probe must be
    able to tell. If iterations fall *and* the floor holds, part of issue 2 is the bottom, and
    lifting the anchored-path gate becomes the urgent fix.
  - *Is the packed np=1536 cliff the redundant gather?* Rerun with
    `PECLET_FLOW_AGGLOM_EXTENT=1000000`. If the regression vanishes, the cliff is the coarsest-level
    `Allgatherv` + serial host solve per V-cycle, not the contrast threshold, and
    `SCALING_ISSUES.md`'s compounding paragraph needs revising.

**P1 — the prediction tool.** Extend `check_decomposition.py` to print, for a grid and rank count,
  the level at which in-place coarsening stops, N_L there, and the ladder each rung would build
  below it. This is the artifact that says whether rung 1 suffices at the rank counts in question
  (is N_L a few hundred thousand cells or a few million?) **before a line of solver code exists**, and
  it fixes issue 6's usefulness. *Gate:* at 384³/np=1536 the predicted rung-1 hierarchy reaches a
  coarsest extent ≤ 4, against ~48 today.

**P2 — rung 1, off by default.** Bottom mode `"geometric"`. *Gates:* (a) off ⇒ **byte-identical**
  on the existing `tests/kokkos_mpi` suite; (b) np=1 unaffected by construction; (c) a ctest that
  forces it on a grid where in-place coarsening is *also* legal, so the two hierarchies can be
  compared — converged solutions agree to solver tolerance; (d) a ctest on a deliberately starved
  partition — iteration count must fall to the single-rank value for the same problem.

**P3 — the decisive measurement, on a dense bed.** Re-run np=384 (reference: 81.7 iterations,
  reproducible to 5 %) and np=1536 packed with rung 1. Iterations should hold near the low-rank
  value; the np=1536 cliff should be gone. Also record rung 1's cost — the Allgatherv volume and
  the per-rank serial work — because that number decides whether rung 2 is needed at this scale or
  only for larger weak-scaling runs.

**P4 — rung 2, if P3 says the redundant gather costs enough to matter.** `agglomerated()`, the
  group gather with its `redistributeGridFields` oracle, per-level comms, the `T` stage. Gates as
  P2 plus `PECLET_FLOW_TELESCOPE_CHECK=1` agreement and a deadlock-free run at ≥ 2 telescope points.

**P5 — promote and follow through.** Default on where it helps; re-run the FoxBerry ladder and
  republish the provisional study page. Then what it unlocks: open problem 5 (a dense-Cholesky
  bottom becomes trivially attractive once the bottom really is tiny), open problem 6 (the redundant
  gather's cost is now measured, not assumed), open problem 4 (the anchored-bottom pathology is
  cheaper to study on a small bottom), and issue 5 (`VelocityMG` can reuse the same primitive).

## 7. Risks

- **Deadlock on the sub-communicator.** The main hazard: an inactive rank entering a collective, or
  an active one skipping it. Contained by making the gather/scatter run on the *parent* comm (all
  ranks present) and by auditing every `comm_` use in `CutcellMG` — there are only three
  (`allreduce`, `allreduceSum2`, the bottom `Allgatherv`). The intermittent multi-node hang already
  on the register (issue 4) is a reason to be careful here and to add a barrier-and-timeout debug
  mode rather than to assume.
- **Results move.** Only when enabled, and only at the reduction-order floor. The contract is the
  one CA smoothing and coarse-first already established: off ⇒ byte-identical; on ⇒ equal within
  solver tolerance. State it in the gate, not after the fact.
- **GPU staging.** Host-staged first (small buffers), device-resident later, exactly as `GridHalo`
  did it. Measure before optimizing.
- **Rung 1's replication cost.** Every rank holds and solves the whole level: N_L doubles of
  memory and N_L-proportional serial work per V-cycle, and an Allgatherv whose aggregate volume
  grows linearly with the rank count. Fine where N_L is ~10⁵ (this ladder); not fine at ~10⁷ (a
  badly-factored grid, §2.2, or an early economic trigger). P1's tool prints N_L, so this is known
  per configuration before running, and it is the number that decides rung 2.
- **Load imbalance in the merged partition.** Merging siblings preserves the ORB's own balance, and
  §2.4 shows the ORB balances well on coarse grids. `agglomerated()` should report imbalance so P2
  can show it rather than assume it.
- **Interaction with CA smoothing.** A telescoped block is *larger*, so it is more likely to clear
  `minBlockExtent >= 4` and become CA-eligible. A bonus, but it means the g=1/g=2 choice must be
  recomputed per level after telescoping, and `parityOg`'s g-dependent red-black origin is a known
  trap (flow's CLAUDE.md flags it explicitly).

## 8. What it should buy

The claim to test, not to assume: **the pressure iteration count should become a property of the
problem, not of the rank count.** Concretely, single-phase 384³ should hold near its np=24 value of
16.6 iterations across the ladder instead of rising to 38.7, recovering most of the 33 % efficiency
gap; and the packed bed should stop falling off a cliff above 384 ranks, which is the outcome that
actually matters, because that cliff is what limits the IBM path today.

Rung 1 should deliver most of that at this ladder's scale within days, because below the telescope
point it *is* the single-rank solver, whose iteration counts are the target. Rung 2 is what keeps
it true when the gathered level no longer fits one rank.

The honest caveat: P0 may show that a share of the single-phase gap is the anchored bottom rather
than the depth. That would not invalidate this plan — telescoping is still what makes the bottom
small enough for any bottom solver to be cheap — but it would change which fix is urgent, and it is
much better to learn that from two reruns than from a week of implementation.
