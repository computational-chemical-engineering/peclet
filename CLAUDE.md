# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`suite/` is the **`peclet`** umbrella repository for GPU-accelerated and parallel scientific computing — particle dynamics, CFD, and the spatial-indexing primitives they build on. It holds **eight method/infrastructure projects as git submodules** (`core`, `amr`, `morton`, `flow`, `pnm`, `dem`, `voro`, `coupling`), each its own self-contained repo with its own `CMakeLists.txt`, build system, and (in some cases) its own `CLAUDE.md`. There is no top-level build or test runner — work happens *inside* a submodule, not at this level.

**Consequence for any task:** `cd` into the relevant submodule before building, testing, or running git. A `git status` / commit / diff issued from `suite/` itself acts on the **umbrella** (submodule pointers + shared `docs/`), not on a method code — so commit code changes inside the submodule first, then bump the pointer in the umbrella.

## Direction of the suite (read before cross-cutting work)

The codes are being given a shared foundation while staying separate method codes: one MPI **block
decomposition** with efficient **asynchronous ghost-layer exchange**, common **SDF** solids and
**IBM**, **GPU** support, and **Python bindings** everywhere. The reusable parts of the old
`block_decomposer` (now **retired/archived**) were extracted into the shared **`core/`**
library (header-only C++20, its own git repo + `CLAUDE.md`) that every method depends on.

**`core/` status:** complete and tested (109 plain / 164 Kokkos / 7 Python ctests, `mpirun -np 1..8`; morton-guarded tests SKIP with exit 77, never pass silently). Provides ORB block
decomposition; the async grid ghost-layer exchange (`peclet::core::halo::GridHalo` — topology/exchange split,
field-agnostic, NBX + persistent neighborhood-collective engines, overlap-capable, plus a GPU-resident
host-staged variant); the Lagrangian halo (`peclet::core::halo::ParticleMigrator` — particle migration +
`gatherGhosts`); SDF geometry with scalar/vector VTI I/O; and **dynamic load balancing** (weighted ORB
`BlockDecomposer::init(…, weights)` + `DistributedOctree::rebalance` for AMR leaf/field migration and
`rebalanceByParticleCount` for the Lagrangian path). See `core/CLAUDE.md`.

**Consumers:** the compute codes are all **Kokkos**-based (raw CUDA retired 2026-06-20). `flow` has a **complete, validated distributed
Navier–Stokes solver** (`flow`) on the core: the whole cut-cell IBM + MG-PCG step runs multi-rank,
bit-exact to single-rank (`tests/kokkos_mpi`, 18 ctests np=1,2,4, gated `PECLET_FLOW_MPI`). `flow` is **THE**
flow solver; pore-network extraction is the separate `pnm/` project (`peclet.pnm`, split out of flow
2026-07). `dem`'s `peclet.dem` module runs the
full XPBD step (ArborX broad-phase) with a validated distributed `step_mpi` that drives the SAME
modern solver stack as the single-GPU step (shared `demSolveContacts` driver, processor-block
Gauss–Seidel: rank-local coloring + warm-started PGS with gid-keyed persistent contacts +
statics/stabilization), a distributed **force-based** engine (`step_hertz_mpi` — explicit
Hertz–Mindlin as the first law of the generalized `demStepForce` driver, domain-decomposed MD-style
with gid-keyed Mindlin history; `tests/kokkos_mpi` 24 ctests, host + CUDA) and periodic **load
rebalancing** (`enable_mpi_step(rebalance_every=…)` / `Sim.rebalance()` — SoA ownership migration on
the weighted ORB, both engines' contact ledgers carried). The single-GPU codes are complete +
faster than the retired CUDA at scale; remaining work is at-scale multi-GPU tuning — see
[docs/ROADMAP.md](docs/ROADMAP.md).

The design contract lives in `docs/`:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layering, dependency graph, Lagrangian/Eulerian/mixed taxonomy, how each code maps onto the core.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — SDF sign, x-fastest indexing, types, precision policy, periodic/Lees–Edwards, Python array shapes.
- [docs/DECISIONS.md](docs/DECISIONS.md) — the **decision register**: what the project chose, what it rejected, and why, for all 512 decisions (460 in force, 52 superseded), with verbatim quotes and provenance in [docs/decisions/](docs/decisions/). It exists because settled decisions were being silently reversed — a later session picking the textbook alternative because nothing in front of it said the project had already rejected that alternative on purpose. Each submodule's `CLAUDE.md` inlines its own highest-risk prohibitions. **Read the entry for anything you are about to change; reversing one takes a new recorded decision, not a judgement call in the moment.**
- [docs/NAMING.md](docs/NAMING.md) — the **naming canon**: one spelling per concept across all five Python APIs (the `origin`/`extent`/`cells`/`spacing` domain quartet, `num_*` counts, `periodic=`, `set_dt`, American spelling, `get_` only for a transfer), the table of every current divergence and its status, and the additive-alias rule for changing a shipped name. **Read before adding a public name.**
- [docs/STYLE.md](docs/STYLE.md) — C++20 host & Kokkos device (morton pins C++17), clang-format/tidy (from voronoi), namespaces, CMake/CI.
- [docs/INTERFACES.md](docs/INTERFACES.md) — shared C++20 concepts: `Domain`, `Decomposition`, `Field`, `HaloExchange`, `SdfGeometry`, `ImmersedBoundary`, `Stepper`.
- [docs/DECOMPOSITION_AND_MULTIGRID.md](docs/DECOMPOSITION_AND_MULTIGRID.md) — how the MPI decomposition and the pressure multigrid constrain each other: the per-axis coarsening rule, why grid dimensions' factors of two decide solver cost, aligned vs coarse-first partitions, the measured evidence, and the open problems. **Read before touching decomposition, load balancing or MG depth.**
- [docs/ROADMAP.md](docs/ROADMAP.md) — phased plan; the decomposition, async halo engine, and dynamic load balancing (Phase 7) are done — remaining work is at-scale multi-GPU tuning.
- [docs/SCALING_ISSUES.md](docs/SCALING_ISSUES.md) — prioritized register of the issues the FoxBerry head-to-head scaling campaign surfaced (2026-09-01). The top two are float operator storage **silently invalidating** dense-bed runs and the multigrid depth cap that costs a third of the strong-scaling efficiency at 1536 ranks. **Read before starting scaling or IBM work.**
- [docs/QUALITY_PLAN.md](docs/QUALITY_PLAN.md) — the **quality work list** opened 2026-09-08 after a full audit: decisions D1–D9 (the next release is the clean-break **1.0.0**, one spelling per concept with no aliases, two API tiers, no numerics-changing env vars, one version source, honest CI, core = infrastructure with AMR *relocated* not deleted), the rename table, and work packages A–H in order. **Read before adding a public name, an env var, or a file at a repo root.** Packages A–F and G.1–G.7 and H are **done in every repo** (verified against the repos 2026-09-11, not merely asserted in the plan); only **G.8** — flow's explicit-instantiation build-time refactor, queued as non-breaking, before or after the tag — remains. Start from **§6, the handoff**, which carries the per-repo starting point, the gates, and the two lessons the work produced.
- [docs/RELEASE.md](docs/RELEASE.md) — the family release workflow (PyPI CPU + CUDA wheels, containers,
  Snellius/LUMI site packages, Zenodo, gallery re-check) with the current cycle's state and decisions in
  [docs/RELEASE_PREP.md](docs/RELEASE_PREP.md); pre-flight + audits in `tools/release/`, site scripts in
  `tools/hpc/`. **Read before bumping a version or tagging anything.**
- [docs/archive/](docs/archive/README.md) — dated design notes and campaign records (AMR, analytic SDF,
  VoF, Voronoi methods, multiphysics, defect correction, MG telescoping, device residency, the CUDA
  wheel prototype). Superseded by the code and the reference docs above — history, not contract.
- [docs/SNELLIUS.md](docs/SNELLIUS.md) — running on the Snellius cluster: the 2024a toolchain, building (and the CMake/venv traps), the sbatch conventions every benchmark script shares, and pre-flight checks. **Read before queueing anything there.**

## Worktrees: the default when another session shares a checkout

**These checkouts are shared.** A dozen-plus Claude sessions run against this suite at once; on
2026-09-11 two separate edits of `flow/CLAUDE.md` were swept into another session's commits within
the hour. Staging named paths (the standing directive) stops *you* taking *their* files; it does not
stop *them* taking yours. A worktree is the other half.

**Work in one whenever another session is or may be in that submodule**, whenever the task spans more
than a commit or two, and always when touching a file everyone touches (`CLAUDE.md`, `CHANGELOG.md`,
`cmake/PecletDeps.cmake`). A read-only look or one quick commit does not need one.

Historically the cost was the rebuild, which is why the shared tree kept winning. QUALITY_PLAN G.8
(compile `Solver<Grid>` once, not once per consumer) cut that materially for `flow`, so the honest
answer has changed: **isolate by default, share only for something trivial.**

### The convention (already in use — `flow` has 15)

A worktree is a **sibling of the submodule**, named `<repo>-<topic>`:

```bash
cd flow && git worktree add ../flow-<topic> -b <topic>     # -> suite/flow-<topic>
cd ../flow-<topic> && source ../.venv/bin/activate
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
```

**The sibling position is load-bearing, not cosmetic.** Everything in this suite is reached by `../`
from inside a submodule: the one venv (`../.venv`), the Kokkos/ArborX prefixes
(`../extern/install/<backend>`), and the sibling headers `PecletDeps.cmake` prefers over a
FetchContent. Put the worktree anywhere else — nested under a subdirectory, or outside `suite/` — and
those resolve to nothing: the venv silently falls through to the system Python (see "One venv"), and
CMake silently fetches pinned tags instead of using your siblings. `suite/tel/flow` is an existing
worktree that does *not* satisfy this; do not copy it.

Each worktree carries **its own `build*/` directories** — never share a build tree between worktrees,
and never point one at another's. The `extern/install/<backend>` prefixes are read-only and shared by
design.

### Housekeeping

- Branch per topic, not per agent. `git worktree list` inside the submodule before adding another —
  there are already abandoned ones (`.claude/worktrees/agent-*` at the umbrella, from 2026-09-02).
- `git worktree remove ../flow-<topic>` when the branch lands; `git worktree prune` for stale entries.
- The submodule is the unit. A worktree of the **umbrella** does not give you worktrees of the
  submodules — it gives you the same submodule checkouts, shared with everyone. Isolate the submodule
  you are changing.
- Umbrella pointer bumps still happen in the real `suite/` checkout, after the submodule is pushed.

## Settled decisions that cross the whole suite

Full register in [docs/DECISIONS.md](docs/DECISIONS.md). These are the cross-cutting ones; each
submodule's `CLAUDE.md` carries its own.

- **The collocated pressure coupling is the Almgren–Bell–Colella approximate projection — NEVER
  Rhie–Chow.** Held independently by `flow`, `amr` and `voro`, and re-proposed by mistake in all
  three. The residual cell divergence is *intrinsic* to cell-centred velocity placement; Rhie–Chow
  is not an "upgrade".
- **Every numerical method runs fully on-device and must be MPI-distributable.** Host serial paths
  are permitted only as oracles and unit tests, never as the production path.
- **Never change numerics while porting.** A backend change is a faithful port, proved bit-identical.
- **Identifiers name what a thing is, never where it runs.** No `Device*` / `*Kokkos` class names;
  device-resident duals take the data-structure suffix `View`. Transfer verbs and prose are the
  kept exceptions.
- **Kokkos device sources are `.cpp`, never `.cu`**; provisioning is a shared install prefix plus
  `find_package`, never `FetchContent`.
- **All coupled methods share one `BlockDecomposer`** — static-only co-decomposition is rejected.
- **USER DIRECTIVE — `peclet.flow` is the reference** for shared-method design elsewhere in the
  suite; study it before designing the same method in another code.
- **USER DIRECTIVE — match or exceed SOTA massively-parallel performance in every component**,
  setup included.
- **USER DIRECTIVE — solvers take a physical domain and physical properties.** Spatial discretization
  is derived, never user-supplied; **never add cell-unit API surface** — new setters take physical
  inputs.
- **USER DIRECTIVE — CFD-DEM defaults to `porous=True`** (volume-averaged NS, ε in the fluid
  equations and not merely in the drag). `porous=False` is a cheap approximation only, never for
  published benchmark comparison.
- **USER DIRECTIVE — never `git add -A` / `git add .` / `git commit -a`.** Stage named paths only;
  on a shared checkout, verify the index before committing — concurrent agents share these trees.
- **USER DIRECTIVE — push directly to main across the suite, no PR flow.** The umbrella is pushed
  **last**, so submodule pointers never dangle; `core` is tagged and published before any consumer.
- **USER DIRECTIVE — quality is the prime objective**; the next release is the clean-break 1.0.0.

## The projects

| Directory | Language / stack | What it does | Has own CLAUDE.md |
|-----------|------------------|--------------|-------------------|
| `core/` | Header-only C++20 + MPI | **Shared infrastructure**: ORB block decomposition + asynchronous ghost-layer exchange (NBX + persistent engines) + particle migration + SDF geometry + dynamic load balancing. The layer every method code depends on; also the shared `solver/` layer (face-CSR operator, BiCGStab, graph colouring, GraphAMG) that voro and amr build on. Tested (53 plain / 68 Kokkos / 6 Python ctests, np 1–8). | **Yes — read it** |
| `amr/` | Header-only C++20 + **Kokkos** + MPI (Python `peclet.amr`) | **Block-octree AMR** (per-block Morton octree, distributed octree with leaf/field rebalance, solution-adaptive refinement) and the collocated cut-cell Navier–Stokes solver on it (ghost projection, mixed-level cut band, AMR multigrid/BiCGStab). Split out of `core/amr/` with its history on 2026-09-10 (QUALITY_PLAN G.2, D6); depends on `core` + `morton` only. Under active development. 100 ctests (np 1–8) + 3 Python. | **Yes — read it** |
| `morton/` | Header-only C++17 (+ **Kokkos**, Python `peclet.morton`) | Morton/Z-order codes with **arithmetic in Morton space** (neighbour-find, axis add, Z-order step without decode→re-encode). BMI2/AVX-512 + runtime dispatch; the foundational spatial-index library. Portable **Kokkos** GPU backend (`include/morton/kokkos.hpp`, CUDA/HIP/OpenMP) — raw CUDA retired. | **Yes — read it** |
| `flow/` | **Kokkos** + C++20 + nanobind (`flow`) | Incompressible Navier–Stokes solver for porous media: staggered MAC grid, Immersed Boundary Method over SDF geometry, pressure projection. **CUDA retired** (Kokkos: CUDA/HIP/OpenMP). | **Yes — read it** |
| `pnm/` | **Kokkos** + C++20 + nanobind (`peclet.pnm`) | Pore-network extraction from SDF geometry: pore detection, marker-controlled watershed segmentation, throat topology (`SDFReader`, `extract_pores`, `segment_volume`, `extract_topology_gpu`, fused `extract_pore_network`). **Distributed MPI extraction** on the core ORB (`extract_pore_network_mpi`, gated `PECLET_PNM_MPI`) — bit-exact to single-rank, `tests/kokkos_mpi` ctests np=1,2,4 host+CUDA. Split out of `flow` (2026-07) with its git history. | Yes (brief) |
| `dem/` | **Kokkos + ArborX** + C++20 + nanobind (`peclet.dem`) | Discrete Element Method (DEM): XPBD solver + SDF point-shell collision for dense particle packing. Optional MPI. **CUDA retired** (Kokkos: CUDA/HIP/OpenMP). | Yes (brief) |
| `voro/` | **Kokkos** + C++17/20 (+ core MPI, nanobind; Voro++ fetched as a benchmark reference) | Dynamic 3D Voronoi tessellation of moving particles; periodic & Lees–Edwards boxes, incremental cell repair, Euler/NS/multiphase dynamics. Kokkos (CUDA/HIP/OpenMP) + core MPI; the legacy half-edge CPU oracle has been **retired**. | No |
| `coupling/` | **Kokkos** + Python (`peclet.coupling`) | CFD-DEM coupling of `flow` + `dem`: unresolved volume-averaged (`CfdDem`) and resolved cut-cell (`ResolvedCfdDem`) drivers; one shared `BlockDecomposer`, distributed when both codes are. Pure-Python drivers live in `python/peclet_coupling/` (see "Local dev imports" below). | No |

Common threads worth knowing when moving between them: SDFs (signed distance fields) are the shared geometry representation across `flow` and `dem`; VTI/VTP files (ParaView/Ovito) are the shared I/O format; periodic boundary conditions appear everywhere; and the GPU codes (`flow`, `dem`, `core`'s device halo) are now **Kokkos**-based — the backend (CUDA/HIP/OpenMP) and arch are chosen by the `extern/install/<backend>` prefix the build is pointed at, not hard-coded in the sources (`tools/bootstrap_deps.sh` + `CMakePresets.json`).

## Per-project quick reference

For `morton` and `flow`, **defer to their own `CLAUDE.md`** — the entries below are only an entry point.

### morton
```bash
cd morton
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
ctest --test-dir build --output-on-failure
./build/tests/morton_tests --test-case="<name>"     # single doctest case
```
The non-BMI2 build is contractually PDEP/PEXT-free (a test greps the binary). AVX-512 batch kernels have no local hardware — validate under Intel SDE (`sde64 -skx -- ./build/tests/morton_tests`). See its CLAUDE.md for the runtime-dispatch and wheel-build subtleties.

Both `flow` and `dem` now build via `find_package(Kokkos)` (+`ArborX` for packing) against the
bootstrapped prefix `extern/install/<backend>` (built once by `tools/bootstrap_deps.sh` — a **hard build
dependency**). Put `nvcc` on `PATH` for the CUDA backend (`export PATH=/usr/local/cuda-13.2/bin:$PATH`).

### flow
```bash
cd flow && source ../.venv/bin/activate       # THE suite venv (see "One venv" below); nanobind
                                              # is found via the active interpreter (SuiteNanobind)
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j                          # -> build/peclet/flow/_flow.*.so (the solver)
# (canonical install: CMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda" pip install .)
PYTHONPATH=$PWD/build python scripts/verify_poiseuille_flow.py        # analytical-solution check
PYTHONPATH=$PWD/build python scripts/verify_periodic_spheres_sdflow.py  # cut-cell Stokes through spheres
```

### pnm
```bash
cd pnm && source ../.venv/bin/activate        # same interpreter/nanobind as every other project
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j                          # -> build/peclet/pnm/_pnm.*.so (import peclet.pnm)
PYTHONPATH=$PWD/build python scripts/test_extraction.py ../flow/data/packing_ring.vti
PYTHONPATH=$PWD/build python scripts/verify_segmentation.py ../flow/data/packing_ring.vti
# Distributed extraction (-DPECLET_PNM_MPI=ON): mpi_block + extract_pore_network_mpi, bit-exact
# to single-rank; MPI ctests: cmake -S tests/kokkos_mpi -B build_kmpi -DMPIEXEC_EXECUTABLE=/usr/bin/mpirun ...
```

### dem
```bash
cd dem && source ../.venv/bin/activate        # the suite venv already has nanobind + numpy
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j$(nproc)                  # -> build/peclet/dem/_dem.*.so (import peclet.dem; -DPECLET_DEM_MPI=ON for the MPI step)
export PYTHONPATH=$PYTHONPATH:$(pwd)/build
python examples/verify_packing_spheres.py       # examples/ = demos; tests/python/ = pytest
# Registered tests: -DPECLET_DEM_BUILD_TESTS=ON → 11 ctests (kokkos + arborx + pytest),
# + -DPECLET_DEM_MPI=ON → 47 (kokkos_mpi + Python MPI at np=1,2,4); every test SKIPs with exit 77.
```
Since 2026-09-08 (QUALITY_PLAN D) there are no root-level scripts: `tests/python/test_*.py` are pytest
functions run by ctest, `tests/python/mpi/` the MPI ones, `examples/` the demos (`pack.py`,
`verify_*.py`, `generate_*.py`, `bench_step.py`). Three legacy gotchas are recorded in `dem/CLAUDE.md`
(the velocity solve is off by default, there is no default gravity, the `(N,4)` w column is the
inverse mass).

### voro
```bash
cd voro && source ../.venv/bin/activate
# Tests are registered ONLY with -DPECLET_VORO_BUILD_TESTS=ON (default OFF): a plain
# `cmake -B build` configures zero tests ("No tests were found!!!"), which is not a failure signal.
cmake -B build_dev -DPECLET_VORO_KOKKOS=ON -DPECLET_VORO_BUILD_PYTHON=ON -DPECLET_VORO_MPI=ON \
  -DPECLET_VORO_BUILD_TESTS=ON -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build_dev --parallel 8      # -> build_dev/peclet/voro/_voro.*.so (import peclet.voro)
OMP_NUM_THREADS=4 OMP_PROC_BIND=false ctest --test-dir build_dev --output-on-failure   # 42 = 24 + 18 `mpi`
bash tools/clang_format_check.sh          # what the blocking Quality job runs (clang-format 18.1.8)
```
Since 2026-09-08 (QUALITY_PLAN D) there is ONE tree: `tests/kokkos_mpi` is folded in under the
`mpi` label (np=1,2,4; the launcher is taken from beside `MPI_CXX_COMPILER` — ParaView's MPICH
`mpiexec` on PATH used to launch N singletons that "agreed" trivially), the `bench_*` binaries and
the Voro++ fetch are opt-in under `PECLET_VORO_BUILD_BENCHMARKS`, and clang-format is **blocking**
(the tree was reformatted once in `a487777`). `tools/clang_format_check.sh` walks `include/`, `src/`
and `tests/` itself — don't hand-roll globs.
The legacy half-edge `voronoi.hpp` CPU oracle is **gone** — retired in voro `0d4f3b8`
("retire the legacy half-edge engine + rewrite the docs (device-only)"); `include/` now holds only
`peclet/voro/`. Voro++ survives solely as a benchmark throughput reference for `bench_convexcell`.
The production device tessellator stores each Voronoi cell as a compact **dual-triangle ConvexCell**
(a vertex is a triple of plane indices) plus a `facetGeometry` CSR — not the old half-edge mesh
(see README).

### One venv for the whole suite

There is **one** development virtualenv, `suite/.venv` (gitignored), and every project uses it:

```bash
source /path/to/suite/.venv/bin/activate    # or ../.venv from inside a submodule
```

It carries nanobind, numpy/scipy/numba/h5py/pandas, matplotlib/pyvista/scikit-image, mpi4py,
cupy-cuda12x, scikit-build-core/hatchling/build, pytest, clang-format and the Jupyter stack — the
union of what the per-project venvs held.

**Why one.** `coupling` composes `flow` + `dem` in a single interpreter by design, and `pnm` already
borrowed flow's venv, so a shared interpreter was the de-facto requirement. The per-project venvs had
also drifted (three nanobind copies; numpy 2.3.5 vs 2.5.0; scipy 1.16.3 vs 1.17.0), and nanobind's
version wants to be consistent across extensions that interoperate.

**Do not `mv` or rename a venv.** A venv bakes absolute paths into `bin/activate*` and every console
script. The retired per-project venvs had been moved repeatedly (`~/Codes/dem-gpu` →
`suite/packing-gpu` → `suite/dem`, and `~/Codes/pnm_from_sdf` → `suite/cfd-gpu` → `suite/flow`), which
left `activate` exporting a dead `VIRTUAL_ENV` and prepending a non-existent `PATH` entry. The failure
is SILENT and nasty: `python` disappears, while `python3` and `pip` fall through to `/usr/bin` — so
everything after `activate` runs against system Python and a `pip install` targets the system
interpreter. If the suite directory ever moves, delete `.venv` and recreate it.

**Local dev imports** come from the build tree, not an install: `PYTHONPATH=<build-dir>`. The
`coupling` module additionally needs its three pure-Python files staged beside the extension
(`cp coupling/python/peclet_coupling/{__init__,driver,resolved}.py <build>/peclet/coupling/`), because the
importable package is `peclet.coupling` — the `python/peclet_coupling/` directory is only the source
location that the wheel install maps into place.

## Conventions across the suite

- **Concurrent agents in ONE repo use worktrees, never one shared checkout.** A bare `git commit` takes the
  whole shared index (flow `628d3da` swept another agent's staged docs, 2026-09-08), and a half-edited
  header breaks the other agent's build. `git -C <repo> worktree add ../<repo>-<task> -b agent/<task>`
  beside the packages (so `../core`, `../morton`, `../extern/install` still resolve), own `build_*` tree
  inside it, the coordinator `--ff-only` merges into `main`, re-gates once, pushes and removes the
  worktree. Agents in *different* repos keep the plain checkouts, and everyone commits with a pathspec
  (`git commit <paths> -m …`). Full rebuilds of flow cost ~50 CPU-minutes (QUALITY_PLAN G.8) — a worktree
  is for real work, not a five-minute fix; `ccache` makes the second one cheap.

- **The `nvidia-cuda` prefix carries an OpenMP HOST backend since 2026-08-30**
  (`OPENMP;SERIAL;CUDA`; `core/docs/amr_setup_parallel_plan.md` D1′): host-side Kokkos
  `parallel_for`/`parallel_scan` (the AMR setup builders) run multithreaded. Consequences:
  **bound the pool** — `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` for test batteries (an unbounded
  pool on a 48-core host is a measured hour-long trap), and thread-count-pinned probes (e.g.
  `.sdf-campaign-probes/flow_probe.py` at 4 threads) must keep their pinned counts. Binaries
  built before the switch statically link the old Kokkos and are unaffected until rebuilt —
  but do NOT compose old- and new-prefix modules in one Python process (e.g. `coupling`
  importing flow + dem) until both are rebuilt against the same prefix.

- **Kokkos C++ projects** (`flow`, `dem`) put device kernels in header-only `.hpp` (compiled as C++; the Kokkos launch compiler routes them through `nvcc`/`hipcc` — never `.cu`) and expose the simulation as an importable Python module via a nanobind binding TU (built with scikit-build-core, on core's zero-copy View↔ndarray bridge); drive simulations from Python, not C++ mains.
- **Header-only C++ projects** (`morton`, `voro`, `core`) put the real logic in templates under `include/`; there is no library to link.
- Build artifacts (`build/`, `build_*/`, `.venv/`, `*.so`, `__pycache__/`) and large output assets (`*.vti`, `*.vtp`, `*.png`) are committed/present in several projects — don't treat their existence as something you created, and prefer the project's own out-of-source `build/` directory.
- Two projects carry `AGENTS.md`/`GEMINI.md` alongside `CLAUDE.md` (flow); when editing guidance, the CLAUDE.md is the one that governs Claude Code.
