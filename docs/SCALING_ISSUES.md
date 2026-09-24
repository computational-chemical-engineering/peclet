# Issues surfaced by the FoxBerry scaling campaign (2026-09-01)

Building `peclet-examples/benchmarks/foxberry-scaling` — a head-to-head reproduction of FoxBerry's
64M-cell strong-scaling cases on Snellius genoa, 24 → 1536 ranks — turned up six issues worth
fixing plus two environment traps. This is the prioritized register; each entry points at the
detailed write-up rather than repeating it.

**Ordering principle:** *silently wrong* beats *visibly broken* beats *slow*. A user who gets a
plausible-looking number that is not converged is worse off than one whose job hangs, because only
the second one knows something went wrong.

*Revised 2026-09-01 after the original issue 1 ("cut-cell IBM + open BCs is a blocker") was found to
be an artifact of the test bed rather than a property of the solver — see issue 3. FoxBerry's Case 3
is reproducible; the remaining defect is narrower.*

| # | Issue | Severity | Status |
|---|---|---|---|
| 1 | Float operator storage caps MG-PCG on dense beds | **High, silently invalid** | **CLOSED by decision 2026-09-11** (`PECLET_FLOW_OPERATOR_DOUBLE` defaults **ON**, `flow/CMakeLists.txt:93`; a float build warns and names this issue); **already shipped** in the 1.0.0 wheels |
| 2 | MG depth capped by the per-rank block | High (scaling shape) | **Fixed 2026-09-02** (telescoping, opt-in), **measured**: iterations flat 24 → 1536 ranks, ≥ 99 % efficiency on the bed |
| 3 | Solid intersecting an OPEN domain face stalls the solve | Medium, silently wrong (narrow) | **Fixed 2026-09-16** (flow: SDF ghost extension + Dirichlet-row aperture), gated `test_openbc_solid{,_mpi}` |
| 4 | Intermittent multi-node hang in warmup | **High, silently wrong** (was: Medium) | **Root-caused and fixed 2026-09-02** (core `10294e6`): NBX inter-round tag race |
| 5 | Momentum solve: cap-bound RB-GS (update criterion) | High (63 % of the packed step) | **Fixed 2026-09-02**: residual stop + velocity MG under MPI (mixed operator); packed step 2.2× faster at 384–1536 ranks |
| 6 | `check_decomposition.py` unusable above ~100 ranks | Low (tooling) | Open |
| 7 | Kokkos oversubscribes inside a CPU-quota container (Colab, Binder, Docker, Slurm) | **High, user-visible** | **CLOSED.** Fixed in the library 2026-09-13 (core `cpu_budget.hpp`); **already shipped** — the PyPI 1.0.1 wheels carry it, measured 2026-09-16 (quick start under a 2-CPU quota: **2.51 s**, was *unfinished in 15 min*) |
| 8 | MPI: the halo wraps a NON-PERIODIC domain face, so the HIGH boundary-face plane returns carrying the opposite boundary | Medium, silently wrong | **Fixed 2026-09-16** (openness re-derived, outflow velocity plane preserved); gated by `vof_bc_mpi`'s composed budget |

---

## 1. Float operator storage caps MG-PCG on dense cut-cell beds — CLOSED BY DECISION 2026-09-11

> **Resolved by flipping the default, not by a new algorithm.** `PECLET_FLOW_OPERATOR_DOUBLE`
> defaults to **ON** as of 2026-09-11 (flow `CMakeLists.txt:48-72`); a float build now emits a
> CMake warning naming this issue. The decision, its rejected alternatives and its consequences
> are recorded in [decisions/flow.md](decisions/flow.md) — *"Double operator storage is the
> DEFAULT"*. The reasoning: the failure is **silent**, so documenting it protects nobody who
> does not already know; ~12% step time is the price of a default that cannot quietly
> invalidate a dense-bed run. The double-*diagonal* fallback stays retired (65x worse on
> divergence — it converges to the float-face operator, not the true one).
>
> **Consequence still open:** this changes numerics in the default build, so regression state
> hashes and `perf_baseline.json` must be re-blessed before the 1.0.0 tag.
>
> The analysis below stands as the record of why.


The documented **WO-M** defect, reproduced independently in the field. Float `MReal` breaks the
singular row-sum identity `A·1 = 0`, the residual floors at 5e-9…6e-8 and rebounds, and any dense
bed above ~256³ burns its iteration cap. Measured on a 5000-sphere φ=0.45 bed at 384³: capped at
300 iterations, where the *same* solve at rtol 1e-6 converges in 36.5 — with `<u>` and `max|div|`
identical to seven digits. The physical answer arrives in ~36 iterations; the rest is chasing a
residual below the storage floor.

*Why it ranks here:* the **default build silently produces invalid runs**. Nothing in the output
says "capped" unless you compare iterations against `PMAXIT` yourself, and the step time then
reflects `PMAXIT` rather than convergence.

*The framing that should change:* fp64 is **~2× faster in wall clock** on such a bed (71 iterations
vs a 200 cap) and lands two orders lower in divergence. On dense beds fp64 is the *performance*
choice, not a +12 % correctness tax. Recommended production fix remains the **double-diagonal**
(faces float, diagonal resummed in double), already proven at the agglomerated bottom and awaiting
generalisation — see `flow/doc/history/vof_workorders_v34.md` (WO-M).

*Actions:* generalise the double-diagonal; failing that, make a capped pressure solve **loud** (a
one-line warning naming `PMAXIT` costs nothing and converts a silent invalid into a visible one);
and add the rtol=1e-6-vs-1e-8 comparison to the diagnostics, since it identifies this in one shot.

## 2. Multigrid depth capped by the per-rank block — HIGH (scaling shape)

A level coarsens an axis only if every rank's block origin *and* size are even on it, because
coarse levels must be the fine decomposition `coarsened()` in place. When no axis qualifies the
hierarchy stops, so **achievable depth is a property of the per-rank block, not the global grid**.

Measured, 384³, 24 → 1536 ranks: pressure iterations rise 16.6 → 38.7 and strong-scaling efficiency
falls to 67 %, while time *per iteration* improves 100× over a 64× rank increase — 156 %,
super-linear. The decomposition is exact: `42.9× speedup = 100.0× per-iteration / 2.33× iteration
growth`. **The entire loss is algorithmic, not communication.** On the badly factored 400³ the same
mechanism gives 96 → 191 iterations and 63 % by np=384.

*This is an implementation limit, not a property of multigrid.* The fix is to let a coarse level
live on its own coarser partition and redistribute inside the transfer — PETSc `PCTELESCOPE`,
MueLu `RepartitionFactory` (which is why FoxBerry's AMG holds near-ideal halving where flow cannot),
hypre's redundant coarse solve, DUNE's *accumulation*. The endpoint already exists here as
`set_pressure_bottom("auto")`; only the intermediate agglomeration steps are missing. Cheapest
thing to measure first: hand the level where geometry stops to the existing `GraphAMG` and let it
coarsen the rest of the way.

**Implemented 2026-09-02** — coarse-level telescoping on the ORB tree (`core a156528`, `flow
db7b1ba`; `set_pressure_telescope(True)` / `PECLET_FLOW_TELESCOPE=1`, off by default and
byte-identical off). The predictor shows 384³/1536 going from a 24×48×24 coarsest grid on 1536
ranks to 3³ on one (5 → 8 levels); the ctest gate shows a starved partition reproducing the
single-rank hierarchy to 2.5e-14. Full treatment: **`DECOMPOSITION_AND_MULTIGRID.md` §2.8 and
open problem 1**; design, implementation and status: **[`MG_TELESCOPING_PLAN.md`](archive/MG_TELESCOPING_PLAN.md)**.

**Measured at scale (2026-09-02, fp64 build, wall-confined bed with FoxBerry's inlet/outlet).**
Pressure iterations per step, telescoped: **43.1 / 42.9 / 41.7 / 39.8 / 39.8 / 39.8 / 39.8** at
24 / 48 / 96 / 192 / 384 / 768 / 1536 ranks (max 45 everywhere), step time 128.7 / 64.9 / 31.6 /
15.6 / 7.28 / 3.24 / 1.33 s — efficiency vs 24 ranks 100 / 99 / 102 / 103 / 110 / 124 / 151 %.
Single-phase (float build): 14.7 → 14.0 iterations flat, 34.8 → 0.656 s, 142 % at 768 and 83 % at
1536 (latency-bound momentum sweeps at 37 k cells/rank — issue 5's territory). A/B at 384 ranks: packed 49.9
iterations (max 69) / 10.8 s in place vs 39.8 / 7.28 s telescoped; single 24.9 / 2.48 s vs 14.0 /
2.01 s. At 24 ranks the two are identical (129.5 vs 128.7 s) — the hierarchy is already full depth
there. Every ladder bottoms at 3³ on one rank (384 → 8 → 1, 768 → 8 → 1, predicted 1536 → 64 → 1).
**What remains of this issue**: telescoping is the DEFAULT since 2026-09-02 (the WO-R2
variable-density outflow coefficient crosses a telescope point since the same evening,
`test_telescope_varrho_mpi`); the `MIN_EXTENT` default (4) is untuned, and the gather is
host-staged (fine on CPU; a device build would want a device-aware path).

**TRAP — a WEIGHTED `dec0` with telescoping on and `nLevels > 1` gathers the whole fine grid onto
one rank per V-cycle — MEASURED 2026-09-24, confirmed (with one qualification below).** Found
2026-09-23 from the `peclet-amr` C1 design (`amr/docs/amr_mg_core_boundary.md` §3) by reading the
code. `mac_cutcell_mg.hpp:513–517` documents the constraint — *"For a weighted dec0 the
coarse-level transfer is only clean when `nLevels==1` (pure RB-GS) — use that (or the
decomposition-agnostic GraphAMG) for a weighted co-decomposition"* — but **nothing enforces it**
(no throw, no warning). A weighted level-0 block is generally not even, so `blocked` is true at
L = 0, the telescope fires there, and the depth search (`mac_cutcell_mg.hpp:751–770`) walks down
for a depth whose blocks are even on every coarsenable axis; *"depth 0 (one block …) always
qualifies"*. What the search really selects is the **shallowest ORB-tree depth that has an odd
split**, so `d = 0` whenever the **root** split lands on an odd plane — by parity alone roughly half of all weight
fields, and at large `np` the shallowest odd split is almost surely within the top few depths (that
last sentence is reasoning, not measured).

*Measured* (flow `main` 8789e2b, host-openmp MPI build, probe
`flow/tests/study/weighted_dec0_telescope_probe.py` + raw logs in `weighted_dec0_results/`, on
flow `0ae29d6` on main, `tests/study/weighted_dec0_telescope_probe.py` + `weighted_dec0_results/`): 96³, periodic 2³ sphere array, cut-cell pressure,
default telescope + `auto` bottom, `rebalance_by_weights(1 + Poisson(4) counts in a bed)` —
exactly what `CfdDem.rebalance(gamma=1)` builds. Ladder from flow's own `[mg]` print
(`PECLET_FLOW_MG_DEBUG=1`, trace only). Before: every case telescopes only at the 6³→3³ bottom
(levels 8) or not at all (levels 4). After:

| bed | np | levels | weighted blocks | ladder after | iters | projection s (max rank) | momentum s |
|---|---|---|---|---|---|---|---|
| heap (tilt 0.5) | 8 | 8 | odd x,y,z (root split x = 45) | **L0 → TELESCOPE, L1–L5 on 1 rank (`d = 0`)** | 8 → 8 | 0.080 → 0.180 | 0.079 → 0.100 |
| heap | 8 | 4 (default) | same | **L0 → 1 rank (`d = 0`)** | 8 → 8 | 0.068 → 0.175 | 0.062 → 0.099 |
| heap | 4 | 8 | odd x,y (root 45) | **L0 → 1 rank (`d = 0`)** | 8 → 8 | 0.167 → 0.241 | 0.166 → 0.173 |
| heap | 4 | 4 | same | **L0 → 1 rank (`d = 0`)** | 8 → 8 | 0.172 → 0.245 | 0.167 → 0.173 |
| flat bed | 8 | 8 | only z odd (x,y stay 48) | L0 → 4 ranks (`d = 2`), then 1 rank below 6³ | 8 → 8 | 0.064 → 0.099 | 0.062 → 0.085 |
| heap (tilt 0.3, seed 11) | 8 | 8 | z odd; x,y at 46 | L0 → 4 ranks, **L1 (23-wide) → 1 rank** | 8 → 8 | 0.079 → 0.111 | 0.079 → 0.088 |
| heap (tilt 0.3, seed 11) | 4 | 8 | all even (46/50) | **L1 (23-wide) → 1 rank** | 8 → 8 | 0.166 → 0.168 | 0.166 → 0.153 |
| flat bed | 4 | 8 | unchanged (np=4 never splits z) | unchanged — null | 8 → 8 | 0.167 → 0.166 | 0.166 → 0.160 |

So the signature (`d = 0` at L0, the root rank receiving the whole 96³ level-0 residual every
V-cycle) appears at both np = 4 and np = 8, at the default depth 4 and at depth 8. The
qualification: it is not always L0 and not always `d = 0` — when the top splits happen to land even,
the collapse is to `2^d` ranks, or it lands one level lower (46 → 23), which is cheap at this size.
**Iterations never change** (8/step throughout): the collapsed hierarchy is the same hierarchy on
one rank, so the cost is time, not convergence — projection ×2.25–2.6 at np = 8 while momentum,
which feels only the (up to 1.8×) cell imbalance a flow-only weighted partition has, rose ×1.27–1.6.
**The two documented escapes do not escape**: the GraphAMG bottom
(`set_pressure_graph_amg(True)`) is what `auto` already runs at 12³ and leaves the L0 telescope
untouched (np = 8: identical ladder, projection 0.085 → 0.218 s); `nLevels = 1` avoids the
telescope but with `auto` it hands the whole 96³ grid to the redundant GraphAMG on every rank (9 s
per step before and after, ~55× slower), and with `set_pressure_bottom("smoother")` it is pure
RB-GS at 29 iterations/step, 0.211 → 0.306 s projection at np = 8 — slower than the collapsed
telescope it was meant to replace. Not measured: np ≥ 16, GPU, a coupled `CfdDem` run (the flow-only
path is the same call), or anything beyond 5 steps.

**Reachable through a shipped public API, not hypothetically.** `CfdDem.rebalance(gamma)`
(`coupling/python/peclet_coupling/driver.py:683–707`) builds a weighted ORB from the coupled
weights and calls `diagnostics.rebalance_by_weights(w)`, which migrates and rebuilds `flow` on it —
the driver's own comment at :291 says *"default equal-cell ORB flow's init_mpi built; rebalance()
overwrites it"*. So any coupled run that rebalances puts `flow`'s pressure multigrid on a weighted
level 0, which is the unguarded combination above. `flow` and `dem` share one `BlockDecomposer` by
settled decision, so this is the intended CFD-DEM path, not a misuse. The two fixes are independent and both wanted: an **aligned**
weighted ORB (split planes on multiples of `2^a`; `coarsenAlignment` at
`mac_cutcell_mg.hpp:524` already computes the unweighted analogue, and at flow's granularity
`a = 1–2` costs a few per cent imbalance at 1536 ranks), and a **repartition** telescope kind that
moves a level onto a fresh proportional ORB on fewer ranks instead of collapsing to one block.
The confirmation this paragraph asked for is the measurement above (`PECLET_FLOW_TELESCOPE` no
longer exists — telescoping is a setter since QUALITY_PLAN D3; the ladder trace is
`PECLET_FLOW_MG_DEBUG=1`).

**FIXED IN PART, 2026-09-24 (flow `d907c57`, on the core stage machinery S4 moved the telescope
onto).** After `rebalance_by_weights` the pressure MG now takes a **Repartition** stage where the
sibling merge would collapse a level larger than one level-0 block onto fewer ranks: the level moves
onto a proportional ORB of its own grid on `np_L` ranks (`[mg]` trace `-> REPARTITION`). Same bits
as the collapse (the coarse arithmetic is pointwise), iterations unchanged. Measured on the probe
above, pinned, median of 5: projection ÷ momentum after the rebalance 1.87 → 1.05 (np = 8, depth 8),
1.77 → 1.09 (np = 8, depth 4), 1.58 → 1.10 (np = 4, depth 8), against 0.97–1.04 unweighted; in a
coupled `CfdDem` run 0.69 → 0.37 (np = 8; 0.34 unweighted). Runs that never rebalance are
byte-identical. **Still open:** the ALIGNED weighted ORB (split planes on multiples of 2^a), which
brings every row to ≤ 1.15× by itself and moves the first stage to level a, is built and measured
(flow branch `s5-aligned-rebalance`) but not landed — dem's `migrate_to_weights` must build the same
partition from the same weights and has no way to yet. The two escapes the source comment used to
recommend (`nLevels = 1`, the GraphAMG bottom) are corrected there. Not measured: np ≥ 16, GPU.
Full record: `amr/docs/amr_mg_core_boundary.md` §11.9.

**P0 answered (2026-09-02).** The anchored-bottom half is real: single-phase np=384 with the
agglomerated bottom *forced* on the inlet/outlet path went **24.9 → 10.9 iterations, 2.48 → 1.88
s/step, with the floor improving 2.1e-9 → 3.4e-10** — the §2.7 degradation did not appear here.
So open problem 4's gate costs ~24 % at 384 ranks on this case and should be revisited. (Both
np=1536 probes hung in warmup — issue 4 — and were cancelled.) Note its P0: two single-rung
reruns should come before any code, because the single-phase case runs an *anchored* operator and so
takes the **smoothed** bottom on a 48-across coarsest grid (`auto` is gated to the singular path),
while the packed case takes the redundant gather. Part of this issue's headline may be the bottom
rather than the depth, and that changes which fix is urgent.

## 3. Solid intersecting an OPEN domain face stalls the pressure solve — FIXED 2026-09-16

> **Two defects, and they had to be fixed together.** (a) The SDF ghost band outside a
> **non-periodic** domain face was filled by PERIODIC WRAP — only free-slip faces were repaired —
> so the boundary-face aperture was teleported from the opposite side of the domain. A solid cell
> against the inlet was handed the far side's fluid, its inflow face came out fully OPEN, and the
> prescribed inflow was counted into a cell whose pressure row is entirely closed: an
> **inconsistent row**, which no Krylov driver and no MG depth can solve — hence the iteration cap,
> `max|div|` stuck at the inflow velocity, and the NaN at shallow depth. (b) A Dirichlet (outflow)
> row carried the literal openness 1.0 instead of the face's own cut-cell aperture, so with a solid
> cutting the outlet the operator disagreed with the divergence constraint by `(1 - aperture)` and
> **the projection pushed mass out through solid** — silently wrong, and invisible until (a) was
> fixed, because the wrapped ghost made the aperture come out ≈ 1 too.
>
> A THIRD defect surfaced while gating the fix distributed, and is the same shape as (b): ghost
> indices along an axis are `0..g-1` and `ext-g..ext-1`, so the LOW domain face of an axis is an
> inner index but the HIGH one is a ghost index — and the halo exchange wraps periodically on every
> axis, so on a rank owning that global face the openness came back carrying **the opposite
> boundary's aperture**. `divergOpen` weights the last cell's outgoing flux by exactly that value,
> so the constraint was wrong too. Invisible until (b), which used to overwrite the plane with 1.0.
> Measured at **np = 1**: the outlet-cut bed differed from single-rank by 1.8e-02 and the inlet-cut
> bed by 6.6e-01; after `buildOpennessHighFace` re-derives that plane, 0.00e+00 on all four beds.
> The same wrap hits `fillVelGhostsTo(..., doOutflow = false)`, whose entire point is to preserve
> the mass-conserving outflow face the projection wrote, and which is also repaired — see **issue
> 8**, where the evidence for that half lives. The two halves are not separable: once the outlet's
> OPENNESS is the outlet's own aperture, it no longer pairs with an outlet VELOCITY that is still
> the inlet's, and `vof_bc_mpi`'s composed conservation budget breaks from 1.3e-14 to 2.5e-02. They
> used to wrap together and stay mutually consistent while both were wrong about the geometry.
>
> Fixes, in `flow`: `extendSdfDomainGhosts` extends the SDF constant out of every non-periodic
> face (type 4 keeps its mirror); the Dirichlet row carries the aperture through the WO-R2 item 1
> save/restore/coarsen machinery, in the constant-density, variable-density and porous coefficient
> paths alike (`set_outflow_operator_coefficient(False)` ablates back to the literal 1.0). Geometry
> that genuinely SEALS fluid cells against an inlet — a row that is closed yet fed, which no
> pressure field satisfies — is now **rejected by `set_solid` with a named error** rather than
> stalled on. Measured, 32×16×16 duct, projected `max|div|`: inlet-cut bed 200 iters / 1.0 →
> 14 iters / 6.1e-09; a bed clear of the open faces byte-identical. The outlet-cut bed *converged*
> before the fix (1.6e-09) — the wrapped ghost handed it an aperture of ~1 and the Dirichlet row
> also said 1, so operator and constraint agreed while both were wrong about the geometry, and the
> mass they conserved was leaving through solid; ablate (b) with the honest aperture in place and it
> reads 6.7e-03, plateaued. Mechanism, numbers and the diagnostic trap:
> **`flow/doc/cutcell_openbc_convergence.md`**.
>
> **The gap it sat in is closed too**: `flow/tests/kokkos/test_openbc_solid.cpp` and
> `flow/tests/kokkos_mpi/test_openbc_solid_mpi.cpp` (np 1/2/4) are the first tests anywhere to call
> `setDomainBc` together with `setSolid` with the solid ON an open face.
>
> The analysis below stands as the record of what was measured before the cause was known.


**Corrected from the original write-up, which called this a blocker and was wrong.** It was found
with a bed whose spheres were *clipped by the inlet and outlet planes* — an artifact of how that bed
was built, not a property of the configuration. With the spheres whole and clear of the open faces —
which is what FoxBerry's case actually specifies — the identical configuration converges, and Case 3
turned out to be reproducible after all.

The real defect is narrower: when solid **cuts** an inflow/outflow face, the cut-cell solve caps and
its divergence sits orders too high. Measured A/B at 128³, everything identical but the bed:

| bed | pressure iters | capped | final `max｜div｜` |
|---|---|---|---|
| whole spheres inside the region | **32.7** | none | 9.6e-05 → **1.95e-06** over 42 steps |
| spheres clipped by the inlet/outlet | 260.8 | 5 of 6 steps | 4.0e-03 |

Still worth fixing — a partially blocked inlet is a reasonable thing to want — but it is a narrow
correctness bug rather than something blocking mainstream use. It may even be legitimate to *reject*
the configuration with a clear error; that should be a decision, not the current silent stall.
Suspected mechanism, minimal-reproducer plan and the wider gap it sits in (nothing anywhere combines
`setDomainBc` with `setSolid`): **`flow/doc/cutcell_openbc_convergence.md`**.

*The methodological lesson is the more valuable output here:* an A/B is only as good as its claim
that A and B differ in one thing. The bed was doing double duty as "the geometry" and as "the thing
that touches the boundary", and conflating those produced a confident, wrong, top-priority finding.

## 4. Intermittent hang in the first warmup step at multi-node scale — ROOT-CAUSED, FIXED (was MEDIUM; actually HIGH, silently wrong)

**What it was.** Not transport. A race between consecutive NBX consensus rounds on one
communicator in `core`'s `NbxEngine`: rounds shared a tag, and a rank that has already observed
round *k*'s `Ibarrier` complete posts round *k+1*'s `Issend`s while a neighbour still draining
round *k* probes `MPI_ANY_SOURCE` on that tag and receives the new message as an old one. Hoefler
et al.'s NBX paper (§4) says consecutive invocations need distinct tags for exactly this reason.
`GridHaloTopology::buildTopology` runs one round per multigrid level, back to back, and a level's
topology is built from both sides asymmetrically: the *recv* side is computed locally from
`ownerOf`, the *send* side is learned from the round — so a swallowed request leaves a rank that
never learns it must send. Larger communicators mean larger barrier-completion skew, which is why
it appeared at ≥ 4 nodes and was intermittent.

**How it was found.** A stack census (parallel gdb over all 192 ranks of a node, `snellius/
stack_census.sh`) showed 178 ranks in the telescope `Scatterv` and the 8 group roots in
`GridHalo::exchangeEnd` — so the hang was in the 64-rank sub-hierarchy, in the *first* exchange on
a fresh topology. A halo timeout diagnostic (`PECLET_CORE_HALO_TIMEOUT=<s>`, `core daf6881`) that
names every pending request then gave the smoking gun on a 1536-rank run: level 5 on 64 ranks,
**26 recv partners on every rank, send partners 26 / 24 / 16 / 12 / 10 / 8 / 6 / 0**, every
pending request a RECV whose sender never learned of it.

**Why it is worse than a hang.** When the leaked message is instead matched by a *later* receive
of the same source pair (the halo exchanges all use tag 0), the run need not hang: it would carry
wrong ghost values on one coarse level. *This face was not observed* — an apparent instance at 768
ranks turned out to be a settings drift (7 multigrid levels and 2 warm-up steps instead of the
ladder's 8 and 5, reproduced to seven digits by a clean run at 1536 ranks with the same settings).
The seven-digit agreement of `<u>` / `max|div|` across rank counts is the acceptance test that
would catch it.

**Fix (core `10294e6`).** `NbxEngine::exchange` sends on `baseTag + round % 64` with the round
counter held as an MPI attribute of the communicator (lives and dies with it; a handle-keyed map
would confuse a freed handle with its reuse on another rank). `buildTopology` now cross-checks
promised against requested cells with one allreduce and **throws** on a mismatch, so this class
of defect fails at build time with a message instead of hanging. Gate:
`core/tests/test_nbx_rounds.cpp` — 300 back-to-back rounds plus interleaved world /
sub-communicator rounds; with the rotation ablated it fails on a laptop (np=8: 62 wrong-round
messages), with it 0. Every NBX consumer (particle migration, ghost gathers, redistribution, the
AMR octree exchanges) inherits the fix.

**Follow-ups.** (a) The same *shape* of race exists for any tag-0 point-to-point exchange that
follows an NBX round on the same communicator; the rotation keeps NBX tags in `[base, base+64)`
and the halo uses tag 0, so they cannot collide, but a new caller passing a small `baseTag` could.
(b) The old stack-census guess ("transport behaviour, UCX") was wrong and is retracted; the
`ob1` and 16×96 discriminators were both consistent with the real cause (the race is
transport-independent and sensitive to skew, not rank density).

## 5. The momentum solve — was the LARGEST cost on the packed case; FIXED 2026-09-02 (two ways)

**Measured 2026-09-02, packed bed with FoxBerry BCs, 384 ranks, telescoped pressure MG:** momentum
4.55 s of a 7.28 s step (63 %), projection 2.55 s. Once telescoping flattens the pressure iteration
count, the RB-GS momentum solve at ν·dt/dx² ≈ 3.8e4 is what the step is made of, and it **hits
its sweep cap on every step** (600 = 3 × 200).

**What it actually was — the stopping rule, not the smoother.** The update criterion stops when
max|Δu| ≤ rtol × the *first sweep's* update. On a warm-started near-steady step the first update
is already noise (measured at 96³: the update-stopped RB-GS and an RB-GS run 25× longer agree to
1e-14 — both are the same stalled iteration), so the rule demands a 10³ reduction of noise and
the cap is the only exit. The fix is a **residual-based stop**, `set_velocity_residual_tolerance
(rtol)`: max|b − A u| ≤ rtol · max(max|b|, max|A u|) over the solved unknowns (flow `d6b3eb5`;
the forcing can enter through the inflow *ghost* rather than `b`, hence the scale, and the held
inflow face is imposed, not solved, hence excluded). Measured at 96³ on the bed, 3 steps:

| solver | stop | sweeps or cycles / step | momentum s/step | rel. error vs converged |
|---|---|---:|---:|---:|
| RB-GS | update 1e-3 (production) | 468 | 0.47 | 1.2e-5 (stalled, lucky) |
| RB-GS | residual 1e-3 | 24 | **0.05** | 9.8e-4 |
| RB-GS | residual 1e-5 | 51 | 0.10 | 1.2e-5 |
| mixed V-cycle, 2–5 levels | residual 1e-3 | 4.7 | 0.13 | 2.7e-4 |
| mixed V-cycle, 2–5 levels | residual 1e-5 | 7.7 | 0.18 | 1.2e-5 |

**The velocity multigrid now runs under MPI** (`VelocityMG::initMpi(dec, …)` on the solver's
decomposition, coarsened in place), with a new **mixed operator** for a solid WITH domain BCs
(`setStaircaseBc`: unfolded cut-cell stencil + solid pin + clean-fluid/held-face exclude at level
0; staircase Helmholtz + upwind advection + domain-face folds on the coarse levels). Gate
`test_velocitymg_bc_mpi` (np 1/2/4, bit-exact distributed, V-cycle == RB-GS fixed point to 4e-9).
Two traps it cost: (i) the RHS treatment and the advection scheme are decided by `bcStencilPath()`
/ `implicitAdv()`, which used to flip with `useVelocityMg_` — turning the MG on silently switched
to *explicit* advection, and two solves converged to 1e-11 residual sat 3e-4 apart; with the same
stencil they agree to 2e-11. (ii) Level 0 is the *unfolded* stencil, so its ghosts are reflections
(`fold=0`), not the folded operator's zeros — with `fold=1` the V-cycle diverges.

**Depth does not matter on a pore-confined bed** (2, 3 and 5 levels identical): the coarse grid
serves only the clean fluid interior and the smoother owns the band, so **the velocity hierarchy
does not need telescoping** where the pressure one did.

**At scale (Snellius genoa, 384³, residual stop 1e-5, telescoped pressure MG):** packed bed
7.28 / 3.24 / 1.33 s/step (capped RB-GS) → **3.32 / 1.48 / 0.834** with the velocity MG and
2.91 / – / 0.844 with RB-GS + residual stop at 384 / 768 / 1536 ranks (8.3× / 8.1× / 6.5×
FoxBerry); single-phase 2.01 / 0.768 / 0.656 → **0.930 / 0.430 / 0.391** (22.7× / 24.6× / 13.0×).
Pressure iterations and `<u>` / `max|div|` unchanged to seven digits. The two momentum solvers tie
at 384 ranks; the V-cycle's fewer halo exchanges win at 1536. rtol 1e-3 is too loose: the
momentum residual it leaves (8e-4) costs the pressure solve 14 → 30 iterations single-phase.

**Closed the same day (flow `c600d79` and after, user decisions):** the residual stop is the
DEFAULT, and its tolerance **follows the pressure solver's rtol** (the projection consumes u* and
resolves the divergence the momentum residual leaves to its own tolerance — the self-consistent
rule; `set_velocity_residual_tolerance(x)` fixes it, `0` restores the update criterion; a round-off
floor and a one-sweep minimum guard the exact cases), the constant-coefficient
domain-BC smoother has its residual (`diffResidual`) so RB-GS covers that path too, and an AUTO
rule picks the 3-level V-cycle under MPI below `PECLET_FLOW_VMG_AUTO_CELLS` = 65536 cells/rank
(the measured crossover). At least one sweep / V-cycle always runs: an early return on a converged warm start left u*
without the O(rtol) momentum response and the hydrostatic acid test (`vardensity_mpi`) drifted
by 1e-8 in dP/dz (bisected; flow `327faf3`). The single-GPU regression suite is identical to its baseline on the coupled default (metrics
+0.00 %, pressure iterations and step counts equal); a fixed 1e-5 had cost steady-state cases 5–20 %
more steps to meet their convergence check. **Still open:** (c) a
max-residual relative to the row scale pins the
solution only to ~rtol × 5·10⁴ on this operator (μ/Δx² against ρ/Δt); 1e-5 is what the ladder
validated (`<u>`/`max|div|` to seven digits, pressure iterations unchanged). (d) A Chebyshev
*momentum* solver was considered and not built: at 1536 ranks the momentum phase is 0.07–0.15 s of
a 0.83 s step; the projection (16 ms per pressure iteration at 37 k cells/rank, latency) is where a
communication-light driver has leverage. **Measured with the existing Chebyshev pressure driver at
1536 ranks, on the SAME node set as a PCG control:** single-phase 0.251 vs 0.256 s/step (14
iterations either way — no gain: the two all-reduces per PCG iteration are not on the critical
path), packed bed **4.18 vs 0.79 s** (238 iterations against PCG's 40: the cut-cell operator's
spectrum is not the one Chebyshev's interval assumes). Not worth switching on this hardware. The
control mattered: a PCG run on a different node set had measured 0.391 s, so a naive A/B would
have credited Chebyshev with a 36 % win that was **node placement** — at 1536 ranks the same
configuration varies by up to 1.5× between allocations, and every top-rung comparison needs a
same-allocation control.

## 6. `check_decomposition.py` is unusable above ~100 ranks — LOW (tooling)

The pre-flight tool is a pure function of (ranks, grid, levels) and needs no hardware, which is its
whole point — but it takes minutes per rank count above ~100 and several combinations simply timed
out or errored during this campaign, so the np=768 and np=1536 partitions could not be checked
before submitting. Given that issue 3 makes the partition the dominant performance variable, this
tool should be fast enough to sweep the whole ladder in one call.

## 7. Kokkos oversubscribes inside a CPU-quota container — RESOLVED 2026-09-16 (added 2026-09-12)

**Reported by the user**: the published quick start "takes forever" on Colab. It is neither the
solver nor the install — all five wheels together are 5.7 MB.

Kokkos sizes its OpenMP pool from the CPUs it can **see**. A container normally shows the whole
host while granting a fraction of it through a cgroup *quota*, and a quota is invisible to OpenMP:
`omp_get_max_threads()` returns the host count, the pool spin-waits at every barrier, and the run
collapses. Note that an affinity **mask** (`taskset`) does not reproduce this — OpenMP honours a
mask and sizes itself correctly. The quota is the trap, and it is the shape Colab actually has.

Measured on this workstation, same wheel, same 42-step quick start (N = 48):

| CPUs visible | budget | `OMP_NUM_THREADS` | time |
|---|---|---|---|
| 2 (affinity) | 2 | unset | 25.7 s |
| 2 (affinity) | 2 | 2 | 25.7 s |
| 48 | **2 (cgroup quota)** | unset | **did not finish in 15 min** |
| 48 | 2 (cgroup quota) | **2** | **26.0 s** |

So: ≥35x, unbounded, and silent. It is the same failure the suite already records for an unbounded
pool on a 48-core host (`CLAUDE.md`, "a measured hour-long trap") — but a container user meets it on
their first run, with no way to know.

Re-measured 2026-09-13 against the **retuned** quick start (N = 32, 14 steps, 2.5 s with the pool
bounded): unbounded under the same 2-CPU quota it again **did not finish in 15 minutes**, so there
the collapse is ≥360x. Shrinking the problem does not shrink the trap — it deepens it, because the
barrier count per unit of work is what the spinning pool taxes. From the same session, the other
half of the shape: an *affinity* oversubscription of 2 threads on 1 CPU costs 12 % against 1 thread
on 1 CPU, and 4 threads on 2 CPUs cost 35 %. This is a large-ratio failure, not a cliff you fall off
at the first thread too many.

**Done:** the Colab notebook's bootstrap cell now reads the real budget out of
`/sys/fs/cgroup/cpu.max` (v1 fallback, then `sched_getaffinity`) and sets `OMP_NUM_THREADS` and
`OMP_PROC_BIND` before peclet is imported; `README.md` and `docs/index.md` carry the warning with
these numbers.

**Decided 2026-09-13 (user): fix it in the library.** `core/include/peclet/core/common/cpu_budget.hpp`
resolves the process's own cgroup from `/proc/self/cgroup` and walks UP, taking the tightest quota on
the chain (v2 `cpu.max`, v1's cfs pair), capped by the affinity mask; `python::install()` — the one
Kokkos init shared by flow, dem, voro, pnm, coupling and amr — passes it through
`InitializationSettings`. Verified against a real cgroup (`systemd-run -p CPUQuota=200%`, 48 CPUs
visible):

| condition | affinity | usable | threads requested |
|---|---|---|---|
| unconstrained | 48 | 48 | **0 — says nothing** |
| 2 CPUs of quota | 48 | **2** | **2** |
| 2 CPUs of quota + `OMP_NUM_THREADS=7` | 48 | 2 | **0 — the user's choice stands** |

Inert on a workstation by construction: same thread count, same schedule, same numbers. **Reaching
users needs a 1.0.1 patch release** of every Kokkos-initialising package — the fix lives inside the
compiled modules.

A caution the fix itself turned up: reading `/sys/fs/cgroup/cpu.max` directly (the obvious
one-liner, and what the notebook first shipped) is right only by accident. That path is the cgroup
ROOT; on a systemd host it reads `max` while the real limit sits on the process's scope below, and
it appears to work in a container solely because a container has its own cgroup namespace.

### Verified end-to-end and CLOSED, 2026-09-16

The table above is the *unit* answer — what the library asks for. What follows is the failure itself,
reproduced and then not reproduced, from a **built module** under a real `systemd-run --user -p
CPUQuota=200% --scope` cgroup on this 48-CPU workstation: `flow` compiled fresh against current
`core` (OpenMP host prefix, worktree `flow-quota-verify`), running the published README quick start
at its shipped `N = 32`. This is `main`, not the 1.0.1 wheel — it converges in 10 steps where the
wheel takes 14, because the momentum-solver work landed since — so compare rows *within* this table,
and see the shipped-wheel numbers further down for the user-facing figure.

| # | CPUs visible | budget | `OMP_NUM_THREADS` | host pool | solve | `u_mean` |
|---|---|---|---|---|---|---|
| A | 48 | 48 | unset | 48 | 1.32–1.57 s | `1.2410234213313371` |
| B | 48 | **2 (cgroup quota)** | unset | **2** | **0.66 s** | `1.2410234213313376` |
| C | 48 | 2 (cgroup quota) | unset, **budget defeated** (`KOKKOS_NUM_THREADS=48`) | 48 | **killed at the 600 s cap** | — |
| F | 48 | 2 (cgroup quota) | **7** | 7 | 3.08 s | `1.2410234213313374` |
| G | 48 | 2 (cgroup quota) | 2 (the documented manual workaround) | 2 | 0.72 s | `1.2410234213313376` |

Read B against C: **the same binary, the same quota, the same script — 0.66 s with the budget, and
still unfinished after 600 s without it**, i.e. ≥ 900x. C is a faithful stand-in for a pre-fix
module and not a contrivance: an isolated probe of the one line `install()` changes shows
`Kokkos::initialize()` (core `v1.0.0`) building a **48-thread** pool under that 2-CPU quota, which is
exactly the pool `KOKKOS_NUM_THREADS=48` builds. Read G against B: the automatic budget reproduces
what the README currently tells the user to do by hand. Read F: the library stays silent when the
user has spoken, even when the user is wrong — 7 threads on 2 CPUs is 4.7x slower than the budget,
and it is still their call.

**Inert unconstrained, measured rather than asserted.** Three runs with the fix active (it requests
nothing) and three with it bypassed entirely gave the same 48-thread pool, the same step count, and
`u_mean` **bit-identical to the last digit** — `1.2410234213313371` six times out of six. (The
last-digit differences in the table are between *different thread counts*, i.e. reduction order, and
appear identically in B and G, which differ only in how the pool got its size.)

**The mask is still not the trap**, re-confirmed: under `taskset -c 0,1` the pre-fix init already
builds a 2-thread pool, and the library correctly says nothing.

### It has already shipped — the crux, settled

`core` is header-only, so the fix is *compiled into* each consumer and reaches a user only when that
consumer is built against a `core` that carries it. A release that tags `core` and forgets the repin
ships a fix that does nothing, so this was checked rather than assumed — and the chain is complete at
every link:

1. The fix landed in core `640c511`…`967b221` and is inside the **pushed tag `v1.0.1`**; it is absent
   from `v1.0.0`, whose `install()` calls a bare `Kokkos::initialize()`.
2. Every consumer's `cmake/PecletDeps.cmake` already moved `PECLET_CORE_TAG v1.0.0 → v1.0.1`, in its
   own 1.0.1 release commit — verified *at the tag* for flow, dem, voro, pnm and coupling, and on
   `main` for amr (unreleased).
3. **peclet 1.0.1 is on PyPI for all seven packages**, so those wheels were built from the repinned
   source.

Point 3 was then confirmed against the artifact itself rather than inferred. Downloading
`peclet-flow==1.0.1` and `peclet-dem==1.0.1` from PyPI and counting the pool's OS threads
(`/proc/self/status`) across `import`, beside the July 2026 wheels still in the suite venv, which
predate the fix:

| module | Kokkos pool under 2 CPUs of quota | unconstrained |
|---|---|---|
| `peclet.flow` wheel, July 2026 (pre-fix `core`) | **48 — the defect** | 48 |
| **`peclet-flow` 1.0.1 from PyPI** | **2** | 48 |
| `peclet.dem` wheel, July 2026 (pre-fix `core`) | **48 — the defect** | 48 |
| **`peclet-dem` 1.0.1 from PyPI** | **2** | 48 |
| `flow` / `dem` built here against `core` `v1.0.1` | 2 | 48 |

And the quick start on the **published wheel**, unmodified, under the same 2-CPU quota with
`OMP_NUM_THREADS` unset: **2.51 s** — the 2.5 s the README advertises — against *did not finish in
fifteen minutes* on the 1.0.0 wheel. Unconstrained the same wheel gives 1.37 s and a `u_mean`
bit-identical to the quota run.

**So: nothing is owed to this issue by the 1.1.0 release.** No repin, no code, no rebuild beyond what
the release does anyway. Two consumers, one shared `install()`, the same result — which is the
argument for the policy living in `core` rather than being restated six times.

**A limit of the fix, found while measuring it.** `peclet.dem` imports numpy, and **numpy's own BLAS
pool is 48 threads under that same 2-CPU quota**, fix or no fix — peclet does not own it and cannot
size it. (Counted by importing numpy first and attributing only the delta: `peclet.dem` adds 47
threads pre-fix and 1 post-fix; numpy's 47 are there either way.) It is the milder half of the same
trap — a BLAS pool is not entered at every solver barrier, and the quick start above ran in 0.66 s
with it present — but it means the container advice is *narrowed* by the library fix, not retired by
it: `OMP_NUM_THREADS` bounded both pools, while the library bounds only Kokkos.

**One thing is still owed, and it is documentation only:** the `> [!WARNING]` block in
`README.md` and `docs/index.md` still tells the container user to set `OMP_NUM_THREADS` by hand
before importing peclet, and the Colab notebook's bootstrap cell still computes the budget itself.
As of the 1.0.1 wheels that is unnecessary *for peclet's own pool* — it is an override now, not a
workaround — but the numpy caveat above means the advice should be **rewritten, not deleted**, and
the notebook cell is harmless where it stands. This is a docs-site edit with no gate behind it; it
is listed here so it is not lost, and it blocks nothing.

Gates at closure: `core` `55/55` plain and `55/55` Kokkos (`OMP_NUM_THREADS=8 OMP_PROC_BIND=false`,
np 1–8). The decision is recorded in [decisions/core.md](decisions/core.md) — *"The host backend is
sized by the CPU BUDGET (cgroup quota ∧ affinity), not by the visible CPU count"*.


## Issues 1 and 2 compound — and that is the most important thing here

They are not independent, and the packed-bed ladder shows it. With the fp64 build (issue 1's fix)
the dense bed converges cleanly at 24…384 ranks — 52 → 82 iterations, `max|div|` ~1e-13, and
strong-scaling efficiency 100 → 69 %. At **1536 ranks it partially caps again even in fp64**:
the repeat hits the 200 cap outright and the first run averaged 122 with per-step counts swinging
63 → 133 → 67, and the step time *regresses* to 16.9 s against 6.19 s at 384 ranks — peclet goes
from 3.9× faster than FoxBerry to slower than it. Meanwhile np=384 reproduces to 5 % across two
runs (6.19 / 6.52 s, 81.7 iterations both times), so this is the rank count and not the draw.

The mechanism ties the two together: **issue 2 starves the hierarchy, which weakens the
preconditioner, which pushes a high-contrast problem back over issue 1's convergence threshold.**
The depth cap therefore does not merely cost iterations at a fixed rate — on a hard problem it can
cost convergence outright, and the cliff arrives suddenly. Two consequences:

- The packed ladder is only reportable to 384 ranks. That point is the *measured* strong-scaling
  limit of the IBM path on this problem, and it is a much lower ceiling than the single-phase
  case's.
- **Fixing issue 2 is worth more than its 33 % suggests.** On the single-phase case coarse-level
  redistribution buys efficiency; on the packed case it plausibly buys the ability to run at all
  above ~400 ranks. That argues for doing it before, or together with, generalising the
  double-diagonal — and for testing the fix on a dense bed, not on a clean single-phase problem
  where the hierarchy is not starved.

A cheap check that would sharpen this before any code is written: rerun the np=1536 packed rung with
`PRESSURE=cheby`. Chebyshev is the driver that survives high contrast in float (measured: 252
iterations where PCG capped), so if it also converges on the starved hierarchy, the cliff is the
preconditioner's indefiniteness rather than the depth per se.

---

## Environment traps (not peclet defects) — recorded in [SNELLIUS.md](SNELLIUS.md)

- **`--exclusive` does not grant the node's memory.** SLURM still caps at ~1792 MiB × ntasks, so a
  24-rank job on a 336 GiB genoa node gets ~43 GiB and is OOM-killed at 64M cells. Use
  `#SBATCH --mem=0`. Cost one wasted job before it was understood.
- **SURF's `sbatch` drops leading `VAR=x sbatch …` env vars**, silently running the default
  instead. Pass such choices as script arguments or via `--export=ALL,VAR=…`. Cost one wasted
  job — *after* the trap had already been written down, which is why the benchmark scripts now take
  the case list as a positional argument rather than relying on discipline.

## What the campaign also confirmed working

Worth stating, because the issues above are not the whole picture: the distributed solve is
bit-consistent (np=1 and np=4 agree to every digit on the same bed), the decomposition machinery
delivers imbalance 1.000 at every 384³ rung, per-iteration cost scales *super-linearly* to 1536
ranks, and peclet is **8.0–9.4× faster than FoxBerry on the single-phase case and 3.9–5.7× on the
packed bed** across the measured ladder. Issues 1 and 2 are what stand between that and matching
FoxBerry's scaling *shape* as well as beating its absolute time.

---

## 8. MPI: a non-periodic domain face's HIGH boundary plane is wrapped by the halo — FIXED 2026-09-16

Found while gating issue 3 distributed, and inseparable from it. The decomposition is periodic by
construction and the non-periodic conditions are imposed on top, so `GridHalo` wraps **every** axis.
The face-index convention makes the two ends of an axis asymmetric: the LOW domain face is an inner
index and survives an exchange, the HIGH one is the first ghost index and does not. Anything whose
high-side boundary plane matters therefore comes back carrying the opposite boundary's value on the
rank that owns that global face.

Two things depend on that plane, and **fixing either one alone makes things worse**, because they
used to wrap *together* and stay mutually consistent while both were wrong about the geometry:

- the cut-cell **openness** — `buildOpennessHighFace` re-derives it from the (already exchanged,
  already domain-extended) SDF after the exchange;
- the **outflow face velocity** — `fillVelGhostsTo(..., doOutflow = false)` exists precisely to keep
  the mass-conserving face the projection wrote (WO-R, gate F2: it has to reach the VoF advection),
  and the exchange inside it destroyed that face anyway. It now saves and restores the plane over
  the block's INNER transverse range; the plane's transverse ghost rows are legitimately the
  neighbour's inner values, which the exchange delivers correctly, so putting stale local values
  back over them would trade one wrong plane for another.

**Scope:** the velocity half is STAGGERED only, and on the collocated grid it is **unreachable**
rather than skipped — all three callers that pass `doOutflow = false` return or throw first
(`bridgeVelocityToVof` takes its own face-field branch, `buildVofCellVelocity` throws,
`maxOpenDivergenceProjectedInternal` delegates). The `!Grid::collocated` guard records that, so a
future caller on that path has to decide deliberately: there the correction lives on the FACE field
while `fillVelGhostsTo` fills the CELL field, whose `doOutflow = false` means "leave the whole ghost
BAND alone", and one restored layer of two would be a third behaviour.

The collocated VoF bridge *does* re-fill the face field's ghosts after the projection corrected the
outflow face, which looks like the same defect — but the advector's boundary flux does not read that
ghost index and the conservation identity closes at **1.1e-16**. Measured, not assumed, and now
gated: `test_vof_bc_mpi`'s `colo-jet` case checks `d Σ C = boundary ledger` on `SolverColocated`,
which had no open-boundary conservation gate of any kind. Nothing remains open on this issue.

*Measured, and the reason the rest is not filed as an open item:* `flow/tests/kokkos_mpi/test_vof_bc_mpi`
already drives a packing whose last sphere **cuts the +z outlet plane**, and gates the composed
conservation identity `d Σ(eps_eff C) = boundary ledger` absolutely. It read **1.25e-14** before any
of this, **2.46e-02** with the openness half fixed alone, and **2.89e-14** with both — at np = 1,
where there is no decomposition at all. Its three callers (the VoF velocity bridge, the VoF momentum
bridge, `max_open_divergence_projected`) are all covered by the one fix; the last of those returned
approximately the inlet velocity under MPI on every bed, converged or not.
