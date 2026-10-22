# Release preparation — family 1.5.0 (cycle opened 2026-10-22; not published)

The one-off companion of [RELEASE.md](RELEASE.md) (the durable workflow): the state of the release
currently being prepared. **Current state:** prepared up to, not including, any outward step (no
merge to `main`, push, tag, publish, GitHub release or workflow dispatch). Every change sits on a
local branch `release-prep` in a sibling worktree. **The flow tag waits for branch `partition2`**
(the 12×2 serial-shell cutoff, WO-A/WO-D): when it lands, rebase `flow-release`, re-run the flow and
coupling rows of §13.4 on both backends, then publish on the user's go (§13.6).

**Earlier cycles, archived verbatim:**

- [archive/RELEASE_PREP_1.4.0.md](archive/RELEASE_PREP_1.4.0.md) — 1.4.0 (published 2026-10-04) and
  the carry-over list of 2026-10-08. Citations "RELEASE_PREP §12.x" refer to it.
- [archive/RELEASE_PREP_1.0-1.1.md](archive/RELEASE_PREP_1.0-1.1.md) — 1.0.0, 1.0.1, 1.1.0
  ("RELEASE_PREP §N", N ≤ 11). Its open lists were not re-verified when archived.
- [archive/RELEASE_PREP_0.7.x.md](archive/RELEASE_PREP_0.7.x.md) — 0.7.0/0.7.1/0.7.2.
- The 1.2.x and 1.3.0 umbrella releases have no RELEASE_PREP record; see the CHANGELOG.

Sections are numbered on from the archived cycle, so "§12.x" stays unambiguous.

## 13. CYCLE — family 1.5.0 (opened 2026-10-22)

### 13.1 Versions (RELEASE.md §4.1)

| Package | Old → new | Why |
|---|---|---|
| peclet-halo / peclet-core | **1.7.0** (released 2026-10-22, with 1.5.0 on 10-09 and 1.6.0 on 10-19) | not re-released; flow and coupling pin `v1.7.0`; `[mpi]` → peclet-core 1.7.0 |
| peclet-flow (+ `-cu13`) | 1.3.0 → **1.4.0** | minor: 20 bound names added (cut-cell scalar API on `Solver`; V-cycle precision, initial guess, prefactor hoist on `diagnostics`), **none removed** (bound-name diff `v1.3.0..dfd62c4`); named numerics changes (CHANGELOG) |
| peclet-coupling | 1.1.1 → **1.2.0** | minor: the `eps_min` default 0.25 → 0.05 changes results wherever ε < 0.25; core pin v1.4.0 → v1.7.0 |
| peclet / peclet-cu13 | 1.4.0 → **1.5.0** | pins changed |
| peclet-dem 1.1.0, peclet-pnm 1.0.3 | kept | no commits since their tags |
| peclet-voro 1.0.4, peclet-morton 1.0.2, peclet-geom 1.0.1, peclet-amr 0.2.0 | kept | one commit each since the tag, none in a wheel: voro removes three pre-Kokkos `mpi/` drivers; morton the vcpkg port file; geom a docstring date; amr a design-note pointer |

**Pin bumps alone do not justify re-releasing dem, pnm, voro, amr or geom** (all pin core `v1.3.0`).
A pin is build-time only: it selects the core headers vendored into that package's own wheel, which
is already built and works. The only run-time contract between packages that core changed after
v1.3.0 could touch is the CFD-DEM co-decomposition: flow's `rebalance_by_weights` and dem's
`migrate_to_weights` must build the same weighted ORB from the same weights. Core's weighted path is
unchanged v1.3.0 → v1.7.0 (`git diff v1.3.0 v1.7.0 -- decomp/block_decomposer.hpp`:
`SplitAxis::Balanced` is consulted only when `weights == nullptr` and the caller asked for it), so a
PyPI dem 1.1.0 (core v1.3.0) and flow 1.4.0 (core v1.7.0) still co-decompose. The local batteries
(§13.4) build every one of them against core v1.7.0 headers, so their next release is a pin bump
with no code change. Re-pin each when it next releases for its own reasons.

### 13.2 Branches (worktrees, all `release-prep`, none merged)

| Repo | Worktree | Commits on `origin/main` | Content |
|---|---|---|---|
| umbrella | `.claude/worktrees/suite-release` | `daa3d3b` + | metapackages 1.5.0; CHANGELOG draft (family 1.5.0 + core 1.5.0/1.6.0/1.7.0 sections); release tooling (venv-wheel guard, audit origin column); dead-path doc fixes; this file + the 1.4.0 archive |
| flow | `suite/flow-release` | `dfd62c4` + | clang-format of `test_mg_fp32_vcycle.cpp` (Quality red on main); version 1.4.0 (pyproject, cu13, Doxyfile, CITATION); `doc/velocity_mg_plan.md` names. **Rebase onto main after `partition2` lands.** |
| coupling | `suite/coupling-release` | `043d5e6` + | core pin v1.7.0; version 1.2.0 |
| core | `suite/core-release` | `8bfd73c` + | clang-format of `grid_halo.hpp` + `test_grid_halo_variants.cpp` (Quality "clang-format (blocking)" red on main since v1.6.0). Format only (identical modulo whitespace and comment slashes); no core release implied |

CITATION `date-released` is set on tag day (left at 2026-10-04 on purpose).

### 13.3 Checklist (RELEASE.md phases)

- [ ] **§1 freeze criteria** — (1) unmerged worktrees: flow `partition2` must land; flow `cpu14`,
  `vof-issues`, `uf-outlet-diag`, `vof-w4` and the detached `flow-s2tdiag`/`flow-main-base`/
  `flow-partition2-base`, core `core-partition2` are campaign trees, not in this release (parked by
  scope) unless the user decides otherwise (Q2). (2)/(3) every checkout at `origin/main`, pointers ==
  HEADs: yes (pre-flight 2026-10-22). (4) CI: core and flow **Quality red** (clang-format) — fixed
  on `release-prep`, green once merged. (5) local matrix: §13.4. (6) "silently wrong" issues: Q3.
- [x] **A pre-flight** run (§13.5); worktree branches parked by scope as above.
- [ ] **B test matrix** (§13.4) — host column done except the rows that wait for `partition2`; CUDA
  column after `partition2`.
- [x] **C versions** (§13.1) on the branches; `check_release_state.sh` re-run on the branches is part
  of the tag-day sequence.
- [ ] **D docs** — CHANGELOG drafted; landing pages pass; docstring audit and
  `check_docs_snippets.py --ref` (§13.5); `mkdocs build --strict` with generated pages.
- [ ] **E publish** (one driver, after the user's go) — §13.6.
- [ ] **F Snellius / G LUMI** — need the user (billed). Still open from 1.4.0 as well.
- [ ] **H containers, GitHub Releases, Zenodo, Site.**
- [ ] **I gallery re-check** (after the release).

### 13.4 Test matrix (2026-10-22, host-openmp prefix, MPI on, `--bind-to none`; trees `build_rel15_host`)

Script: `bubble_column_perf/release_prep/matrix_host{,2}.sh`; one line per step in
`release_prep/summary_host.txt`, logs in `release_prep/logs/`.

| Repo | host-openmp | nvidia-cuda | Notes |
|---|---|---|---|
| core | **78/78** plain; **115/115** Kokkos; **8/8** Python | not run | |
| amr | **102/102** (`-LE 'bench\|np8'`) + **21/21** np8 | not run | |
| morton | 1/1 + 2/2 non-BMI2 (no `pdep`/`pext` in the binary); pytest 9 passed | — | |
| geom | builds, imports | — | |
| pnm | **9/9**; extraction 7199 pores | not run | |
| dem | **303/303** | not run | dem and pnm split `MPIEXEC_PREFLAGS` on spaces: the suite's documented `"--bind-to;none"` made 272 dem MPI ctests fail with "unrecognized option"; re-run with `"--bind-to none"`. Convention divergence, see Q5 |
| voro | **42/42** | not run | |
| flow `release-prep` | 66 passed, 0 failed of 248 when stopped | not run | stopped on the coordinator's wrap-up; must re-run in full after `partition2` anyway |
| flow verify scripts, coupling | not run | not run | wait for `partition2` |
| docs | `check_docs_snippets.py --ref origin/main --run`: NAMES PASS; RUN PASS ×3 (k = 1.2410e-01, as in 1.4.0); `mkdocs build --strict` PASS with pages generated from the build trees | | |

**Still to run** (RELEASE.md §3): after `partition2` lands — flow full battery host + CUDA, the three
flow verify scripts on CUDA, coupling ctests + MPI tests against the rebased flow tree. CUDA column of
core-Kokkos, pnm, dem, voro: not run (the GPU was busy with another session's campaign at 99 %;
these repos are unchanged since 1.4.0 except for the core headers they compile against — run them
with the flow CUDA battery).

### 13.5 Pre-flight and audits (2026-10-22)

`check_release_state.sh` on the main checkouts: every checkout at `origin/main`, pointers == HEADs;
"bump before tagging" for flow (231 commits), coupling (2), geom/amr/morton/voro (1 each — kept,
§13.1); consumer includes vs pins OK; landing pages OK (18 pages, 49 retired spellings); API page
coverage OK; CI on main green except **core and flow Quality (clang-format)** — fixed on the
branches. **Docstring audit** (against the build trees, every module's origin printed): 1062 bound
callables, **0 undocumented, 0 stale**, all nine packages importable.

### 13.6 Before publishing — user actions, then the sequence

**User actions:** the go (scope: flow 1.4.0, coupling 1.2.0, metapackages 1.5.0); Q1–Q5 below;
`gh auth refresh -s workflow` only if a workflow file changes (none does so far).

**Sequence** (RELEASE.md §6; each member's `release.yml` runs `landing-pages` before `publish`):

1. `partition2` merged to flow main; `git -C flow-release rebase origin/main`; re-run the flow +
   coupling rows; set CITATION dates; the CHANGELOG partition entry and date/title.
2. core: `git -C core-release push origin release-prep:main` (format only; no tag).
3. flow: push `release-prep:main`, tag `v1.4.0` (annotated), watch Release (CPU wheels + cuda-wheel);
   `pip index versions peclet-flow` / `peclet-flow-cu13` show 1.4.0.
4. coupling: same, tag `v1.2.0`.
5. umbrella: gitlinks to the released flow/coupling (and core) commits, push `release-prep:main`,
   tag `v1.5.0` → Release (landing pages, two metapackages, quickstart) and Containers (the cpu leg
   dispatches Site).
6. GitHub Releases flow `v1.4.0`, coupling `v1.2.0`, umbrella `v1.5.0` (and core v1.5.0–v1.7.0 if
   they have none) → Zenodo.
7. Smoke in a fresh venv: `pip install peclet==1.5.0` (+ `peclet-cu13`, `peclet[mpi,cfd-dem]`),
   `check_docs_snippets.py --installed --run`.

### 13.7 Open questions and items for the user

- **Q1 cut-cell scalar naming** (flow CLAUDE.md "pending FRANK" 2: `set_scalar_tolerance` →
  `set_scalar_residual_tolerance`, `maxit` → `max_iter`, the `cutcell=` spelling). The names are on
  `Solver` (public tier) and ship in 1.4.0: renaming before the tag is free, after it costs the alias
  ladder. Recommendation: settle before tagging flow.
- **Q2 branch `uf-outlet-diag`** (legacy scalars at high-side open faces read a wrapped velocity
  plane — "silently wrong" in a default configuration, RELEASE.md §1.6): merge before the tag, or
  ship it as a known limitation (the CHANGELOG draft carries a conditional bullet).
- **Q3 stale wheels in `suite/.venv`** (peclet 1.1.0 family, 2026-09-19): uninstall
  (`pip uninstall peclet peclet-flow peclet-dem peclet-morton peclet-pnm peclet-voro`); refused to
  the agent as a shared-resource change. The pre-flight now flags them.
- **Q4 billed phases**: Snellius (F) and LUMI (G), open since 1.4.0.
- **Q5 (no user needed, non-trivial)**: the `MPIEXEC_PREFLAGS` convention differs (core/flow/amr/voro a
  `;` list, dem/pnm a space string); flow `quality.yml` vof-w4 exclusions; GitHub hygiene
  (merged remote branches, Dependabot PRs) still needs the user.

### 13.8 Carried from 1.4.0 (re-verified 2026-10-22)

- Core tagged before flow ships — **done** (v1.7.0; flow pins it).
- coupling's minor bump — **in this cycle** (1.2.0).
- Docstring audit env gap — **root cause found**: `.venv` again carries the peclet **1.1.0** wheel
  family (installed 2026-09-19), so the audit graded those wheels for flow/pnm/dem/voro/morton and
  failed only on the four packages 1.1.0 lacks. The pre-flight now fails while any `peclet*`
  dist-info is in the venv and prints each module's origin. Uninstalling them needs the user
  (shared venv; refused to the agent).
- GitHub hygiene (merged remote branches, Dependabot PRs) — **still needs the user**.
- Doc debt: `PHYSICAL_UNITS_PLAN.md` / `ROADMAP.md` dead paths — fixed; flow
  `doc/velocity_mg_plan.md` names — fixed; flow `doc/porous_drag_scheme.md` states the ερ inertia
  (`2d1564a`) — resolved; `DEVELOPMENT.md`, `CORE_BOUNDARY.md`, `AGENT_WORKFLOW_HARDENING.md` still
  outside the mkdocs nav (harmless under `--strict`; a nav decision); flow `quality.yml` still
  excludes the six `vof-w4` files from clang-format — not trivial (formatting `flow_ibm.hpp` and
  `flow_bindings.cpp` would collide with `partition2`); do it after the release; flow `AGENTS.md` vs
  the compacted CLAUDE.md not re-checked.
- 1.4.0 follow-ups still open: quiet-GPU timing of the CUDA backward-facing step against v1.2.0; the
  pocket mask for `get_p` and the traction (known limitation).
