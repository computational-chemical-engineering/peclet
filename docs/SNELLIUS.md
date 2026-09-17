# Running peclet on Snellius (SURF)

Consolidated runbook: the toolchain, how to build, how to queue, and the traps that have actually
cost time. The authoritative *scripts* are
`peclet-examples/examples/wall-bounded-turbulence/{snellius_env.sh,install_snellius.sh}` — this
document explains them and the conventions the benchmark job scripts share.

## Coordinates

| | |
|---|---|
| host | `snellius` (SSH config alias; `int4.local.snellius.surf.nl` etc.) |
| account | `tes24005` (every `#SBATCH --account`) |
| project space | `/projects/0/prjs1022/peclet` — the suite lives at `.../peclet/suite` |
| the venv | `$SUITE/.venv` — **one** venv for everything, as on the workstation |
| CPU partition | `genoa` — 192 cores/node, 336 GiB; `--exclusive` |
| GPU partition | `gpu_h100` — 4× H100 94 GB/node, 16 cores/GPU (also `gpu_a100`) |

## Toolchain — the 2024a stack

`snellius_env.sh` is sourced by build *and* run scripts so they cannot disagree:

```
module load 2024
module load gompi/2024a                                    # GCC 13.3 + OpenMPI + UCX 1.16
module load CUDA/12.6.0
module load UCX-CUDA/1.16.0-GCCcore-13.3.0-CUDA-12.6.0
module load Python/3.12.3-GCCcore-13.3.0
export OMPI_MCA_pml=ucx UCX_MEMTYPE_CACHE=n                # GPU-aware MPI
```

The 2024a stack is the one that satisfies **both** Kokkos 5.1.1 (CUDA ≥ 12.2) and GPU-aware MPI
(UCX-CUDA exists for this CUDA). On the older 2023 stack those two were mutually exclusive. The
script fails fast with a `module avail` dump if a name has drifted — fix names there, in one place.

Module versions on Snellius **do drift**. The one hard requirement is that the OpenMPI loaded here
is the same one `mpi4py` was pip-built against, since `pip install mpi4py` compiles against
whatever `mpicc` is on `PATH`. Never mix module stacks between build and run.

## Installing a release (`tools/hpc/`)

For a *released* family, use the site-install script instead of the campaign tree: it clones the
umbrella at the tag into its own tree + venv, bootstraps Kokkos for the backend and builds every
package with `PECLET_*_MPI=ON`, leaving a site-specific wheelhouse other project members can
`pip install --no-index --find-links` from (never upload those wheels to PyPI — they link the
module OpenMPI and CUDA):

```bash
cd $PROJ/suite-v<family>          # SUBMIT FROM INSIDE THE TREE (see the traps below)
sbatch --nodes=1 --gpus-per-node=1 --ntasks-per-node=1             tools/hpc/install_snellius.sh v<family> h100
sbatch -p gpu_a100 --nodes=1 --gpus-per-node=1 --ntasks-per-node=1 tools/hpc/install_snellius.sh v<family> a100
sbatch -p genoa --gpus-per-node=0 --ntasks=1 --cpus-per-task=32    tools/hpc/install_snellius.sh v<family> cpu
sbatch tools/hpc/smoke_snellius.slurm     # certifies it: 1- vs 8-rank permeability, dem step_mpi
```

Arguments are positional (SURF's `sbatch` drops leading `VAR=x`); `snellius_env.sh` next to it is the
shared module recipe. The pre-built containers are the other route ([containers](containers.md)).

**Three traps, all hit on this script's first real run (2026-09-16, peclet 1.1.0) and all now fixed
in the script — the recipe above is the corrected one; see [RELEASE](RELEASE.md) §7.**

- **Submit from inside the tree.** sbatch copies the script to `/var/spool/slurm/...`, so the
  `$SLURM_SUBMIT_DIR` fallback is what finds `snellius_env.sh`; submitting from the parent resolves
  to a nonexistent `$PROJ/tools/hpc` and the job dies on a bare `No such file or directory`.
- **Each backend gets its own tree** — `$PROJ/suite-<tag>-<backend>`. `h100` and `a100` both build
  the `nvidia-cuda` prefix at different arch, and the script does `venv --clear` on `$SUITE/.venv`,
  so two backends in one tree destroy each other whether run together or in sequence.
- **`--gpus=0` does not override `#SBATCH --gpus-per-node=1`** on a GPU-less partition; use
  `--gpus-per-node=0` or sbatch rejects the job.

### Validated releases

| family | backend | tree | job | outcome |
|---|---|---|---|---|
| v1.1.0 | cpu (genoa) | `suite-v1.1.0-cpu` | 26813727 | **OK** — `flow OpenMP has_mpi True`; **smoke 26814834 CERTIFIED** (see below) |
| v1.1.0 | h100 | `suite-v1.1.0-h100` | 26813725 | **OK** — `flow Cuda has_mpi True`; smoke **26813984 queued** (gpu_h100 was at 56 alloc / 12 resv; est. start 2026-09-17T12:30) — result will be `suite-v1.1.0-h100/peclet-smoke-26813984.out`, compare its two `k` lines |
| v1.1.0 | a100 | `suite-v1.1.0-a100` | 26813726 | **OK** — `flow Cuda has_mpi True`; **smoke 26815101 CERTIFIED** (see below) |

Each wheelhouse (`$PROJ/wheelhouse/v1.1.0-<backend>/`) carries all seven packages at the released
versions: flow 1.1.0, core/dem/pnm/voro 1.0.2, morton/coupling 1.0.1, cp312, linked against the
module OpenMPI + CUDA 12.6 — **site-specific, never upload these to PyPI**. Project members install
with `pip install --no-index --find-links $PROJ/wheelhouse/v1.1.0-<backend> peclet-flow`.

`$PROJ/suite-v1.1.0` (no backend suffix) is the tree the release was submitted *from*; it carries
`tools/` only and has no venv.

**Smoke certification, v1.1.0 cpu/genoa (job 26814834, 4 ranks).** The first fully green run of
`smoke_snellius.slurm` in its family-wide form:

```
flow OpenMP has_mpi=True | dem OpenMP step_mpi=True | voro OpenMP VoronoiHalo=True | pnm OpenMP mpi=True | coupling=True
np=1: k=5.845422163491e+00  div=1.847e-13   block(rank0)=origin[0,0,0] size[32,32,32]
np=4: k=5.845422163491e+00  div=1.847e-13   block(rank0)=origin[0,0,0] size[16,16,32]
[OpenMP] np=4  grid=1x2x2  global=48x96x96  per-rank=48^3=110592 cells (~53 spheres/tile)
    per-step: max 205.657 ms  min 205.656 ms  imbalance 0.0%  pressure_iters=9  0.54 Mcell/s/rank
```

`k` identical to all thirteen digits at np=1 and np=4 — the distributed solve on the site install is
bit-exact to single-rank, which is what this job exists to prove.

**Smoke certification, v1.1.0 a100 (job 26815101, 4 GPUs).**

```
flow Cuda has_mpi=True | dem Cuda step_mpi=True | voro Cuda VoronoiHalo=True | pnm Cuda mpi=True | coupling=True
np=1: k=5.845422163491e+00  div=1.847e-13
np=4: k=5.845422163491e+00  div=1.847e-13
[Cuda] np=4  grid=1x2x2  global=48x96x96  per-rank=48^3
    per-step: max 103.604 ms  min 103.603 ms  imbalance 0.0%  pressure_iters=9  1.07 Mcell/s/rank
```

**The CUDA `k` equals the OpenMP `k` to all thirteen digits** (`5.845422163491e+00`), at the same
`div = 1.847e-13` and the same 9 pressure iterations. Two backends, one answer — direct evidence for
the standing position that a backend change is a faithful port, not a re-derivation. The A100 runs
the tile at 103.6 ms/step against genoa's 205.7 ms (1.07 vs 0.54 Mcell/s/rank), which is a timing
difference and not a numerical one.

The **h100 smoke is queued, not yet run** (job 26813984, submitted 2026-09-17T00:03, 4 GPUs). Its
install is verified and the CUDA backend is already certified by the a100 run above, so this job is a
third confirmation rather than an open question — but until it completes, the h100 row is
*install-verified, not smoke-certified*. To finish it: read
`$PROJ/suite-v1.1.0-h100/peclet-smoke-26813984.out`, check the np=1 and np=4 `k` lines are identical
(expect `5.845422163491e+00`, the same value both other backends gave), and fill in the row.

It took three submissions to get there, and the two failures were **real defects in the repo, not the
install**: `benchmarks/profile_mpi_flow.py` still called `set_body_force(fx, fy, fz)` (repacked into
one 3-sequence by 1.0.0) and then `set_velocity_solver_params` / `last_pressure_iterations` on the
`Solver` (moved to `solver.diagnostics` by the 1.0.0 tiering). Both had been broken since 1.0.0 and
neither is covered by CI. Five more of the same `set_body_force` defect were found in
`pnm/scripts/`. **None of it was visible to a static audit** — nothing was *renamed* — which is the
argument for this job existing at all.


The releases validated this way are also recorded in [RELEASE_PREP](RELEASE_PREP.md) (Snellius
section) by the release procedure ([RELEASE](RELEASE.md) §7).

## Building the development tree

```bash
cd <peclet-examples>/examples/wall-bounded-turbulence
sbatch install_snellius.sh h100     # -> peclet-build-<jobid>.out; CHECK "has_mpi: True"
sbatch install_snellius.sh cpu      # the OpenMP/CPU build, for genoa
FRESH=1 sbatch install_snellius.sh h100   # clean rebuild — REQUIRED when CUDA version/arch changes
```

It pulls the umbrella, `git submodule update --init --recursive` (core and flow **must** be at
matching umbrella-pinned commits), rebuilds the venv, re-bootstraps Kokkos for the backend, and
configures flow with `-DPECLET_FLOW_MPI=ON`. Products:

| target | backend | build dir |
|---|---|---|
| `h100` | `nvidia-cuda`, HOPPER90 | `$SUITE/flow/build_cuda_mpi` |
| `a100` | `nvidia-cuda`, AMPERE80 | `$SUITE/flow/build_cuda_mpi` |
| `cpu` | `host-openmp` | `$SUITE/flow/build_omp_mpi` |

Build gotchas that have bitten:

- **`-DPython_EXECUTABLE` with a capital P.** The lowercase spelling is silently ignored and CMake
  falls back to the system python, which has no nanobind.
- **A venv has no `Python.h`** — pass `-DPython_INCLUDE_DIR=$(python3 -c 'import sysconfig;
  print(sysconfig.get_config_var("INCLUDEPY"))')`.
- **FindPython's artifact variables are sticky.** Once a build dir has configured (even
  unsuccessfully) with the wrong interpreter, re-running with the right `-DPython_EXECUTABLE`
  changes nothing. Always `rm -rf` the build dir. (Hit again on the workstation 2026-09-01: a
  `build_mpi` cached against the retired per-project `flow/.venv` failed with "Cannot run the
  interpreter" until wiped.)
- **`dem`'s `PecletDeps.cmake` silently falls back** instead of failing: with `nvcc` absent
  (env not sourced) `find_package(Kokkos)` fails and it FetchContent-builds a vendored
  **OpenMP+Serial host** Kokkos without erroring. Read the configure output: no
  `[peclet] building+installing kokkos` line, and Kokkos reporting device `CUDA`.
- **Never `mv` a venv** — absolute paths are baked into `activate` and every console script, and
  the failure is silent (`python` disappears; `python3`/`pip` fall through to `/usr/bin`). If the
  directory moves, delete and recreate.

## Submitting jobs

Conventions every benchmark script in `peclet-examples/benchmarks/*/snellius/` follows:

- **Submit from inside the `snellius/` directory.** Scripts resolve `../<driver>.py`, `../results`
  and the shared `snellius_env.sh` relative to `$SLURM_SUBMIT_DIR`.
- **Rung selection is a positional argument, not an env var** — SURF's `sbatch` drops leading
  `VAR=x sbatch …` env vars. `SUITE`/`BUILD`/`GPU_AWARE` overrides must be `export`ed beforehand,
  or passed via `--export=ALL,VAR=…`.
- **Argument 2 is a result tag.** Runs skip an existing JSON so a job is resumable after a
  timeout, which also means that after any solver change an untagged rerun silently reports the
  *stale* numbers. Change the tag.
- **Nodes come from `--nodes=`**, the rank/GPU count from the argument; the script checks the two
  agree and refuses otherwise.

```bash
cd <peclet-examples>/benchmarks/<study>/snellius
sbatch --nodes=1 <study>_gpu.sh 4
sbatch --nodes=8 <study>_genoa.sh 1536 mgfix2
squeue -u $USER;  scancel <jobid>;  tail -f <job>-<jobid>.out
```

Launcher lines that work:

```bash
# GPU: one rank per GPU
srun --mpi=pmix --ntasks=$N --gpus-per-task=1 --gpu-bind=per_task:1 "$VENV/bin/python" driver.py
# CPU (genoa): pure MPI, one rank per core
srun --mpi=pmix --ntasks=$N --ntasks-per-node=$RPN --cpus-per-task=1 \
     --distribution=block:block --cpu-bind=cores "$VENV/bin/python" driver.py
```

- **Force `-DMPIEXEC_EXECUTABLE=/usr/bin/mpirun`** when configuring the ctest suites — FindMPI may
  pick ParaView's bundled `mpiexec` from `PATH`, which launches the OpenMPI-linked binaries as
  singletons, so `*_np4` silently runs 4× np=1.
- **Bound the OpenMP pool**: `OMP_NUM_THREADS` explicitly (`=1` for pure-MPI CPU runs),
  `OMP_PROC_BIND=spread OMP_PLACES=cores` when threading. An unbounded pool on a many-core host is
  a measured hour-long trap since the CUDA prefix gained an OpenMP host backend (2026-08-30).
- **genoa node-set variability is real** — the same config measured 3.2 vs 8.0 s/step on different
  node sets. Report best-of or the spread, never a single draw.
- **Memory: `--exclusive` does NOT give you the node's memory.** SLURM still caps the job at
  roughly 1792 MiB × ntasks (SURF's per-core default), so a job that holds a whole 336 GiB genoa
  node with only 24 ranks is limited to ~43 GiB and gets OOM-killed on a large grid — measured
  2026-09-01, job 26280702, `Detected 2 oom_kill events`. Add **`#SBATCH --mem=0`** (all node
  memory) to any script whose low-rank rungs under-fill a node; at 192 ranks/node the per-task
  allowance already sums to the node, which is why only the sparse rungs fail and the fully packed
  ones pass. An OOM-killed rank also leaves the survivors hung in a collective, so drivers print a
  heartbeat; a run past ~10 min with no heartbeat progress is hung → `scancel`.

## Result flow

Drivers write one JSON per (study, rung, variant) plus a `.log` beside it. Collect and plot on the
workstation; commit the JSONs (they are the reproducibility record), not the logs.

```bash
scp -r 'snellius:/projects/0/prjs1022/peclet/.../results/snellius-h100' results/
python plot_<study>.py
```

## Pre-flight without a GPU

Decomposition and multigrid depth for any (grid, np) combination — a pure function of
(ranks, grid, levels), so it needs no hardware:

```bash
PYTHONPATH=<build> python $SUITE/flow/scripts/check_decomposition.py \
  --grid 400,400,400 --levels 5 --np 24 --mode 0,coarse
```

It is **slow above ~a hundred ranks** — run it in the background, one rank count at a time. Watch
for: an odd axis never coarsens at all, and under MPI a level coarsens an axis only if *every*
rank's block is even on it, so achievable depth is set by the per-rank block, not the global grid.

## Pointers

- `docs/DECOMPOSITION_AND_MULTIGRID.md` — the per-axis coarsening rule, aligned vs coarse-first
  partitions, and why grid dimensions' factors of two decide solver cost. Read before choosing a
  benchmark grid.
- `docs/archive/COMMUNICATION_SCALING.md` — the halo/smoother communication design the scaling studies test.
- `peclet-examples/benchmarks/porous-scaling/README.md` — the most complete worked runbook
  (two ladders, ablations, and a forensic history of a real GPU-only corruption bug).
