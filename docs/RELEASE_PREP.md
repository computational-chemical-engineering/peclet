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

### 1.2 SCALING_ISSUES #1 — float operator storage, in the default build [D]

Not fixed. `PECLET_FLOW_OPERATOR_DOUBLE` is an opt-in compile flag, default **OFF**
(`flow/CMakeLists.txt:52`); the production double-diagonal storage was deliberately not shipped
(`flow/doc/history/vof_workorders_v34.md:636`). Live corroboration from `QUALITY_PLAN.md:371-372`,
written 2026-09-11: the porous path's default MG-PCG reports a **non-finite preconditioner on 2 of 5
steps, deterministically**.

A clean-break 1.0.0 should not ship a silent correctness defect in its default configuration. The
maintainer decides which: ship the double-diagonal; flip the default to double storage and accept the
cost; or document it as a stated limitation with a loud runtime warning. **Not a decision to defer
past the tag** — whichever is chosen changes either the numerics, the perf baseline, or the docs.

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

1. **[B]** SCALING_ISSUES #1 — §1.2 above.
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

1. **SCALING_ISSUES #1** — ship the double-diagonal, flip the default, or document the limitation
   loudly (§1.2). Blocks the tag.
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
