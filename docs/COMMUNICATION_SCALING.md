# Communication scaling of the distributed IBM step

*Evidence from the porous-scaling campaign (Snellius gpu_h100, 2026-08; peclet-examples
`benchmarks/porous-scaling`) and the plan to close the gap. Companion to
[DECOMPOSITION_AND_MULTIGRID.md](DECOMPOSITION_AND_MULTIGRID.md), which governs *iteration
counts*; this note is about the **cost per iteration** under MPI.*

## 1. The observation

Weak scaling of the porous sphere-bed benchmark (cut-cell IBM, 256³ cells/GPU, 1→32 H100) is
markedly worse than the TGV parallel-scaling study or the turbulent-channel DNS on the same
machine: per-rank throughput drops 36 → 13 Mcell/s (≈35 % weak efficiency), where TGV holds
≈90 %. The per-phase timers in the campaign JSONs locate the loss precisely.

**What it is NOT:**

- Not the solver deteriorating: pressure iterations stay flat across the ladder (21–33/step),
  exactly as on one GPU. The multigrid + agglomerated bottom work as designed.
- Not per-cell cost: projection compute is 0.63 ns/cell/iteration in BOTH studies — the
  cut-cell operator costs the same per cell as the all-fluid one.
- Not the PCG dot products: total allreduce time at np=32 is 7 ms of a 1323 ms step. Chebyshev
  would buy ~0.5 %.

**What it IS — three multiplicative factors:**

1. **Iteration multiplicity.** The φ=0.5 cut-cell Poisson needs 21–33 MG-PCG iterations/step
   vs ~4 for the smooth periodic TGV; the Stokes momentum solve at dt=60 is similarly stiff
   (236 ms vs 49 ms at np=1). Communication happens per *smoother sweep per MG level*, not per
   step: one 7-level V-cycle ≈ 30 halo events, so a porous step fires **~700 halo events** vs
   ~130 for TGV. Each event carries fixed latency; coarse-level messages are pure latency.
2. **Amortization.** 16.8 M cells/GPU (porous) vs 46 M (TGV): each exchange is amortized over
   ~2.7× less compute. Halo cost ~ surface, compute ~ volume.
3. **Baseline.** Efficiency is measured against comm-free np=1. The toll is *fixed*, not
   growing: 8→32 GPUs is flat (13.5 → 12.7 Mcell/s/rank) — a machine-size-independent tax,
   which predicts ~13 Mcell/s/rank holds at 64+ GPUs too.

Corroborating detail: host-staged MPI beats GPU-aware UCX by 7 % at np=32 — the traffic is many
small latency-bound messages, the regime where GPU-aware per-message overhead loses.

Measured phase growth np=1 → np=32 (cut-cell): momentum 236 → 470 ms, projection 227 → 851 ms.
The ghost IBM is the same story times its own iteration count (76→160 iters/step, projection
1650 → 11 216 ms).

## 2. Work items

### 2.1 Fat blocks (measurement first — no solver change)

Attack factor 2 directly: the H100s have 94 GB; ~512³ = 134 M cells/GPU fits comfortably
(≈35–40 GB at ~35 doubles/cell incl. the MG hierarchy and IBM overlay). One ablation rung at
32 GPUs, 512³ cells/GPU (2048×2048×1024 = 4.3 G cells; the 4×4×2 split gives exactly cubic
512³ blocks at imbalance 1.000) quantifies how much of the gap is pure amortization before any
code changes. Implemented as the `fat` argument of
`benchmarks/porous-scaling/snellius/spheres_weak_gpu.sh` (cut-cell only — the ghost march is
unstable at large elongated rungs; packing runs on the CPU dem build per the H100 workaround).
Expectation: per-iteration halo surface grows 4× while compute grows 8× → the np=32 per-rank
throughput should recover substantially toward the np=1 number; whatever gap remains is latency
(factor 1), which the code items below attack.

### 2.2 Halo–compute overlap in the RB-GS sweeps (async computation) — DONE

`peclet::core::halo::GridHalo` is already overlap-capable (post/finish split). The sweep structure
is

```
post_exchange(color A results)
smooth interior (cells ≥1 from block boundary) of color B      // overlaps the wire
finish_exchange
smooth boundary shell of color B
```

The boundary shell reads exactly the same operand values as the blocking form, only later — the
update is **bit-identical** by construction, and the existing `tests/kokkos_mpi` bit-exactness
ctests (np=1,2,4 vs single-rank) are the acceptance gate, unchanged. Fine levels overlap well (the
interior dwarfs the shell); coarse levels have no interior to hide behind — they are factor-1
territory (below).

Status: the `CutcellMG`/`VelocityMG` per-level smoothers, the V-cycle residual and the level-0
matvec had this since flow `3ace962`/`5d77deb`/`d548ccc` (the note's original "call sites use it
synchronously" was stale for them); the remaining synchronous site — the implicit-diffusion RB-GS
of the momentum phase (`flow_ibm.hpp` `smoothComp`, the biggest single win: dozens of sweeps/step
on the Stokes march) — was overlapped in flow `1e9c5db`, on the periodic/IBM path (the domain-BC
paths keep the blocking order they depend on, mirroring the VelocityMG decision).

### 2.3 Communication-avoiding smoothing (wider ghosts, fewer events) — DONE

Attack factor 1's event count: exchange a **2-deep ghost layer once per red-black pair** instead
of 1-deep before every colour. Within a pair, the first colour redundantly re-smooths the 1-deep
ghost ring of the neighbour's cells it holds — computed from the same operands the neighbour uses,
so the ring values come out bit-identical to what a fresh exchange would deliver — and the second
colour then sweeps with **no exchange at all** (its boundary cells read only first-colour ring
cells; a colour never reads its own colour). Standard CA-smoothing with the RB ordering preserved
across the seam; the block's own cells are bit-identical to the exchange-every-sweep result.

Implemented (flow, second commit after `1e9c5db`), gated by `PECLET_FLOW_CA` (default ON, `=0`
kills it) and applied only where every rank's block extent is ≥ 4 (below that: per-colour
exchange). Halves the event count where it engages:

- **Momentum** (`flow_ibm.hpp` `smoothComp`, periodic/IBM path): the velocity block is g=2
  already, so no new topology. The ring rows of the float stencil + mask are halo-exchanged once
  per operator (re)build (per solve on the per-step-rebuild paths: implicit-FOU Picard, variable
  properties, implicit drag), the rhs once per solve — bit-exact owner values.
- **`CutcellMG` coarse levels** (L ≥ 1, where every message is pure latency): per-level ghost
  width is now a runtime `Level::g` — width-2 topologies (the `GridHaloTopology` width parameter)
  on eligible levels, and the rediscretized operator build box is widened by 1 so the ring rows
  are assembled locally from the exchanged openness (bit-identical to the owner's inner rows).
  Level 0 keeps g=1 (its exchange is already overlapped and the solver's g=1 bridge assumes it);
  domain-BC (non-periodic) hierarchies keep g=1 everywhere — byte-identical to the pre-CA code.
  A parity subtlety: with mixed ghost widths the red-black colour of a cell must be derived from a
  g-independent origin (`parityOg`), or the colours on g=2 levels come out swapped vs the g=1
  reference (3 axes → parity flips).

Numerics: bit-identical by construction; gate = the same `tests/kokkos_mpi` ctests (np=1,2,4,
CUDA + OpenMP, 33 tests) + `sdflow_regression.py` at +0.00 %, plus a trace-verified check that the
CA path actually engages (MG levels g=2 and momentum pairs active in the np=2 Stokes test, results
unchanged to the last printed digit with `PECLET_FLOW_CA=0/1`).

Order of implementation: 2.1 (script only, run now) → 2.2 (mechanical, bit-exact) → 2.3
(needs width-2 topologies + seam-ordering care). Expected combined effect at 256³/GPU:
2.2 hides most of the fine-level exchange time behind compute, 2.3 halves what remains plus
the coarse-level latency count; together with the flat 8→32 plateau this should lift np=32
weak efficiency from ~35 % into the 60–80 % band, with the fat-block rung telling us how much
was amortization all along.

## 3. Status

- [ ] 2.1 fat rung: script support merged; run pending (`sbatch --nodes=8 --time=01:30:00
      spheres_weak_gpu.sh fat`)
- [x] 2.2 overlap in flow_ibm diffusion (flow `1e9c5db`; the MG smoothers had it since `3ace962`)
- [x] 2.3 CA smoothing (width-2 ghosts, exchange once per RB pair; `PECLET_FLOW_CA`)
- [x] performance validation on Snellius (2026-08-18, peclet-examples `d139d2d`): np=32 cut-cell
      **1323 → 759 ms/step, 12.7 → 22.1 Mcell/s/GPU, weak efficiency 35 % → 62 %**; np=16
      14.8 → 23.6. Iterations and k/R² identical to every printed digit at every rung. The CA-off
      ablation (np=32, 13.8 Mcell/s/GPU) shows the gain is almost entirely 2.3's event-count
      halving — the latency diagnosis was right. Ghost IBM: np=16 6966 → 4281, np=32
      11689 → 6349 ms/step (its np≥16 march instability is unchanged, a separate open bug).
      Open oddity: the np=8 rungs' projection phase got *slower* under CA (cut-cell 342 → 465 ms;
      the step is still net faster) while np=16/32 improved — untraced.
- [ ] 2.1 fat rung result (`spheres_weak_gpu.sh fat overlap`) — still pending in the queue at
      the time of the ladder analysis
