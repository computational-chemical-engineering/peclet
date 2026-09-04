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

- Open worktrees: flow has 9 (`flow-dc` dc-p1, `flow-rebalance` vof-rebalance, `flow-v9` vof-v9,
  `flow-vof` p3h-doc, `flow-w3` vof-w3, `tel/flow` telescope, + detached `flow-ex*`, `flow-rebal-base`);
  core has `tel/core` telescope. Unmerged branches: core `dev/aperture-compat-rhs`,
  `drag-study-harness`; flow `analysis/high-re-stability`, `vof-v6`, `vof-w0`, `vof-w12`, `vof-w3`,
  `vof-wor2`; voro `feature/flexible-cell-storage`. **Each must be merged or declared parked before
  the freeze [B].**
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

   | project | host | CUDA | MPI | notes |
   |---|---|---|---|---|
   | core | | | | |
   | morton | | – | – | |
   | flow (kokkos / kmpi / regression / verify_*) | | | | |
   | pnm | | | | |
   | dem (kokkos / kmpi / verify_packing) | | | | |
   | voro | | | | |
   | coupling | | | | |

3. Fix the **`__version__` drift** [B]: every `packaging/*_init.py` (flow 0.3.0, dem 0.3.2, voro 0.3.3,
   coupling 0.2.0) and morton's package `__init__` (0.1.0) lag their pyproject. Recommended permanent
   fix: derive it at import — `from importlib.metadata import version; __version__ = version("peclet-flow")`
   with a `PackageNotFoundError` fallback to `"0+dev"` for `PYTHONPATH=<build>` use — so the number
   can never drift again. `check_release_state.sh` flags the mismatch.
4. Gallery-found suite defects still open (from `peclet-examples/ISSUES.md`): decide per item
   whether it is fixed or listed as a known limitation in the notes [D1]:
   - `max_open_divergence()` returns 0 on a bare box, so `advect_vof`'s divergence guard is inert
     without a pressure geometry (flow) — a user-facing silent-wrong; fix or make `advect_vof` refuse.
   - interface-local Courant band has no wisp guard (flow VoF) — usability.
   - `set_contact_angle` ignored on a domain-BC wall; `vof_geometry()` throws on an all-fluid solver;
     `step()` not atomic across the Weymouth–Yue throw; `set_state` + `advect_vof` on the collocated
     solver advects with a zero face field (flow VoF).
   - no free-slip domain BC (flow); VoF interface area not exposed (flow).
   - inflow/outflow diverging to NaN in one configuration — "investigating" since July (flow).
   - Kokkos "deallocated after finalize" warning under Jupyter (packaging; the live() registry fix
     covers flow's FlowSolver — check dem/voro under a notebook teardown).
   - Poiseuille verify metric ("fake convergence") — `verify_poiseuille_flow.py` was renamed and
     re-metricked; confirm the issue entry can close.
5. dem root-level `verify_*.py` / `test_*.py` / `build_log*.txt` scratch: they are inside the
   package repo and ship in the sdist tree-walk — move under `dem/tests/scratch/` or gitignore [A].

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

1. **CUDA family** [D3]: today only `peclet-flow-cu13`. Recommended for 0.7.0: add `cuda-wheel`
   jobs + `packaging/pyproject-cuda.toml` for **pnm, dem, voro** (dem: add the ArborX build to the
   prefix step) and a `peclet-cu13` metapackage from the umbrella, so `pip install peclet-cu13`
   mirrors `pip install peclet`. Validate each with a local `pip wheel` against `extern/install/nvidia-cuda`
   in a fresh venv before tagging; register the four new PyPI project names' trusted publishers.
   Multi-arch SASS (only sm_75 + PTX today) stays as is; note JIT on first import in the docs.
2. **coupling CI**: none exists — add `ci.yml` (OpenMP prefix, build flow + dem + coupling, run `tests/test_terminal_velocity.py`).
3. **Containers**: DONE 2026-09-04 — `push` input added to `containers.yml`; pnm + coupling added to
   the three `.def` files and proven by a `only=cpu, push=false` dispatch (run 33869278789: every member
   installed, `peclet-cpu.sif` built). cuda/hip defs carry the same lines, untested until the next tag/dispatch.
4. **HIP link error** — the LUMI blocker: run RELEASE.md §8 experiment 1 (override
   `CXX_VISIBILITY_PRESET` to `default` under `Kokkos_ENABLE_HIP` in flow/pnm/dem/voro/coupling)
   through a `only=hip, push=false` dispatch. If it links, publish `peclet-hip:0.7.0-gfx90a` as
   *untested*; if not, the release ships without a HIP image and says so.
5. Optional but cheap: `check_release_state.sh --ci` as the first step of each `release.yml`
   (tag == version == `__version__`), and a `workflow_dispatch` dry run of the CUDA wheel job.
6. Dependabot action majors differ across repos (`upload-artifact` v4 in flow vs v7 in the umbrella) — harmless per repo, but keep each repo's upload/download pair on the same major.

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
