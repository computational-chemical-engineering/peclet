# Coarse-level telescoping for the pressure multigrid — design + implementation plan

Written 2026-09-01, answering open problem 1 of
[`DECOMPOSITION_AND_MULTIGRID.md`](DECOMPOSITION_AND_MULTIGRID.md) and issue 2 of
[`SCALING_ISSUES.md`](SCALING_ISSUES.md): the multigrid hierarchy stops coarsening when a per-rank
block hits an odd extent, which costs a third of the strong-scaling efficiency at 1536 ranks and,
on a dense bed, costs convergence outright.

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

### 4.1 The level model

Today a `Level` already carries everything that varies per level *except* its parallel layout: its
own `og` (global inner origin), `gdim` (global dims), ghost width `g` (already 1 or 2 depending on
CA eligibility), and its **own** `GridHaloTopology` + `GridHalo`. The topology is built as

```cpp
v.halo->buildTopology(dec, rank, v.g, per, comm);
```

— already parameterized by decomposition, rank and communicator. A telescoped level therefore needs
no new halo machinery at all: it passes a different `dec`, a different `rank`, and a different
`comm`. `Level` gains four members:

```cpp
BlockDecomposer<3> dec;   // this level's partition
MPI_Comm  comm;           // this level's communicator (subset below a telescope point)
bool      active;         // does this rank hold a block on this level?
bool      telescoped;     // is the transition INTO this level a redistribution?
```

plus, on a telescoped transition, a **staging buffer** laid out on `dec_L.coarsened(ratio)` — the
partition the coarse level *would* have had in place.

### 4.2 The V-cycle transition

The transfer kernels are untouched. Telescoping brackets them:

```
restrictAvg(staging.rhs, lv.res, ...)                  // as today, on the parent partition
gatherToGroups(staging.rhs -> cs.rhs)                  // NEW: one gather per group
if (cs.active) vcycle(L+1)                             // inactive ranks skip the sub-tree
scatterFromGroups(cs.x -> staging.x)                   // NEW: the inverse
prolongAdd(lv.x, staging.x, ...)                       // as today
```

Restriction and prolongation arithmetic is unchanged and still local; the only new thing between
them is a pure data movement. Non-telescoped transitions keep exactly today's two lines, so a
hierarchy with telescoping disabled is byte-identical.

### 4.3 Choosing the coarse partition

A pure function of `(tree, blocks, grid)` — replicated on every rank, no communication, in keeping
with the existing rule that the decomposition search must not depend on anything rank-local.

```
telescopeFactor(dec, gs):
  for d = depth(dec)-1 down to 1:
     cand = dec.agglomerated(d)                  # truncate the ORB tree to depth d
     if any axis passes can(gs[ax]) && evenBlocks(cand, ax):
         return cand                             # fewest merges that unblocks coarsening
  return none                                    # already on one rank -> bottom
```

Truncating by one tree level halves the rank count and merges along one ORB split axis; the loop
merges further only if one level was not enough. The invariant it maintains: **a block never falls
below the size at which it can still coarsen**, so the hierarchy runs to a small grid on few ranks
instead of stopping at 48 cells across on all of them.

A second, *economic* trigger belongs behind a knob and should not ship in the first cut: even when
coarsening is legal, a 4×4×4 block with a ghost layer is mostly ghost, and MueLu/PETSc both
agglomerate before that point (`min rows per proc`). Add
`PECLET_FLOW_TELESCOPE_MIN_EXTENT` once §6's measurements say what the threshold should be.

### 4.4 Communicators and idle ranks

`MPI_Comm_split(parent, color = isGroupRoot ? 0 : MPI_UNDEFINED, key = groupIndex)` gives the coarse
level a communicator in which **sub-rank == block index**, so nothing downstream needs a rank↔block
map. Ranks that get `MPI_COMM_NULL` are inactive on that level and every level below it: they
participate in the gather and the scatter (which run on the *parent* comm, where everyone is
present) and skip the rest. Idleness is real but confined to levels that are a vanishing share of
the work — the trade every scalable multigrid makes.

Three collectives currently hard-wired to `comm_` must become per-level: `allreduce`,
`allreduceSum2` (used by `removeMean`), and the bottom's `Allgatherv`. That is a mechanical change
and is the main place a deadlock could hide (§7).

### 4.5 The data movement

Because the agglomeration is nested, each coarse block is exactly the union of a *contiguous* set of
fine blocks, so the movement is a gather within disjoint groups: each group member packs its inner
box, the root unpacks. One `MPI_Gatherv` on a group communicator, no handshake, deterministic.

core already has the general primitive — `decomp::grid_redistribute.hpp`'s
`redistributeGridFields(oldDec, newDec, rank, g, oldFields, newFields, comm)`, NBX-based, bit-exact
by construction, written for weighted-ORB load balancing. It is *more* general than needed here
(arbitrary A→B, irregular). **Use the group gather as the fast path and keep
`redistributeGridFields` as a debug oracle**: a `PECLET_FLOW_TELESCOPE_CHECK=1` mode that performs
the same movement both ways and compares gives a strong, cheap correctness gate, and reuses tested
code to validate new code. (`redistributeGridFields` is host-only; the group gather should be
host-staged on the GPU backend at first, following `GridHalo`'s precedent. Coarse-level buffers are
small — two fields, and at the telescope point a block is a few hundred cells.)

### 4.6 Setup

Per V-cycle only two fields move (`rhs` down, `x` up). The operator is built **once** at setup: move
the openness fields (`ox, oy, oz`) through the same gather and rebuild the coarse operator on the new
partition with the existing rediscretization, rather than moving seven assembled coefficient arrays.
That keeps the "rediscretized cut-cell coarse operator" semantics intact, which is what makes the IBM
path work, and it keeps the per-cycle traffic minimal. `applyBoundaryOpenness` and
`touchesGlobalFace(lv, f)` key off `og`/`gdim`, which a telescoped level carries correctly, so the
domain-BC path needs no special handling.

## 5. What changes where

| where | change | size |
|---|---|---|
| `core/decomp/block_decomposer.hpp` | `agglomerated(int depth)` → truncated-tree `BlockDecomposer` + `groupOfBlock()` map. Boxes from a downward walk; asserts exact tiling. Reusable by dem/voro/AMR. | ~80 lines |
| `core` (new or in `grid_redistribute.hpp`) | `gatherGroups` / `scatterGroups` on a group comm | ~120 lines |
| `flow/src/mac_cutcell_mg.hpp` | `Level` gains `dec/comm/active/telescoped` + staging; `initMpi` level loop calls `telescopeFactor` at the `break`; `vcycleImpl` brackets the transfers; per-level comm in `allreduce`/`allreduceSum2`/bottom | ~250 lines |
| `flow/scripts/check_decomposition.py` | print the telescoped ladder (rank count and block per level) | ~40 lines |
| `flow/tests/kokkos_mpi/` | new ctest (§6 P3) | ~200 lines |

Nothing in `restrictAvg`, `prolongAdd`, the smoother, `GridHalo` or `GridHaloTopology` changes.

## 6. Staging

**P0 — two probes before any code (hours, no new code).** Either could re-order everything.
  - *Is the single-phase loss the depth, or the anchored bottom?* That case runs a **smoother** on a
    48-across coarsest grid because `auto` is gated to the singular path (open problem 4). Force it:
    `set_pressure_bottom("agglomerated")` at np=384 and 1536, single-phase. If iterations collapse
    toward the np=24 value, a large part of issue 2's headline is recoverable by lifting the
    anchored-path gate — a much smaller change than telescoping, which then becomes the *general*
    fix rather than the *urgent* one.
  - *Is the packed np=1536 cliff the redundant gather?* Rerun it with
    `PECLET_FLOW_AGGLOM_EXTENT=1000000` (disables auto agglomeration). If the regression vanishes,
    the cliff is the coarsest-level `Allgatherv` + serial host solve per V-cycle, not the contrast
    threshold, and `SCALING_ISSUES.md`'s "issues 1 and 2 compound" paragraph needs revising.
  
  Both are single-rung reruns on an existing build. **Do not start P1 before these report.**

**P1 — the decomposition primitive, no MPI, no solver.** `BlockDecomposer::agglomerated()` +
  `telescopeFactor`, with unit tests: the truncated blocks tile the global grid exactly; every fine
  block is contained in exactly one coarse block; the group map is a partition; imbalance is
  reported. *Gate:* pure-function tests pass at a spread of rank counts, including non-powers of two
  (24, 96, 384, 1536) — §2.3 is the warning that powers of two are not the interesting cases.

**P2 — the prediction tool.** Extend `check_decomposition.py` to print the ladder telescoping would
  build. This produces the authoritative level table for the grids in question **without a job or a
  GPU**, and it is the artifact that says whether the design delivers the depth before a line of
  solver code exists. It also fixes issue 6's usefulness. *Gate:* at 384³/np=1536 the predicted
  hierarchy reaches a coarsest extent ≤ 4, against ~48 today.

**P3 — the solver, telescoping OFF by default.** `Level` members, the `initMpi` hook, the V-cycle
  bracketing, per-level comms. *Gates:* (a) with telescoping disabled, **byte-identical** to today
  on the existing `tests/kokkos_mpi` suite; (b) np=1 unaffected by construction; (c) a new ctest
  that forces telescoping on a grid where in-place coarsening is *also* legal, so the two
  hierarchies can be compared: converged solutions must agree to the solver tolerance (they will not
  be bitwise — coarse-level `removeMean` sums in a different order, the same class as coarse-first
  vs aligned at 3.3e-12); (d) `PECLET_FLOW_TELESCOPE_CHECK=1` agrees with `redistributeGridFields`.

**P4 — the decisive measurement.** The configuration that motivated all of this: a block small
  enough that in-place coarsening stops early. Iteration count must fall toward the value the same
  problem shows at low rank count. Measure on **a dense bed, not a clean single-phase problem** —
  `SCALING_ISSUES.md` is explicit that the hierarchy is only starved where it matters on the packed
  case. Run np=384 (known-good reference: 81.7 iterations, reproducible to 5 %) and np=1536.

**P5 — promote and follow through.** Default on where it helps; re-run the FoxBerry ladder and
  republish the (currently provisional) study page. Then the items it unlocks: open problem 5 (a
  dense-Cholesky bottom becomes trivially attractive once the bottom really is tiny), open problem 6
  (the redundant gather's cost mostly evaporates), open problem 4 (the anchored-bottom pathology is
  much cheaper to study on a small bottom), and issue 5 (`VelocityMG` can reuse the same primitive).

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

The honest caveat: P0 may show that a share of the single-phase gap is the anchored bottom rather
than the depth. That would not invalidate this plan — telescoping is still what makes the bottom
small enough for any bottom solver to be cheap — but it would change which fix is urgent, and it is
much better to learn that from two reruns than from a week of implementation.
