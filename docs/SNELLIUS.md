# Running peclet on Snellius (SURF)

Consolidated runbook: the toolchain, how to build, how to queue, and the traps that have actually
cost time. The authoritative *scripts* are in `tools/hpc` — the `sn` toolkit below for campaign
work, `install_snellius.sh` / `smoke_snellius.slurm` for releases, and the shared `snellius_env.sh`.
The older `peclet-examples/examples/wall-bounded-turbulence/` scripts are their ancestors and stay
there as history. This document explains them and the conventions the job scripts share.

## The `sn` toolkit

`tools/hpc/sn` is one bash CLI, run on TRS2, that pushes source to Snellius, builds it, runs jobs on
it and brings results back, so that no session writes its own Snellius scripts again. Sessions call
it through the entry skill `.claude/skills/snellius/SKILL.md`. Its job bodies, templates and helpers
are in `tools/hpc/snellius/`; `tools/hpc/snellius/selftest.sh` checks them locally (no ssh).

**Remote layout** (`/projects/0/prjs1022/peclet/`):

| path | what | written by |
|---|---|---|
| `src/<tree>/` | the source, `MANIFEST` (`repo sha source` per line), **read-only** after the push | `sn push` |
| `build/<tree>-<target>/` | `env.sh` (the tree's `snellius_env.sh`, copied), `.venv`, `extern/install/<backend>`, `cmake/<pkg>`, `BUILD_INFO`, `build-<jobid>.out` | `sn build` |
| `runs/<campaign>/<tag>/` | `job.sh` (the job, self-contained), `cases.txt`, `slurm-*.out`, `<idx>/` (the driver's cwd and its log), `summary.tsv` | `sn run` |

`<tree>` = `<campaign>-<first 8 hex of sha256 over the manifest's "repo sha" columns>`. The same
sources give the same tree, which is then reused, never rewritten; a changed repo is a new tree, so a
job cannot run a mixture of sources (incident 2026-08-31). `extern/` is never pushed.

**Free commands** (no billing):

```bash
sn budget                                    # per budget line: SBU left; accuse this month; prjs1022 quota
sn push <campaign> [repo=<worktree|ref> ...] [umbrella=<worktree|ref>] [--only r1,r2] [extra=<name>:<repo-path>[@ref] ...]
sn pull <campaign>[/<tag>] <local dir> [--only 'fields.npz,meta.json,*.log']
sn status [campaign];  sn cancel <jobid|campaign>     # jobs are named sn-<campaign>.<tag>
```

- Names: a campaign is letters, digits, `_` and `-` (never `.`, never `build`, not all digits); a
  tag may also hold `.`. Run jobs are named `sn-<campaign>.<tag>`, build jobs
  `sn-build.<tree>.<target>`, so `sn status x` / `sn cancel x` match campaign `x` exactly, never `x-y`.
- `cancel <jobid>` (a job, an array task `A_i` or a whole array `A`) also cancels every job that
  depends on it, transitively (the chain successor, queued `afterany`, would otherwise run), and
  first writes `runs/<c>/<t>/<idx>/.stop`; `cancel <campaign>` cancels all its run and build jobs and
  writes `runs/<c>/<t>/.stop`. A job that finds a `.stop` exits without running and queues nothing,
  so a successor queued after the cancel's squeue snapshot stops too; `sn run --resume` removes them.
  A plain `scancel` by hand is also caught: a TERM long before the limit ends the chain (below).

- `push` sends the umbrella at `origin/main` of `~/Codes/suite` with every submodule at the SHA it
  pins, laid out as in the suite (`<tree>/core`, `<tree>/flow`, ..., `<tree>/tools`), by
  `git archive <sha> | ssh ... tar -x` per repo (no `.git` remote side). `repo=<path>` takes a
  worktree's HEAD (refused if dirty; untracked files are ignored; a relative path may be relative to
  the current directory or to the submodule, so `voro=../voro-ale-s0` works from either);
  `repo=<ref>` takes any commit of the submodule's own repo, also one not on origin. `--only voro`
  pushes voro plus what it needs to build (core, morton): a sibling missing from the tree would make
  CMake FetchContent the *pinned tag* from GitHub without an error.
- `extra=<name>:<repo-path>[@ref]` adds any committed local git repo (a study repo, peclet-papers) at a
  ref (default HEAD; a dirty HEAD and a plain directory are refused) as `<tree>/extra/<name>`, with a
  MANIFEST line `extra/<name> <sha> ...` that enters the tree hash. A job then runs e.g.
  `-- extra/<name>/perf/s2/run_chunked.sh` (driver paths resolve relative to the tree).
- `pull` is rsync with an include filter: with `--only`, everything not matching is excluded.

**Billed commands** — each submit needs its own signed Decision Desk card:

```bash
sn build <tree> <h100|a100|cpu> [packages...] [--where gpu|genoa|cbuild] [--time 03:00:00] [--rebuild]
         [--define <pkg>:<CMAKE_DEFINE>=<value>]...
sn run <tree> <target> <campaign>/<tag> <template> [--array cases.txt [--array-max P]] [--chain K]
       [--gpus N] [--ranks N] [--nodes N] [--threads T] [--exclusive] [--time T] [--env K=V]
       [--no-srun] [--resume] -- <driver> <args...>
sn smoke <tree> <target>                    # the release 1- vs N-rank certification on an sn build
sn check-gpu-aware <tree> <h100|a100>       # check_gpu_aware_mpi.sh on 2 GPUs; tests the transport only
sn walltime-test <tree>                     # the walltime/chain path for real (tools/hpc/snellius/walltime_test.sh)
```

- `--test-only` (any billed command) runs `sbatch --test-only` with the script on stdin: it prints the
  sbatch line, SURF's "charged for" line, the start slot, the cost, the refusals a real submit would
  hit (`note:`) and the card's action text, and writes and submits nothing. `--print-action` is the
  same run with the action text alone on stdout (everything else on stderr).
- `--time`: `H:MM:SS`, `D-HH`, `D-HH:MM` or `D-HH:MM:SS` only. A two-field `30:00` is refused (sbatch
  reads minutes:seconds; `02:00` meant as hours would get 1/60 of the limit).
- Without `--test-only` a billed command needs `--card <id> --desk <dir>`. `sn` then runs
  `decision_desk_verify.py <dir> <id> --action "<ACTION>"` and submits only on `VERIFIED`, once per
  card. `<ACTION>` = the argument vector with `--card`/`--desk` (and `--test-only`, `--print-action`)
  removed, each argument `printf %q`-quoted (lossless: `-- bash -c "a b"` is `-- bash -c a\ b`),
  single-spaced, then ` | time <T>, template <name>@<sha256[:12] of the .tpl>, estimate <X> SBU`
  (`build`: `where <W>` in place of the template):
  `sn build m7-1a2b3c4d h100 voro | time 03:00:00, where gpu, estimate 576.0 SBU`. The effective
  `--time` (also a default), the template's content and the cost are on the card. `--array cases.txt`
  appears as `--array cases.txt@<sha256[:12] of its content>`, so a card covers the exact case list:
  `sn` recomputes the hash at submit (a changed file no longer matches the card) and refuses a typed
  `@hash` that does not match the file.
- **A real submit refuses** (none of this is on the card, so none of it may vary): the environment
  overrides `SN_HOST`, `SN_PROJ`, `SN_ACCOUNT`, `SN_VERIFY`, `SN_LEDGER` (they exist for the selftest
  and `--test-only`); a toolkit (`tools/hpc/sn`, `tools/hpc/snellius/`) with uncommitted changes —
  the job script and `BUILD_INFO` record its commit; `--env PYTHONPATH=…` and `--env LD_*=…` (code
  that is not the build's); a template flag the template does not read (`--exclusive` on `gpu1` or
  `gpu-mpi`, `--ranks` on `gpu1`, …: refused always).
- **The card is the lock.** `sn` appends the card id to a local ledger, `~/.cache/sn/used_cards`,
  right after `VERIFIED` and *before* the upload and `sbatch`, and refuses a card it finds there; a
  submit that then fails spends the card (ask for a new one). The ledger is per host, so the real
  lock is `executed: {at, by, result}` on the card, which the session writes right after the submit:
  `sn` prints the job id and `EXECUTED-NOTE: write executed{at,by,result} on card <id> now`.
- **Cost before every submit**: allocation × walltime × array size × chain cap, against what the budget
  line of that partition has left (`accinfo`); refused if it exceeds it. The allocation is the larger
  of the request and what `--test-only` reports. Rates, confirmed 2026-11-19 from the `billing=` TRES
  of past jobs (sacct) against `accuse`: **H100 192 SBU/GPU-h** (job 28537289: `billing=768` for 4
  GPUs, 236 s → 50.3 SBU), **A100 128 SBU/GPU-h** (28555799: `billing=512`, 184 s → 26.2 SBU),
  **genoa 1 SBU/core-h** (28535366, 28464076). `cbuild` is assumed 1 SBU per allocated core-h
  (unconfirmed; sbatch prints no charge line there and gives 32 processors for 16 requested).
- What `--test-only` showed (2026-11-19): a shared GPU job is "charged for 1 GPUs" (gpu1) or "4 GPUs"
  (gpu-mpi 4), never the node; a genoa shared job is charged in 24-core units (32 cores → 48,
  4 ranks → 24); multi-node and `--exclusive` jobs print no charge line (the full nodes are charged).

**Build** (`tools/hpc/snellius/build.sh`, the steps of `install_snellius.sh` from a pushed tree):
source the tree's `snellius_env.sh` (copied to `build/.../env.sh`, which every run sources); venv with
`mpi4py` compiled against the module OpenMPI (`--no-binary=mpi4py`); `bootstrap_deps.sh` (a copy in
the build dir, so the prefix lands there) with HOPPER90/90, AMPERE80/80 or host-openmp; the packages
in dependency order with `pip install --no-deps --no-build-isolation`, MPI on, the CMAKE_ARGS traps
below, each in `build/.../cmake/<pkg>`, from a writable copy `build/.../src` of their repos whose
sha256 over all files must equal the tree's (`src_copy` in `BUILD_INFO`) — morton's CMake writes its
`.so` into its own source dir, which the read-only tree refuses (found by a local build of the job,
2026-11-19); then the **proof** that each package compiled that core: every `-I` of its generated
build files resolved, written to `BUILD_INFO` as `core_include <pkg> <path> OK` — a fetched sibling
(`_deps/peclet_sib_*`), another path or no line at all fails the build; the import check (a GPU target built with `--where genoa|cbuild` defers it to `sn smoke`:
no `libcuda` there); `rm -rf extern/build extern/src src` (inodes); `BUILD_INFO` last (its presence means
built; `sn build` refuses a built dir unless `--rebuild`). Default `--where`: `gpu` (one GPU of the
target's partition, budget L3) for h100/a100, `genoa` for cpu.

- **A GPU target is a CUDA build or no build**: h100/a100 fail before anything is built when `nvcc`
  is not on `PATH`, and after the Kokkos bootstrap (which now runs *before* the venv, so this costs
  minutes, not the pip installs) when `Kokkos_DEVICES` has no `CUDA`; the import check (on a GPU
  node) fails when a device module (flow, pnm, dem, voro, amr, coupling) does not report a `Cuda`
  `execution_space`. `BUILD_INFO` lists `import_modules` and `device_modules`; every GPU job repeats
  the `Cuda` check at its start (a host-only "h100" build would bill GPUs for nothing — the dem
  fallback trap below).
- `BUILD_INFO` also records `pip freeze` (the unpinned deps as installed, `pip <pkg>==<ver>`), the
  toolkit commit and every `--define`.
- `--define <pkg>:<KEY>=<VALUE>` (repeatable; on the card as typed) passes
  `cmake.define.<KEY>=<VALUE>` to that package's CMake — e.g. `voro:PECLET_VORO_BUILD_TESTS=ON` for
  the C++ test executables. Keys `sn` sets itself (`PECLET_*_MPI`, the voro engine switches, the
  Python/MPI executables, `CMAKE_PREFIX_PATH`) are refused; a define that moves core
  (`PECLET_SIBLING_PECLET_CORE`, `PECLET_VENDOR_DEPS`) fails the include proof. Each package's CMake
  build dir stays at `build/<tree>-<target>/cmake/<pkg>` (jobs get it as `SN_CMAKE_BUILD`), and the
  source copy of a package with a define is kept (`src_kept` in `BUILD_INFO`): its test binaries
  may read their sources.
- **geom** "vendors" core's geom headers at `PECLET_CORE_TAG` only as the self-contained sdist,
  when `../../core` is absent. In a tree core is always present (push adds it), geom compiles
  `-I <tree>/core/include` and gets the same `core_include` check as every other package: a fetched
  or foreign core fails it (local build of the job, 2026-11-19: `core_include geom ... OK`).
- `--rebuild` refuses while a build job of that dir or any queued/running `sn run` job whose
  `job.sh` names that build dir exists (`sn status`, `sn cancel` first); a second build of one dir
  is refused too.

**Templates** (`tools/hpc/snellius/templates/*.tpl`, the srun lines and binding rules of this document):

| template | target | allocation | launch |
|---|---|---|---|
| `gpu1` | h100, a100 | 1 node, 1 GPU, 16 (18) cores; billed for 1 GPU | `srun --mpi=pmix --ntasks=1 --gpus-per-task=1 --gpu-bind=per_task:1` |
| `gpu-mpi` | h100, a100 | `--gpus N` (4): N ≤ 4 on one node, else N/4 nodes × 4 (N a multiple of 4) | one rank per GPU, `--gpus-per-task=1 --gpu-bind=per_task:1` |
| `genoa-mpi` | cpu | `--ranks N` (192): one shared node below 192, else whole nodes, `--mem=0` when under-filled | `--cpus-per-task=1 --distribution=block:block --cpu-bind=cores`, `OMP_NUM_THREADS=1` |
| `genoa-hybrid` | cpu | `--nodes N` (1), exclusive, `--mem=0`; `--threads T` ∈ 1, 2, 4, 8 | one rank per CCD × 8 threads, `OMP_PLACES=cores OMP_PROC_BIND=close` |
| `quiet1` | cpu | one exclusive genoa node, `--mem=0` (timing gates) | 1 × 24 threads on cores 0–23 by default; `--ranks R --threads T` |

**In every job** (`tools/hpc/snellius/injob.sh`), in this order: refuse a requeue
(`SLURM_RESTART_COUNT > 0`; every job is also `--no-requeue`); stop on `.done`, `.stop` or (a chain
successor) `.failed`; refuse a build dir without `BUILD_INFO` or with a `BUILD_INFO` whose sha256 is
not the one `sn` read at submit (passed as a positional: a rebuild since then); source
`build/.../env.sh`, activate the build's venv, print `BUILD_INFO`'s `MANIFEST` line, on a GPU target
assert `Cuda` in every device module; only then queue the chain successor, and an EXIT trap cancels it
on any exit that does not keep the chain going. Then run the driver in `runs/<campaign>/<tag>/<idx>/`
(`idx` = the array index, 0 without `--array`) and append one line to `summary.tsv`:
`jobid  array_idx  tree  target  rc  wall_s  <last driver line matching ^CERT >` (rc `TERM` at the
walltime, `CANCEL` on an early TERM). The driver gets `SN_OUT`, `SN_DONE`, `SN_IDX`, `SN_CASE`,
`SN_FRESH`, `SN_TREE`, `SN_BUILD`, `SN_CMAKE_BUILD`, `SN_SRUN`; a driver path relative to the tree is
taken from the tree, a `.py` driver runs under the venv's python; `--no-srun` runs the driver in the
batch shell (it launches its own steps with `$SN_SRUN`). `--array cases.txt`: one non-comment line per
index, appended to the driver's arguments.

**Chains** (`--chain K`, the wall-bounded-turbulence pattern): at most K jobs in total per index per
submit from `sn`. The job script takes `fresh <bi>` (first submit), `resume <bi>` (`sn run
--resume`: the count starts again at 1) or `chain <bi> <n>` (a successor, carrying its count). Each
job queues its successor `afterany`; the driver ends the chain by creating `$SN_DONE`; `SN_OUT` stays
the same so a successor resumes from the driver's checkpoint; `SN_FRESH=1` only on the first submit.
A driver that exits non-zero cancels its successor and leaves `.failed` (a successor that runs
anyway stops on it). **Walltime:** every job asks `--signal=B:TERM@120`, so 120 s before the limit
(Slurm may send it up to 60 s early) the batch shell gets TERM; the trap forwards it to the driver
(through `srun` to the tasks), waits up to 90 s for it to checkpoint and exit, records `TERM` and
keeps the successor — a walltime end never writes `.failed` and never cancels the chain. A TERM
more than 240 s before the limit is a cancel (`scancel` by hand): `CANCEL`, the successor is
cancelled, no `.failed`. That the batch shell really gets the signal on Snellius is proven by
`sn walltime-test <tree>` (1 genoa core, `--time 0:03:00`, chain 2, ~3 SBU; verdict
`tools/hpc/snellius/walltime_test.sh check <campaign>/<tag>`).

`sn run` refuses an existing `<campaign>/<tag>` unless `--resume`; `--resume` refuses while jobs of
that tag are queued or running, and unless its `--array` file is byte-identical to the run's
`cases.txt` (an array run needs the same `--array`; the indices map onto the old checkpoints).

## Coordinates

| | |
|---|---|
| host | `snellius` (SSH config alias; `int4.local.snellius.surf.nl` etc.) |
| account | `tes24005` (every `#SBATCH --account`) |
| project space | `/projects/0/prjs1022/peclet` — `src/`, `build/`, `runs/` of the `sn` toolkit (above); the old shared `.../peclet/suite` tree was deleted 2026-11-13 |
| the venv | one per build, `build/<tree>-<target>/.venv` (releases: `$PROJ/suite-<tag>-<backend>/.venv`) |
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
package with `PECLET_*_MPI=ON` — `peclet-morton`, `peclet-geom`, `peclet-halo` (built by `core/`),
the pure-Python `peclet-core` compatibility shell, `peclet-flow`, `-pnm`, `-dem`, `-voro`, `peclet-amr`
and `peclet-coupling` — then import-checks the canonical modules under
`-W error::DeprecationWarning`. It leaves a site-specific wheelhouse other project members can
`pip install --no-index --find-links` from (never upload those wheels to PyPI — they link the
module OpenMPI and CUDA):

```bash
cd $PROJ/suite-v<family>          # SUBMIT FROM INSIDE THE TREE (see the traps below)
sbatch --nodes=1 --gpus-per-node=1 --ntasks-per-node=1             tools/hpc/install_snellius.sh v<family> h100
sbatch -p gpu_a100 --nodes=1 --gpus-per-node=1 --ntasks-per-node=1 tools/hpc/install_snellius.sh v<family> a100
sbatch -p genoa --gpus-per-node=0 --ntasks=1 --cpus-per-task=32    tools/hpc/install_snellius.sh v<family> cpu
# certify each backend (positional <tag> <target>; 1- vs 4-rank permeability, dem step_mpi):
sbatch --nodes=1 --gpus-per-node=4 --ntasks-per-node=4             tools/hpc/smoke_snellius.slurm v<family> h100
sbatch -p gpu_a100 --nodes=1 --gpus-per-node=4 --ntasks-per-node=4 tools/hpc/smoke_snellius.slurm v<family> a100
sbatch -p genoa --gpus-per-node=0 --ntasks-per-node=4 -c 4         tools/hpc/smoke_snellius.slurm v<family> cpu
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
- **Multi-node GPU jobs: request `--nodes=N --gpus-per-node=4`, never a total `--gpus=K` with K > 4.**
  SURF wiki ("Allocating multiple GPU nodes", noted 2026-10-22): with a total above 4, OpenMPI jobs
  that call srun or mpirun hang. Our scripts already use the per-node form (s4, surf_repro).
- **A multi-node GPU job with fewer than 4 GPUs per node is rejected unless `--exclusive`**
  ("You've requested less than the maximum amount of GPUs for your multi-node job", measured
  2026-10-24), and with `--exclusive` it is **billed for all 4 GPUs of every node** — a 2-node ×
  1-GPU test costs 8 GPU-hours per hour. Keep such tests short (`--time=00:10:00`).

### Validated releases

| family | backend | tree | job | outcome |
|---|---|---|---|---|
| v1.1.0 | cpu (genoa) | `suite-v1.1.0-cpu` | 26813727 | **OK** — `flow OpenMP has_mpi True`; **smoke 26814834 CERTIFIED** (see below) |
| v1.1.0 | h100 | `suite-v1.1.0-h100` | 26813725 | **OK** — `flow Cuda has_mpi True`; smoke **26813984 queued** (gpu_h100 was at 56 alloc / 12 resv; est. start 2026-09-17T12:30) — result will be `suite-v1.1.0-h100/peclet-smoke-26813984.out`, compare its two `k` lines |
| v1.1.0 | a100 | `suite-v1.1.0-a100` | 26813726 | **OK** — `flow Cuda has_mpi True`; **smoke 26815101 CERTIFIED** (see below) |
| v1.5.0 | cpu (genoa) | `suite-v1.5.0-cpu` | 28535053 | **OK** — all ten packages incl. amr; `flow OpenMP has_mpi True`; **smoke 28535366 CERTIFIED**: np=1 and np=4 `k=5.845422163491e+00`, `div=1.847e-13` (= 1.1.0) |
| v1.5.0 | h100 | `suite-v1.5.0-h100` | 28535051 FAILED, 28536575 | **OK without amr** — stock script fails on `peclet-amr` (below); rebuilt with the amr-skipping variant `$PROJ/phaseF-v1.5.0/install_noamr.sh`; `flow Cuda has_mpi True`; **smoke 28537289 CERTIFIED** (np=1 = np=4 `k=5.845422163491e+00`); **2 nodes x 1 GPU 28537290 CERTIFIED** (np=1 = np=2, same `k`) |
| v1.5.0 | a100 | `suite-v1.5.0-a100` | 28536577 | **OK without amr** (same variant); `flow Cuda has_mpi True`; **smoke 28555799 CERTIFIED** (np=1 = np=4 `k=5.845422163491e+00`) |
| v1.5.0 | container sm90 | `peclet-cuda:1.5.0-sm90` | 28536273; 2-node 28536563 | **OK** via `containers/snellius-run.sh` (fixed b8c4146; first try 28535248 died on `libhwloc.so.15`): `flow 1.4.0 Cuda has_mpi True`, np=1 `k=5.845422163491e+00`; 2 nodes x 1 GPU host OpenMPI 4.1.5/UCX bound: np=2 same `k` |
| v1.5.0 | container sm80 | `peclet-cuda:1.5.0-sm80` | 28536272 | **OK** — `flow 1.4.0 Cuda has_mpi True`, np=1 `k=5.845422163491e+00` |

Each wheelhouse (`$PROJ/wheelhouse/v1.1.0-<backend>/`) carries all seven packages at the released
versions: flow 1.1.0, core/dem/pnm/voro 1.0.2, morton/coupling 1.0.1, cp312, linked against the
module OpenMPI + CUDA 12.6 — **site-specific, never upload these to PyPI**. Project members install
into their own venv:

```bash
source $PROJ/suite-v<family>-<backend>/tools/hpc/snellius_env.sh   # Python 3.12 + the OpenMPI/CUDA the wheels link
python3 -m venv ~/venvs/peclet && source ~/venvs/peclet/bin/activate
pip install numpy mpi4py      # from PyPI: the wheelhouse holds only peclet wheels; mpi4py builds against the module mpicc
pip install --no-index --find-links $PROJ/wheelhouse/v<family>-<backend> peclet-flow
python -c "import peclet.flow as f; print(f.execution_space, f.has_mpi)"   # h100/a100: on a GPU node
```

Without the module environment `python3` is the system 3.9 and the cp312 wheels do not match; without
the `numpy` step the `--no-index` install fails on `numpy>=1.20` (the 1.1.0 text said only the last
pip line; corrected 2026-10-24). A GPU wheelhouse does not import on a login node (no `libcuda.so.1`).

**v1.5.0 (Phase F, 2026-10-24/25).** Every backend gives `k = 5.845422163491e+00`, `div = 1.847e-13`,
9 pressure iterations — the 1.1.0 value to all thirteen digits, on cpu, h100, a100, both containers and
across two nodes. **The GPU wheelhouses lack `peclet-amr`:** the tag's amr (0.2.0, `7bf183a`) does not
compile under nvcc 12.6 (`amg_bottom.hpp`/`multigrid.hpp`: extended `KOKKOS_LAMBDA` in private member
functions; fixed on amr main `ae970b1`, unreleased), so `install_snellius.sh` dies at `wheel ./amr`.
The h100/a100 trees were built with `$PROJ/phaseF-v1.5.0/install_noamr.sh` (the stock script minus amr)
and smoked with `smoke_noamr.slurm` (minus the `peclet.amr` import). The next family release with the
amr fix needs the stock script again. Containers: `$PROJ/containers-v1.5.0/` (sifs + `container_smoke.slurm`).
The 4-GPU tile is slow on both GPU partitions (h100 3152 ms/step, a100 2346 ms against 1.1.0's 103.6) —
anomaly G5 below; numerics unaffected.

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

Superseded for campaign work by `sn build` (above), which builds a pushed, read-only tree instead of
a shared clone. Kept as the record of the scripts it came from.

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

One NUMA domain, hybrid MPI × OpenMP (genoa, NPS4: cores 0–23 = 3 CCDs × 8 cores). Threads per
rank must divide the 8 cores of a CCD (1, 2, 4, 8); one rank per CCD is the recommended hybrid
(`../docs/DECOMPOSITION_AND_MULTIGRID.md` §3 rule 9). On an exclusive node, inside the job's
`--cpus-per-task` blocks:

```bash
# 3 ranks x 8 threads (one rank per CCD) / 6 ranks x 4 threads (two per CCD)
export OMP_NUM_THREADS=8 OMP_PLACES=cores OMP_PROC_BIND=close     # 4 for 6x4
srun --mpi=pmix --ntasks=3 --cpus-per-task=8 --distribution=block:block --cpu-bind=cores \
     "$VENV/bin/python" driver.py                                     # --ntasks=6 --cpus-per-task=4
```

Never 8 × 3 (two ranks straddle a CCD, +18 % step time measured); `init_mpi` warns about such a
placement on stderr. ctests keep `--bind-to none` (MPIEXEC_PREFLAGS).

**3 × 8 is confirmed** (S-PART, job 28464076, cores 0–23 of one node, the bubble column 128×96×64,
median ms/step; `flow/doc/vof_distributed_partition_design.md` §13): one rank × 24 threads 68.0
(no MPI needed: use it); **3×8 78.5**, the fastest distributed layout (+15 %); 6×4 81.7; 24×1 85.5
(only when the code needs one thread per rank); 8×3 100.1. Multi-node: the same rule per node,
one rank per CCD:

```bash
# N nodes x 24 ranks x 8 threads (2-socket genoa node = 24 CCDs of 8 cores)
export OMP_NUM_THREADS=8 OMP_PLACES=cores OMP_PROC_BIND=close
srun --mpi=pmix --nodes=$N --ntasks-per-node=24 --cpus-per-task=8 --distribution=block:block \
     --cpu-bind=cores "$VENV/bin/python" driver.py
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

## Measured: VoF bubble-swarm weak scaling, H100 (2026-10-26..28)

256³ cells + 8 bubbles (d/h 20) per GPU, triply periodic, MG depth 7, flow 661eee6, 110 timed steps per leg,
host-staged halos (the Snellius default). Bit-identical across transports and comm-avoiding modes; 9.03
pressure iterations per step at every NP. 454 SBU in total. Record: `~/Codes/bubble_column_perf/gpu_diag/weak/WEAK_PROD.md`.

| NP (tiles) | 1 | 2 (2,1,1) | 4 (2,2,1) | 8 (2,2,2) | 16 (4,2,2) | 32 (4,4,2) |
|---|---|---|---|---|---|---|
| ms/step, host-staged | 104.4 | 166.0 | 229.3 | 270.9 | 264.8 | 298.0 |
| ms/step, comm-avoiding off | | | 206.5 | 232.2 | | 263.5 |
| E vs single rank (99.7) | 0.955 | 0.600 | 0.435 | 0.368 | 0.377 | 0.334 |

- The loss is inside a node (1 → 4 GPUs: 104 → 229 ms); 4 → 32 GPUs costs 229 → 298 ms (0.77 over 8×).
- Comm-avoiding smoothing is slower on GPUs at every NP measured (−21…−39 ms/step off) and bit-identical;
  USER 2026-10-29: its default becomes off on device backends.
- GPU-aware MPI (G5) remains 1.6× (np 2) and 5.6× (np 4) slower than host-staged; SURF still investigating.
- A first NP 16 run took 446.8 ms/step (≈ 214 ms outside the timed solver phases); the repeat on other nodes,
  same hash, 264.8 — one-off, like C1.

## Open performance anomalies (2026-10-18)

Unexplained timings on Snellius, kept here so a later run is read against them. Multi-GPU runs are
judged by weak scaling at a size per GPU that fills the GPU (register, suite-wide, 2026-10-18).
Evidence lives in `~/Codes/bubble_column_perf/` (not in git) unless a repo path is given.

| # | where | what | status |
|---|---|---|---|
| G1 | gpu_h100, 1 node, job 28221803 (gcn105) | bubble column 128x96x64 split over 4 H100s (64x48x64 per rank, GPU-aware UCX, `--gpu-bind=per_task:1`): 1335 ms/step against 46 ms at 2 GPUs; only the pressure solve slows (~3.4 ms per halo exchange, cost follows bytes). The 4-rank case is the only one-node case pairing GPUs (26,C6) and (06,A6). Not reproducible on the workstation (MPI there is not CUDA-aware; the same decomposition costs the same as an x-only split). | reproduced stand-alone, job 28262849 (gcn87, core v1.5.0 `GridHalo` bench): 2x2 layout 4.4 ms/exchange (4.3 ms inside the MPI_Isend/Irecv posts) vs 52-64 µs for 4x1 and 2x1 with larger messages; same with all 4 GPUs visible per rank (4.3 ms); host-staged 96 µs. Per-task binding denies other `/dev/nvidiaN` (no CUDA IPC). GPU pair vs pattern not separated. Workaround: host-staged MPI (the default). Ticket sent to SURF 2026-10-22 (type Problem; `gpu_diag/SURF_TICKET_DRAFT.md`) |
| G2 | gpu_h100, 2 nodes, job 28221804 (gcn153, gcn158) | same case with 0.79M cells per GPU, 8 GPUs: ~1.2 ms per halo exchange, bytes-sensitive (one node: 0.08-0.2 ms). | same as G1, inter-node path |
| G3 | gpu_h100, release 1.1.0 | packed bed 384³ strong ladder: 16 GPUs 1349 ms/step against 574 at 8 and 539 at 32; same iterations and sweeps, reproduced on 4 allocations | undiagnosed (`peclet-examples/benchmarks/release-1.1.0-scaling/index.qmd`) |
| G4 | gpu_h100, one node | fixed cost per halo exchange 0.08-0.2 ms with GPU-aware MPI between H100s on one node, against ~10-20 µs expected over NVLink | job 28262849: the bare exchange is 34-65 µs per exchange (1-3 partners, ~11 µs of it launch + sync), so most of flow's 0.08-0.2 ms is flow-side overhead, not transport; matters only for small subdomains |
| G5 | gpu_h100 + gpu_a100, 1 node x 4 GPUs, release smoke tile (`profile_mpi_flow.py --L 48`, grid 1x2x2, default host-staged MPI) | v1.5.0: h100 3152 ms/step (28537289), a100 2346 ms/step (28555799) against 103.6 ms on a100 at v1.1.0 (26815101); 2 nodes x 1 GPU (grid 2x1x1) 61.6 ms (28537290); cpu 142.5 ms (28535366). Same 9 pressure iterations, same `k`. Same 2x2-layout signature as G1, but now on A100 too and ~20x the 1.1.0 time | **transport, not layout** (job 28563748, a100, 2026-10-25): same tile, same 1x2x2 grid and 48³ blocks in both runs (as at 1.1.0), (a) default = `peclet.core halo: DEVICE MPI buffers (auto)` 2558.6 ms/step; (b) `PECLET_CORE_GPU_AWARE_MPI=0` = host-staged 112.0 ms/step (1.1.0: 103.6); `k=5.845422163491e+00`, `div=1.847e-13` identical in both. So it is G1's 2x2 GPU-aware pathology, exposed because core's GPU-aware path now auto-enables when the probe passes; the partition did not change. (c) a forced 1-D split: NOT RUN -- the 1.5.0 API (`set_decomposition(levels, max_imbalance)`, `mpi_block`) cannot force 4x1 on this 48x96x96 domain without code. Workaround on Snellius until SURF answers the G1 ticket: `export PECLET_CORE_GPU_AWARE_MPI=0` |
| C1 | genoa, 192 cores (64 ranks x 3 threads), jobs of 2026-10-03 and 28238662 | rare single-step stalls of 340-500 ms against a 55 ms median in peclet runs (seen in both jobs) | undiagnosed; quote medians of runs |

## Pointers

- `docs/DECOMPOSITION_AND_MULTIGRID.md` — the per-axis coarsening rule, aligned vs coarse-first
  partitions, and why grid dimensions' factors of two decide solver cost. Read before choosing a
  benchmark grid.
- `docs/archive/COMMUNICATION_SCALING.md` — the halo/smoother communication design the scaling studies test.
- `peclet-examples/benchmarks/porous-scaling/README.md` — the most complete worked runbook
  (two ladders, ablations, and a forensic history of a real GPU-only corruption bug).
