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
| 2 | MG depth capped by the per-rank block | High (scaling shape) | **Fixed 2026-09-02** (telescoping, opt-in), measuring at scale |
| 3 | Solid intersecting an OPEN domain face stalls the solve | Medium, silently wrong (narrow) | Open, new |
| 4 | Intermittent multi-node hang in warmup | Medium (reliability) | Open, undiagnosed |
| 5 | Velocity multigrid is single-rank only | Medium (unverified impact) | Known restriction |
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

## 4. Intermittent hang in the first warmup step at multi-node scale — MEDIUM

Some multi-node runs hang in warmup and never emit another line, at full CPU on every rank (which
distinguishes nothing — OpenMPI busy-polls a blocked collective). Single-phase 384³ np=768 hung in
two independent 4-node allocations; 400³ np=1536 hung on 8 nodes; packed 384³ np=1536 hung once and
**ran normally on the retry**. That last point is what makes it intermittent rather than a property
of a rank count, and it cost two rungs of the ladder plus several node-hours.

**Stack dumps taken 2026-09-02** (`srun --jobid --overlap … gdb -p`, two nodes, five ranks each,
on an 8-node 1536-rank job without telescoping): **every sampled rank on every node is in
`MPI_Waitall` under `ompi_request_default_wait_all`**, i.e. a point-to-point halo exchange whose
completions never arrive, in the *first* step. Nobody is in a collective, nobody is elsewhere in
the solver. Four of four 8-node jobs hung today (float and fp64 builds, telescoping on and off,
different node sets); two 8-node jobs succeeded the day before. That is transport behaviour at
≥4 nodes with 192 ranks/node (OpenMPI 5.0.3 + UCX 1.16, `uct_mm` shared-memory progress visible
on the other threads), not a solver mismatch — a mismatch would put ranks in different places.
Discriminators submitted: `OMPI_MCA_pml=ob1` (UCX bypassed) and 16 nodes × 96 ranks (same
rank count, half the ranks per node). Failing that,
`PECLET_FLOW_AGGLOM_EXTENT=1000000` removes the agglomerated coarse solve's global `Allgatherv`
from every V-cycle, separating a coarse-solve collective from a halo one; and the host-staged halo
path isolates the exchange engine.

## 5. Velocity multigrid is single-rank only — now the LARGEST cost on the packed case

**Measured 2026-09-02, packed bed with FoxBerry BCs, 384 ranks, telescoped pressure MG:** momentum
4.55 s of a 7.28 s step (63 %), projection 2.55 s. Once telescoping flattens the pressure iteration
count, the RB-GS momentum solve at ν·dt/dx² ≈ 3.8e4 is what the step is made of. And it **hits its
sweep cap on every step**: 600 sweeps/step = 3 components × the 200-sweep cap, so the 1e-3
tolerance stop never engages — the momentum solve is under-converged as well as expensive (its
cost is then a fixed 600 sweeps × cells, which strong-scales perfectly but is where the absolute
time lives). A distributed velocity multigrid (`VelocityMG::initMpi` is what is missing) would
attack both at once; it is the next lever on this case now that the pressure side is flat.

`IbmSolver` never calls `VelocityMG::initMpi`, so under MPI the momentum solve is RB-GS with a
sweep cap and there is no alternative. This campaign did not measure whether that bit, but it is
worth checking here specifically: FoxBerry's packed case uses `u = 0.001`, giving `dt = 0.26` and
therefore **ν·dt/dx² ≈ 3.8e4** — an extremely stiff implicit diffusion for a point smoother, where
the single-phase case sits at ≈ 38. If the momentum solve is under-converged at the sweep cap, the
projection is chasing a moving target and some of issue 2's iteration growth may not be the
hierarchy at all. *Cheap check:* sweep `VSWEEPS` at fixed rank count and see whether the pressure
iteration count moves.

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
