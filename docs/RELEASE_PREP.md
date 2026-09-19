# Release preparation — state on 2026-09-11 (cycle: **peclet 1.0.0**, shipped; then 1.0.1 and 1.1.0)

> **This file still describes the 1.0.0 cycle.** 1.0.0 shipped 2026-09-12, 1.0.1 on 2026-09-14 and
> **1.1.0 on 2026-09-16** (flow 1.1.0; core/pnm/dem/voro 1.0.2; morton/coupling 1.0.1 and amr 0.1.1
> unchanged). It has NOT been re-cut for those, so read every "next release" below as 1.0.0 and check
> the item against the repo before acting on it. RELEASE.md's instruction to re-cut this file and
> archive the previous cycle is outstanding — see the 1.1.0 entry in the CHANGELOG for what actually
> shipped.

The one-off companion of [RELEASE.md](RELEASE.md) (the durable workflow), re-cut for the 1.0.0 cycle
as that file's own header instructed. The previous cycle's record (0.7.0/0.7.1/0.7.2, measured
2026-09-04) is archived verbatim at
[archive/RELEASE_PREP_0.7.x.md](archive/RELEASE_PREP_0.7.x.md) — §8 of that file, the physical-domains
feature, is still live work and is carried forward as §7 below.

Everything here was measured on **2026-09-11** with `tools/release/check_release_state.sh`,
`tools/release/audit_docstrings.py`, `tools/release/audit_examples.py` and four read-only surveys of
the repos. Development continues meanwhile: **re-run the three tools on the day** and refresh these
numbers.

Legend: **[B]** blocks the release · **[R]** do during the release window · **[A]** after the release,
does not block · **[D]** decision needed from the maintainer.

## 0. Snapshot

| package | version | last tag | commits since | notes |
|---|---|---|---|---|
| core | 0.6.1 | `v0.6.1` | 22 | must be tagged and published **first** (RELEASE.md §4) |
| amr | 0.1.0 | — | — | new eighth package (split 2026-09-10); ships at 0.x per QUALITY_PLAN **D9 exception**, sdist-only |
| morton | 0.2.1 | `pre-legacy-removal` | 4 | |
| flow | 0.5.1 | `v0.5.1` | 45 | |
| pnm | 0.1.2 | `v0.1.2` | 13 | |
| dem | 0.5.1 | `v0.5.1` | 20 | |
| voro | 0.5.1 | `v0.5.1` | 26 | |
| coupling | 0.4.0 | `v0.4.0` | 10 | |
| umbrella | 0.7.2 | — | — | |

Single version source (D4) is honoured everywhere: every `CMakeLists.txt` reads its own
`pyproject.toml`, `__version__` is `importlib.metadata`-derived, and `CITATION.cff` / `Doxyfile`
agree. No drift found. Kokkos 5.1.1 / ArborX v2.1 are pinned identically across every repo's CI,
`tools/bootstrap_deps.sh` and every `PecletDeps.cmake`.

**QUALITY_PLAN status correction.** The umbrella `CLAUDE.md` claim that "F and G remain" is stale:
verified against the repos, F and G.1–G.7 are done in all eight. Only **G.8** (flow explicit
instantiation, the build-time refactor) is outstanding, and QUALITY_PLAN queues it explicitly as
"before or after the tag, not breaking".

## 1. Blockers [B]

### 1.1 The core pin must be advanced as part of the release sequence — and nothing enforced it

`voro` and `amr` include core headers that **do not exist at the `PECLET_CORE_TAG "v0.6.1"` they
pin**. A wheel build sets `PECLET_VENDOR_DEPS=ON`, FetchContents core at the pin, and fails to
compile:

- `voro` → `peclet/core/solver/{coloring,csr_bicgstab}.hpp`
- `amr` → `peclet/core/scheme/cut_cell_closure.hpp`, `peclet/core/solver/{coloring,csr_bicgstab,csr_operator,face_csr,vector_ops}.hpp`

Cause is benign — core `d93c323` lifted the face-CSR solver layer out of `amr/` on 2026-09-10 and
voro `aee039b` moved to it the same day — and amr's CI documents the pin as a placeholder its release
repins. This is therefore a **sequencing requirement**, not a defect to patch today: core is tagged
and published first, then every consumer repins, then consumers are tagged. Do **not** cut an interim
`v0.6.2` for this; it would burn a PyPI version for nothing.

What made it a blocker is that **three independent safety nets were blind to it**:

1. the `PECLET_VENDOR_SIBLINGS` CI guard *configured* without compiling, so it proved the tag
   resolved but not that anything built against it — a missing header fails at compile;
2. `check_release_state.sh` grepped `PECLET_TPX_TAG`, a name the rename table retired, so it printed
   `core=` blank for every consumer and reported nothing wrong;
3. `release.yml` (the wheel build, which would have failed honestly) triggers only on a `v*` tag —
   i.e. it discovers the problem *during* the release.

**Fixed 2026-09-11:** `check_release_state.sh` now greps the correct variable, covers `amr`, and
verifies every `peclet/core/*.hpp` a consumer includes against the tag that consumer pins, failing
loudly. voro's `ci.yml` guard now compiles the module the wheel actually builds. **Still to do [R]:**
give `flow`, `dem`, `pnm`, `coupling` and `amr` the same compiling pre-tag guard — today the
pre-flight is their only net.

### 1.2 SCALING_ISSUES #1 — DECIDED 2026-09-11: double operator storage is the default [R]

Not fixed. `PECLET_FLOW_OPERATOR_DOUBLE` is an opt-in compile flag, default **OFF**
(`flow/CMakeLists.txt:52`); the production double-diagonal storage was deliberately not shipped
(`flow/doc/history/vof_workorders_v34.md:636`). Live corroboration from `QUALITY_PLAN.md:371-372`,
written 2026-09-11: the porous path's default MG-PCG reports a **non-finite preconditioner on 2 of 5
steps, deterministically**.

**Decision taken 2026-09-11: flip the default.** `PECLET_FLOW_OPERATOR_DOUBLE` is now `ON`
(flow `CMakeLists.txt:48-72`) and a float build emits a CMake warning naming this issue. Documenting
the limitation was rejected because the failure is *silent* — documentation protects only a user who
already knows. The double-*diagonal* fallback stays retired (65x worse on divergence). Recorded in
[decisions/flow.md](decisions/flow.md) and [SCALING_ISSUES.md](SCALING_ISSUES.md) §1.

**What this leaves to do in the release window [R]** — measured 2026-09-12, outcomes inline:

1. ~~**Re-bless the regression baselines.**~~ **NOT NEEDED — the baselines do not move.**
   `sdflow_regression.py` against the *existing* `perf_baseline.json`, run on a double-default build
   (`flow/build_rel_omp`, host-openmp): **PASS**, with every gated metric at **+0.00 %** — `K_inf`
   7.447, `k*_inf` 0.0062362 and 0.017183 (was 0.017184, +0.00 %), convergence orders 2.29 / 2.19 /
   1.38 unchanged, and **every pressure-iteration count identical** (368/560/525/976/1607,
   635/573/439/717, 746/667/1308/2250). What moved is `max|div|`, by about two orders of magnitude
   *in the right direction* — e.g. the N=64 ring bed 1.4e-10 → 1.0e-11, the Z&H sphere 4.5e-11 →
   2.1e-12 — and the gate on divergence is an upper bound, so an improvement passes. **Do NOT run
   `--update`**: it would overwrite a baseline that still holds and discard the historical reference.
   The three regression beds are simply not the high-contrast dense beds where float storage breaks.
   *What does move is `state_hash.py`*: nine of the ten single-rank entry paths and the np=2 case
   change, which is expected and is the deliberate numerics change. `scalar` is byte-IDENTICAL
   (`711f587dab95ca…`) because that case carries no cut-cell operator and no multigrid contrast, so
   the storage type never reaches it — a useful sanity check that the flip did only what it claims.
   New hashes: staggered_bed `e933ca12437925a8`, colocated_ghost `b5208af291d680c0`,
   colocated_gauge_exact `43fe1408541bbe83`, colocated_plain `0fa88904b2ea78b6`, colocated_embed
   `22a77cf1104be469`, channel `9d1daa0e9928ec50`, vof_droplet `929eb7c21c99250f`, porous
   `44d3ffd55797efcb`, scene_moving `6d8df1d3917f7b62`, mpi_np2 `6b300a8da0c97703`.
   **And the defect the flip exists to fix is gone**: the float build printed
   `CutcellMG::solvePCG: preconditioner produced non-finite z … (reported as 500/500 iterations,
   i.e. a CAPPED solve)` twice on the porous case; the double build prints it zero times.
2. **Re-measure the ~12%** — STILL OPEN. A first attempt on 2026-09-12 was contaminated: four
   builds were running concurrently and the float arm measured 358 ms/step against a quiet-machine
   value of 311 ms/step for the same binary, i.e. the load term was larger than the effect. Redo it
   on a quiet host as a back-to-back A/B of the two modules (`build_g8h2` float vs `build_rel_omp`
   double), min of three runs of twenty steps. The regression's own wall-clock column suggests
   **+2 % to +10 %** depending on the case rather than a uniform 12 %, but that column is a
   single-shot number and is not evidence.
3. ~~**Check the CUDA build.**~~ **Host half DONE, CUDA half open.** On host-openmp the macro reaches
   every target: `PECLET_FLOW_OPERATOR_DOUBLE=1` is present in `flags.make` for `peclet_flow_solver`,
   `peclet_flow_solver_mpi` (G.8's two instantiation libraries), `peclet_flow` and the consumer tests
   — so there is no TU at a different precision from the headers it shares, and no silent ODR
   violation. Repeat the same `flags.make` check on an `nvidia-cuda` tree before tagging.
4. **Re-check any published dense-bed number** produced by a float build — the porous-scaling study
   and RingBed in particular. STILL OPEN.

### 1.3 The verification scripts silently bind to a stale build [B]

`flow/scripts/*.py` (38 files) open with

```python
sys.path.insert(0, .../os.environ.get("SDFLOW_BUILD", "build_mpi"))
```

which puts `flow/build_mpi` at `sys.path[0]` and **overrides `PYTHONPATH`**. So the workflow
flow's own `CLAUDE.md` documents —

```
PYTHONPATH=$PWD/build python scripts/verify_poiseuille_flow.py
```

— does not test `$PWD/build`. It silently tests `build_mpi`, whose `_flow.so` is currently dated
**2026-09-01**, ten days and ~45 commits stale. The override variable also still carries the retired
`SDFLOW_` prefix (QUALITY_PLAN rename table: `sdflow` → `flow`), so it reads as dead configuration
and nobody sets it.

Found 2026-09-11 while validating the operator-precision flip: the run failed with
`set_body_force(): incompatible function arguments`, because the Sep-1 module still had the
three-float signature that the current source replaced with a 3-sequence. **The failure mode that
matters is the opposite one** — when the stale module's API happens to still match, the script
prints PASS and nobody learns which binary it validated.

This is the same class as §2.1's stale `build_rel*` trees, and together they mean the suite's two
validation entry points — the verification scripts and the docstring audit — can both certify a
build nobody intended.

**Fix before the tag:** have the scripts prefer `PYTHONPATH` when it is set, rename the variable to
`PECLET_FLOW_BUILD`, and make the default an explicit failure rather than a stale directory. Then
re-run the verification battery and note which build produced each number. `scripts/` is 38 files
and was heavily edited on 2026-09-11 by the G.8 work, so this wants one owner doing it in a single
pass, not a scattered edit.

## 2. Documentation [R]

Doxygen is in good shape: 7 of 8 repos ship a CI-wired Doxyfile and `mkdocs.yml:78-85` links all
seven sites correctly (voro generates its Doxyfile via CMake by design). No stale module names
(`sdflow`, `vorflow`, `tpx`, `pnm_backend`) survive outside `docs/archive/` and historical citations.
No stale version literals on site pages. `tools/gen_python_api.py`'s `PAGES` list is current. amr is
fully integrated — README, CLAUDE.md, four workflows, `docs/python/amr.md`, mkdocs nav, umbrella
README.

1. **[B for the audit, not the release] Re-run `audit_docstrings.py` against a CLEAN family build.**
   The 2026-09-11 run reported `894 callables, 36 undocumented, 0 stale`, but every `build_rel*` tree
   it imported predates the current HEAD — e.g. `core/python/build_rel_omp` was built 2026-09-05,
   before `Migrator`→`ParticleMigrator` landed, so the audit flagged classes that no longer exist
   while the real ones are documented. RELEASE.md §5.1 already requires the clean rebuild; it has not
   happened since the renames. **Treat the 36 as unverified until re-run.**
2. **Fixed 2026-09-11:** `audit_docstrings.py` audited `peclet.core.amr`, removed when AMR split out,
   so `peclet.amr` was audited by nothing. Now corrected. (A manual run of the script's logic against
   `amr/build_q` gives 98 callables, 0 undocumented — clean, but by luck, not by process.)
3. **`peclet.coupling` docstrings** — was 10 of 14 public callables undocumented (71%), the worst
   public surface in the suite: `CfdDem` and its `step`/`compute_forces`/`update_void_fraction`/
   `last_drag`/`last_slip`, `ResolvedCfdDem` and its `step`/`forces`/`torques`. Being written
   2026-09-11; verify on the rendered page before the tag.
4. Remaining undocumented singles: `core/python/geom_bindings.cpp` — `SceneBuilder.__init__`,
   `add_union`, `add_intersection`, `num_nodes`, `num_instances`; `flow/src/flow_bindings.cpp` —
   `has_scene`, `pressure_telescope` (both solvers), `velocity_multigrid_active` (both diagnostics).
5. **`coupling` has no Doxygen setup** — no `docs/Doxyfile`, no `docs.yml`, not in mkdocs' C++ API
   list, though `src/{drag.hpp,coupling_kernels.hpp,coupling_bindings.cpp}` are real C++. The only
   such gap in the suite. [A] unless coupling's C++ is considered public API for 1.0.0.

## 3. Packaging and CI [R]

1. **The repin gate** — see §1.1. `check_release_state.sh` now fails loudly; run it before tagging
   anything and again after the core tag.
2. **`coupling/CITATION.cff` is missing** — the only package without one; a per-repo Zenodo metadata
   gap.
3. **`docs/RELEASE.md` §11** predates amr (not listed) and states "coupling has no CI at all", which
   is false — `coupling/.github/workflows/ci.yml` builds flow+dem+coupling and runs the pytest
   battery. Re-verify the rest of that gap list (family rehearsal workflow, `--ci` in `release.yml`,
   CUDA dry-run).
4. CI is honest by the D standard: no `xfail` anywhere, no disabled jobs; the only
   `continue-on-error` jobs are clang-format (informational by design) and morton's Intel-SDE AVX-512
   job (the SDE download URL rots). amr's `ci.yml` carries an explicit "Honest CI" header — the
   best-documented CI in the suite.
5. The 0.7.1 core-sdist trap does **not** recur in amr: its `cmake/PecletDeps.cmake` defines a
   self-contained `peclet_require_nanobind()`.

## 4. Tests — qualify any "tests pass" claim [R]

Several repos register **zero tests** under a plain `cmake -B build`:

| repo | default | full |
|---|---|---|
| voro | **0** (needs `-DPECLET_VORO_BUILD_TESTS=ON`) | 42 (24 + 18 MPI) |
| pnm | **0** (needs `-DPECLET_PNM_BUILD_TESTS=ON`) | + MPI with `-DPECLET_PNM_MPI` |
| flow | 43 kernel (needs `-DPECLET_FLOW_BUILD_TESTS=ON`) | 106 distributed with `-DPECLET_FLOW_MPI=ON` |
| dem | 11 | 47 with `-DPECLET_DEM_MPI=ON` |
| core | 52 plain / 67 Kokkos np1–8 / 6 Python | |
| amr | 100 (92 C++ + 5 bench + 3 Python) | |

"No tests were found!!!" is **not** a pass signal. The exit-77 SKIP convention is honoured
everywhere, and the MPI launcher is pinned to the linked MPI in every repo — both former footguns are
fixed and regression-tested.

## 5. Open technical issues, ranked [R/A]

1. **[R]** SCALING_ISSUES #1 — decided 2026-09-11, default flipped; the re-blessing work is §1.2.
2. **[R]** SCALING_ISSUES #2, MG depth cap: telescoping ships and is the default, but the underlying
   defect (intermediate levels must coarsen in place) is routed around, not solved. flow's CLAUDE.md
   calls it "the top open item at scale".
3. **[A]** SCALING_ISSUES #3 — **FIXED 2026-09-16**, so it is no longer a limitation to state: the
   SDF ghost outside a non-periodic face was periodic-wrapped (an inconsistent pressure row at a cut
   inlet) and the Dirichlet outlet row carried the literal openness 1.0 instead of the face
   aperture (mass leaving through solid). Gated by `test_openbc_solid{,_mpi}`, the first tests to
   combine `set_domain_bc` with `set_solid`. **Two consequences for the release:** the 1.0.0
   "Known limitations" bullet in [the CHANGELOG](https://github.com/computational-chemical-engineering/peclet/blob/main/CHANGELOG.md) is superseded and 1.1.0 needs a
   Fixed entry; and a THIRD, MPI-only defect it surfaced is **new issue #8** (the halo wraps a
   non-periodic face's HIGH boundary plane), also fixed — both halves, openness and the outflow
   velocity plane, since fixing either alone breaks `vof_bc_mpi`'s composed conservation budget.
4. **[R]** Collocated ghost-mode `(matrix_order=1, rhs_order=2)` is march-unstable above ~2000
   spheres and is documented do-not-use. Collocated MPI validated only at np=1,2,4; np≥16 unresolved.
5. **[R]** voro CUDA `clipCellAgainstSdf` wrong by up to 22% on device at 128/256 grids (correct on
   OpenMP).
6. **[D]** Interstitial vs superficial drag normalisation — the only ⚠️ UNRESOLVED entry in
   [DECISIONS.md](DECISIONS.md). `ibm-accuracy-sphere-validation.md` assigns Zick–Homsy and
   vdH/Beetstra to **opposite** conventions in the same file. Decides a (1−φ) factor on published
   permeabilities, so it reaches the porous-scaling study, RingBed and the gallery.
7. **[A]** `check_decomposition.py` unusable above ~100 ranks (still models full coarsening).
8. **[A]** Fixed and verified: SCALING_ISSUES #4 (NBX inter-round tag race, core `10294e6`) and #5
   (momentum residual stop, now default).
9. **[A]** `vof-w4` is parked and unmerged (`f29c8e7`), correctly scoped out — flow's CLAUDE.md
   already documents colliding markers as outside the rating. Only a gate if release docs claim VoF
   collision physics; they do not.
10. **[A]** Open from QUALITY_PLAN §6: C.3 (one shared `cmake/PecletDeps.cmake` — pnm/dem/coupling
    are byte-identical, voro and flow differ), D.6 (composite Kokkos CI action), D7
    (INTERFACES.md still carries its "design sketch, not realised as code" banner — the decision
    between `concepts.hpp` + `static_assert`s and a duck-typed contract is still open).

## 6. Decisions needed [D]

1. ~~**SCALING_ISSUES #1**~~ — **decided 2026-09-11**: default flipped to double operator storage
   (§1.2). What remains is re-blessing, not deciding.
2. **Drag normalisation** — settle interstitial vs superficial (§5.6) before any permeability number
   is republished under 1.0.0.
3. **D7 / INTERFACES.md** — realise the concepts or restate the file as a contract.
4. **coupling C++ as public API?** — decides whether §2.5 (no Doxygen) is [A] or [R].

## 7. Physical domains — carried forward

Phase 1 landed 2026-09-06, Phase 2 (anisotropic cells) 2026-09-07; see
[PHYSICAL_UNITS_PLAN.md](PHYSICAL_UNITS_PLAN.md) and the archived
[RELEASE_PREP_0.7.x.md §8](archive/RELEASE_PREP_0.7.x.md). This is the headline feature of 1.0.0
alongside the API clean break. Open from Phase 2: the rotating-body torque gate,
`check_decomposition` `predict()`, and the coupling/AMR guards.

Note for readers of the submodule docs: `flow/doc/anisotropic_vof.md` and
`amr/docs/amr_anisotropic.md` cite "RELEASE_PREP §8.1 / §8.2". Those refer to the **archived**
0.7.x file, not to a section of this one.

## 8. Gallery [A]

`audit_examples.py` over 56 pages flags 14 as `NEEDS-NEXT-RELEASE`, all for one symbol — dem's
`set_periodic`/`relax`. That is expected: the gallery is already written against the unreleased 1.0.0
dem API, and the flag clears when dem is tagged. Re-run after the release and re-check the pages the
QUALITY_PLAN rename table touches.

## 9. Execution log — the 1.0.0 release run (started 2026-09-12)

Appended as the release is executed. Newest entries at the bottom. Anything here that contradicts
§§1-8 supersedes them; §§1-8 were written before the work was done.

**2026-09-12, Phase A + blockers.**

- **G.8 landed first** (flow `61e9f58` + `8f79c3b`, umbrella `02b389b`), since it changes build time
  and nothing else: `Solver<Grid>` is compiled once per grid rather than once per consumer, and
  consumers see declarations only. Bit-exact, no step-time change, CI green. Full numbers in
  QUALITY_PLAN §3.G.8. A flow rebuild is now 12 CPU-minutes instead of 45, which is what makes
  re-running the release matrix on this host affordable at all.
- **§1.1 core-pin staleness, confirmed as sequencing, not a defect.** voro's CI is RED on main and the
  cause is exactly the predicted one: run `34645794829`, job `kokkos-openmp`, step "Build against the
  pinned core / morton tags", failing with `peclet/core/solver/coloring.hpp: No such file or
  directory`. It turned red only now because voro's own `8cdac25` made that guard *compile* rather
  than merely configure. It clears when core is tagged and voro repins. **voro cannot be green on
  main before core is tagged**, so RELEASE.md §1.4's "CI green on every repo" is not satisfiable for
  voro until step one of Phase E is done. Expect it; do not treat it as a new blocker.
- **The umbrella Site workflow was red and is now green** (`f6392ba`). `mkdocs build --strict` aborted
  on four broken links in `docs/archive/RELEASE_PREP_0.7.x.md`: archiving the 0.7.x prep file moved it
  into `docs/archive/` without repointing its relative links, so `QUALITY_PLAN.md`, `RELEASE.md` and
  `PHYSICAL_UNITS_PLAN.md` still resolved against `docs/`, and `archive/VORONOI_METHODS_PLAN.md` kept a
  now-doubled `archive/` prefix. Worth remembering as a class: **archiving a document breaks every
  relative link inside it**, and strict mode turns that into a red release gate.
- **§1.2 measured — the regression baselines do NOT move.** See §1.2 above, rewritten with the
  numbers. `--update` must not be run.

**Phase B, as it completes** (host prefix `extern/install/host-openmp`, CUDA prefix
`extern/install/nvidia-cuda`, `OMP_NUM_THREADS=4 OMP_PROC_BIND=false`, trees named `build_rel*`):

| package | result | counts |
|---|---|---|
| core | **PASS** | 53 plain / 68 Kokkos / 6 Python, host *and* CUDA, np 1-8, **0 skips** |
| morton | **PASS** | default 1/1, non-BMI2 2/2 including the PDEP/PEXT-free contract, Kokkos-OpenMP 2/2, Kokkos-CUDA 2/2, pytest 9/9, 0 skips |
| flow | **PASS** at the float default | 155/155 host (49 single-rank + 106 MPI) and 49/49 CUDA single-rank, before *and* after G.8; regression PASS; re-run at the double default pending §1.3's landing |
| dem | pending | |
| voro | pending | |
| pnm | pending | |
| amr | pending | |
| coupling | pending | |

Corrections Phase B has produced so far:

- **`core/CLAUDE.md`'s ctest counts are stale**: it says 52 plain / 67 Kokkos; the measured numbers are
  **53 plain / 68 Kokkos** (54/69 counting the `bench` label), identically on host and CUDA. The
  umbrella `CLAUDE.md`'s "109 plain / 164 Kokkos / 7 Python" for core is wrong by a wider margin and
  looks like a pre-AMR-split figure. Fix both before tagging; they are quoted in release notes.
- **morton's AVX-512 batch kernels are UNVALIDATED for this HEAD.** This host is a Threadripper PRO
  5965WX with no AVX-512F, and Intel SDE is not installed and could not be obtained. The path was not
  silently skipped — it was not exercised. Either confirm it was validated elsewhere for this HEAD or
  state it as an untested path in the release notes. Do not claim it passed.
- **morton's nearest tag by ancestry is `pre-legacy-removal`, not `v0.2.1`** — `git describe` picks the
  marker tag, which is why the pre-flight prints an odd "since" count. The changelog writer should
  diff against `v0.2.1`.

**2026-09-12, the one step that needs the maintainer's hands.** `peclet-amr` is a NEW PyPI project
(`https://pypi.org/pypi/peclet-amr/json` returns 404), and Trusted Publishing will not accept a first
upload for a name that has no publisher registered. Two halves:

- **GitHub half: DONE.** `peclet-amr` had no `pypi` deployment environment, which its `release.yml`
  publish job declares (`environment: pypi`), so the job would have failed after building the sdist.
  Created to mirror `peclet-pnm`'s (no protection rules, no branch policy).
- **PyPI half: CANNOT BE DONE HEADLESSLY.** Register a *pending publisher* at
  <https://pypi.org/manage/account/publishing/> BEFORE the `v0.1.0` tag is pushed, with exactly:

  | field | value |
  |---|---|
  | PyPI Project Name | `peclet-amr` |
  | Owner | `computational-chemical-engineering` |
  | Repository name | `peclet-amr` |
  | Workflow name | `release.yml` |
  | Environment name | `pypi` |

  Every other package already exists on PyPI and needs nothing. If the tag goes first, the build
  succeeds and only the publish step fails; re-running that job after registering is enough, so this
  is recoverable rather than fatal — but it burns a release run.

Also created: `coupling/CITATION.cff` (coupling `fefc2c4`), closing §3.2. It was the only package
without one, so its GitHub release would have been the family's only archive with no authorship or
title metadata for Zenodo to read.

**2026-09-12, the double default made two GATES fail, and both were the gates' fault.**
Running flow's full battery at the new default (`build_rel_omp`, host-openmp) gave **153/155**, with
exactly two failures. Neither was a solver defect, and neither was tolerance noise to be widened away;
both were tests measuring the wrong thing, which float storage had been hiding.

1. **`verify_lid_cavity_sdflow`** marched to "steady state" by watching the plane-MEAN of `u` change by
   less than 1e-5 relative between 50-step samples. In a lid-driven cavity that mean is near zero by
   symmetry, so it is dominated by round-off in the pressure solve rather than by the flow: the test
   was watching noise settle, not the field converge. Float's higher noise floor kept the march
   running by accident. With double storage the mean settled sooner, the march stopped at step **400**
   instead of 650, and an **unconverged** field was compared to Ghia — centreline min u −0.1934
   against the tabulated −0.2058, rms 0.0247/0.0256 against a 0.02 gate.
   Fixed (flow `1ef4330`) to the largest velocity change anywhere on the plane, with the threshold
   read off a measured trajectory rather than guessed: `maxdu/U` decays 1.5e-1 (step 100) → 1.4e-2
   (400) → 4.3e-3 (650) → 9.6e-4 (1000) → 2.1e-7 (3000), while the Ghia error reaches a plateau of
   u_rms 0.0067 / v_rms 0.0053 by about step 1400 and never moves again. **The result that settles
   the question: with the corrected criterion the float and double builds agree to four digits** —
   both 1000 steps, u_rms 0.0067, v_rms 0.0037, min centreline u −0.2124, max flux divergence
   1.1e-16. Operator storage precision does not change the converged cavity answer at all.
2. **`vardensity_mpi_np4`** required the distributed Chebyshev V-cycle count to equal the single-rank
   count EXACTLY at every rank count. That is not well posed above np = 1: the stopping test is
   `maxabs(r) < rtol*r0` and at np > 1 both sides come from a global reduction whose summation order
   is not the single-rank order, so a step near the threshold can spend one V-cycle more or less. The
   test's own comment already recorded that the count sequence changes with the **OpenMP thread
   count** alone at fixed np = 1 — the conclusion was simply never drawn. Every physics gate passed by
   three orders of magnitude or more while it failed: du 4.4e-17 against 1.0e-15, dp 5.7e-13 against
   1.2e-08, max|u| 2.8e-17 against 1e-14, dP/dz error 1.1e-15 against 1e-11.
   Fixed (flow `65b2b6a`): the count gate is exact at np = 1, ±1 above it; the answer tolerances are
   untouched. A real decomposition defect shows as a large and growing divergence, never as a steady ±1.

flow `228fe02` corrects `flow/CLAUDE.md`, which described the double build as "151/155 with four
float-tuned gates". Two of those four (`vof_bc_mpi_np2`, `vof_bc_mpi_np4`) do not reproduce at all.

**The lesson for the rest of this release:** the stale-build trap (§1.3, fixed in flow `41c8356`) was
hiding both of these. The first honest local run of the verify battery is the run that found them. Any
"it passed before" from before that commit is not evidence.

**2026-09-12, Phase B results and two more traps.**

| package | result | counts |
|---|---|---|
| core | **PASS** | 53 plain / 68 Kokkos / 6 Python, host *and* CUDA, np 1-8, 0 skips |
| morton | **PASS** | default 1/1, non-BMI2 2/2 incl. the PDEP/PEXT-free contract, Kokkos-OpenMP 2/2, Kokkos-CUDA 2/2, pytest 9/9, 0 skips. AVX-512 NOT re-validated (no AVX-512F on this host, no Intel SDE) |
| pnm | **PASS** | 9/9 host and CUDA, 0 skips; np = 1/2/4 bit-exactness genuinely ASSERTED against a single-rank oracle, not assumed; 7199 pores / 7499 labels / 53020 connections on `packing_ring.vti`, identical on both backends |
| flow | **PASS** at the DOUBLE default | 49/49 single-rank; MPI block re-running after the two gate fixes. 49/49 CUDA single-rank. Regression PASS |
| amr | **PASS**, shippable as 0.1.0 | 100/100 host; CUDA 99/100 + 1 skip |
| coupling | **PASS** | 3/3, 0 skips; docstring audit 12/12 documented |
| dem | running | |
| voro | running | |

**Docstring audit, finally run against a CLEAN family build** (§2.1's blocked item): **955 callables,
15 undocumented, 0 stale** — not the "894 / 36" that §2.1 correctly refused to trust, because every
tree that earlier run imported predated the renames. All nine modules import from build trees in one
interpreter, none from site-packages, verified before the audit ran. The 15 are being written: flow 6
(`has_scene`, `pressure_telescope`, `velocity_multigrid_active`, each on both grids), pnm 1
(`SDFReader`), voro 2 (the two `__init__`s), core 6 (`SceneBuilder` and five of its members).

**amr's one CUDA skip is self-diagnosing and correct.** `python_state_hash` exits 77 because
`peclet.amr.build_toolchain` reports `'GNU14.2.0Releasex86_64Kokkos5.1.1'` on the CUDA build against
the committed reference's spaced `'GNU 14.2.0 Release x86_64 Kokkos 5.1.1'`: the
`target_compile_definitions(amr PRIVATE "PECLET_AMR_BUILD_TOOLCHAIN=\"…\"")` string loses its
embedded spaces when the TU is routed through the Kokkos launch compiler. Same compiler, same
everything — a quoting defect in the *label*, not in the build. The gate did exactly what it is for:
skipped rather than compare across toolchains, and it cannot produce a false pass. **[A]** fix the
quoting after the release.

**Worktrees and unmerged branches — RELEASE.md §1.1, resolved by PARKING, not merging.** flow carries
14 worktrees and the suite has 7 unmerged flow branches (`analysis/high-re-stability`, `vof-issues`,
`vof-v6`, `vof-w0`, `vof-w12`, `vof-w4`, `vof-wor2`), plus `dev/aperture-compat-rhs` and
`drag-study-harness` in core/amr and `feature/flexible-cell-storage` in voro. Every one of the flow
branches is between 72 and 629 commits BEHIND main, and their content has been integrated by other
routes — `vof-issues`, the only one ahead by a substantial 10 commits, carries the free-slip domain
BC, `step_adaptive`, the visible preconditioner-breakdown flag and the contact-angle wall binding,
and **main already has all four** (`kBcTypes` includes `"slip"`, `stepAdaptive` is in
`flow_ibm_vof.hpp`, `pressure_solve_failed` is bound, and `test_wall_slip_mpi.cpp` supersedes the
branch's `test_freeslip_bc_mpi.cpp`). **Decision: all are explicitly PARKED and their work is NOT in
1.0.0.** The worktrees are NOT removed — removal would destroy other sessions' build trees for no
release benefit, and §1.1 is satisfied by explicit parking. Reversible: run the removals later.

**2026-09-12, Phase E — tagging and publishing.** Phase B finished green in all eight packages, so
the release was cut. Order as §0 requires: core and morton first, then the four method packages that
vendor their headers, then coupling, then the umbrella.

| package | tag | PyPI |
|---|---|---|
| peclet-core | `v1.0.0` | 1.0.0 |
| peclet-morton | `v1.0.0` | 1.0.0 |
| peclet-pnm | `v1.0.0` | 1.0.0 (+ `peclet-pnm-cu13` 1.0.0) |
| peclet-dem | `v1.0.0` | publishing |
| peclet-voro | `v1.0.0` | publishing |
| peclet-coupling | `v1.0.0` | 1.0.0 |
| peclet-amr | `v0.1.0` | 0.1.0 |
| peclet-flow | pending its CI | |

**§1.1's sequencing premise is CONFIRMED, not merely assumed.** voro's CI had been red on `main`
since 2026-09-11 because it vendored core at `v0.6.1`, a tag predating the two solver headers it
includes. The moment core `v1.0.0` existed and voro's `PECLET_CORE_TAG` was repinned to it, that CI
went green with no other change. amr was in the same state against six core headers. This is worth
keeping in the durable workflow: **a consumer's pinned-tag CI job cannot be green between the commit
that adopts new core headers and the release that tags them** — it is a scheduled red, not a defect,
and RELEASE.md §1.4's "CI green on every repo" has to be read with that exception.

**The amr PyPI worry was half right and the half that mattered was fixable from a shell.** The
missing piece was not a PyPI pending publisher but the `pypi` DEPLOYMENT ENVIRONMENT in the
`peclet-amr` GitHub repo, which its `release.yml` publish job declares (`environment: pypi`) and
which every other package already had. Created to mirror `peclet-pnm`'s, and the first `v0.1.0`
publish then went through untouched — sdist and publish both green, `peclet-amr` 0.1.0 live. **No
manual PyPI registration was needed.** Record it that way so the next new package in this family
checks the GitHub environment first.

**GitHub Releases created** (the Zenodo webhook mints a version DOI from each): `peclet-core`
`v1.0.0`, `peclet-morton` `v1.0.0`, `peclet-pnm` `v1.0.0`, `peclet-dem` `v1.0.0`,
`peclet-coupling` `v1.0.0`, `peclet-amr` `v0.1.0`. Each carries a package-specific paragraph plus the
shared 1.0.0 note; voro, flow and the umbrella follow once their wheels finish. Check the Zenodo
deposition for each afterwards — a webhook that fires before `CITATION.cff` is in the tag reads no
metadata, which is why `coupling/CITATION.cff` was created before any tagging (coupling `fefc2c4`).

### What remains, as of 2026-09-12 ~01:50Z

Everything below is mechanical and ordered; the working tree is already prepared for it.

1. **Waiting on**: `peclet-voro` and `peclet-flow` CUDA-wheel jobs (`Release` workflow on their
   `v1.0.0` tags). Their sdists and CPU wheels are already green; only `cuda wheels` is outstanding.
   These jobs build Kokkos-CUDA statically with SASS for every supported GPU major, so 40-90 minutes
   is normal. Nothing needs doing until they finish.
2. **When they do**: confirm `peclet-voro`, `peclet-voro-cu13`, `peclet-flow`, `peclet-flow-cu13` all
   read 1.0.0 on the PyPI JSON endpoint (`pip index versions` caches for minutes — use the JSON), then
   `gh release create v1.0.0` for both, with the same per-package paragraph plus shared body used for
   the other six.
3. **Then the umbrella, LAST** — its pins are exact (`==`) and cannot resolve until every member is
   live. **The commit is already staged in the working tree**: `CHANGELOG.md` (the `[Unreleased]`
   heading is now `## [1.0.0] — 2026-09-12` and the Tested table is written), `CITATION.cff`,
   `pyproject.toml`, `packaging/pyproject-cu13.toml`, and all eight submodule pointers, which already
   equal the tagged commits (verified tag-by-tag). Commit those by NAME, push, then tag `v1.0.0` —
   that publishes both the `peclet` and `peclet-cu13` metapackages and triggers `Containers`.
4. **Smoke test** in a fresh venv per RELEASE.md §6: `pip install peclet==1.0.0` then import
   flow/dem/voro/pnm/morton; repeat with `peclet[mpi,cfd-dem]` (the sdist members, core and coupling —
   the core sdist was silently unbuildable 0.1.0 through 0.6.0, so this one matters).
5. **Check a CUDA wheel carries native SASS for every GPU major**, not just PTX:
   `cuobjdump --list-elf <module>.so`. RELEASE.md records that 0.4.0-0.5.0 shipped sm_75 plus PTX only
   and failed on every non-Turing GPU with a 13.0/13.1 driver, because a driver older than the toolkit
   that emitted the PTX cannot JIT it and the launch silently no-ops.
6. **After the release, not blocking**: the Snellius site package (Phase F), the LUMI one (Phase G,
   still untested on AMD hardware), Zenodo deposition checks, and the example gallery re-render
   (Phase I) — `~/Codes/peclet-examples` holds ~30 local commits written against this API and pushes
   nothing until the wheels exist, which they now do.

## 10. RELEASED — peclet 1.0.0, 2026-09-12

All nine repositories are tagged, published and GitHub-released.

| package | tag | PyPI | CUDA twin |
|---|---|---|---|
| peclet-core | `v1.0.0` | 1.0.0 (sdist) | — |
| peclet-morton | `v1.0.0` | 1.0.0 | — |
| peclet-flow | `v1.0.0` | 1.0.0 | `peclet-flow-cu13` 1.0.0 |
| peclet-pnm | `v1.0.0` | 1.0.0 | `peclet-pnm-cu13` 1.0.0 |
| peclet-dem | `v1.0.0` | 1.0.0 | `peclet-dem-cu13` 1.0.0 |
| peclet-voro | `v1.0.0` | 1.0.0 | `peclet-voro-cu13` 1.0.0 |
| peclet-coupling | `v1.0.0` | 1.0.0 (sdist) | — |
| peclet-amr | `v0.1.0` | 0.1.0 (sdist) | — |
| peclet (metapackage) | `v1.0.0` | 1.0.0 | `peclet-cu13` 1.0.0 |

**Post-publish verification, all done:**

- CPU wheels install and run in a clean interpreter, reporting 1.0.0 and the OpenMP backend.
- **The core SOURCE distribution builds and imports** — 5 s in a fresh venv. This is the check
  RELEASE.md flags as having silently failed from 0.1.0 through 0.6.0; it does not recur.
- **flow's CUDA wheel carries native SASS for sm_75, 80, 90, 100 and 120**, confirmed with
  `cuobjdump --list-elf` on the downloaded wheel — not PTX alone, which is what made 0.4.0 and 0.5.0
  abort at import on every non-Turing GPU with a 13.0/13.1 driver.
- `pip install "peclet[mpi,cfd-dem,amr]==1.0.0"` into a fresh venv resolves all nine packages in
  70 s, every module imports in one interpreter, and a five-step flow solve runs.

**One operational lesson worth carrying into RELEASE.md.** The umbrella's `publish` job failed the
first time with `requests.exceptions.ConnectionError: Connection reset by peer` raised inside
`sigstore` while signing the attestation against the Rekor transparency log. Both build jobs had
succeeded and **nothing had been uploaded** — the failure is upstream of the upload. `gh run rerun
<id> --failed` fixed it on the first retry. Treat a publish failure whose traceback ends in
`sigstore/_internal/rekor/client.py` as transient infrastructure, re-run the job, and do NOT start
editing versions or cutting a new tag; `skip-existing: true` makes the retry safe even if part of an
upload had landed.

**Containers: ALL FOUR published**, `Containers` workflow green on the `v1.0.0` tag —
`peclet-cpu`, `peclet-cuda` (`sm80` and `sm90`) and `peclet-hip` (`gfx90a`), each pushed under both
the versioned and the moving tag (log confirms e.g. `peclet-cuda:1.0.0-sm80` then
`peclet-cuda:sm80`, both "Upload complete"). **This is the first tag on which `hip-gfx90a` has
succeeded** — RELEASE.md §0 records it failing on every tag from 0.3.0 through 0.6.0, and §8 that it
has built since 2026-09-04. The image is published; it remains UNTESTED on AMD hardware, which is a
different claim and stays a known limitation.

**Remaining, none of it blocking and all of it after-the-release by design:** the Snellius site
package (RELEASE.md Phase F), the LUMI one (Phase G, still untested on AMD hardware), confirming
each Zenodo deposition minted a version DOI, and re-rendering the example gallery (Phase I) —
`~/Codes/peclet-examples` holds around thirty local commits written against this API and pushes
nothing until the wheels exist, which they now do.

**Deferred with a reason, not forgotten:** the interstitial-vs-superficial drag normalisation is
still the one unresolved entry in DECISIONS.md, so **no permeability number is published in the
1.0.0 notes**; morton's AVX-512 batch kernels were not re-validated for this HEAD and the notes say
so; and amr's CUDA `python_state_hash` skip is a quoting defect in the build-toolchain LABEL that
loses its embedded spaces through the Kokkos launch compiler.

### Post-release: the landing page did not run (found by a user, 2026-09-12)

The very first thing 1.0.0 offered a new reader — the quick start on `README.md`, `docs/index.md`
and the Colab notebook — raised `TypeError` on line 12. The clean break had renamed
`cell_centres()` to `cell_centers()` and repacked `set_body_force(fx, fy, fz)` into one
3-sequence, and no check in this document looks at the suite's own docs: `audit_examples.py` scans
the sibling **gallery** only (`examples/`, `benchmarks/`, `sanity-checks/`), and §5.2's instruction
is to *read* the prose, which catches a stale version number but not a deleted method.

Fixed on those four pages (`docs/CONVENTIONS.md` carried the old spelling too), verified by running
all three pages against `pip install peclet-flow` == 1.0.0 in a fresh venv: `k = 1.23512e-01` at
N = 48, matching the notebook's committed output and its refinement table, so the stored outputs
did not need regenerating.

**The gate is now CI, not a checklist line.** `.github/workflows/quickstart.yml` runs
`tools/release/check_docs_snippets.py --installed --run` on a docs push or PR, weekly, and as a
`needs: publish` job of `release.yml` on **every tag** — against the wheels that tag just put on
PyPI, retrying while the index propagates (RELEASE.md §5.2, §11). A release is not done until that
job is green. Two lessons in the shape of the tool's two passes:

1. **Nothing was executing the docs.** A page reachable from the front door is a test, and it
   should be run in a venv holding the *published* wheels — the same thing the Colab badge does.
2. **A static name audit cannot see a signature change.** `cell_centres` → `cell_centers` is a
   NAMES failure; `set_body_force(fx, fy, fz)` → `set_body_force(force)` renamed nothing and is
   invisible to every audit in `tools/release/` — only running it finds that class. Any future
   clean break should assume there are more of these than renames.

Two coverage holes in `audit_examples.py` surfaced while fixing this and are closed in the same
commit: `amr`'s bindings moved out of `core` in G.2 and were never re-registered (so every
`peclet.amr` call in the gallery read as an unknown name), and voro's `packaging/voro_scenes.py` /
`voro_pore_mesh.py` were missing (`scenes.sphere_union_scene` read as retired). Both were silent
because `surface()` swallowed a missing path; it now warns.

### Post-release: the film, and the channel goes public (2026-09-12)

The 1.0.0 release film is live — **<https://www.youtube.com/watch?v=L_uAHnL6Gq8>**, 7:30, public,
and the channel trailer — and every clip on **[@PecletHPC](https://www.youtube.com/@PecletHPC)** is
now public (trickle flow was the one held back for review). The workflow is written up as
RELEASE.md §10.1; what this run learned:

1. **The film was cut on two clocks and nobody would have noticed for six minutes.**
   `assemble.py` gives each beat its narration *plus* a 0.55 s pause, but `narration_full.wav` had
   been concatenated by hand from the beat wavs with no pauses at all. The picture therefore lagged
   the voice by 0.55 s per beat — 13.2 s by beat 25 — and `-shortest` cut the tail: the last frame
   of the published-to-be film was the packed-bed *g(r)* figure while the narrator said "Peclet,
   version one point zero". Fixed by building the track from `narration.json` and `voice.yaml`'s
   `pause.beat` inside `assemble.py`, so one constant governs both tracks (the caption clock was
   counting `beat - sentence`, drifting 0.28 s a beat the other way, and now agrees too). The film
   was re-muxed from the unchanged picture: 7:17 → 7:30, closing card restored.
   *A narrated film needs watching to the end before it is published; a duration that looks
   plausible is not evidence.*
2. **The four remaining pages with a local mp4 now embed the YouTube copy** (peclet-examples
   `56d7ed2`), which took the last 11 MB of video out of that repository. Their Quarto freezes were
   deliberately **not** re-stamped: 45 of the 48 frozen pages are already stale from the 1.0.0
   migration and are waiting on the §10 re-render, and marking three of them fresh would have
   published pre-1.0.0 output as current. That also leaves the committed `.ipynb` copies for the
   same pass (`quarto convert` regenerates them).
3. **Interlinking, both directions.** Every video description carries its page, the repository and
   the documentation — `site.docs` in `videos.yaml` had been pointing at the PyPI project page, not
   the docs site. The docs home page, the gallery landing page and the README carry the film; the
   gallery navbar and the docs footer carry the channel.
4. **Captions are not uploaded.** `captions.insert` needs the `youtube.force-ssl` scope, which the
   stored token does not hold, and widening it means another browser consent round; YouTube's
   automatic captions cover the narration in the meantime. `films/release-1.0.0/build/captions.srt`
   is correct on the film's clock if that is ever revisited.


---

## 11. NEXT CYCLE — 1.0.1, the container thread-pool patch (opened 2026-09-13)

**Why a release at all.** The fix lives inside the compiled modules, so no user gets it from a docs
change: `peclet::core::python::install()` now sizes the host pool by the process's real CPU budget
(`core/include/peclet/core/common/cpu_budget.hpp`, SCALING_ISSUES issue 7). Without it, a Colab or
Binder user's FIRST run collapses by ≥35x, silently. That is a patch-worthy regression in practice
even though no code was wrong at 1.0.0.

**Scope: patch only.** No API change, no numerics change. On an unconstrained machine the new code
requests nothing and the build is inert — that is the property to state in the notes, and the one
`core`'s `test_cpu_budget` pins.

**Order** (RELEASE.md §6: core first, umbrella last):

1. `core` → **v1.0.1**. Merge branch `cpu-budget` (worktree `suite/core-cpu-budget`), gate on the
   full ctest battery, tag, publish.
2. Repin `PECLET_CORE_TAG "v1.0.0"` → `"v1.0.1"` in `cmake/PecletDeps.cmake` of **flow, dem, voro,
   pnm, coupling, amr** (`morton` does not use core), rebuild, gate, tag:
   flow/pnm/dem/voro/coupling → **1.0.1**, amr → **0.1.1** (D9, stays 0.x).
3. CUDA twins with them: `peclet-flow-cu13`, `peclet-pnm-cu13`, `peclet-dem-cu13`,
   `peclet-voro-cu13` → 1.0.1 (four literals, §5.3).
4. Umbrella `peclet` and `peclet-cu13` → **1.0.1**, pins bumped, pushed LAST.

**Gates.** Each repo's own ctest battery, plus:

- `core`: `test_cpu_budget` (fixture cgroup trees) — and the real-cgroup probe, which is the check
  that actually matters and is not automatable in CI:
  `systemd-run --user --scope -p CPUQuota=200% <probe>` must report `usable=2` with 48 CPUs visible,
  `0` threads requested when unconstrained, and `0` when `OMP_NUM_THREADS` is set.
- **End-to-end, on a rebuilt flow wheel:** the quick start under a 2-CPU quota with all CPUs visible
  must finish in **~2.5 s** — the retuned N = 32 page (§11.1); the N = 48 page it replaces was ~26 s.
  At 1.0.0, with the pool unbounded, *neither* finishes in 15 minutes (both measured). This is the
  number the release exists for; do not tag without it.
- `tools/release/check_docs_snippets.py --installed --run` against the published 1.0.1 wheels — the
  `quickstart.yml` job does this automatically as a `needs: publish` job of the tag.

### 11.1 What the first outside reports turned up (2026-09-13)

A Windows laptop and a Colab runtime, both on the published 1.0.0 wheels. Two separate problems,
one release.

**Windows: `pip install peclet` ends inside CMake.** There is no Windows wheel and no macOS wheel;
pip answers a missing wheel by falling back to the *sdist*, and the source build then dies with
"No CMAKE_CXX_COMPILER could be found" — a message about a compiler, when the answer is "not this
operating system". Nothing on the PyPI page, in `README.md` or in `DEPLOYMENT.md` had said Linux.
Fixed: a pre-`project()` guard in flow, dem, pnm, voro, core, amr and coupling (commit *say "Linux
only" before CMake says "no compiler"*) naming WSL2, a Linux container and Colab, with
`-DPECLET_ALLOW_UNSUPPORTED_PLATFORM=ON` as the escape hatch; `Operating System :: POSIX :: Linux`
in every package's classifiers (umbrella metapackages included); an "Operating system: Linux
x86-64" section in `docs/DEPLOYMENT.md` and a paragraph in `README.md` / `docs/index.md`. **The
guard ships inside the sdists, so it reaches a Windows user only at 1.0.1** — the docs reach them
today.

**Colab: the quick start took ~5 minutes, not the promised half-minute.** Not the thread-pool trap
of issue 7: the bootstrap cell bounded the pool correctly (it printed `OMP_NUM_THREADS = 2`) and
the run returned the same 42 steps and the same k as CI. The promise was simply written against
the wrong machine — the N = 48 solve is 25.6 s on two Threadripper 5965WX cores and ~35 s on a
two-core GitHub runner, and a free Colab runtime's two shared vCPUs are several times slower again.
So the quick start was retuned (docs-only, live now):

| | 1.0.0 | now |
|---|---|---|
| resolution | N = 48 | **N = 32** |
| stop rule | increment < 1e-5, single step | **three-step window < 1e-3** |
| steps to steady | 42 | **14** |
| solve, two cores | 25.6 s | **2.5 s** |
| permeability k | 1.23512e-01 | **1.2407e-01** |

Both k values sit within 0.2 % of what their own grid gives when iterated to convergence (N = 32 →
0.123885, N = 48 → 0.123495 at 200 steps), so the cheap run is not the less honest one; `N` is
still the knob, and the page now says what the finer grids cost. The single-step increment test was
the worse half of the old bill: at N = 32 it fires at 13 steps for tol 1e-4 **and** for 3e-5, and
only at 43 for 1e-5, because the increment dips through the tolerance on the way down. The
three-step window does not have that failure mode at any N tested.

Two measurements from the diagnosis, worth keeping:

- **Mild oversubscription is cheap.** 2 OpenMP threads on 1 CPU (affinity) cost 12 % against 1
  thread on 1 CPU; 4 threads on 2 CPUs cost 35 %. The >=35x collapse of issue 7 needs a *large*
  ratio (48 visible, 2 granted) — a slightly-too-big pool is not a cliff.
- **Per-cell step cost is flat to N = 48 and doubles at N = 64**: 5.6 / 5.6 / 5.5 / 10.4 µs per cell
  per step at N = 24 / 32 / 48 / 64 on two cores, while the steps to steady go 13 / 14 / 31 / 51.
  N = 64 therefore costs ~80x N = 32, not the 8x the cell count suggests. Unexplained — a candidate
  for `SCALING_ISSUES.md` if it reproduces at scale or on a GPU.

### 11.2 Wheels for four platforms (probe, 2026-09-13)

The Windows report above asked a question nobody had asked: *does the family build anywhere but
Linux x86-64?* A throwaway `wheel-probe.yml` (umbrella, `workflow_dispatch`) answered it in five
rounds — cibuildwheel for one interpreter per package per runner, `fail-fast: false`.

**Result: everything builds.** Nothing in peclet's C++ was the obstacle, and nothing numerical
changed. Kokkos 5.1.1 configures under MSVC 19.51 with `/std:c++20` and under AppleClang 21 with
`-std=gnu++20`. Five build-system assumptions failed, each inert on Linux, each now fixed:

| | what failed | fix |
|---|---|---|
| MSVC | `C1128: number of sections exceeded object file format limit` in the templated Kokkos TUs | `/bigobj` |
| MSVC | `LNK2038: RuntimeLibrary MDd_DynamicDebug doesn't match MD_DynamicRelease` | a multi-config generator ignores `CMAKE_BUILD_TYPE`; the nested install needed `--config Release` |
| MSVC | `D8021: invalid numeric argument '/Wextra'`, including inside nanobind-static | voro handed GNU warning flags to every target |
| MSVC | `C2065: 'M_PI': undeclared identifier` ×8 | `M_PI` is POSIX, not C++; replaced by the same double (memcmp-identical to glibc's) |
| MSVC, AppleClang | `Could NOT find OpenMP_CXX` — version 2.0, and absent, respectively | vendor Kokkos with OpenMP where `find_package(OpenMP 3.0)` succeeds, Serial where it does not |

**The OpenMP finding is the one that shaped the outcome.** MSVC defines `_OPENMP` as 200203 whatever
runtime is selected — `/openmp:llvm` reaches the LLVM runtime and CMake still reads 2.0, measured —
and Kokkos requires 3.0. AppleClang ships no OpenMP at all, and Homebrew's libomp is a dead end for
wheels: it now publishes only a Tahoe bottle, so delocate refuses anything with a floor below macOS
26. So:

**DECISION — Windows and macOS wheels ship the Kokkos Serial backend; Linux keeps OpenMP.**
Rejected: vendoring a libomp built from LLVM source in every macOS wheel job (a floor of macOS 11 for
free is worth more than threads on a laptop, and `coupling` importing flow+dem would then load two
libomp copies); and arguing MSVC's `_OPENMP` down by pre-setting `OpenMP_CXX_SPEC_DATE`, which fakes
a capability check. `execution_space` reports the backend, and the quick start prints it, so nobody
is misled. Reversible in one line of each `cmake/PecletDeps.cmake`; a toolchain that grows a usable
OpenMP is picked up with no change at all.

**The shipping matrix** (each cell green on the probe, in the release configuration):

| | x86-64 | aarch64 | backend |
|---|---|---|---|
| Linux | ✅ | ✅ | OpenMP |
| Windows | ✅ | — (no runner) | Serial |
| macOS | — (no Intel runner) | ✅ | Serial |

CPython **3.10–3.14** (morton from 3.9). **cp314 was missing everywhere** and is the same trap from a
different direction: a user on a current Python fell through to a source build even on Linux. Verified
green for all five packages.

**Not shipped, and why:** macOS x86-64 — GitHub has retired the Intel runners (a `macos-13` job now
queues forever), so it could only be cross-compiled and never tested; Intel Macs build from the sdist,
which the probe showed works. musllinux — never tried. win_arm64 — no runner, nobody asking.

**Full-matrix validation** (run 34771289649, `peclet-flow`, every interpreter on every runner): 20
wheels, all green, and each one reports the backend this section claims —

| runner | wheels | `peclet.flow.execution_space` |
|---|---|---|
| ubuntu-latest | cp310–cp314 `manylinux_2_28_x86_64` | `OpenMP` |
| ubuntu-24.04-arm | cp310–cp314 `manylinux_2_28_aarch64` | `OpenMP` |
| windows-latest | cp310–cp314 `win_amd64` | `Serial` |
| macos-latest | cp310–cp314 `macosx_11_0_arm64` | `Serial` |

Free-threaded CPython built and passed too (`cp314t` on all four) because the probe's selector was
`cp3*`; the release selector is `cp314-*`, which excludes it. nanobind needs an explicit
`mod_gil_not_used()` before that is worth shipping — a separate decision, not this cycle's.

**Still unexercised: the release workflow itself.** The matrix above was measured through
`wheel-probe.yml`, which runs the same cibuildwheel against the same pyproject but not the sdist,
artifact-collection or publish jobs around it. Dispatch one `release.yml` manually before tagging —
`workflow_dispatch` builds everything and the publish job is gated on a tag push, so nothing reaches
PyPI.

**Delete `wheel-probe.yml`** once a real release has gone out on this matrix; it exists only to
answer a question that is now answered.

### 11.3 Threads, not Serial, where there is no OpenMP (2026-09-13)

§11.2 shipped Serial to Windows and macOS because neither toolchain supplies an OpenMP that Kokkos
accepts. That was the wrong stopping point: **Kokkos' C++ `std::thread` backend needs no OpenMP
runtime at all**, and the suite is indifferent to which host backend it gets — exactly one line in
eight repositories names `Kokkos::OpenMP`, and it is `#ifdef`-guarded (`core/.../grid_halo.hpp`, an
MPI-only early-out, which now names `Kokkos::Threads` as well).

Measured, quick start at N = 32 on the wheel each runner built (runs 34784791863 / 34784795953).
**Every run returned 14 steps and k = 1.2407e-01** — the backend changes nothing numerical:

| platform | vCPU | backend | 1 thread | 2 threads | all threads |
|---|---|---|---|---|---|
| Linux | 4 | OpenMP | 5.73 s | **2.99 s** | 3.04 s |
| Windows | 4 | **Threads** | 6.74 s | **3.87 s** | 6.79 s |
| Windows | 4 | Serial | 6.37 s | 6.37 s | 6.34 s |
| macOS | 3 | **Threads** | 3.85 s | **3.00 s** | 3.91 s |
| macOS | 3 | Serial | 5.12 s | 4.99 s | 5.72 s |

**DECISION — Windows and macOS wheels ship `Kokkos::Threads`.** Supersedes the Serial decision in
§11.2, which stood for about four hours. What changed: Serial was chosen against *OpenMP* and its
vendored-libomp costs, and the third option was not on the table. Threads is **1.65x faster than
Serial** on both platforms at the same numbers (3.87 vs 6.37 on Windows, 3.00 vs 4.99 on macOS),
needs no bundled runtime, asserts no version the build cannot check, and keeps the macOS wheel floor
at 11. Rejected, unchanged: clang-cl (real OpenMP 5.0, but swaps the compiler and bundles
`libomp.dll`) and pre-setting `OpenMP_CXX_SPEC_DATE` to walk MSVC's `_OPENMP = 200203` past Kokkos'
3.0 gate (asserting a version nothing verifies).

**The "all threads" column above is mislabelled, and the reason matters.** Those runs left the thread
count *unset*, and on both platforms they came back at exactly the one-thread time (6.79 vs 6.74 s;
3.91 vs 3.85 s). That is not a spin-wait collapse — it is the default. `Kokkos::Threads` asks hwloc
for the topology and **falls back to one thread when hwloc is absent**
(`Kokkos_Threads_Instance.cpp:487`), and hwloc is absent in every peclet wheel. On 48 real cores, the
same wheel:

| threads | 1 | 2 | 4 | 8 | 16 | 24 | 48 | *unset* |
|---|---|---|---|---|---|---|---|---|
| best of 3 | 4.420 s | 2.314 | 1.240 | 0.905 | 0.741 | **0.644** | 1.023 | **4.428** |

So the backend scales perfectly well — **6.9x on 24 cores for a 32³ problem** — and ships at 1/7th of
it unless something supplies a count. OpenMP never had this problem: its default is the whole
machine.

**Ordering, and what it means for the wheels.** The thread-count fix lives in `peclet-core`, which
the wheel builds pull by *tag* (`PECLET_CORE_TAG`, FetchContent). So it reaches a Windows or macOS
wheel only after step 1 of this cycle — core tagged v1.0.1 — and step 2, the repin. Until then a
Threads wheel built from `main` is single-threaded. Verified locally instead, end to end on a real
Threads wheel built against the branch: the quick start's default goes **4.428 s → 0.899 s** (4.9x,
k unchanged at 1.24075e-01), `OMP_NUM_THREADS=4` gives 1.209 s and `KOKKOS_NUM_THREADS=8` gives
0.890 s — both honoured, as before.

**Consequence, fixed in core `36966ad`:** `defaultHostThreads()` now asks whether the backend sizes
*itself*. OpenMP does (its runtime reads `OMP_NUM_THREADS`, its default is the machine), so its
behaviour is unchanged in every case, including the inertness on an unconstrained workstation that
the whole file exists to preserve. Threads and Serial do neither, so they are handed the budget
outright. Without that, every Windows and macOS wheel would have shipped single-threaded and said
nothing about it — the same shape of bug as SCALING_ISSUES issue 7, and this cycle exists for that
one.

### 11.4 `vof_bc_mpi_np2` and `vof_collocated_mpi` — RESOLVED 2026-09-14 (gates, not code)

> **Release gate, on the tagged commit (flow v1.0.1): 155/155 at `OMP_NUM_THREADS=8` AND at
> `OMP_NUM_THREADS=2`.** The second number is the one that matters — 2 is the thread count at which
> `vof_collocated_mpi_np{2,4}` used to fail while passing at 1, 4 and 8. The re-specified gates are
> not merely green at the documented count, they are green at the count that caught the old ones.

Both gates were asking for something the discretization does not provide, and both have been
replaced. flow's local battery is **155/155** at `OMP_NUM_THREADS=8` and at `OMP_NUM_THREADS=2`.
The reasoning is in [decisions/flow.md](decisions/flow.md) ("The np>1 VoF colour parity gates gate
conservation, not the pointwise field"); the work order that produced it is
[wo_vof_mpi_parity_gates.md](wo_vof_mpi_parity_gates.md). In short:

**`vof_bc_mpi`.** The packing case's 3.174e-09 is not a decomposition defect and not a tolerance
leak. It is **one ulp** of colour, amplified by `mycNormal`'s estimator selection — a strict
comparison, `if (fabs(mm[cn][cn]) > t0) cn = 3;`, between the centred and the Youngs candidate,
which at a near-axis-aligned interface is an exact tie. Traced on the failing face: the two runs'
3x3x3 stencils agree to 1.4e-17, the centred candidate scores 0.99986893026188128 against Youngs'
0.99986893026188106 at np=2 (Youngs wins by one ulp) and 0.99986893026188106 against
0.99986893026188106 single-rank (equal, so the centred one wins); the winners differ by 2.9e-06 in
their transverse components and the face's slab volume by 4.795e-09, which lands as +/-4.795e-09 in
two adjacent cells, equal and opposite. Over 24 (ranks, threads) pairs the outcome is binary: np=1
bitwise at every thread count, np=2 flips at 2..16 threads and not at 1, np=4 flips at 2, 3, 4, 6
and 12 but not at 1, 8 and 16 — which is the whole reason np4 passed here and CI saw nothing.

The pressure-rtol hypothesis recorded in this section is **falsified**: under `step()` the velocity
and pressure fields agree between decompositions to 1.4e-14 and 1.4e-13 (on |p| = 1.9e+02), ten
thousand times tighter than the gate, and the colour difference is not proportional to any
tolerance.

The gates now are: pointwise colour at 1e-6 (a bound on the field going *wrong*, verified by
injection — deleting the WO-F owner rule gives 1.000e+00 against it); a new **signed-sum** gate at
1e-11 relative, which is the reduction-floor gate on the quantity that actually has one (a
difference that cancels is colour moved, one that does not is colour created); and a new
**`packing-kin`** case that drives the same composed cut-cell x open-boundary scene with a
prescribed 3-D velocity and is gated **bitwise** — measured 0.000e+00 at np=2 and 4 and at 1..16
threads, which is the exactness the 1e-11 was reaching for and never had.

**`vof_collocated_mpi`.** `hydro-z` is a rest state: converged |uf| = 1.9e-13 on |P| = 1.2e+03, so
the pressure solve's r0 is the round-off of the hydrostatic balance, not a physical residual, and
differs between decompositions by an O(1) *relative* amount. The V-cycle count is a random walk, not
a shifted copy — over 20 steps at np=2 the sequences part at ten steps, by one at nine and by two at
step 11 (10 vs 12), and whether the worst gap is one or two depends on the OpenMP thread count alone
(one at 1, 4, 8; two at 2). `d(iters) <= 1` (flow `65b2b6a`'s shape) was a coin toss here. The gate
is now the **cost envelope** — worst step within one V-cycle of the reference's worst, total within
one V-cycle per step — with np=1 keeping its exact zero.

No numerics changed: the diff is `tests/kokkos_mpi/` only.

### 11.5 voro's CUDA job, and the rehearsal nobody knew they had (2026-09-14)

`peclet-voro 1.0.1` is **tagged but unpublished**: every CPU wheel job and the sdist went green, then
`cuda-wheel` was killed at **6 h 0 m 3 s** — GitHub's hard per-job cap — and `publish`, which needs
it, was skipped. PyPI still serves voro 1.0.0, so the `peclet` metapackage (which pins
`peclet-voro==1.0.1`) cannot go out either.

**Nothing in 1.0.1 caused it.** At 1.0.0 the same job took **4 h 59 m**: it has been running at 83 %
of the cap all along and this run drew a slower machine.

**Where the five hours go** (step timings, 1.0.0 run): CUDA toolkit install 44 s, Kokkos-CUDA prefix
**2 m 20 s**, then `for PY in cp310..cp313` — four *serial* `pip wheel` calls at **~73 min each**.
No tests run in that job at all; it is pure compilation. And each 73 minutes is **one translation
unit**: voro is header-only, so `nanobind_add_module(voro NB_STATIC NOMINSIZE src/voro_bindings.cpp)`
pulls ~12,250 lines of templated device code through nvcc, for **five GPU architectures** (sm_75
base + 80/90/100/120 via `NVCC_APPEND_FLAGS`).

The five architectures are **not** the thing to cut — they are the fix for a real field failure
(0.4.0–0.5.0 shipped sm_75 + PTX only and Kokkos aborted at import on every non-Turing GPU with a
13.0/13.1 driver; RELEASE.md §6). What is wasteful is the *structure*: the device half of that TU
does not depend on the Python ABI, yet it is recompiled once per CPython, serially. flow, whose
module is split across TUs, does all four wheels in **54 min** — 5.4x faster per wheel.

| repo | cuda-wheel duration |
|---|---|
| pnm | 9 min |
| dem | 25 min |
| flow | 54 min |
| **voro** | **6 h (killed)** |

**The fix, and the reason it need not be a gamble.** Matrix the `for PY` loop over CPython: Kokkos
costs 2 minutes, so four parallel jobs are ~80 min each — 4.5x margin instead of none, with no build
flag and no wheel content changed. And it can be **verified before any tag moves**, because
`cuda-wheel` carries no `if:` in any of the four repos (RELEASE.md §11, corrected): a plain
`gh workflow run release.yml` builds the CUDA wheel, uploads it as an artifact and publishes nothing.
That rehearsal existed all along and the guide said it did not.

**Open, for the user:** (a) fix, rehearse by dispatch, then re-point `v1.0.1` — never published, so
the tag has no consumers; (b) same, shipped as 1.0.2, no ref rewrite; (c) re-run unchanged. The
serial loop is in **all four** wheel-building members, so this is a family-wide fragility that voro
merely reached first.

**Also in this cycle, if cheap:** `peclet-core` and `peclet-amr` publish an **sdist only**. That is
why `pip install peclet-core` starts a Kokkos source build, and why the quick-start CI job had to
stop installing them (it hung for 20 minutes on the first attempt). Either ship wheels or say so in
their PyPI descriptions; the `BUILD_GATED` list in `check_docs_snippets.py` widens on its own once
they do.

### 11.6 The same fix in the other three, and the cp314 hole it exposed (2026-09-15)

§11.5 ended by saying the serial `for PY` loop was in **all four** wheel-building members and voro
had merely reached the cap first. It is now matrixed in all four, together with `timeout-minutes`
on every job, so no release.yml in the family can meet the 6-hour cap as a silent kill again.

Measured, from each package's own `v1.0.1` release run:

| repo | v1.0.1 run | fixed setup (container + CUDA + Kokkos[+ArborX]) | 4 wheels, serial | per wheel | 5 wheels serial → predicted | **measured, fanned out** | timeout |
|---|---|---|---|---|---|---|---|
| pnm | 34788223729 | 4 m 04 s | 4 m 54 s | ~1 m 14 s | ~10 min → ~5 min | **4–5 min** | 60 |
| dem | 34788226605 | 4 m 11 s | 20 m 31 s | ~5 m 08 s | ~30 min → ~9 min | **8–10 min** | 60 |
| flow | 34863077902 | 3 m 35 s | 40 m 58 s | ~10 m 15 s | ~55 min → ~14 min | **12–18 min** | 90 |
| voro | 34876338696 | ~3 min | (matrixed 09-14) | 72–93 min | ~5 h → ~95 min | **92–98 min** | 180 |

**Rehearsed by dispatch before anything was tagged**, which is the property §11.5 established and
RELEASE.md §11 had wrongly denied: `cuda-wheel` carries no `if:`, only `publish` does, so
`gh workflow run release.yml` builds everything and publishes nothing. Runs 34976227196 (pnm),
34976230935 (dem), 34976234668 (flow), 34976238591 (voro), 2026-09-15: **every job green in all four,
`publish` skipped in all four, PyPI untouched.** Each produced five separate `wheels-cuda-cp3XX-cp3XX`
artifacts — the per-interpreter artifact name is what keeps the five jobs from overwriting each other
— and the cp314 CUDA wheel, which had never been built before, built everywhere. flow's CUDA stage
went 41 min → 18 min wall *while gaining a fifth interpreter*; voro's ~5 h → 98 min.

The timeouts are budgets with 5–12x margin except voro's, which is 1.8x on a 98-minute worst job.
That is deliberate: the 1.0.1 kill came from a machine ~1.2x slower than the 1.0.0 one, and 180 holds
that same slowdown at 118 min. Revisit if a voro job is ever seen past ~2 h.

None of the other three was near the cap, and for **pnm the fan-out is a wash on wall clock** — the
setup dominates a 1-minute wheel, so five jobs spend ~2.7x the machine minutes to save ~5 minutes.
It is done anyway: these four files diverging is not a neutral state, and the next item is what that
costs.

**The cp314 hole (found by the user, 2026-09-15).** `[tool.cibuildwheel] build` gained `cp314-*` on
2026-09-13 (§11.2) and the `cuda-wheel` interpreter list did not — in **all four** repos. So
`peclet-{flow,pnm,dem,voro} 1.0.1` each ship a CPU wheel for Python 3.14 and their `-cu13` twins stop
at cp313, confirmed against PyPI: CPU `['cp310','cp311','cp312','cp313','cp314','sdist']` against
cu13 `['cp310','cp311','cp312','cp313']`. A 3.14 user doing `pip install peclet-cu13` gets a source
build that cannot succeed (no CUDA toolkit on the host by design). Both lists now read cp310–cp314,
and the comment above each matrix says they are one decision. `/opt/python/cp314-cp314` is present in
the `quay.io/pypa/manylinux_2_28_x86_64` image the CUDA job runs in — checked, not assumed.

`docs/RELEASE.md` §0 said "cp310–cp313" and that three of the four cu13 packages "do not exist yet";
both were stale and are corrected.

### 1.1.0: the film re-cut, and what a viewer's eye found that no gate did (2026-09-18)

The 1.1.0 release film is **<https://www.youtube.com/watch?v=7D5Em5zvZRI>** (7:52, public, the
channel trailer); the 1.0.0 cut is **private** on the channel, kept rather than deleted so a later
`ytpub sync` keeps pushing `private` instead of leaving it public. Two things were wrong with the
1.0.0 film and neither had a gate:

1. **The picture.** A viewer reported it as blurred at the start with static graphs shimmering left
   to right. `films/QUALITY.md` is the design note that came out of measuring it, and the ranking
   was not what the pipeline's parameters suggested. The shimmer was `zoompan`, entirely: it
   truncates its crop origin *and* its crop size to whole input pixels, so a 0.02 %-per-frame
   push-in advances in whole-pixel jumps. Fitted to the zoom model, translation noise went
   **0.69 px std / 2.21 px max → 0.0008 / 0.0055** by replacing it with `perspective` and per-frame
   corner expressions. The blur was three separate things — the figures' source DPI (the gallery
   pages set `figure.dpi: 130` in their own `rcParams`, so a plot is 627–751 px and gets enlarged
   1.5–2.7×), YouTube's 1080p AVC rendition of a slow zoom over text, and an opening that was the
   *YouTube channel banner* run through the figure branch. The film now masters at **3840×2160**,
   draws its opening natively, fits pictures into the box the strips leave free (the old rule put a
   4:3 figure's title under the caption strip), and encodes each item **once**. Generation loss,
   the thing that looked most suspect, measured ≤ 0.4 % and was not a cause.
   *The colour was also wrong and nobody had looked*: the composite went to `yuv420p` through
   swscale's BT.601 default, untagged, so every BT.709 player showed the channel teal as
   **(0,132,136)** instead of (13,148,136). The 1.1.0 master reads back (12,147,134).
2. **The numbers.** The 1.0.0 film's headline — "7.7 Gcell/s at 90 % weak efficiency on 32 H100" —
   is the *head-to-head* study on a geometry-free box with pressure iterations pinned at 4.0. True,
   still published, and not what a release film should lead with. Beat 18 is now
   `benchmarks/release-1.1.0-scaling`, measured at the tag on the case the solver is for: **1.81
   billion cells on 32 H100 at 64 % weak efficiency**, with ⟨u⟩ identical to **8e-11** across 34
   runs, 1 → 1536 ranks, both backends. Beat 20 carries 1.1.0's momentum-solve doubling and the
   16-GPU rung the record reports as reproducible and undiagnosed; the old "MG depth cap costs a
   third at 1536 ranks" line was **dropped because it had stopped being true** — SCALING_ISSUES #2
   was fixed by telescoping on 2026-09-02.

Gates now run on every cut (`tools/quality_check.py film`): the frame ledger against the narration
clock, BT.709 tagging, one lossy encode per item asserted from the command log, and the zoom fit.
The 1.1.0 master passes all four. **Open, and recommended in `films/QUALITY.md` §4.3:**
`fig-format: retina` in the gallery, which is the only remaining fix for figure sharpness and needs
Quarto — not installed on this host, so it belongs to whoever re-executes the pages next.


### The README on PyPI is a snapshot, not a mirror (2026-09-19)

`pypi.org/project/peclet/` showed the 1.0.0 film two days after the 1.1.0 film replaced it, and
nothing in the repositories could change that: a distribution carries a **frozen copy** of the
README, the 1.1.0 sdist was uploaded 2026-09-16 19:36 UTC, and PyPI forbids re-uploading a
version. Anything on a PyPI page — README prose, keywords, classifiers, project URLs — lands only
with the **next** upload.

Two consequences worth planning around:

1. **A superseded film is retired to `unlisted`, never `private`** (RELEASE.md §10.1). Private
   broke the 1.1.0 page: 404 thumbnail, sign-in wall.
2. **The metadata improvements of 2026-09-19 are not on PyPI yet** — keywords (there were none),
   classifiers (6 → 14/15), and the Examples/Issues/Changelog URLs are all in the repositories and
   will appear at the next upload. For the *metapackage* that upload is cheap: `peclet` is
   dependency-only, so a patch release is one sdist and one pure-Python wheel with no compilation
   and no per-interpreter matrix. Worth doing on its own if the front page matters before the next
   feature release; the component packages can wait for theirs.
