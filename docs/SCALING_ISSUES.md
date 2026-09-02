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
| 1 | Float operator storage caps MG-PCG on dense beds | **High, silently invalid** | Known (WO-M), fix not defaulted |
| 2 | MG depth capped by the per-rank block | High (scaling shape) | **Fixed 2026-09-02** (telescoping, opt-in), **measured**: iterations flat 24 → 1536 ranks, ≥ 99 % efficiency on the bed |
| 3 | Solid intersecting an OPEN domain face stalls the solve | Medium, silently wrong (narrow) | Open, new |
| 4 | Intermittent multi-node hang in warmup | **High, silently wrong** (was: Medium) | **Root-caused and fixed 2026-09-02** (core `10294e6`): NBX inter-round tag race |
| 5 | Momentum solve: cap-bound RB-GS (update criterion) | High (63 % of the packed step) | **Fixed 2026-09-02**: residual stop + velocity MG under MPI (mixed operator); packed step 2.2× faster at 384–1536 ranks |
| 6 | `check_decomposition.py` unusable above ~100 ranks | Low (tooling) | Open |

---

## 1. Float operator storage caps MG-PCG on dense cut-cell beds — HIGH

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
generalisation — see `flow/doc/vof_workorders_v34.md` (WO-M).

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
open problem 1**; design, implementation and status: **[`MG_TELESCOPING_PLAN.md`](MG_TELESCOPING_PLAN.md)**.

**Measured at scale (2026-09-02, fp64 build, wall-confined bed with FoxBerry's inlet/outlet).**
Pressure iterations per step, telescoped: **43.1 / 42.9 / 41.7 / 39.8 / 39.8 / 39.8 / 39.8** at
24 / 48 / 96 / 192 / 384 / 768 / 1536 ranks (max 45 everywhere), step time 128.7 / 64.9 / 31.6 /
15.6 / 7.28 / 3.24 / 1.33 s — efficiency vs 24 ranks 100 / 99 / 102 / 103 / 110 / 124 / 151 %.
Single-phase (float build): 14.7 → 14.0 iterations flat, 34.8 → 0.656 s, 142 % at 768 and 83 % at
1536 (latency-bound momentum sweeps at 37 k cells/rank — issue 5's territory). A/B at 384 ranks: packed 49.9
iterations (max 69) / 10.8 s in place vs 39.8 / 7.28 s telescoped; single 24.9 / 2.48 s vs 14.0 /
2.01 s. At 24 ranks the two are identical (129.5 vs 128.7 s) — the hierarchy is already full depth
there. Every ladder bottoms at 3³ on one rank (384 → 8 → 1, 768 → 8 → 1, predicted 1536 → 64 → 1).
**What remains of this issue is policy, not mechanism**: telescoping is still opt-in
(`PECLET_FLOW_TELESCOPE=1`), the `MIN_EXTENT` default (4) is untuned, and the gather is
host-staged (fine on CPU; a device build would want a device-aware path).

**P0 answered (2026-09-02).** The anchored-bottom half is real: single-phase np=384 with the
agglomerated bottom *forced* on the inlet/outlet path went **24.9 → 10.9 iterations, 2.48 → 1.88
s/step, with the floor improving 2.1e-9 → 3.4e-10** — the §2.7 degradation did not appear here.
So open problem 4's gate costs ~24 % at 384 ranks on this case and should be revisited. (Both
np=1536 probes hung in warmup — issue 4 — and were cancelled.) Note its P0: two single-rung
reruns should come before any code, because the single-phase case runs an *anchored* operator and so
takes the **smoothed** bottom on a 48-across coarsest grid (`auto` is gated to the singular path),
while the packed case takes the redundant gather. Part of this issue's headline may be the bottom
rather than the depth, and that changes which fix is urgent.

## 3. Solid intersecting an OPEN domain face stalls the pressure solve — MEDIUM

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

**Closed the same day (flow `c600d79`, user decision):** the residual stop is the DEFAULT (1e-5;
`set_velocity_residual_tolerance(0)` restores the update criterion), the constant-coefficient
domain-BC smoother has its residual (`diffResidual`) so RB-GS covers that path too, and an AUTO
rule picks the 3-level V-cycle under MPI below `PECLET_FLOW_VMG_AUTO_CELLS` = 65536 cells/rank
(the measured crossover). The single-GPU regression suite passes on the default (metrics +0.00 %, pressure iterations/step
identical; steady-state cases need 5–20 % more steps to meet their convergence check, since the
over-converged update-criterion solve made the per-step drift smoother). **Still open:** (c) a
max-residual relative to the row scale pins the
solution only to ~rtol × 5·10⁴ on this operator (μ/Δx² against ρ/Δt); 1e-5 is what the ladder
validated (`<u>`/`max|div|` to seven digits, pressure iterations unchanged). (d) A Chebyshev
*momentum* solver was considered and not built: at 1536 ranks the momentum phase is 0.07–0.15 s of
a 0.83 s step; the projection (16 ms per pressure iteration at 37 k cells/rank, latency) is where a
communication-light driver has leverage. **Measured with the existing Chebyshev pressure driver at
1536 ranks:** single-phase **0.391 → 0.251 s/step** (14 iterations either way, the PCG's two
all-reduces per iteration were on the critical path; 20× FoxBerry), packed bed **0.834 → 4.18 s**
(238 iterations against PCG's 40: the cut-cell operator's spectrum is not the one Chebyshev's
interval assumes). A per-case choice, not a default; an automatic pick would need a spectrum
probe.

## 6. `check_decomposition.py` is unusable above ~100 ranks — LOW (tooling)

The pre-flight tool is a pure function of (ranks, grid, levels) and needs no hardware, which is its
whole point — but it takes minutes per rank count above ~100 and several combinations simply timed
out or errored during this campaign, so the np=768 and np=1536 partitions could not be checked
before submitting. Given that issue 3 makes the partition the dominant performance variable, this
tool should be fast enough to sweep the whole ladder in one call.

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
