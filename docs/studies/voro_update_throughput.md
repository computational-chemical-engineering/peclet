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
| ≥ 1e-2 (gate → rebuild) | 0.38 | 0.86 | 0.85 | 0.8–0.88 | 1e-15 | 0 |

(After voro 75f4926 the clip reports the gap its commit test computes, so the near-miss
recording costs no second vertex scan; after voro 45d5adf a gate-rebuild skips the emission
and the first low-churn step pays one emitting rebuild — the adjacency's lazy pattern — so the
rebuild guard is back near a cold build.)

The residual "missed" relations are zero-area slivers below the certificate tolerance (the
volumes agree to 1e-11). Over 400 steps (`test_sdf_dynamic`) the wall-free drift fell from
1.6e-3 to 5.5e-11 (default tolerance) and 1.2e-15 (tight); the SDF path from 1.6e-3 to 5.9e-8.
The gate's rebuild costs 0.86× a cold build (lazy emission; the remaining gap is the store
emission itself, as before).

## Cold build vs N (CUDA, FP64, MAXP 64 / MAXT 112)

| N | plain build Mcells/s | build emitting the resident store Mcells/s | store bytes/cell |
|---|---|---|---|
| 20k | 0.78 | 0.71 | 1260 |
| 100k | 1.35 | 1.13 | 1260 |
| 200k | 1.37 | 1.13 | 1260 |
| 1M | 1.45 | 1.32 | 1260 |

## Snellius H100 weak scaling (job 26366044, 2026-09-05)

The distributed path at scale: `voro/tools/snellius_voro_mpi.sh` on one `gpu_h100` node
(4 × H100, one rank per GPU, Kokkos CUDA, OpenMPI 5.0.3, CUDA 12.6; voro 9a3d6a2 with the
near-miss certificate, core c98964a, morton 2a810b7). `bench_repair_mpi` at **400 000 seeds per
GPU** (weak scaling: N = 400k / 800k / 1.6M at np = 1 / 2 / 4), 8 steps per displacement,
FP64; the distributed repair is checked against a distributed cold build every step
(`maxRelV`), the SDF variant additionally against a single-rank cold SDF build.

### Wall-free periodic box — repair vs cold build, ms per step (speedup = cold / repair)

| disp | np=1 cold | np=1 repair | speedup | np=2 cold | np=2 repair | speedup | np=4 cold | np=4 repair | speedup | max rel. ΔV (worst rank count) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1e-4 | 149.8 | 37.1 | **4.04** | 174.0 | 40.9 | **4.25** | 212.9 | 46.1 | **4.62** | 2.0e-10 |
| 2e-4 | 147.4 | 36.8 | 4.01 | 169.8 | 40.4 | 4.20 | 205.4 | 46.0 | 4.47 | 1.7e-9 |
| 5e-4 | 147.5 | 44.2 | 3.34 | 169.2 | 48.5 | 3.49 | 203.5 | 53.8 | 3.78 | 9.6e-6 |
| 1e-3 | 147.5 | 64.7 | 2.28 | 169.4 | 68.9 | 2.46 | 204.9 | 74.6 | 2.75 | 2.4e-7 |
| 2e-3 | 147.5 | 93.0 | 1.59 | 170.0 | 96.8 | 1.76 | 206.0 | 103.4 | 1.99 | **2.8e-4** |
| 5e-3 | 146.8 | 171.2 | 0.86 | 169.2 | 178.1 | 0.95 | 205.4 | 188.7 | 1.09 | 1.2e-6 |
| 1e-2 (gate → rebuild) | 147.4 | 188.8 | 0.78 | 168.4 | 201.3 | 0.84 | 205.4 | 219.6 | 0.94 | 1.3e-15 |

Exactness line: `REPAIR(MPI) exactness: PASS` at every rank count. Flagged fractions are the
same as on the workstation (1.4 / 2.7 / 6.6 / 12.6 / 23.2 / 47.5 % of the cells, then the gate).

| | np=1 (400k) | np=2 (800k) | np=4 (1.6M) |
|---|---|---|---|
| cold build, aggregate Mcells/s | 2.71 | 4.72 | 7.79 |
| repair at 1e-4 spacing/step, aggregate Mcells/s | 10.8 | 19.6 | 34.7 |
| weak-scaling efficiency, cold (t₁/t_np) | 100 % | 87 % | 72 % |
| weak-scaling efficiency, repair at 1e-4 | 100 % | 91 % | 80 % |
| weak-scaling efficiency, gate rebuild (1e-2) | 100 % | 94 % | 86 % |

### The same sweep through the SDF scene (`--sdf`)

| disp | np=1 cold | np=1 repair | ratio | np=2 cold | np=2 repair | ratio | np=4 cold | np=4 repair | ratio | max rel. ΔV vs single-rank cold SDF |
|---|---|---|---|---|---|---|---|---|---|---|
| 1e-4 | 155.8 | 174.8 | 0.89 | 178.8 | 182.4 | 0.98 | 209.5 | 197.5 | 1.06 | 1.4e-10 |
| 2e-4 … 2e-3 | 153.6–154.2 | 176.0–177.2 | 0.87–0.88 | 175.4–176.4 | 180.7–181.4 | 0.97 | 205.3–206.1 | 193.7–196.2 | 1.05–1.06 | ≤ 1.6e-10 |
| 5e-3 | 154.3 | 187.1 | 0.82 | 175.6 | 194.3 | 0.90 | 206.1 | 210.7 | 0.98 | 4.8e-12 |
| 1e-2 | 154.2 | 197.8 | 0.78 | 175.7 | 208.7 | 0.84 | 205.5 | 226.6 | 0.91 | 4.9e-11 |

`REPAIR(MPI,SDF) exactness: PASS`, `emptyMismatch = 0` at every row and rank count: the
distributed SDF repair reproduces the single-rank cold SDF build to 1e-10 in every cell.

### What the H100 numbers say

- **The repair scales weakly at 80 % to 4 GPUs and its speedup over the cold build *grows*
  with the rank count** (4.04× → 4.62× at 1e-4), because the distributed cold build pays the
  gather of the ghost layer every step while the repair only touches the flagged cells; the
  cold build itself drops to 72 % at np = 4 (the ORB block's halo-to-volume ratio at 400k seeds
  per rank). Per GPU the H100 cold build is 2.71 Mcells/s FP64 = 2.4× the RTX 5080 (whose FP64
  rate is a fraction of its FP32) and the repair 10.8 Mcells/s = 4.4× the RTX 5080 (2.48) and
  2.6× the 8-thread host (4.23).
- **The gate rebuild stays at 0.78–0.94× a cold build**, as on the workstation — the guard holds
  distributed.
- **The SDF path's repair costs a cold build (0.87–1.06×) while the certificate flags no cell
  (p1 = 0 %).** The per-step cost is therefore outside the re-clip. The candidate is the boundary
  watch (`sdfWouldClip` evaluates the wall for every cell every step) plus the SDF clip inside the
  full re-evaluation; the kernel-level split A4 asks for (certify / re-eval / re-clip timers) will
  say which. Until then the SDF path has no per-step advantage over rebuilding — the A4 tuning
  item with the largest payoff for track D/E (every moving-cell fluid case has walls).
- **One exactness caveat (open):** at 2e-3 spacing per step the wall-free repair deviates by
  **2.8e-4** (np = 1) and 1.5e-4 (np = 4) in one cell's relative volume, against ≤ 1e-5 in every
  other row; np = 1 shows it, so it is not a distribution artefact. It is the same class as the
  nondeterministic `test_sdf_dynamic` "2e-3 × 400 tol 1e-4" case seen on the workstation
  (thread/atomic-order dependence of the moving repair at moderate displacement; the workstation
  near-miss table shows 9e-12 / 9e-7 for the same row). The bench's PASS gate is looser than the
  1e-11 the near-miss certificate achieves at small displacement; the residual miss is real and
  needs a deterministic worklist order or a tighter certificate for the 1e-3..5e-3 band.

### `test_flow_mpi` at 4 ranks on the H100s (rung C5 at scale)

n = 24 jittered lattice, TGV, 20 steps, 23 383 ghost cells at np = 4 — every gate OK:

| solver | max \|U − U_ref\| / max\|U\| (gate) | E/E_ref − 1 (gate) | max face div | PCG iterations |
|---|---|---|---|---|
| collocated, RK3 | 1.0e-15 (1e-12) | 0 (1e-13) | 1.6e-14 | 49 |
| collocated, implicit diffusion | 4.2e-11 (1e-9) | 2.2e-15 (1e-12) | 5.5e-14 | 51 |
| covolume, RK3 | 2.6e-14 (1e-12) | 1.1e-16 (1e-13) | 8.5e-13 | (not reported: the covolume path does not fill the test's iteration counter) |

The isolated distributed pressure solve: 52 PCG iterations, recursive residual == true residual
(9.37e-13), |K·1| = 0, symmetry defect 3.6e-15, zero ghost gid mismatches; the device-packed
ghost exchange equals the host reference path in every entry (gate X). Raw output:
`$SUITE/voro/voro-mpi-26366044.out` on Snellius (7 min 23 s of the 40 min allocation, 4 GPUs).

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
