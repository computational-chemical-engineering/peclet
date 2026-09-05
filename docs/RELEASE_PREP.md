# Release preparation — state on 2026-09-04 (next family release, proposed **peclet 0.7.0**)

The one-off companion of [RELEASE.md](RELEASE.md) (the durable workflow). Everything here was
measured on 2026-09-04 with `tools/release/check_release_state.sh`, `tools/release/audit_docstrings.py`,
`tools/release/audit_examples.py` and two read-only audits of the docs and the gallery. It is a
checklist to tick when the release window opens; development continues meanwhile, so re-run the
three tools on the day and refresh the numbers.

Legend: **[B]** blocks the release · **[R]** do during the release window · **[A]** after the release,
does not block · **[D]** decision needed from the maintainer.

---

## 0. Snapshot

| package | on PyPI | last tag | commits since | checkout | `__version__` | proposed |
|---|---|---|---|---|---|---|
| peclet-core | 0.5.0 | v0.5.0 | 80 | at origin/main | – (no `__version__`) | **0.6.0** (geom/SceneBuilder module, rebalance, NBX tag-race fix, GPU-aware halo) |
| peclet-morton | 0.2.1 | v0.2.1 | 0 | at origin/main | **0.1.0 (stale)** | 0.2.1 unchanged — not re-released |
| peclet-flow (+ -cu13) | 0.4.0 | v0.4.0 | 264 | **55 behind origin/main** | **0.3.0 (stale)** | **0.5.0** (geometric VoF + contact angle + phase change, analytic scenes / moving instances, momentum residual stop, velocity MG, telescoping pressure, ghost MASK exchange, rebalance_by_weights) |
| peclet-pnm | 0.1.0 | v0.1.0 | 0 | at origin/main | – | 0.1.0 unchanged — re-tag only if the core header pin must move (it vendors core headers at `PECLET_TPX_TAG`; decide with [D2]) |
| peclet-dem | 0.4.0 | v0.4.0 | 22 | at origin/main | **0.3.2 (stale)** | **0.5.0** (set_wall_transform / wall_sdf_at, set_external_torques, analytic walls, scene particles, two OOB-write fixes, docstring fixes) |
| peclet-voro | 0.4.0 | v0.4.0 | 23 | at origin/main | **0.3.3 (stale)** | **0.5.0** (FlowSolver covolume + collocated NS, redistribute_pore_mesh, covolume MPI hooks, device-packed ghost exchange) |
| peclet-coupling | 0.3.0 | v0.3.0 | 5 | at origin/main | **0.2.0 (stale)** | **0.4.0** (resolved.py `ResolvedCfdDem`, reaction torque opt-in, staging fix) |
| peclet (meta) | 0.6.0 | v0.6.0 | – | umbrella f7d9e64 | – | **0.7.0** |

Other facts of the snapshot:

- **Worktrees and branches — verdicts taken 2026-09-05** (by patch identity against `origin/main`,
  `git cherry`): everything with code value is on main; nothing here blocks the freeze.

  | repo | branch (worktree) | state | verdict |
  |---|---|---|---|
  | flow | `rel-issues`, `rel-teardown`, `issues-merge` (flow-vof), `vof-v9`, `vof-w3`, `dc-p1` (flow-dc), `telescope` (tel/flow) | 0 ahead of main | **merged**; worktrees can be pruned when their sessions close |
  | flow | `vof-w4` (flow-w4) | 0 ahead, 7 files modified | **active** (VoF W4 session) — leave alone |
  | flow | `vof-issues` (flow-issues) | 2 patches not on main | **superseded** — the older free-slip type-4 draft; main carries the rel-issues implementation (e6c2c4e) |
  | flow | `vof-v6`, `vof-w0`, `vof-w12`, `vof-wor2` | ≤ 2 doc patches not on main | **merged by rebase** (W1/W12 content is on main as 0755bf6…ba62a7e; only the pre-rebase doc commits differ) — parked, deletable |
  | flow | `analysis/high-re-stability` | 1 debug commit, 2026-04, 570 behind | **parked** (historical debug branch) |
  | core | `telescope` (tel/core) | 0 ahead | merged |
  | core | `dev/aperture-compat-rhs`, `drag-study-harness` | 1 commit each (experiment with a negative result; a study harness) | **parked** |
  | voro | `feature/flexible-cell-storage` | 14 commits, 2026-03 | **parked** (pre-Kokkos era; would not apply) |

  Shared checkouts: `flow/` fast-forwarded to `2a89c67` (was 55 behind, then 4 behind after the
  rel-issues merge); `core/` carries another session's uncommitted AMR edits
  (`ghost_projection_sampled.hpp`, the mixed-level plan) — commit from named paths only.
- PecletDeps pins in flow/pnm/dem/voro/coupling: core `v0.5.0`, morton `v0.2.1`, Kokkos `5.1.1`,
  ArborX `v2.1`. core moves → repin in all five [R].
- `CITATION.cff` says 0.5.0 / 2026-07-06; `CHANGELOG.md` stops at 0.2.0.
- Containers on GHCR: `peclet-cpu`, `peclet-cuda:*-sm80/-sm90` published through 0.6.0; the
  `Containers` workflow shows **failure on every tag since v0.3.0** because the `hip-gfx90a` job fails
  (the other three jobs succeed and push). No `peclet-hip` image exists.
- The images install flow, dem, voro, core, morton — **not pnm, not coupling**.
- Local test trees are campaign trees (`build_l3_cuda_final`, `build_woi_*`, `build_a0`, …); the
  release matrix (RELEASE.md §3) must be run in fresh `build_rel_*` trees.

---

## 1. Code — fully functioning [B]

1. Merge/park the worktree branches above; fast-forward `flow/` (`git -C flow pull --ff-only`).
2. Run RELEASE.md §3 on host **and** CUDA, MPI np=1,2,4, and paste the counts here:

   | project | host (`extern/install/host-openmp`, fresh `build_rel*`, 2026-09-05) | CUDA | MPI | notes |
   |---|---|---|---|---|
   | core | plain 103/103 (np 1–8) · Kokkos-OpenMP 157/157 (np 1–8; the 5 AMR np4/np8 failures of the pre-fix run gone; re-run 157/157 at 730a6e1) · python module builds (mpi/geom/amr import) | Kokkos-CUDA **157/157** (np 1–8, fresh `build_rel_k_cuda` at 730a6e1); `python/test_amr.py` serial + np=4 on both prefixes | in the counts | **after** the NBX tag-range fix (core 5ca7037): before it, `particle_halo_np8` hung on 2 pinned cores (the CI hang) and `amr_distributed_{fv,mg,graded_mg,openness,poisson}_np{4,8}` failed intermittently (1–3 per run on a pristine main) |
   | morton | ctest 1/1 · non-BMI2 build ctest 1/1 · pytest 9/9 | – | – | |
   | flow (kokkos / kmpi / regression / verify_*) | 36/36 | 36/36, regression PASS, verify 5/5 | 103/103 np=1,2,4 | 2026-09-04, main at the rel-issues merge; OMP_NUM_THREADS=4. Host module rebuilt 2026-09-05 at 2a89c67 for the coupling tests |
   | pnm | module builds · `test_extraction.py packing_ring.vti` = **7199 pores** | module builds (`PECLET_PNM_MPI=ON`), 7199 pores; `tests/kokkos_mpi` **6/6** (np 1,2,4) | `tests/kokkos_mpi` 6/6 (np 1,2,4) | |
   | dem (kokkos / kmpi / verify_packing) | `tests/kokkos` 8/8 · `verify_packing_spheres.py` runs to completion (final overlap 0.000) | `tests/kokkos` **8/8** · `tests/kokkos_mpi` **24/24** · `verify_packing_spheres.py` to completion | `tests/kokkos_mpi` 24/24 (host) | module built with `PECLET_DEM_MPI=ON` |
   | voro | in-tree Kokkos+Python+MPI build **24/24** (352 s); `tests/kokkos_mpi` 18/18 re-run at 29dcaaf (np=1 gate 0.000e+00) | in-tree **24/24** · `tests/kokkos_mpi` **18/18** at 29dcaaf — was 15/18: the three `flow_mpi_*_np1` gates demanded bit-exactness, which a device backend cannot give (round-off, run-to-run nondeterministic via the tessellator's atomics); the gate is now 1e-13 / 1e-14 on a device backend, 0.0 on host (voro 29dcaaf) | `tests/kokkos_mpi` 18/18 (np 1,2,4; `OMP_NUM_THREADS=1`) | H100 np=4 gates all OK on Snellius 2026-09-05 (job 26366044, [VORONOI_METHODS_PLAN C5](VORONOI_METHODS_PLAN.md)) |
   | coupling | `terminal_velocity`, `fixed_bed_ergun` **2/2** (flow + dem host modules on PYTHONPATH) | **2/2** (flow 8767878 + dem CUDA modules on PYTHONPATH) | – | |
   | whole family | import smoke: flow/dem/voro/pnm/core.amr report `OpenMP`; core.mpi, core.geom, morton, coupling import | flow/dem/voro/pnm/core.amr report `Cuda`; core.mpi, core.geom, morton, coupling import | – | `PYTHONPATH` over the seven `build_rel*` trees |

   **CUDA column run 2026-09-05** (fresh `build_rel*_cuda` trees, `nvidia-cuda` prefix, `OMP_NUM_THREADS=4`,
   GPU otherwise idle): every project green; the only red on first pass was voro's np=1 bit-exact gate on
   the GPU (test fixed, see the row). morton has no CUDA row. The flow CUDA row is from 2026-09-04 at
   b7669d3; the commits since touch CI/docs/study files only (`git diff b7669d3..20756a6 --stat`).

3. ~~Fix the **`__version__` drift**~~ **DONE 2026-09-04** (all seven packages derive `__version__` from
   `importlib.metadata`, with the `-cu13` distribution as fallback; pre-flight reports `meta`). Original item: every `packaging/*_init.py` (flow 0.3.0, dem 0.3.2, voro 0.3.3,
   coupling 0.2.0) and morton's package `__init__` (0.1.0) lag their pyproject. Recommended permanent
   fix: derive it at import — `from importlib.metadata import version; __version__ = version("peclet-flow")`
   with a `PackageNotFoundError` fallback to `"0+dev"` for `PYTHONPATH=<build>` use — so the number
   can never drift again. `check_release_state.sh` flags the mismatch.
4. Gallery-found suite defects still open (from `peclet-examples/ISSUES.md`): decide per item
   whether it is fixed or listed as a known limitation in the notes [D1]:
   - ~~`max_open_divergence()` returns 0 on a bare box, so `advect_vof`'s divergence guard is inert
     without a pressure geometry~~ **RESOLVED 2026-09-03** (flow WO-R2: `advect_vof` throws without a
     cut-cell pressure operator and gates on `max_open_divergence_projected()`; ISSUES.md closed).
   - ~~interface-local Courant band has no wisp guard~~ **RESOLVED 2026-09-03** (WO-R2 item 4b: the
     band predicate uses `wispEps`, 1e-8 by `enable_vof`; Zalesak's reported CFL tracks the bound).
   - ~~`set_contact_angle` ignored on a domain-BC wall; `vof_geometry()` throws on an all-fluid solver;
     `step()` not atomic across the Weymouth–Yue throw; `set_state` + `advect_vof` on the collocated
     solver advects with a zero face field~~ **RESOLVED 2026-09-04, the ISSUES sweep on flow main**:
     `2f54317` (atomic `step()`), `709d038` (`step_adaptive`), `ea70354` (contact angle binds to a
     domain-BC wall), `81dd6a3` (`vof_geometry` on an all-fluid solver), `4649878` (collocated
     `set_state` seeds the face field; `advect_vof` refuses a blank one), `2f9f238`
     (`pressure_solve_failed()` makes a preconditioner breakdown visible); battery 34/34 on both
     trees + 12/12 and 3/3 MPI (flow `0f06f18`).
   - ~~free-slip domain BC (flow)~~ **MERGED + VERIFIED 2026-09-04**: flow main `e6c2c4e`
     (free-slip/symmetry `set_domain_bc` type 4, both grids, MPI), `eda0029` (outflow-reversal census +
     warning), `e5e1bbf`/`b7669d3` (CLAUDE.md notes) — the `rel-issues` branch, fast-forwarded onto
     main (it already sat on top of `84189ae`, no rebase conflict). Matrix on fresh trees: `tests/kokkos`
     36/36 OpenMP + 36/36 CUDA (incl. `freeslip`, `outflow_backflow`), `tests/kokkos_mpi` 103/103 at
     np=1,2,4 (free-slip pass of `test_velocitymg_bc_mpi` bit-exact at np=1, 1.6e-14 at np=2/4),
     regression suite 0.00 % on every metric vs baseline (not re-recorded), the five verify scripts
     PASS on CUDA. Physical gate: half channel + symmetry plane == full Poiseuille channel node for
     node to 2.5e-13 / 3.4e-12 / 2.6e-11 at N=16/32/64 on both grids; uniform flow along four slip
     faces stays uniform to 7e-12. ISSUES.md entry closed with the hashes.
   - ~~VoF interface area not exposed~~ **RESOLVED** on flow main: `vof_interface_area()` and
     `vof_geometry()['interface_area']` (per-block areas in `vof_block_stats()`).
   - inflow/outflow diverging to NaN — **DETECTOR LANDED 2026-09-04** (flow `eda0029`), NaN not
     reproducible: the entry's own configuration is steady with β=0.2 and β=0 alike (bit-identical,
     no reversal, nothing to warn about); where the outlet does reverse (BFS Re_S=800, β=0) the
     warning fires at step 693, the run stays finite but episodic (reversed fraction up to 0.34,
     `max_open_divergence` up to 1e-2 during the episodes), β=0.2 the same. A census + warning, not a
     fix — a convective/energy-stable outflow stays the remedy if a case ever needs one. Channel and
     cylinder-vortex-street configurations bit-identical to pre-merge main. ISSUES.md entry updated.
   - ~~Poiseuille metric closure~~ **DONE 2026-09-04**: `scripts/verify_poiseuille_flow.py` (flow
     6f0a312) is the pointwise node metric, re-run on CUDA at main `b7669d3` (6.49e-8 / 1.10e-6 /
     2.47e-5 at N=16/32/64, both meshes); ISSUES.md entry marked resolved.
   - ~~Kokkos "deallocated after finalize" warning under Jupyter~~ **RESOLVED 2026-09-04**: it was a
     `Kokkos::abort` (exit 134) whenever a bound object or zero-copy view outlived the atexit
     finalize. One shared pattern now (`core/include/peclet/core/python/kokkos_teardown.hpp`:
     `Releasable` registry + `ViewCapsule` + release-then-finalize atexit) in flow/dem/voro/pnm/
     coupling/core.amr — harness: 6 modules × 5 exit paths × OpenMP/CUDA all silent, exit 0
     (core c1df85a, flow 3035320, dem 90366c0, voro 2c2e819, pnm af0c692, coupling 684513e).
   - ~~NEW (found by the teardown work): `peclet.core.amr.Flow.step()` without any `set_solid` segfaults; a
     Python-callable `set_solid` deadlocks under the OpenMP host backend~~ **RESOLVED 2026-09-05, core
     `730a6e1`**: `AmrFlow` carries a readiness flag and `step()`/`project()`/`beginAdapt()` throw a
     named `std::runtime_error` without an operator (Python `RuntimeError`); the callable bindings
     (`set_solid`, `finish_adapt`, `rebalance_mpi`) release the GIL around the multithreaded host build
     (nanobind's callable wrapper re-takes it per sample — serialised, cannot deadlock). Both reproduced
     first (SIGSEGV; hang at 4 threads, fine at 1), then gated: `tests/test_amr_flow_solver.cpp` (device)
     and `python/test_amr.py` (raises before `set_solid`; the callable form completes) — 157/157 Kokkos
     ctests host + CUDA, `test_amr.py` serial + np=4 on both prefixes.
   - ~~Poiseuille verify metric ("fake convergence")~~ closed with the item above.
5. ~~dem root-level `verify_*.py` / `test_*.py` / `build_log*.txt` scratch ship in the sdist~~ **DONE
   2026-09-05** (dem 6c74aa6): `sdist.exclude` for the root-level scripts, logs, `.vtp` and helper shell
   files; verified in a fresh clone — the sdist root holds only CITATION.cff, CMakeLists.txt, LICENSE,
   README.md, pyproject.toml, requirements.txt, .clang-format, .gitignore.
6. **Phase C (versions) DONE 2026-09-05 — the tree is release-ready; only the tags remain.** Per D4:
   core `be9db10` (0.6.0), flow `8767878` (0.5.0, +cu13), pnm `bcc79e8` (0.1.1, +cu13), dem `6c74aa6`
   (0.5.0, +cu13), voro `29dcaaf` (0.5.0, +cu13), coupling `812c107` (0.4.0), morton unchanged at 0.2.1
   (its one commit since the tag is the `__version__`-from-metadata change; not re-released, per D4).
   Every consumer's `PecletDeps.cmake` pins core **v0.6.0** — that tag does not exist until core is
   tagged, so **tag core first** (RELEASE.md order); CI is unaffected (flow/pnm/dem build core `main`,
   voro checks out the sibling), only a local `pip install .` of a consumer needs the tag. `CITATION.cff`
   in every member + the umbrella: version + `date-released: 2026-09-05` (re-set the date if tagging
   slips). Umbrella `pyproject.toml` 0.7.0 with the new `==` pins, `packaging/pyproject-cu13.toml` 0.7.0,
   container image tags 0.7.0 in `docs/containers.md`, `containers/README.md`, `containers/submit/*.slurm`,
   `CHANGELOG.md` section filled (rename the `[Unreleased]` heading to `[0.7.0] — <tag date>` when tagging).
   `tools/release/check_release_state.sh` is the readiness readout.

---

## 2. Documentation [R] (line numbers from the 2026-09-04 audit)

### 2.1 Wrong or stale statements (fix)

- `docs/DEPLOYMENT.md` L15-16: "the flow Python module is single-rank, its multi-rank solver lives
  in the C++ tests" — **wrong** (`Solver.init_mpi`, `mpi_block`, `has_mpi`); L31/L64/L78-80 package
  lists omit pnm and coupling; L92 "distributed (dem)"; L133-140 API table lacks pnm MPI, coupling,
  `core.geom`; L147-151 "CUDA/HIP not built in this environment", ".def files are not CI-built".
- `docs/containers.md`: every pull/run line says `0.1.0`; the `peclet-hip` pull is shown as if
  the image existed; L8-9 "full family (flow, dem, voro, core, morton)" (no pnm/coupling); L124
  "produced in CI" without the failure note. Same in `containers/README.md` L4, L20-22, L100-101.
- `containers/cpu.def` L9 "pip-installs the sdflow and dem modules"; all three `.def` lack pnm and
  coupling (`pip install /opt/peclet/pnm`, `/opt/peclet/coupling` after flow+dem) [R, changes CI
  images — test with a `push=false` dispatch first].
- `docs/PORTABILITY.md` L33 "six sibling repos"; L80-96 future tense for shipped items; L95-96
  "voro uses the OpenMP backend only… half-edge mesh repair on the host" — wrong, voro is device-native.
- `docs/ROADMAP.md` L26/L156 `tpx` names; Phase 5 voro item and Phase 6 packaging items done but unchecked; no coupling.
- `docs/ARCHITECTURE.md` L17-22 taxonomy lacks pnm/coupling; L73 old `tpx/python` path; L93
  half-edge/`block_decomposer` sentence contradicts L24-25.
- `docs/index.md` L24 CPU family omits pnm; L43-50 lacks coupling; L73 "This release (v0.2.0)".
- umbrella `README.md` L35-42 layout lacks `coupling/`, calls voro "header-only C++17"; L59-67
  PyPI table lacks peclet-coupling and `core.geom`; L100 "This release (v0.2.0)"; L80-82 CI list.
- `CLAUDE.md` L7 "five projects"; L28 dead link `docs/CUDA_RETIREMENT.md`; no `coupling/` row.
- `CONTRIBUTING.md` L3-4 five projects; L19 creates `flow/.venv`; L22 `verify_poiseuille_sdflow.py` does not exist.
- `CITATION.cff` (umbrella and per repo): version/date; add the 0.7.0 version DOIs after Zenodo mints them.
- `CHANGELOG.md`: add 0.2.1, 0.2.2, 0.3.0, 0.4.0–0.4.4, 0.5.0, 0.6.0 (one line each from the GitHub
  Release titles) and the full 0.7.0 section.
- `docs/SNELLIUS.md` L15 `$SUITE/flow/.venv` → `$SUITE/.venv`; add the "Validated releases" table and point at `tools/hpc/`.
- Submodules: `flow/README.md` L54 `-DCFD_BUILD_MPI=ON` → `PECLET_FLOW_MPI`, L61/L69 `.venv` → `../.venv`;
  `flow/CLAUDE.md` L36, L192-194 single-rank wording; `dem/README.md` L52/L67 `-DDEM_MPI` →
  `PECLET_DEM_MPI`, L57 own venv; `voro/README.md` L81/L117 `sdflow`; `core/README.md` L56 and
  `core/CLAUDE.md` L139-142 `tpx_mpi.cpp`/`tpx_amr.cpp` → `mpi_bindings.cpp`/`amr_bindings.cpp`, add
  `geom_bindings.cpp`; `morton/README.md` L4 badge 3.8+ vs `requires-python >= 3.9`;
  `coupling/README.md` and `pnm/README.md` have no badge row / PyPI install line.

### 2.2 Generated Python API pages

`docs/python/*.md` were regenerated 2026-07-25 and are far behind the bindings: flow 130 of 213
names missing (all VoF, scenes, MPI, rebalance), dem 43 of 91, voro 38 of 63 (`FlowSolver`,
`VoronoiHalo` absent), pnm 7 of 15, core lacks `geom` and 13 amr names. Fix `tools/gen_python_api.py`:

- add `peclet.coupling` (CfdDem, ResolvedCfdDem) and `peclet.core.geom` (SceneBuilder) pages;
  remove the duplicated `peclet.pnm` entry (the module docstring is emitted twice);
- fix `emit_functions`: nanobind free functions report `__module__ == "peclet.pnm._pnm"`, so the
  filter drops every pnm/morton function;
- run it from an **MPI-enabled** build so `init_mpi`/`mpi_block`/`step_mpi`/`VoronoiHalo` appear;
- add `python/pnm.md` and the new pages to `mkdocs.yml` nav, plus `peclet-pnm` in the Doxygen link list;
- consider running it in `site.yml` instead of committing snapshots [A].

### 2.3 Docstrings (`tools/release/audit_docstrings.py`, run 2026-09-04 against local builds)

631 bound callables, 59 without a docstring, 3 stale. Fix at least the public entry points [R]:

- **pnm**: `extract_pores`, `segment_volume`, `extract_topology_gpu`, classes `Pore`, `SDFReader` — the package's core API is undocumented.
- **voro** `FlowSolver`: constructor, `step`, `set_body_force`, `set_pressure_tolerance`, `get_pressure`, `get_cell_volume`, `kinetic_energy`, `max_divergence`, `pressure_iterations`, `num_cells/faces/wall_faces`, `layout`; `Tessellation.__init__`, `Simulation.__init__`.
- **coupling**: `CfdDem` (`__init__`, `step`, `update_void_fraction`, `compute_forces`, `last_slip`, `last_drag`), `ResolvedCfdDem` (all five) — the driver classes users subclass.
- **core.mpi**: `Migrator.__init__`, `Halo.__init__`, `owner_of`, `num_ghost`, `num_owned`; **core.geom**: `SceneBuilder.__init__`, `add_union`, `add_intersection`, `num_nodes`, `num_instances`.
- **dem**: `Simulation.__init__(capacity)`, `get_angular_velocities`, `get_inv_inertia`, `get_masses`, `get_num_contacts`, `get_num_manifolds`, `get_max_overlap`; stale "CUDA-API alias" on `initialize`.
- **flow**: `has_scene`, `pressure_telescope`, `scene_instance_count`, `velocity_multigrid_active`; stale `rank`/`size` docstring in the non-MPI branch ("the multi-rank path is the tests/kokkos_mpi suite"); class docstrings for `Solver`/`SolverColocated`.
- Pure Python: `voro_init.py` `size_of`, `measure`; `dem/packaging/particle_builder.py` `f_body`.

---

## 3. Packaging and CI [R]

1. **CUDA family** [D3] — **DONE 2026-09-04** (pnm 76fd56e, dem 1f72dc4, voro 749cd26, umbrella ed3ec42):
   `packaging/pyproject-cuda.toml` + `cuda-wheel` jobs in pnm/dem/voro, `peclet-cu13` metapackage
   (`packaging/pyproject-cu13.toml`, umbrella `build-cu13` job). Validated locally in one fresh venv: all four
   modules `execution_space == Cuda`, libcudart from the `nvidia-cuda-runtime` wheel, pnm 7199 pores, dem
   bit-identical to the dev tree, voro smoke PASS, flow exact (its exit-134 teardown abort is now fixed too).
   CI-only unknowns: dem's ArborX build inside the manylinux container; the jobs need core 0.6.0 + repinned
   `PECLET_TPX_TAG` (an isolated build at v0.5.0 lacks the geom headers); Trusted Publishers for the four
   new names. Original item: today only `peclet-flow-cu13`. Recommended for 0.7.0: add `cuda-wheel`
   jobs + `packaging/pyproject-cuda.toml` for **pnm, dem, voro** (dem: add the ArborX build to the
   prefix step) and a `peclet-cu13` metapackage from the umbrella, so `pip install peclet-cu13`
   mirrors `pip install peclet`. Validate each with a local `pip wheel` against `extern/install/nvidia-cuda`
   in a fresh venv before tagging; register the four new PyPI project names' trusted publishers.
   Multi-arch SASS (only sm_75 + PTX today) stays as is; note JIT on first import in the docs.
2. **coupling CI**: none exists — add `ci.yml` (OpenMP prefix, build flow + dem + coupling, run `tests/test_terminal_velocity.py`).
3. **Containers**: DONE 2026-09-04 — `push` input added to `containers.yml`; pnm + coupling added to
   the three `.def` files and proven by a `only=cpu, push=false` dispatch (run 33869278789: every member
   installed, `peclet-cpu.sif` built). cuda/hip defs carry the same lines, untested until the next tag/dispatch.
4. **HIP link error** — the LUMI blocker. **Experiment 1 (visibility override) WORKS for the method
   codes**: Containers run 33868865327 (`only=hip, push=false`) built and installed `peclet-flow`,
   `peclet-dem`, `peclet-voro` (all with `PECLET_*_MPI=ON`) under hipcc/lld for the first time since
   0.3.0. The job then failed on **core's `amr` module** with the same class of error but for the
   binding TU's own wrapper classes (`undefined hidden symbol: vtable for (anonymous
   namespace)::Octree / Releasable / Poisson / Flow / DistributedOctree`, `core/python/amr_bindings.cpp`
   L61–632): virtual classes in an anonymous namespace under hipcc's host/device split. Fix in
   progress (move them to a named namespace, folded into the teardown work on that file); then
   re-dispatch `only=hip, push=false`. pnm and coupling were never reached in that run (they install
   after core) — expect them to link like flow/dem/voro. **Re-runs:** 33873014855 got past core.amr and
   died on voro's own anonymous-namespace wrappers (Tess/Flow/Sim, introduced by the teardown rewrite;
   moved to `peclet::voro::pybind`, voro dfc1def); **33874788583 (2026-09-04 13:20 UTC) BUILT
   `peclet-hip.sif` WITH THE WHOLE FAMILY** (flow, dem, voro, pnm, core, coupling, morton, MPI on),
   push skipped by design. RESOLVED as a build: the next tag publishes `peclet-hip:0.7.0-gfx90a`
   (still *untested on AMD hardware* — docs/LUMI.md §5).
5. Optional but cheap: `check_release_state.sh --ci` as the first step of each `release.yml`
   (tag == version == `__version__`), and a `workflow_dispatch` dry run of the CUDA wheel job.
6. Dependabot action majors differ across repos (`upload-artifact` v4 in flow vs v7 in the umbrella) — harmless per repo, but keep each repo's upload/download pair on the same major.

7. **CI on `main` made green again, 2026-09-05** (pre-flight showed every code repo red):
   - **core**: `CI` hung in `particle_halo_np8` for the 6 h job limit on every push since 09-04
     (cancelled, not failed — easy to miss). Cause: the per-round NBX tag (10294e6, `baseTag + round`)
     collided with the particle halo's direct tags (7501 + 1 = 7502) and with the AMR gather tags
     (family 0 over 11/41/45) on oversubscribed ranks. Fix core `5ca7037`: rounds use a reserved
     tag range, gated by `test_nbx_rounds`. Rule recorded in `core/CLAUDE.md`.
   - **flow / pnm / dem** `CI`: died at the first `#include` because CI vendors core at the
     `PECLET_TPX_TAG` default (`v0.5.0`, no geom / teardown headers). Workflows now pass
     `-DPECLET_TPX_TAG=main` (flow 20756a6, pnm 3cbfffc, dem d6afedc + f2650f1 for the kernel tests'
     `TPX_DIR`). The vendored default still moves to `v0.6.0` at release time (§0).
   - **flow** `Quality`: ruff F821 in `tests/study/vof_momentum_consistency.py` (a `del` of a name a
     closure still binds) — flow 2a89c67.
   - **voro** `CI`: built Kokkos 4.5.00 while the family pins 5.1.1 (`test_energy_layer` no longer
     compiles against 4.5) — voro b8a49a9; then `test_mesh_optimizer` used a `(real_t[3]){…}`
     compound literal that g++ 13 rejects — voro 91daffc.
   - The `clang-format (informational)` jobs are `continue-on-error` already; a red badge on Quality
     means ruff.

---

## 4. Snellius [R, billed]

- `tools/hpc/install_snellius.sh <tag> h100|a100|cpu` (new, family-wide; its flow part is the
  validated `peclet-examples/.../install_snellius.sh`) → wheelhouse under
  `/projects/0/prjs1022/peclet/wheelhouse/<tag>-<backend>/`; then `tools/hpc/smoke_snellius.slurm`.
  First run of the family script **is** part of the release; expect one round of fixes for dem/voro/pnm
  (they have only ever been built on Snellius one at a time, in campaign trees).
- Pull `peclet-cuda:0.7.0-sm90` and run the same smoke through `containers/snellius-run.sh`.
- Record both in `docs/SNELLIUS.md` "Validated releases".

## 5. LUMI [A, untested]

`docs/LUMI.md` + `tools/hpc/install_lumi.sh` are written from documentation, not runs. The release
notes state: *LUMI/HIP recipe provided, untested; no container image published.* Straightening it
out needs the HIP link fix (§3.4) and a LUMI allocation.

---

## 6. Gallery: pages to re-check after the release [A]

Static audit (`tools/release/audit_examples.py`, confirmed by a manual read of every page):
**53 pages; 24 examples call API that exists only on `main`** and therefore run from PyPI only once
0.7.0 is out. Their frozen outputs were produced by local builds between 2026-08-30 and 09-04, so
they are the first to re-execute against the published wheels. Priority order:

| priority | pages | needs | re-run cost |
|---|---|---|---|
| 1 — CPU, minutes | `tennis-racket`, `stirred-column`, `pall-ring-packing` (writes the npz that `pall-ring-flow` reads), `pore-mesh-redistribution`, `voronoi-taylor-green`, `voronoi-sphere-drag`, `vof-advection-benchmarks` (32³/64³), `parasitic-currents`, `capillary-oscillations` | core 0.6.0 geom + dem 0.5.0 / voro 0.5.0 / flow 0.5.0 | ≤ 10 min each on CPU |
| 2 — GPU (`peclet-flow-cu13` or local CUDA) | `oscillating-sphere`, `nonsphere-drag`, `dumbbell-drag`, `pall-ring-flow`, `moving-sphere-drag`, `galilean-drag`, `confined-drag-screening`, `jeffery-orbit`, `ten-cate-sphere`, `drafting-kissing-tumbling`, `rotating-sphere-torque`, `rising-bubble`, `droplet-wetting`, `bubble-through-packing`, `trickle-flow-packing` | flow 0.5.0 (+ core geom, dem, coupling) on a GPU | 10 min – hours each |
| 3 — confirm the 20 OK pages on the new wheels | `poiseuille-ibm`, `pipe-poiseuille`, `taylor-green`, `lid-driven-cavity`, `developing-channel`, `zick-homsy`, `random-packed-bed`, `ring-packed-bed`, `rotating-drum`, `sdf-particle-packing`, `pore-network-extraction`, `pore-mesh-voronoi`, `staggered-vs-collocated`, `sanity-checks` (fast, CPU); `backward-facing-step`, `cylinder-vortex-street`, `rayleigh-benard`, `tumbling-cubes`, `fluidized-bed`, `hcs-clustering`, `bidisperse-segregation`, `single-bubble-injection` (cached/GPU — smoke the bootstrap only) | peclet 0.7.0 CPU wheels | minutes each for the fast set |
| 4 — static/HPC pages | `wall-bounded-turbulence`, `benchmarks/{channel,foxberry,parallel,porous}-scaling`, `benchmarks/dem-bulk-dosta2024` | their driver scripts use main-only flow API (`last_step_timers`, `set_pressure_bottom`, `set_pressure_fcg`, `set_pressure_mean_removal`, telescope) → they become reproducible on the Snellius 0.7.0 install; no render needed | Snellius, billed |

Page-level fixes to make while re-running:

- `rotating-sphere-torque` imports `peclet_coupling.resolved` (the source-tree name); the installed
  package is `peclet.coupling` — change the import or the page can never run from a wheel.
- `pall-ring-packing` and `tennis-racket` carry a "newer than the current PyPI release" callout — remove after 0.7.0.
- `pore-mesh-redistribution` / `voronoi-*` say "a recent peclet (peclet-voro with …)" — pin to `>= 0.5.0`.
- ISSUES.md L375 calls the pore-mesh optimizer "not in PyPI" but it shipped in voro 0.4.0 — close.
- Bump `publish.yml` action versions (Node 20 deprecation) and `pyproject.toml` `sim = ["peclet>=0.7"]`.

The gallery site itself is unaffected by the release (it renders from `_freeze/`); nothing here blocks tagging.

---

## 7. Decisions [D] — taken 2026-09-04

- **D1** VoF defects: handed to the VoF session. The non-VoF items of §1.4 (free-slip domain BC,
  inflow/outflow NaN, Poiseuille metric closure, Kokkos teardown warning) are being worked in this
  release-prep session (flow worktrees `flow-rel-issues`, `flow-rel-teardown`).
  **Outcome 2026-09-05 (VoF session):** every VoF item of §1.4 is fixed on flow main (hashes there);
  nothing VoF-side is left to list as a defect. **The VoF scope of 0.7.0 and its stated limitations**
  (the release notes should carry these, wording as in `flow/CLAUDE.md`'s VoF section):
  1. Geometric VoF (PLIC + Weymouth–Yue + HF curvature cascade + balanced-force CSF), cut-cell
     transport over SDF solids, static/dynamic contact angle with hysteresis and Navier slip, open
     two-phase boundaries, phase change (Stefan/sucking at the noise floor; Scriven bubble growth
     closes at Ja 0.5 to 0.03 % but NOT at Ja 2 — 3.6 %, `energy_order` default 1, the P3h dossier),
     the multiple-marker block container (checkpointable bitwise), MPI + CUDA throughout.
  2. **Colliding bubbles are outside the block container's rating**: `channel_18` (Re_τ 127,
     D/Δ = 10) ends at ~1.5 eddy turnovers when two markers interpenetrate, independent of dt
     (WO-W3 §7). Rung W4 is parked (flow branch `vof-w4`, WIP f29c8e7) and resumes after 0.7.0.
  3. The block container is all-fluid, staggered-only for the block CSF, ratio ≲ 100 with motion;
     the collocated two-phase path (V8) is all-fluid, ratio ≲ 100 with motion; staggered is the
     reference.
  4. Wall-bounded turbulence at Re_τ ≈ 127 needs `dy⁺ ≲ 1.6`; flow's cubic cells give 3.18 on the
     `channel_18` grid, so the near-wall turbulence decays and the bubbles do not disperse (W3 §8) —
     a `flow` limitation (no anisotropic cells), not a VoF one. TBFsolver's 16-turnover `channel_18`
     statistics (`flow/tests/study/channel_18/results/`) are the first reference for the case.
  5. Dynamic wetting: the contact-line mobility inside the wetting band (V6c) is open; the V7
     pore-scale campaign's packing imbibition shows no wettability effect and the micromodel is
     non-monotone in θ (documented on the V7 gallery page). The Lamb mode-2 ~4 % band-force residual
     on curved interfaces is a known, characterised deviation (inviscid reference; not a κ bias).
- **D2** yes: pnm 0.1.1 repinned to core v0.6.0 at release time.
- **D3** yes, full CUDA family: `peclet-pnm-cu13`, `peclet-dem-cu13`, `peclet-voro-cu13` +
  `peclet-cu13` metapackage (implementation in progress, validated locally before CI).
- **D4** version numbers of §0 accepted (family 0.7.0).
- **D5** attempt the HIP link experiments now via CI: experiment 1 (visibility override, all
  modules) dispatched as Containers run 33868865327 (`only=hip, push=false`, version tag
  `0.7.0-hipexp1`). Results are appended to §3.4 below as they come in.

Original questions, for the record:


- **D1** Which of the open flow VoF defects in §1.4 are fixed before 0.7.0 vs listed as known limitations (recommendation: fix the inert divergence guard and the collocated zero-face-field case, list the rest).
- **D2** Re-tag pnm 0.1.0 → 0.1.1 to repin core headers at v0.6.0 (recommendation: yes, one-line change, keeps the family on one core header set).
- **D3** CUDA family scope: flow-only (as today) or flow+pnm+dem+voro + `peclet-cu13` (recommendation: full family; the job is a copy of a working one and the user-facing story becomes "CPU or CUDA, same names").
- **D4** Version numbers in §0 (all minors; 0.7.0 family).
- **D5** Whether to attempt the HIP link experiments before the release (≈ 3 CI dispatches, no local hardware needed) or ship 0.7.0 without a HIP image.
