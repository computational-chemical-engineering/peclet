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
| the venv | `$SUITE/flow/.venv` — **one** venv for everything, as on the workstation |
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

## Building

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
- **Memory**: genoa has 336 GiB/node. An OOM-killed rank leaves the survivors hung in a collective,
  so drivers print a heartbeat; a run past ~10 min with no heartbeat progress is hung → `scancel`.

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
- `docs/COMMUNICATION_SCALING.md` — the halo/smoother communication design the scaling studies test.
- `peclet-examples/benchmarks/porous-scaling/README.md` — the most complete worked runbook
  (two ladders, ablations, and a forensic history of a real GPU-only corruption bug).
