# Development environment — worktrees, the suite venv, per-project build notes

The long-form companion of the umbrella `CLAUDE.md`, which keeps only the rules and one-line
pointers here. Moved out of `CLAUDE.md` on 2026-10-08 (wording kept; counts and dates are those of
the day each paragraph was written — the submodule's own `CLAUDE.md` is authoritative for its test
battery).

## 1. Worktrees: why they are the default

**These checkouts are shared.** A dozen-plus Claude sessions run against this suite at once; on
2026-09-11 two separate edits of `flow/CLAUDE.md` were swept into another session's commits within
the hour. Staging named paths (the standing directive) stops *you* taking *their* files; it does not
stop *them* taking yours. A worktree is the other half. Earlier, a bare `git commit` took the whole
shared index (flow `628d3da` swept another agent's staged docs, 2026-09-08), and a half-edited header
breaks the other agent's build.

Historically the cost was the rebuild, which is why the shared tree kept winning. QUALITY_PLAN G.8
(compile `Solver<Grid>` once, not once per consumer; flow `61e9f58`/`8f79c3b`) cut that materially
for `flow`, so the honest answer has changed: **isolate by default, share only for something
trivial.** (The older guidance, written alongside: "Full rebuilds of flow cost ~50 CPU-minutes
(QUALITY_PLAN G.8) — a worktree is for real work, not a five-minute fix; `ccache` makes the second
one cheap.")

**The sibling position is load-bearing, not cosmetic.** Everything in this suite is reached by `../`
from inside a submodule: the one venv (`../.venv`), the Kokkos/ArborX prefixes
(`../extern/install/<backend>`), and the sibling headers each repo's `cmake/PecletDeps.cmake` prefers
over a FetchContent. Put the worktree anywhere else — nested under a subdirectory, or outside
`suite/` — and those resolve to nothing: the venv silently falls through to the system Python (§2),
and CMake silently fetches pinned tags instead of using your siblings. `suite/tel/flow` is an
existing worktree that does *not* satisfy this; do not copy it.

Housekeeping:

- Branch per topic, not per agent. `git worktree list` inside the submodule before adding another —
  there are already abandoned ones (`.claude/worktrees/agent-*` at the umbrella, from 2026-09-02).
- `git worktree remove ../flow-<topic>` when the branch lands; `git worktree prune` for stale entries.
- The coordinator `--ff-only` merges the branch into `main`, re-gates once, pushes and removes the
  worktree. Agents in *different* repos keep the plain checkouts, and everyone commits with a
  pathspec (`git commit <paths> -m …`).
- The submodule is the unit. A worktree of the **umbrella** does not give you worktrees of the
  submodules — it gives you the same submodule checkouts, shared with everyone. Isolate the
  submodule you are changing.
- Umbrella pointer bumps still happen in the real `suite/` checkout, after the submodule is pushed.

## 2. One venv for the whole suite

There is **one** development virtualenv, `suite/.venv` (gitignored), and every project uses it
(`source /path/to/suite/.venv/bin/activate`, or `../.venv` from inside a submodule).

It carries nanobind, numpy/scipy/numba/h5py/pandas, matplotlib/pyvista/scikit-image, mpi4py,
cupy-cuda12x, scikit-build-core/hatchling/build, pytest, clang-format and the Jupyter stack — the
union of what the per-project venvs held — **and `quarto` (the `quarto-cli` wheel, which ships the
real binary), because the examples gallery is a Quarto site and rendering it is suite work.**

**Tools live in the venv, so `which quarto` in a fresh shell says nothing.** It answered "not
installed" on 2026-09-18 while two copies existed — `peclet-examples/.venv/bin/quarto` and an
unused `~/.local/quarto-1.6.40` tarball — and a `find / -maxdepth 4` cannot reach a venv binary,
which sits six levels down. **Activate first, then look**; to search, `find ~/Codes -maxdepth 8`.
The version is pinned to the one the gallery's own venv carries (1.9.38) so a re-render does not
silently change output. The 1.6.40 tarball was deleted the same day and
`peclet-examples/render_example.sh`, which hardcoded it, now uses `$SUITE/.venv/bin/quarto`.

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
(`cp coupling/python/peclet_coupling/{__init__,driver,resolved}.py <build>/peclet/coupling/`), because
the importable package is `peclet.coupling` — the `python/peclet_coupling/` directory is only the
source location that the wheel install maps into place.

## 3. Per-project build notes

### morton

The non-BMI2 build is contractually PDEP/PEXT-free (a test greps the binary). AVX-512 batch kernels
have no local hardware — validate under Intel SDE (`sde64 -skx -- ./build/tests/morton_tests`). See
its `CLAUDE.md` for the runtime-dispatch and wheel-build subtleties.

### dem

Registered tests (as of 2026-09-08): `-DPECLET_DEM_BUILD_TESTS=ON` → 11 ctests (kokkos + arborx +
pytest), + `-DPECLET_DEM_MPI=ON` → 78 (kokkos_mpi + Python MPI at np=1,2,4); every test SKIPs with
exit 77.

Since 2026-09-08 (QUALITY_PLAN D) there are no root-level scripts: `tests/python/test_*.py` are pytest
functions run by ctest, `tests/python/mpi/` the MPI ones, `examples/` the demos (`pack.py`,
`verify_*.py`, `generate_*.py`, `bench_step.py`). Three legacy gotchas are recorded in `dem/CLAUDE.md`
(the velocity solve is off by default, there is no default gravity, the `(N,4)` w column is the
inverse mass).

### voro

The battery was 42 ctests = 24 + 18 `mpi` (as of 2026-09-08). Since 2026-09-08 (QUALITY_PLAN D)
there is ONE tree: `tests/kokkos_mpi` is folded in under the `mpi` label (np=1,2,4; the launcher is
taken from beside `MPI_CXX_COMPILER` — ParaView's MPICH `mpiexec` on PATH used to launch N singletons
that "agreed" trivially), the `bench_*` binaries and the Voro++ fetch are opt-in under
`PECLET_VORO_BUILD_BENCHMARKS`, and clang-format is **blocking** (the tree was reformatted once in
`a487777`). `tools/clang_format_check.sh` walks `include/`, `src/` and `tests/` itself — don't
hand-roll globs.

The legacy half-edge `voronoi.hpp` CPU oracle is **gone** — retired in voro `0d4f3b8`
("retire the legacy half-edge engine + rewrite the docs (device-only)"); `include/` now holds only
`peclet/voro/`. Voro++ survives solely as a benchmark throughput reference for `bench_convexcell`.
The production device tessellator stores each Voronoi cell as a compact **dual-triangle ConvexCell**
(a vertex is a triple of plane indices) plus a `facetGeometry` CSR — not the old half-edge mesh
(see its README).

## 4. State of the consumers (snapshot, moved from `CLAUDE.md`)

The compute codes are all **Kokkos**-based (raw CUDA retired 2026-06-20). `flow` has a **complete,
validated distributed Navier–Stokes solver** on the core: the whole cut-cell IBM + MG-PCG step runs
multi-rank, bit-exact to single-rank (`tests/kokkos_mpi`, np=1,2,4, gated `PECLET_FLOW_MPI`). `flow`
is **THE** flow solver; pore-network extraction is the separate `pnm/` project (`peclet.pnm`, split
out of flow 2026-07). `dem`'s `peclet.dem` module runs the full XPBD step (ArborX broad-phase) with a
validated distributed `step_mpi` that drives the SAME modern solver stack as the single-GPU step
(shared `demSolveContacts` driver, processor-block Gauss–Seidel: rank-local coloring + warm-started
PGS with gid-keyed persistent contacts + statics/stabilization), a distributed **force-based** engine
(`step_hertz_mpi` — explicit Hertz–Mindlin as the first law of the generalized `demStepForce` driver,
domain-decomposed MD-style with gid-keyed Mindlin history; `tests/kokkos_mpi`, host + CUDA) and
periodic **load rebalancing** (`enable_mpi_step(rebalance_every=…)` / `Sim.rebalance()` — SoA
ownership migration on the weighted ORB, both engines' contact ledgers carried). The single-GPU codes
are complete + faster than the retired CUDA at scale; remaining work is at-scale multi-GPU tuning —
see [ROADMAP.md](ROADMAP.md).

`core/` provides ORB block decomposition; the async grid ghost-layer exchange
(`peclet::core::halo::GridHalo` — topology/exchange split, field-agnostic, NBX + persistent
neighborhood-collective engines, overlap-capable, plus a GPU-resident host-staged variant); the
Lagrangian halo (`peclet::core::halo::ParticleMigrator` — particle migration + `gatherGhosts`); SDF
geometry with scalar/vector VTI I/O; and **dynamic load balancing** (weighted ORB
`BlockDecomposer::init(…, weights)` + `DistributedOctree::rebalance` for AMR leaf/field migration
and `rebalanceByParticleCount` for the Lagrangian path). Morton-guarded tests SKIP with exit 77,
never pass silently.
