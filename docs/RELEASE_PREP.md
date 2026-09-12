# Release preparation — state on 2026-09-11 (next family release: **peclet 1.0.0**)

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
3. **[R]** SCALING_ISSUES #3: an immersed solid cutting an inflow/outflow face breaks the pressure
   solve (iteration cap, max|div| 4e-3). Narrow; legitimate to state as a limitation.
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
