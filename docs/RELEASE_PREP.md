# Release preparation — family 1.4.0 (published 2026-10-04); the next cycle is not yet opened

The one-off companion of [RELEASE.md](RELEASE.md) (the durable workflow): the state of the release
currently being prepared. **Current state:** the family 1.4.0 release (flow 1.3.0, coupling 1.1.1,
metapackages `peclet` / `peclet-cu13` 1.4.0; core 1.4.0 the day before) was published on
2026-10-04 — §12.9. No later cycle has been opened. When one is, re-cut this file as RELEASE.md §9
says: archive §12 next to the earlier cycles and start a new section from RELEASE.md's phase
headers.

**Still open from the 1.4.0 cycle** (§12.9): Phase F (Snellius package) and Phase G (LUMI) — both
need the user, as they spend billed cluster time; the gallery re-check (RELEASE.md §10); a quiet-GPU
timing of the CUDA backward-facing step against v1.2.0; the pocket mask for `get_p` and the traction
(a CHANGELOG known limitation).

**Carried into the next cycle** (found by the pre-flight and the doc clean-up, 2026-10-08):

- **Core must be tagged before flow ships.** flow `main` includes `peclet/core/scheme/cut_cell_geometry.hpp`
  and `probe_flux.hpp`, which are absent at its pin `v1.4.0`: a wheel would not compile. Cut the core
  tag, repin flow (`PECLET_CORE_TAG`), then release. `tools/release/check_release_state.sh` flags it.
- **coupling's next version is a minor bump:** the `eps_min` default changed 0.25 → 0.05 (results
  change wherever ε fell below 0.25; CHANGELOG [Unreleased]; register, coupling).
- **The pre-flight's docstring audit fails locally** because `peclet.halo/geom/amr/coupling` are not
  installed in the suite venv — an environment gap, not a package defect; install or point it at the
  build trees before trusting the audit.
- **Needs the user — GitHub hygiene:** (a) ~40 remote branches already merged into `main` (core,
  flow `vof-p*`/`telescope`/`kokkos-migration`…, dem, voro, umbrella) can be deleted without loss —
  blocked for agents by the permission policy; (b) ~35 open Dependabot GitHub-Actions PRs across
  core, morton, flow, dem, voro and the umbrella (some from July): apply as direct commits or close.
- **Doc debt to check in the release docs pass:** flow `doc/porous_drag_scheme.md` §2 may still show
  the plain-u predictor/projection coefficients without ε (ρε inertia landed in flow `2d1564a`);
  flow `doc/velocity_mg_plan.md` may cite stale names (`set_ibm_solid`,
  `setVelocityStaircaseCoarse`); flow `AGENTS.md` not re-checked against the compacted CLAUDE.md;
  `docs/DEVELOPMENT.md`, `CORE_BOUNDARY.md`, `AGENT_WORKFLOW_HARDENING.md` are not in the mkdocs nav
  (`mkdocs build --strict` not run); dead plain-text paths in `PHYSICAL_UNITS_PLAN.md:319,321,415,459`
  (`core/python/amr_bindings.cpp`, `test_amr.py` moved to amr) and `ROADMAP.md:101`
  (`dem/mpi/test_particle_migration.cpp`); flow `quality.yml` still excludes six `vof-w4` files
  from clang-format although `vof-w4` is superseded.

**Earlier cycles, archived verbatim:**

- [archive/RELEASE_PREP_1.0-1.1.md](archive/RELEASE_PREP_1.0-1.1.md) — 1.0.0 (2026-09-12), 1.0.1
  (2026-09-14) and 1.1.0 (2026-09-16), §0–§11 with their original numbering. Its open lists were
  **not re-verified** when it was archived — check each item against the repos before acting: the
  operator-storage follow-ups (§1.2 items 2–4), open technical issues (§5), decisions needed (§6),
  physical domains (§7).
- [archive/RELEASE_PREP_0.7.x.md](archive/RELEASE_PREP_0.7.x.md) — 0.7.0/0.7.1/0.7.2.
- The 1.2.x and 1.3.0 umbrella releases (2026-09-21, 2026-09-27) have no RELEASE_PREP record; see
  the CHANGELOG.

Section 12 keeps its number so that citations of "RELEASE_PREP §12.x" (the decision register cites
§12.5) stay valid.

## 12. CYCLE — family 1.4.0 (opened 2026-10-03)

Prepared up to, not including, any outward step (no push, tag, publish, GitHub release or workflow
dispatch). Every change sits on a local branch `rel-1.4.0` in a sibling worktree, ready for
`git merge --ff-only`. The coordinator publishes on the user's go.

### 12.1 Versions (RELEASE.md §4.1)

| Package | Old → new | Why |
|---|---|---|
| peclet-halo / peclet-core | 1.4.0 (released alone today) | not re-released; flow and coupling pin `v1.4.0` |
| peclet-flow (+ `-cu13`) | 1.2.0 → **1.3.0** | minor: `march_to_steady`, `set_pressure_bottom_solver`, the force API (`hydro_force_torque()` deprecated), the GPU device bottom (a named numerics change) |
| peclet-coupling | 1.1.0 → **1.1.1** | patch: the traction reader + fallback, core pin |
| peclet / peclet-cu13 | 1.3.0 → **1.4.0** | pins changed; the LE claim removed from the page; `[mpi]` → peclet-core 1.4.0 |
| peclet-voro (+ `-cu13`) | 1.0.4 (kept) | the one commit since `v1.0.4` removes three stale scripts under `mpi/` and edits docs; the README (its PyPI page) never carried the Lees–Edwards or "14–17 M cells/s" claims (checked at `v1.0.4` and `main`); LE lived in the umbrella README/`docs/index.md`, fixed there. **Open question Q1.** |
| peclet-morton | 1.0.2 (kept) | one commit: the vcpkg port file (not in any wheel) |
| peclet-geom | 1.0.1 (kept) | one commit: a module docstring date (`peclet-core 1.3.1`, not 1.3.0); its vendored core `geom/*.hpp` are byte-identical v1.3.0 → v1.4.0 (`git diff --quiet`) |
| peclet-amr | 0.2.0 (kept) | one commit: a design-note pointer |
| peclet-pnm, peclet-dem | kept | no commits since their tags |

### 12.2 Branches (worktrees left in place)

- flow `rel-1.4.0` (`suite/flow-rel140`): version bump, cell-unit trap docstrings, README capabilities;
  rebased onto flow main `b63402d` after the battery. The tested tree (`ff6402c`) and the release head
  differ only under `doc/` and `tests/study/` (`git diff --stat` outside those: empty).
- coupling `rel-1.4.0` (`suite/coupling-rel140`): core pin v1.4.0, version bump.
- voro `rel-1.4.0` (`suite/voro-rel140`): core pin v1.4.0, 1.0.5 bump — **prepared but not pinned
  by the metapackage** (Q1); publish only if Q1 is answered "release".
- umbrella `rel-1.4.0` (`.claude/worktrees/rel140`): api-autogen (rebased: `f4ccf80`, `f203911`,
  `f6295e7` cherry-picked cleanly onto origin/main 5251d49), the LE fix, the metapackage pins, the
  release-tooling binding map, this section, the CHANGELOG, and the submodule gitlinks.
- dem `suite/dem-rel140` (detached at origin/main): build trees for the coupling tests only.

### 12.3 Checklist

- [x] A: state pre-flight; worktree branches of flow/core/dem/voro/amr are campaign branches, not in this release (parked by scope).
- [x] B: test matrix (§12.4).
- [x] C: versions (§12.1), `PECLET_CORE_TAG v1.4.0` in coupling (and voro's prepared branch).
- [x] D: landing pages (flow README gains steady states + forces; umbrella README loses LE), `check_landing_pages.py`, `check_docs_snippets.py --ref origin/main --run` (§12.5), `mkdocs build --strict` with generated pages.
- [ ] E: publish (coordinator, after the user's go) — §12.6.
- [ ] H: containers (now with geom + amr), Site dispatch, GitHub Releases, Zenodo.

### 12.4 Test matrix (2026-10-03, host-openmp and nvidia-cuda prefixes, MPI on, `--bind-to none`)

| Repo | host-openmp | nvidia-cuda | Notes |
|---|---|---|---|
| flow `rel-1.4.0` | **194/194** (`-LE bench`) | **194/194** | host first pass at 4 threads/rank, `-j4`, load 57–75: 96 passed, then `velocitymg_bc_mpi_np4`, `sdflow_mpi_np4`, `sdflow_colocated_mpi_np4` hit the 3600 s timeout (OpenMP spin under oversubscription, the flow/CLAUDE.md trap). Stopped and re-ran the remaining 98 at 2 threads/rank, `-j3`: 98/98, those three in 7.8 s, 14.9 s and 430 s. Not a code failure. |
| flow verify scripts | PASS ×3 | PASS ×3 | `verify_periodic_spheres_sdflow`, `verify_channel_sdflow`, `verify_bfs_sdflow` (poiseuille, lid cavity, regression are ctests above). CUDA BFS: the first run hit its 3600 s timeout with the GPU shared by another session (the process sat in `cudaDeviceSynchronize`, i.e. GPU-bound); re-run with a 9000 s budget: PASS in 5056 s, x_r/S 5.26 / 8.16 identical to the host. Per step 0.18 / 0.25 s on the shared GPU vs 0.13 / 0.14 s on 8 host threads; the case is a small quasi-2D grid with a non-singular operator, so the new device bottom is not engaged (GraphAMG, as in 1.2.0). Not attributed; worth a quiet-GPU timing against v1.2.0 after the release |
| coupling `rel-1.4.0` | **3/3** | **3/3** | against flow `rel-1.4.0` + dem origin/main build trees (`PECLET_FLOW_BUILD` / `PECLET_DEM_BUILD` set); traction smoke: no DeprecationWarning, split filled |
| voro `rel-1.4.0` (prepared, Q1) | **42/42** | **42/42** | CUDA first pass 41/42: `repair_sdf_mpi_np4` failed to allocate 4.6 MiB on the GPU while the flow CUDA battery shared it; re-run alone: PASS (7.6 s) |
| docs | — | — | `check_docs_snippets.py --ref origin/main --run` (with the fixed binding map): NAMES PASS; RUN PASS ×3 (README, index, notebook; k = 1.2410e-01); `mkdocs build --strict` PASS with pages generated from the MPI build trees |
| geom, amr wheels | built | — | `pip wheel ./geom`, `pip wheel ./amr` against host-openmp: both build and import (`peclet.amr` OpenMP) — de-risks the new `cpu.def` lines (the Apptainer image itself is built only in CI) |

### 12.5 Pre-tag checks

1. **dem: dense periodic growth of an elongated grid-SDF particle — does not reproduce.** The
   2026-07-04 crash (position → inf → segfault at scale ~0.85) was reproduced by protocol on dem
   main (`2b0aebd` = v1.1.0, no commits since): a `build_particle` spherocylinder (L/D 3.2, 288 shell
   points), fully periodic cube, forced linear scale ramp 0.3 → 1.0 (no overlap gate) over 1400
   steps + 600 settle. CUDA N 200 φ 0.50: PASS, positions finite throughout, max overlap 5.6 % of
   the particle length; host-openmp, same case: PASS, 1.3 %; CUDA N 400 φ 0.60: PASS through scale
   0.85–0.875 and to the end, finite — but the forced ramp past jamming ends at max overlap 0.82 of
   the length (expected for an un-gated ramp, not a crash). Consistent with dem `7b5d1b8` having
   fixed the OOB writes. Script: `dem_elongated_periodic_growth.py` (session scratchpad; recorded in
   the coordinator report).
2. **CUDA teardown abort — not reproduced on the CUDA build tree.** `peclet.flow` (nvidia-cuda
   prefix, flow `rel-1.4.0`): N 32 sphere, 5 steps, interpreter exit with the Solver alive → exit
   0; same with a `diagnostics.field_view` capsule held past exit → exit 0. The fix is flow
   `3035320` (Releasable solver + capsule, atexit release-then-finalize), shipped since flow
   0.5.0; the open-item note was stale. The `peclet-flow-cu13` *wheel* itself was not built locally (its CI cuda-wheel
   job builds it at the tag; `gh workflow run release.yml` would dry-run it but is a workflow
   trigger, outside this preparation).
3. **`cell_centers()` vs analytic scene, cell units — confirmed and documented.** Without an
   extent `cell_centers()` = i + 1/2; `set_scene` places cell i's centre at i. The same sphere
   installed through `set_solid(SDF sampled on cell_centers())` and through `set_scene` differs in
   its blocked x-face centroid by (0.5, 0.5, 0.5) cells (N 24); with `extent=` the difference is
   0. Docstrings of `cell_centers` and `set_scene` now say so (flow `4cf66df`); CHANGELOG known
   limitation; a register entry deferring the API fix to 2.0.0 is DRAFTED for the user (not
   committed).

### 12.6 Before publishing — user actions, then the sequence

**User actions before publishing:**

1. The go for the release (scope: flow 1.3.0, coupling 1.1.1, metapackages 1.4.0; Q1 voro).
2. `gh auth refresh -s workflow` — the umbrella branch changes `.github/workflows/containers.yml`
   and `site.yml`; a push without the `workflow` scope is refused.
3. Answer or accept the defaults of the open questions (§ coordinator report): Q1 voro, Q2 the
   cell-centers register entry.

**Sequence** (RELEASE.md §6; each member's `release.yml` runs `landing-pages` before `publish`):

1. **flow**: if `origin/main` moved, `git -C flow-rel140 rebase origin/main` (only doc commits so
   far) — then `git -C flow-rel140 push origin rel-1.4.0:main`; `git -C flow-rel140 tag v1.3.0 &&
   git -C flow-rel140 push origin v1.3.0`; watch Release (CPU wheels + cuda-wheel, ~90 min); confirm
   `pip index versions peclet-flow` and `peclet-flow-cu13` show 1.3.0.
2. **coupling**: same with `coupling-rel140`, tag `v1.1.1`; confirm `peclet-coupling` 1.1.1.
3. **umbrella**: re-point the gitlinks if flow or coupling were rebased
   (`git update-index --cacheinfo 160000,<sha>,flow` in `.claude/worktrees/rel140`, amend the pointer
   commit), then `git push origin rel-1.4.0:main`, `git tag v1.4.0`, push the tag → Release
   (landing-pages, the two metapackages, quickstart) and Containers (cpu/cuda/hip; the cpu leg
   dispatches Site with `image_tag=1.4.0`).
4. GitHub Releases: flow `v1.3.0`, coupling `v1.1.1`, umbrella `v1.4.0`, body = the CHANGELOG
   sections → Zenodo version DOIs.
5. Smoke in a fresh venv: `pip install peclet==1.4.0` (+ `peclet-cu13` on the GPU box, +
   `peclet[mpi,cfd-dem]`), `check_docs_snippets.py --installed --run`.

### 12.9 PUBLISHED — family 1.4.0, 2026-10-04 (user go 2026-10-03)

- **PyPI:** peclet-flow + peclet-flow-cu13 1.3.0 (tag v1.3.0 on 7c95c20; 13/13 Release jobs, CUDA wheels cp310–cp314),
  peclet-coupling 1.1.1 (v1.1.1 on 485ca1f), peclet + peclet-cu13 1.4.0 (umbrella v1.4.0 on 00078fb; Release
  incl. landing-page and quickstart jobs green). peclet-halo / peclet-core 1.4.0 the day before (core v1.4.0 on c656ccb).
- **Not re-released:** voro 1.0.4 (§12 Q1: the stale claims were on the umbrella page, fixed), dem, pnm, morton, geom, amr.
- **Containers:** cpu, cuda-sm80, cuda-sm90 AND hip-gfx90a all green. The CPU leg dispatched Site with the 1.4.0 image:
  the API pages for flow (march_to_steady), amr and halo/geom are generated, none a "not importable" stub.
- **GitHub Releases / Zenodo:** core v1.3.2 and v1.4.0 (neither had one), flow v1.3.0, coupling v1.1.1, umbrella v1.4.0.
- **Smoke:** fresh venv `peclet==1.4.0` and `peclet-cu13==1.4.0` import (versions as pinned; `march_to_steady` present);
  `check_docs_snippets.py --installed --run` PASS on README, index and quickstart notebook (k = 1.2410e-01, N 32)
  once matplotlib is installed (the snippets plot; not a peclet dependency).
- **Tag type:** flow v1.3.0 and core v1.4.0 are lightweight (convention: annotated); `describe --tags` tooling unaffected.
- **NOT done (need the user: billed cluster time):** Phase F Snellius package, Phase G LUMI; gallery re-check (§10).
- **Follow-ups:** quiet-GPU compare of the CUDA backward-facing step against v1.2.0 (0.18–0.25 s/step vs 0.13–0.14 s on
  8 host threads, unattributed); pocket mask for get_p + pocket cells out of the traction (CHANGELOG known limitation).
