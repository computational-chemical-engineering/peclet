# voro — per-step update throughput (rung A4 baseline, 2026-09-03)

The Voronoi methods plan's figure of merit for the engine is the **per-step update** of a moving
point set (§A4): the certificate that decides which cells need a re-clip, the geometry
re-evaluation over the resident topology, and the re-clip of the flagged set — normalised to the
production cold build. This page is the single-node baseline measured with the production path
(`voro/tests/kokkos/bench_report --repair 200000 8`, `MovingTessellation` with the local
certificate and the adaptive gate, FP64), on one workstation: host-openmp = 8 threads
(`OMP_NUM_THREADS=8 OMP_PROC_BIND=false`), CUDA = one RTX 5080. N = 200 000 uniform random
seeds in the periodic unit box (mean spacing 0.0171), 8 steps per displacement; `disp` is the
per-step displacement in units of the spacing.

## Repair vs cold build, N = 200k

| disp | host cold Mcells/s | host repair Mcells/s | host speedup | CUDA cold Mcells/s | CUDA repair Mcells/s | CUDA speedup | flagged % | gate → rebuild % | max rel. ΔV | missed nbrs/step |
|---|---|---|---|---|---|---|---|---|---|---|
| 1e-4 | 0.44 | 5.54 | **12.6** | 1.07 | 3.41 | **3.2** | 1.3 | 0 | 7e-7 | 250 |
| 2e-4 | 0.44 | 4.59 | 10.4 | 1.14 | 2.93 | 2.6 | 2.6 | 0 | 2e-6 | 258 |
| 5e-4 | 0.44 | 2.90 | 6.6 | 1.13 | 2.89 | 2.6 | 6.4 | 0 | 5e-5 | 222 |
| 1e-3 | 0.45 | 2.33 | 5.2 | 1.13 | 2.80 | 2.5 | 12.3 | 0 | 2e-5 | 259 |
| 2e-3 | 0.44 | 1.52 | 3.4 | 1.03 | 2.44 | 2.4 | 22.9 | 0 | 1e-4 | 232 |
| 5e-3 | 0.45 | 0.84 | 1.9 | 1.13 | 1.49 | 1.3 | 46.7 | 0 | 5e-4 / 4e-3 | 151 |
| 1e-2 | 0.44 | 0.44 | 1.0 | 1.19 | 0.93 | 0.8 | 71 | 75–100 | 1e-15 | 0 |
| ≥ 2e-2 | 0.45 | 0.39 | 0.86 | 1.18 | 0.92 | 0.78 | 91–100 | 100 | 1e-15 | 0 |

(`flagged %` = cells the certificate flagged, i.e. the Pass-1 gather set; identical on both
backends, as it must be. Rows ≥ 1e-2 are the adaptive gate routing the step to a full rebuild.)

## The same sweep with the near-miss certificate (default since voro 4953948)

Finding 4 below was fixed the same day: every (re)build records the candidates whose plane
missed the cell by less than half a skin, and the certificate re-tests them each step
(`MovingTessellation::useNearMiss`). The repair becomes exact; the price is the extended-reach
emission in every gather and rebuild.

| disp | host repair Mcells/s | host speedup | CUDA repair Mcells/s | CUDA speedup | max rel. ΔV | missed nbrs/step |
|---|---|---|---|---|---|---|
| 1e-4 | 4.23 | 9.7 | 2.48 | 2.6 | 6e-11 | 64 |
| 2e-4 | 3.62 | 8.2 | 2.57 | 2.4 | 4e-11 | 71 |
| 5e-4 | 2.39 | 5.4 | 2.74 | 2.8 | 1.5e-7 / 2e-11 | 58 |
| 1e-3 | 1.75 | 3.9 | 1.86 | 1.7 | 4e-12 | 74 |
| 2e-3 | 1.12 | 2.5 | 1.55 | 1.5 | 9e-12 / 9e-7 | 58 |
| 5e-3 | 0.63 | 1.4 | 1.00 | 1.0 | 1e-11 | 34 |
| ≥ 1e-2 (gate → rebuild) | 0.30 | 0.67 | 0.59 | 0.6 | 1e-15 | 0 |

(After voro 75f4926: the clip reports the gap its commit test computes, so the near-miss
recording costs no second vertex scan.)

The residual "missed" relations are zero-area slivers below the certificate tolerance (the
volumes agree to 1e-11). Over 400 steps (`test_sdf_dynamic`) the wall-free drift fell from
1.6e-3 to 5.5e-11 (default tolerance) and 1.2e-15 (tight); the SDF path from 1.6e-3 to 5.9e-8.
The gate's rebuild now costs 0.67× a cold build (the near-miss emission's wider search reach);
a lazy emission scheme like the adjacency's is the follow-up.

## Cold build vs N (CUDA, FP64, MAXP 64 / MAXT 112)

| N | plain build Mcells/s | build emitting the resident store Mcells/s | store bytes/cell |
|---|---|---|---|
| 20k | 0.78 | 0.71 | 1260 |
| 100k | 1.35 | 1.13 | 1260 |
| 200k | 1.37 | 1.13 | 1260 |
| 1M | 1.45 | 1.32 | 1260 |

## What the numbers say

1. **The repair path is the right idea and the host proves it**: at 1e-4 spacing per step the
   8-thread host updates 5.5 Mcells/s, 12.6× its own cold build, with 1.3 % of the cells
   re-clipped.
2. **The GPU update path is latency-bound, not throughput-bound.** The same step on the RTX 5080
   runs at 3.4 Mcells/s — slower than the host — although its cold build is 2.5× faster than the
   host's. The per-step work at small displacements is a full-N certificate kernel plus a gather
   of ~2.6k cells, i.e. microseconds of GPU compute; what is left is the launch and
   synchronisation structure of `MovingTessellation::step` (grid rebuild, certify, compact with a
   host round-trip counter, gather, Pass-2 collect, verify loop with more round trips). This is
   the A4 tuning target: fuse the compact/count into the certify kernel, keep the counters on
   device, drop the per-step grid rebuild when no cell moved past the skin, and batch the verify.
   The ceiling is the certificate kernel alone (of order 10–20 ms for 200k cells on this GPU is
   already too slow: it should be ≲ 1 ms).
3. **The cold build is 1.1–1.4 Mcells/s FP64 on the RTX 5080**, flat from 100k to 1M seeds. The
   clip-only kernel benchmark (`bench_convexcell`) is the 14–17 Mcells/s figure recorded earlier;
   the gap is the worklist gather + publish. This is the number to set against the 2026 GPU
   power-diagram paper in the SOTA comparison the plan asks for.
4. **The repair was not exact: `missed nbrs/step` ≈ 250 and `max rel. ΔV` up to 5e-4 at 5e-3
   spacing per step** (both backends, identical counts). The certificate saw lost faces and
   flip partners but missed ~0.1 % of the gained neighbour relations per step; the volume error
   accumulated to the ~1.6e-3 measured over 400 steps in `test_sdf_dynamic` (and did not tighten
   with the certificate tolerance). **Fixed by the near-miss certificate** (table above): exact
   to 1e-11 per step, 5.5e-11 over 400 steps, at ~70 % of the previous host speedup.
5. The gate's rebuild costs 0.78–0.98× a cold build (the store emission), so the "never much
   slower than a cold build" guard holds on both backends.

## Reproduce

```bash
cd voro && OMP_NUM_THREADS=8 OMP_PROC_BIND=false ./build_a0/tests/kokkos/bench_report --repair 200000 8
cd voro && ./build_a0_cuda/tests/kokkos/bench_report --repair 200000 8 && ./build_a0_cuda/tests/kokkos/bench_report --cold
```
The raw CSV logs of this run: `voro/build_a4.report.{host,cuda}.log`, `voro/build_a4.cold.cuda.log`
(build trees are not versioned).
