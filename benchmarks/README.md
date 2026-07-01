# Benchmarks

## `profile_mpi_flow.py` — distributed CFD communication-overhead (weak scaling)

Measures the **MPI communication overhead** of the distributed staggered-MAC Navier–Stokes solver
(`peclet.flow`, multi-rank) — the halo exchange plus the global pressure-solve all-reduces — using a
**weak-scaling** setup where every rank/GPU does *identical* work.

### How it isolates communication

- The geometry is a **periodic random sphere packing** of `L³` cells (one tile).
- Tiles are **glued periodically** into the global domain: for `np` ranks it picks a balanced rank grid
  `px·py·pz = np`, makes the global grid `L·px × L·py × L·pz`, and fills each rank's block from the same
  periodic tile. The global field is therefore seamless and **every rank simulates the same subdomain**.
- Per-rank work is thus **constant** as `np` grows. The only things that change with `np` are the
  **ghost-layer halo exchange** (every step) and the **global MG-PCG pressure solve** (couples all ranks).
  So the rise in per-step wall-time = the communication tax (+ any non-weak-scalable growth in the solver,
  visible as a climbing `pressure_iters`).

Ideal weak scaling ⇒ per-step time is **flat** vs `np`. **The packing generation is not timed** (only the
warm-then-timed `step()` loop is).

### Run

```bash
# local CPU/OpenMP sweep — compare the per-step time across np:
for n in 1 2 4 8; do mpirun -np $n python benchmarks/profile_mpi_flow.py --L 48 --steps 100 --csv wk.csv; done

# on a cluster, launch through the site bind-wrapper (multi-GPU or multi-node CPU):
srun containers/snellius-run.sh peclet-cuda_0.1.0-sm80.sif benchmarks/profile_mpi_flow.py --L 128 --steps 200 --csv wk.csv
```

Key flags: `--L` per-rank grid (raise until a GPU is saturated, e.g. 128–192), `--steps`, `--warmup`,
`--phi` packing solid fraction, `--csv` appends one row per run.

### Reading the output

```
[Cuda] np=8   grid=2x2x2  global=256x256x256  per-rank=128x128x128=2097152 cells  (~1900 spheres/tile)
    per-step: max  12.3 ms  min  12.1 ms  imbalance 1.6%   pressure_iters=14   170.5 Mcell/s/rank
```

- **per-step max** vs `np` — the weak-scaling curve; the climb over the `np=1` value is the comm overhead.
- **imbalance** — should stay near 0 (identical tiles); a large value means the rank grid didn't tile evenly
  (use `np` = a product of small factors, ideally powers of two).
- **pressure_iters** — if this climbs with `np`, the pressure solve is the non-`O(N)` cost, not the halo.
- **Mcell/s/rank** — per-rank throughput; on one node this should stay near the single-rank device number.

Requires `peclet.flow` built with `PECLET_FLOW_MPI=ON` (`flow.has_mpi == True`) and `mpi4py`. The GPU
containers (`peclet-cuda`, `peclet-hip`) and the CPU container are built with the flag on.
