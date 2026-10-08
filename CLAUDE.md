# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`suite/` is the **`peclet`** umbrella repository for GPU-accelerated and parallel scientific computing — particle dynamics, CFD, and the spatial-indexing primitives they build on. It holds **nine method/infrastructure projects as git submodules** (`core`, `geom`, `amr`, `morton`, `flow`, `pnm`, `dem`, `voro`, `coupling`), each its own self-contained repo with its own `CMakeLists.txt`, build system, and (most of them) its own `CLAUDE.md`. There is no top-level build or test runner — work happens *inside* a submodule, not at this level.

**Consequence for any task:** `cd` into the relevant submodule before building, testing, or running git. A `git status` / commit / diff issued from `suite/` itself acts on the **umbrella** (submodule pointers + shared `docs/`), not on a method code — so commit code changes inside the submodule first, then bump the pointer in the umbrella.

Long-form development notes (worktree rationale, the venv's history, per-project build notes, a
snapshot of each consumer's state) live in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Direction of the suite (read before cross-cutting work)

The codes share one foundation while staying separate method codes: one MPI **block decomposition**
with **asynchronous ghost-layer exchange**, common **SDF** solids and **IBM**, **GPU** support, and
**Python bindings** everywhere. That foundation is **`core/`** (header-only C++20, own repo +
`CLAUDE.md`; extracted from the retired `block_decomposer`): ORB decomposition, `GridHalo` and
`ParticleMigrator`, SDF geometry + VTI I/O, and dynamic load balancing (weighted ORB). It is complete
and tested at `mpirun -np 1..8` — battery and counts in `core/CLAUDE.md`.

**Consumers** are all **Kokkos**-based (raw CUDA retired 2026-06-20). `flow` is **THE** flow solver,
distributed and bit-exact to single-rank; `pnm` (split out of flow) does pore-network extraction;
`dem` runs XPBD and Hertz–Mindlin, both distributed with load rebalancing. Remaining work is at-scale
multi-GPU tuning — [docs/ROADMAP.md](docs/ROADMAP.md); details in DEVELOPMENT.md §4.

The design contract lives in `docs/`:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layering, dependency graph, Lagrangian/Eulerian/mixed taxonomy, how each code maps onto the core.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — SDF sign, x-fastest indexing, types, precision policy, periodic/Lees–Edwards, Python array shapes.
- [docs/DECISIONS.md](docs/DECISIONS.md) — the **decision register**: what the project chose, what it rejected, and why, for every recorded decision (in force and superseded), with verbatim quotes and provenance in [docs/decisions/](docs/decisions/). It exists because settled decisions were being silently reversed in favour of the textbook alternative. Each submodule's `CLAUDE.md` inlines its own highest-risk prohibitions. **Read the entry for anything you are about to change; reversing one takes a new recorded decision, not a judgement call in the moment.**
- [docs/NAMING.md](docs/NAMING.md) — the **naming canon**: one spelling per concept across the Python APIs (`origin`/`extent`/`cells`/`spacing`, `num_*`, `periodic=`, `set_dt`, American spelling, `get_` only for a transfer), current divergences, and the rule for changing a shipped name. **Read before adding a public name.**
- [docs/STYLE.md](docs/STYLE.md) — C++20 host & Kokkos device (morton pins C++17), clang-format/tidy, namespaces, CMake/CI.
- [docs/INTERFACES.md](docs/INTERFACES.md) — shared C++20 concepts: `Domain`, `Decomposition`, `Field`, `HaloExchange`, `SdfGeometry`, `ImmersedBoundary`, `Stepper`.
- [docs/DECOMPOSITION_AND_MULTIGRID.md](docs/DECOMPOSITION_AND_MULTIGRID.md) — how the MPI decomposition and the pressure multigrid constrain each other (per-axis coarsening, factors of two, aligned vs coarse-first partitions, measured evidence, open problems). **Read before touching decomposition, load balancing or MG depth.**
- [docs/ROADMAP.md](docs/ROADMAP.md) — phased plan; decomposition, async halo and dynamic load balancing (Phase 7) are done.
- [docs/SCALING_ISSUES.md](docs/SCALING_ISSUES.md) — prioritized register of the issues the FoxBerry scaling campaign surfaced (2026-09-01), each with its status (#1 float operator storage: resolved, double by default; #2 MG depth cap: routed around by telescoping, the default). **Read before starting scaling or IBM work.**
- [docs/QUALITY_PLAN.md](docs/QUALITY_PLAN.md) — the quality work list of 2026-09-08 (decisions D1–D9: the clean-break **1.0.0**, one spelling per concept with no aliases, two API tiers, no numerics-changing env vars, one version source, honest CI, core = infrastructure with AMR *relocated* not deleted; the rename table; packages A–H). **All packages are done**, G.8 (flow's explicit instantiation, flow `61e9f58`/`8f79c3b`) included; 1.0.0 shipped 2026-09-12. Its decisions still govern: **read it before adding a public name, an env var, or a file at a repo root.**
- [docs/RELEASE.md](docs/RELEASE.md) — the family release workflow (PyPI CPU + CUDA wheels, containers, Snellius/LUMI site packages, Zenodo, gallery re-check); the current cycle's state in [docs/RELEASE_PREP.md](docs/RELEASE_PREP.md); pre-flight + audits in `tools/release/`, site scripts in `tools/hpc/`. **Read before bumping a version or tagging anything.**
- [docs/SNELLIUS.md](docs/SNELLIUS.md) — the Snellius cluster: 2024a toolchain, building (and the CMake/venv traps), the shared sbatch conventions, pre-flight checks. **Read before queueing anything there.** ([docs/LUMI.md](docs/LUMI.md) for LUMI.)
- Also: [docs/CORE_BOUNDARY.md](docs/CORE_BOUNDARY.md) (what stays in core vs geom/amr), [docs/PHYSICAL_UNITS_PLAN.md](docs/PHYSICAL_UNITS_PLAN.md), [docs/PORTABILITY.md](docs/PORTABILITY.md), [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md), [docs/containers.md](docs/containers.md), [docs/AGENT_WORKFLOW_HARDENING.md](docs/AGENT_WORKFLOW_HARDENING.md).
- [docs/archive/](docs/archive/README.md) — dated design notes, campaign records and closed release cycles. History, not contract.
- **Papers** live in the private hub `computational-chemical-engineering/peclet-papers` (checkout `~/Codes/peclet-papers`, since 2026-09-29): publication plan (`PLAN.md`), idea register (`REGISTER.md`, which replaces `docs/PAPER_IDEAS.md` — add an idea there when one comes up), central bibliography, paper agents. Each paper has an Overleaf manuscript, a public study repo `peclet-study-<ID>-<slug>`, and its data on 4TU. The JOSS paper stays in `docs/paper/`.

## Worktrees: the default when another session shares a checkout

**These checkouts are shared** by a dozen-plus concurrent sessions. Staging named paths stops *you*
taking *their* files; only a worktree stops *them* taking yours (incidents: DEVELOPMENT.md §1).
**Isolate by default** — whenever another session is or may be in that submodule, whenever the task
spans more than a commit or two, and always when touching a file everyone touches (`CLAUDE.md`,
`CHANGELOG.md`, a repo's `cmake/PecletDeps.cmake`). A read-only look or one quick commit does not need
one. Agents in *different* repos keep the plain checkouts; everyone commits with a pathspec.

A worktree is a **sibling of the submodule**, named `<repo>-<topic>`, branch per topic (not per agent):

```bash
cd flow && git worktree add ../flow-<topic> -b <topic>     # -> suite/flow-<topic>
cd ../flow-<topic> && source ../.venv/bin/activate
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
```

- **The sibling position is load-bearing.** `../.venv`, `../extern/install/<backend>` and the sibling
  headers `PecletDeps.cmake` prefers all resolve by `../`; anywhere else the venv silently falls
  through to system Python and CMake silently fetches pinned tags. (`suite/tel/flow` violates this;
  do not copy it.)
- **Own `build*/` per worktree** — never share or point at another's. `extern/install/<backend>` is
  read-only and shared by design.
- `git worktree list` before adding one (abandoned ones exist); `git worktree remove` when the branch
  lands (the coordinator `--ff-only` merges, re-gates, pushes); `git worktree prune` for stale entries.
- The submodule is the unit: an **umbrella** worktree shares the same submodule checkouts with
  everyone. Umbrella pointer bumps happen in the real `suite/` checkout, after the submodule is pushed.

## Settled decisions that cross the whole suite

Full register in [docs/DECISIONS.md](docs/DECISIONS.md). These are the cross-cutting ones; each
submodule's `CLAUDE.md` carries its own.

- **The collocated pressure coupling is the Almgren–Bell–Colella approximate projection — NEVER
  Rhie–Chow.** Held independently by `flow`, `amr` and `voro`, and re-proposed by mistake in all
  three. The residual cell divergence is *intrinsic* to cell-centred velocity placement; Rhie–Chow
  is not an "upgrade".
- **Collocated pressure and forces stay INSIDE the implicit momentum predictor — never a face
  acceleration added after the viscous solve (the Basilisk `centered.h` "kick").** Held by `flow`,
  `amr` and `voro`. After the implicit solve the projection cancels the lagged pressure exactly:
  Chorin's dt-dependent steady state, and with the rotational update an explicit pressure diffusion
  growing −12κ·dt/(ρh²) per step (measured −12.0000; it capped flow's collocated VoF at density
  ratio ~100). It came back once despite a register entry, so the guard is a GATE — flow's
  `collocated_stability_guard` and amr's `amr_stability_guard` ctests — not a grep. Design:
  flow `doc/collocated_varrho_forces.md`.
- **Every numerical method runs fully on-device and must be MPI-distributable.** Host serial paths
  are permitted only as oracles and unit tests, never as the production path.
- **Never change numerics while porting.** A backend change is a faithful port, proved bit-identical.
- **Identifiers name what a thing is, never where it runs.** No `Device*` / `*Kokkos` class names;
  device-resident duals take the data-structure suffix `View`. Transfer verbs and prose are the
  kept exceptions.
- **Kokkos device sources are `.cpp`, never `.cu`**; provisioning is a shared install prefix plus
  `find_package`, never `FetchContent`.
- **All coupled methods share one `BlockDecomposer`** — static-only co-decomposition is rejected.
- **No environment variable changes a result** (QUALITY_PLAN D3): numerics and algorithm choices are
  API setters; env vars are for debug output only.
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
- **USER DIRECTIVE — quality is the prime objective** (it set the clean-break 1.0.0, shipped
  2026-09-12).

## The projects

| Directory | Language / stack | What it does | Own CLAUDE.md |
|-----------|------------------|--------------|---------------|
| `core/` | Header-only C++20 + MPI | **Shared infrastructure**: ORB block decomposition, async ghost-layer exchange (NBX + persistent engines), particle migration, SDF geometry, dynamic load balancing; also the shared `solver/` layer (face-CSR operator, BiCGStab, graph colouring, GraphAMG) that voro and amr build on. Tested np 1–8. | **Yes — read it** |
| `geom/` | Header-only C++20, nanobind, **no Kokkos and no MPI** (`peclet.geom`) | **Analytic-SDF scene authoring**: CSG over SDF primitives, batch evaluation, lattice baking, rigid-body mass properties. Its six `peclet/core/geom/*.hpp` headers STAY in `core`, vendored at `PECLET_CORE_TAG` ([docs/CORE_BOUNDARY.md](docs/CORE_BOUNDARY.md)); `peclet.core.geom` works through a compatibility shell until 2.0.0. | No |
| `amr/` | Header-only C++20 + **Kokkos** + MPI (`peclet.amr`) | **Block-octree AMR** (distributed per-block Morton octree, leaf/field rebalance, adaptive refinement) and the collocated cut-cell NS solver on it. Split out of `core/amr/` 2026-09-10 (QUALITY_PLAN G.2, D6); depends on `core` + `morton` only. | **Yes — read it** |
| `morton/` | Header-only C++17 (+ **Kokkos**, `peclet.morton`) | Morton/Z-order codes with **arithmetic in Morton space** (neighbour-find, axis add, Z-order step without decode→re-encode); BMI2/AVX-512 runtime dispatch; Kokkos GPU backend. | **Yes — read it** |
| `flow/` | **Kokkos** + C++20 + nanobind (`peclet.flow`) | Incompressible Navier–Stokes for porous media: staggered MAC grid (and a collocated mode), cut-cell IBM over SDF geometry, MG-PCG pressure projection. Carries an `AGENTS.md` too; `CLAUDE.md` governs. | **Yes — read it** |
| `pnm/` | **Kokkos** + C++20 + nanobind (`peclet.pnm`) | Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology); distributed `extract_pore_network_mpi` (`PECLET_PNM_MPI`), bit-exact to single-rank. Split out of `flow` 2026-07. | Yes |
| `dem/` | **Kokkos + ArborX** + C++20 + nanobind (`peclet.dem`) | Discrete Element Method: XPBD solver + SDF point-shell collision for dense packing, explicit Hertz–Mindlin; optional MPI. | Yes |
| `voro/` | **Kokkos** + C++17/20 (+ core MPI, nanobind; Voro++ only as a benchmark reference) | Dynamic 3D Voronoi tessellation of moving particles; periodic boxes, incremental cell repair, Euler/NS/multiphase dynamics. The legacy half-edge CPU oracle is **retired**. | Yes |
| `coupling/` | **Kokkos** + Python (`peclet.coupling`) | CFD-DEM coupling of `flow` + `dem`: unresolved volume-averaged (`CfdDem`) and resolved cut-cell (`ResolvedCfdDem`) drivers on one shared `BlockDecomposer`. Pure-Python drivers in `python/peclet_coupling/`. | No |

Common threads: SDFs are the shared geometry representation; VTI/VTP (ParaView/Ovito) the shared I/O
format; periodic boundaries appear everywhere. The Kokkos backend (CUDA/HIP/OpenMP) and arch are
chosen by the `extern/install/<backend>` prefix the build points at (`tools/bootstrap_deps.sh` +
`CMakePresets.json`), never hard-coded.

## Per-project quick reference

For each project with its own `CLAUDE.md`, **defer to it** — these are entry points only; more in
DEVELOPMENT.md §3. `flow`, `pnm`, `dem`, `voro`, `amr` build via `find_package(Kokkos)` (+`ArborX` for
dem) against the bootstrapped prefix `extern/install/<backend>` (built once by
`tools/bootstrap_deps.sh` — a **hard build dependency**). Put `nvcc` on `PATH` for the CUDA backend
(`export PATH=/usr/local/cuda-13.2/bin:$PATH`).

```bash
# morton — non-BMI2 build is contractually PDEP/PEXT-free; AVX-512 only under Intel SDE
cd morton && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
ctest --test-dir build --output-on-failure
./build/tests/morton_tests --test-case="<name>"     # single doctest case

# flow — THE suite venv; nanobind is found via the active interpreter (SuiteNanobind)
cd flow && source ../.venv/bin/activate
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build -j                          # -> build/peclet/flow/_flow.*.so
# (canonical install: CMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda" pip install .)
PYTHONPATH=$PWD/build python scripts/verify_poiseuille_flow.py        # analytical-solution check
PYTHONPATH=$PWD/build python scripts/verify_periodic_spheres_sdflow.py  # cut-cell Stokes through spheres

# pnm — same configure; -DPECLET_PNM_MPI=ON for the distributed extraction
cd pnm && source ../.venv/bin/activate
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda" && cmake --build build -j
PYTHONPATH=$PWD/build python scripts/test_extraction.py ../flow/data/packing_ring.vti
PYTHONPATH=$PWD/build python scripts/verify_segmentation.py ../flow/data/packing_ring.vti
# MPI ctests: cmake -S tests/kokkos_mpi -B build_kmpi -DMPIEXEC_EXECUTABLE=/usr/bin/mpirun ...

# dem — -DPECLET_DEM_MPI=ON for the MPI step; tests need -DPECLET_DEM_BUILD_TESTS=ON (SKIP = exit 77)
cd dem && source ../.venv/bin/activate
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda" && cmake --build build -j$(nproc)
PYTHONPATH=$PYTHONPATH:$PWD/build python examples/verify_packing_spheres.py   # examples/ = demos; tests/python/ = pytest

# voro — tests are registered ONLY with -DPECLET_VORO_BUILD_TESTS=ON: a plain configure has zero
# tests ("No tests were found!!!"), which is not a failure signal
cd voro && source ../.venv/bin/activate
cmake -B build_dev -DPECLET_VORO_KOKKOS=ON -DPECLET_VORO_BUILD_PYTHON=ON -DPECLET_VORO_MPI=ON \
  -DPECLET_VORO_BUILD_TESTS=ON -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda"
cmake --build build_dev --parallel 8
OMP_NUM_THREADS=4 OMP_PROC_BIND=false ctest --test-dir build_dev --output-on-failure
bash tools/clang_format_check.sh          # the blocking Quality job (clang-format 18.1.8); no hand-rolled globs
```

### One venv for the whole suite

There is **one** development virtualenv, `suite/.venv` (gitignored); every project uses it
(`source ../.venv/bin/activate` from inside a submodule). History and contents: DEVELOPMENT.md §2.

- **Tools live in the venv** (nanobind, numpy/scipy, mpi4py, cupy, pytest, clang-format, Jupyter,
  `quarto` 1.9.38 for the gallery): `which quarto` in a fresh shell says nothing. **Activate first,
  then look**; to search, `find ~/Codes -maxdepth 8`.
- **Do not `mv` or rename a venv.** It bakes absolute paths; a moved one SILENTLY drops `python` while
  `python3`/`pip` fall through to `/usr/bin` system Python. If the suite moves, delete `.venv` and
  recreate it.
- **Local dev imports** come from the build tree: `PYTHONPATH=<build-dir>`. `coupling` also needs its
  pure-Python files staged beside the extension:
  `cp coupling/python/peclet_coupling/{__init__,driver,resolved}.py <build>/peclet/coupling/`.

## Conventions across the suite

- **The `nvidia-cuda` prefix carries an OpenMP HOST backend since 2026-08-30**
  (`OPENMP;SERIAL;CUDA`; `amr/docs/amr_setup_parallel_plan.md` D1′): host-side Kokkos
  `parallel_for`/`parallel_scan` (the AMR setup builders) run multithreaded. Consequences:
  **bound the pool** — `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` for test batteries (an unbounded
  pool on a 48-core host is a measured hour-long trap), and thread-count-pinned probes (e.g.
  `flow/tests/study/sdf_campaign/flow_probe.py` at 4 threads) must keep their pinned counts. Binaries
  built before the switch statically link the old Kokkos and are unaffected until rebuilt —
  but do NOT compose old- and new-prefix modules in one Python process (e.g. `coupling`
  importing flow + dem) until both are rebuilt against the same prefix.
- **MPI ctests need `--bind-to none`** (`-DMPIEXEC_PREFLAGS="--bind-to;none"`): OpenMPI's default
  pins every rank of an np≤2 run to the same cores.
- **Kokkos C++ projects** (`flow`, `dem`, `pnm`) put device kernels in header-only `.hpp` (compiled as
  C++; the Kokkos launch compiler routes them through `nvcc`/`hipcc` — never `.cu`) and expose the
  simulation as an importable Python module via a nanobind binding TU (scikit-build-core, on core's
  zero-copy View↔ndarray bridge); drive simulations from Python, not C++ mains.
- **Header-only C++ projects** (`morton`, `voro`, `core`, `amr`, `geom`) put the real logic in
  templates under `include/`.
- Build artifacts (`build/`, `build_*/`, `.venv/`, `*.so`, `__pycache__/`) and large output assets
  (`*.vti`, `*.vtp`, `*.png`) are present in several projects — don't treat their existence as
  something you created; prefer the project's own out-of-source `build/` directory.
