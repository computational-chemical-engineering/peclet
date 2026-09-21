# The `core` boundary — what is shared infrastructure, what is MPI, and what each is called

Design note, 2026-09-21. Answers the brief at `/tmp/claude-1003/brief/core_boundary.md` (the
question: how should `core` be decomposed and named, C++ and Python separately, so its MPI-free
functionality is installable without an MPI toolchain, and how is that reached from the shipped 1.0
API under NAMING.md §0). Status: **proposal — nothing here is implemented.** Sections 6 and 7 are
written so that `DECISIONS.md` and `NAMING.md` entries can be lifted verbatim once accepted.

## 0. Verdict in five lines

1. **The C++ identity does not move.** `peclet::core`, `peclet/core/...`, repo `core`, tags `v*`,
   Zenodo lineage, the `peclet::core` / `peclet::halo` CMake targets — all unchanged. The MPI
   boundary already exists there (the `common/mpi.hpp` shim, the `halo/` directory, the two
   targets); what it lacks is a gate that stops it drifting. Add the gate; rename nothing.
2. **The Python identity splits into two distributions cut at the install-time requirement and
   named for what a user installs them to get:** `peclet-geom` → `peclet.geom` (wheels, numpy
   only, in the `peclet` metapackage) and `peclet-halo` → `peclet.halo` (sdist, MPI + mpi4py,
   behind `[mpi]`). `peclet-core` on PyPI becomes a pure-Python compatibility shell for the
   ladder's duration and is frozen at its last 1.x at 2.0.0.
3. **The brief's crux is right and I agree with it explicitly (§2.3):** the C++ header library and
   the Python package are different products for different audiences with different change costs,
   and conflating them is what made the name deceptive. Splitting them is what makes the fix cheap.
4. **The `find_package(MPI)` guard is the right *shape* of stopgap only in its loud, opt-in form,
   and it entrenches nothing** — but it is not the right first move (§4). Step 1 of the ladder
   costs about a day, is permanent, and is what the gallery actually needs (a wheel, not a
   friendlier source build). Ship the guard as core 1.0.3 only if the gallery cannot wait for the
   next family release.
5. **Everything worth doing is doable now without spending a major.** The only thing the major
   buys is deleting the shell.

**The one reserved decision is settled: the halo package is `peclet.halo`.** Confirmed by the
maintainer 2026-09-21, taking the recommendation of §1.2 over the initially suggested `peclet.mpi`.
Every occurrence below is final, not provisional.

## 1. Target structure

### 1.1 C++ — unchanged identity, an explicit and gated boundary

| element | today | target | rationale |
|---|---|---|---|
| repo, tags, DOI | `core`, `v1.0.2`, `10.5281/zenodo.21132435` | unchanged | six repos pin `PECLET_CORE_TAG`; `check_release_state.sh` checks every consumer include against that tag; a rename buys a user nothing |
| namespace, header path | `peclet::core`, `peclet/core/...` | unchanged | build-time only; the layering is already expressed by directory (`halo/`) and target (`peclet::halo`) |
| CMake targets | `peclet::core` (header-only, MPI-free), `peclet::halo` (`peclet::core` + `MPI::MPI_CXX`, or the stub) | unchanged | this *is* the C++ boundary and it is already right |
| MPI manifest | implicit — whichever headers happen to include `common/mpi.hpp` | **explicit and gated**: the set is `halo/*.hpp` (8) + `decomp/grid_redistribute.hpp`; a `quality.yml` grep step fails if a header outside the manifest includes `common/mpi.hpp` or `<mpi.h>`, or if a manifest header stops including it | the boundary drifted once already (`grid_redistribute.hpp` lives under `decomp/`, and the brief counted it MPI-free); a gate is cheaper than the next audit |
| geom closure | implicit | **gated**: `geom/{primitives,scene,scene_builder,scene_query,quadrature,body_properties}.hpp` + `common/{types,portable}.hpp` compile with no Kokkos and no MPI on the include path — `peclet-geom`'s CI proves this by construction (§1.2) | this closure is what makes the wheel trivial; a `#include <Kokkos_Core.hpp>` creeping into `scene_builder.hpp` would silently make it a Kokkos wheel |
| `grid_redistribute.hpp` location | `decomp/` | leave in place, listed in the manifest | flow includes it at the current path (`flow/src/mac_cutcell_mg.hpp`); a forwarding header across a tag boundary is more machinery than the tidy is worth |
| Kokkos + no-MPI | `amr/CLAUDE.md:19-20` says it was never a valid core configuration; nothing records it | **recorded as unsupported** (DECISIONS entry, §6) — `mpi_stub.hpp` covers the host halo, the Kokkos `GridHalo` is untested against it and CI's `no-mpi` job has no Kokkos | out of scope to fix; in scope to stop a future session "fixing" the stub to cover it without deciding to |

Nothing in this column changes a byte of any consumer's build. The one new artefact is a CI step.

### 1.2 Python — two distributions, cut at the install-time requirement

| | `peclet-geom` | `peclet-halo` | `peclet-core` (during the ladder only) |
|---|---|---|---|
| import | `peclet.geom` | `peclet.halo` | `peclet.core.geom`, `peclet.core.mpi` — re-exports |
| contents | `SceneBuilder` (analytic-SDF authoring, CSG, instancing, `encode`, `eval*`, `bake`, `body_properties`, `principal_frame`) — today's `peclet.core.geom`, unchanged | `ParticleMigrator`, `ParticleHalo`, `build_toolchain` — today's `peclet.core.mpi`, unchanged | three pure-Python files |
| build needs | C++20 compiler + nanobind; **no Kokkos, no MPI, no OpenMP** | MPI toolchain; mpi4py at runtime | nothing |
| ships as | **wheels** — the §11.2 matrix (manylinux x86-64 + aarch64, win_amd64, macosx arm64, cp310–cp314) + sdist | sdist only (MPI ABI, as today) | pure-Python wheel |
| runtime deps | `numpy` | `numpy` (+ mpi4py, unpinned, as today) | `peclet-geom==X`, `peclet-halo==Y` |
| pulled by | `peclet` **and** `peclet-cu13` metapackages (one wheel serves both — it is host-only, there is no `-cu13` variant) | `[mpi]` extra | `[mpi]` extra during the ladder (so `peclet[mpi]` keeps providing `peclet.core.mpi`) |
| repo | **new sibling repo `peclet-geom`**, a consumer of core's headers at `PECLET_CORE_TAG` through the same `peclet_sibling_include` + `PECLET_VENDOR_DEPS` machinery every method code uses (the `peclet-amr` precedent, D6/G.2) | the `core` repo's `pyproject.toml`, renamed | `core/packaging/pyproject-core.toml`, built by core's `release.yml` the way the umbrella builds `peclet-cu13` from `packaging/pyproject-cu13.toml` |
| module layout | `peclet/geom/__init__.py` + `_geom.*.so` + `_geom.pyi` (the `peclet/flow/_flow.*.so` convention) | `peclet/halo/__init__.py` + `_halo.*.so` + `_halo.pyi` | `peclet/core/{__init__,geom,mpi}.py` |
| version at step 1 | 1.0.0 — the shipped, unchanged 1.0 API, first standalone release | core's version (1.1.0) — the tag consumers pin is the tag `peclet-halo` is cut from, exactly as `peclet-core` is today | core's version |

**Why `halo`, not `mpi`, for the second package.** The suite's naming rule is that an identifier
names *what a thing is, never where it runs* (the Device*/`*Kokkos` retirement, umbrella
`CLAUDE.md`). `mpi` names a dependency; `halo` names the thing — and it is already the thing's name
on the C++ side (`peclet::halo`, `halo/`, `GridHalo`, `ParticleHalo`). `init_mpi` / `step_mpi` /
`mpi_block` in the method codes are variant *suffixes* on a verb, the kept prose-like exception; a
top-level package name is the identity, not a variant. `peclet.mpi` would be the only package in
the family named for what it links against. This was the one class of decision the standing
policy reserves for the maintainer, and it was put to them and **settled on `halo` (2026-09-21)**;
`peclet.mpi` was technically equivalent (same ladder, same shell) and is recorded as the rejected
alternative in §6.

**Why geom gets a repo and halo does not.** Geom needs the four-platform cibuildwheel release
matrix and a CI that proves "no Kokkos, no MPI" by never installing them — a different release
machine from core's (MPI, Kokkos, np=1..8), and it will grow user-facing Python conveniences the way
`voro.scenes` did. Halo is a thin binding over core's own headers whose tests (`test_mpi.py`
np=1,2,4,8; `state_hash.py`) are part of core's counted battery (54 / 69 / **6**); moving them out
to a third repo would split the MPI battery for symmetry alone. The asymmetry is deliberate and
recorded (§5, R9).

### 1.3 Where the C++ and Python identities meet

`peclet-geom` and (after the ladder) `peclet-halo` are both *consumers* of the C++ `core` at a
pinned tag, like `flow` and `amr`. The release order gains one rung and loses nothing:

```
core (tag)  →  geom, morton  →  flow, pnm, dem, voro  →  coupling  →  peclet / peclet-cu13  →  containers, sites, gallery
```

`peclet-halo` is cut from the core tag itself (it is core's `pyproject.toml`), so it sits on the
first rung. No method wheel depends on `peclet-geom` at runtime: dem's `scene_particle.build`
takes the builder duck-typed, flow's `set_scene` takes the encoded arrays. That stays so — the
physical-units plan's D2 rejected a wheel-to-wheel runtime dependency on core, and the reasoning
(a wheel must not pull a source build) is unchanged even though geom is now a wheel: the coupling
is through arrays, and it should remain so.

## 2. Why this boundary

### 2.1 The C++ principle: a header is on the MPI side iff it includes `common/mpi.hpp`

That is the shim's whole purpose (`mpi.hpp:1-4`: "Include this instead of `<mpi.h>`"). It gives a
mechanical, greppable definition of the boundary, which is why the manifest gate in §1.1 is a
five-line CI step and not a judgement. Applied today it yields: `halo/` (8 headers) plus
`grid_redistribute.hpp` — nine headers of forty-seven. The layering the manifest expresses:

```
common/{types,portable}                        ← C++17-clean, Kokkos-optional, MPI-free
  ├─ geom/*, decomp/{block_decomposer,block_indexer,morton_indexer}, solver/*, vof/*, scheme/*, field/*, interp/*
  │                                             ← MPI-free (some Kokkos-dependent: solver/graph_amg_device, common/view, python/*)
  └─ halo/*, decomp/grid_redistribute           ← MPI (real, or the single-rank stub under PECLET_CORE_NO_MPI)
```

"MPI-free" is not "dependency-free": `python/ndarray_interop.hpp` and `kokkos_teardown.hpp` need
Kokkos and nanobind, `solver/graph_amg_device.hpp` needs Kokkos. The Python `geom` module's closure
is the strict subset that needs *neither* — six `geom/` headers and two `common/` ones — and that
subset, not "the MPI-free part of core", is what `peclet-geom` builds. `geom/device_scene.hpp` and
`geom/grid_sdf.hpp` (Kokkos-side, `View`-based) stay where they are; they are the bridge the method
codes compile, not something a Python user imports.

### 2.2 The Python principle: a distribution is cut at its install-time requirement and named for the one thing a user installs it to get

Two consequences, and they are the whole design:

- **Nothing that needs no MPI may live behind an MPI toolchain.** `peclet.core.geom` violates this
  today — a pure-geometry authoring API that eleven gallery pages import cannot be installed on Colab
  without `apt-get install libopenmpi-dev` and a source build. The fix is not a friendlier source
  build; it is a wheel, and a wheel needs a distribution whose build closure is wheel-able. That
  distribution is `peclet-geom`.
- **`peclet-core` is a distribution named for a C++ layer, and nobody pip-installs "the core".** They
  install the particle halo or the scene builder. Once geom leaves, what remains in `peclet-core`
  is the halo, and a package containing exactly the halo should say so. That is why the second
  rename rides the same ladder rather than waiting: the ladder's cost is per release, not per name,
  and "getting it wrong twice costs two majors" applies equally to getting it half-right.

### 2.3 The crux: the C++ identity and the Python identity are separate decisions

I agree with the brief, and want to state why in a form that survives this note:

| | C++ header library | Python package |
|---|---|---|
| audience | developers of the eight repos | users of PyPI |
| binding | `#include "peclet/core/..."` at a pinned git tag | `import peclet.core.…` at a pinned PyPI version |
| what a rename costs | a mechanical edit across ~330 `peclet/core/` include lines in six repos (flow 114, amr 125, voro 55, dem 24, pnm 9, coupling 4), six repins, forwarding headers across a tag boundary, and a `check_release_state.sh` rewrite | a three-release ladder (bind beside, warn, remove at the major) plus a metapackage bump |
| what a rename buys | nothing a user sees | the name a user reads, and the install path a user takes |
| the honest name | "core" — it *is* the shared foundation (`common`, `decomp`, `geom`, `solver`, `vof`, `halo`) | "core" — deceptive: the package is two unrelated tools, one of which needs MPI and one of which does not |
| naming principle | what it is *to the suite* | what it is *to the user* |

The name is the same string, but it is two names. The C++ one is right and expensive to change;
the Python one is wrong and cheap to change. Treating them as one name is what produced the brief's
dilemma ("rename without re-cutting the boundary would relabel the problem"); treating them as two
dissolves it — re-cut the Python boundary, relabel the Python name, leave the C++ alone.

## 3. The migration ladder

Family versions as they stand: metapackage `peclet` 1.1.1; `peclet-core` 1.0.2; `peclet-flow`
1.1.0; the rest 1.0.2. The ladder below is NAMING.md §0 applied literally: **N** binds the new
name beside the old, **N+1** warns on the old, the **next major** removes it. D9 makes the removal a
major whatever N+2 is numbered.

### Step 0 (optional, now) — core 1.0.3: the loud opt-in guard

Only if the gallery cannot wait for step 1 (§4 for the verdict). `python/CMakeLists.txt`:

```cmake
option(PECLET_CORE_PYTHON_MPI "Build peclet.core.mpi (needs an MPI toolchain); OFF builds geom only" ON)
if(PECLET_CORE_PYTHON_MPI)
  find_package(MPI COMPONENTS CXX)
  if(NOT MPI_FOUND)
    message(FATAL_ERROR "peclet-core: peclet.core.mpi needs MPI and none was found. Install an MPI "
      "toolchain (Ubuntu/Colab: apt-get install libopenmpi-dev), or build geom only: "
      "pip install --config-settings=cmake.define.PECLET_CORE_PYTHON_MPI=OFF peclet-core")
  endif()
  # … mpi_bindings target, tests, exactly as today …
endif()
# geom_bindings unconditional, as today
```

Costs an hour. Breaks nothing. Never falls back silently (§4 for why that matters). Dies with the
file at step 1.

### Step 1 (family 1.2.0) — bind the new names beside the old

| repo | change | breaks | cost |
|---|---|---|---|
| **new `peclet-geom`** | repo created; `python/geom_bindings.cpp`, `packaging/core_geom.pyi`, the geom half of `state_hash.py` + its reference entries moved **with history** (`git filter-repo`, as amr was); `cmake/PecletDeps.cmake` with `PECLET_CORE_TAG`; `NB_MODULE(_geom)` installed as `peclet/geom/_geom.*.so` + `__init__.py` (`from ._geom import *`) + `_geom.pyi` + `py.typed`; CI = build on ubuntu with **no MPI and no Kokkos installed** + state-hash + a `SceneBuilder` pytest; `release.yml` = cibuildwheel on the §11.2 matrix + sdist; PyPI Trusted Publisher; Zenodo; README/CITATION/LICENSE; `quality.yml` (clang-format) | nothing | ~1 day (the G.2 precedent) |
| **core 1.1.0** | `pyproject.toml` name → `peclet-halo`; `NB_MODULE(_halo)` installed as `peclet/halo/`; `mpi_bindings.cpp` → `halo_bindings.cpp`; stubs renamed; `state_hash.py` keeps its mpi half, imports `peclet.halo`; `test_mpi.py` imports `peclet.halo`; `python/CMakeLists.txt` loses `geom_bindings`; **`packaging/pyproject-core.toml`** = the shell (hatchling, `peclet/core/{__init__,geom,mpi}.py`, `dependencies = ["peclet-geom==1.0.0", "peclet-halo==1.1.0"]`); `release.yml` builds both (the umbrella's `cp packaging/… pyproject.toml` pattern); the C++ manifest gate (§1.1) added to `quality.yml`; CHANGELOG | nothing: `peclet.core.geom` and `peclet.core.mpi` keep working, same objects, same docstrings, no warning | ~½ day |
| **shell modules** | `peclet/core/geom.py`: `"""peclet.core.geom — the pre-1.2 spelling of peclet.geom; `from peclet import geom` is canonical."""` then `from peclet.geom import *` and `__all__`; same for `mpi.py` over `peclet.halo`; `__init__.py` keeps `__version__` from the `peclet-core` dist | `peclet.core.geom.SceneBuilder is peclet.geom.SceneBuilder` → `True`; pickles, isinstance, docs all unchanged | trivial |
| **umbrella** | `pyproject.toml` + `packaging/pyproject-cu13.toml`: `dependencies += ["peclet-geom==1.0.0"]`; `mpi = ["peclet-core==1.1.0"]` (the shell, so `peclet[mpi]` still provides `peclet.core.mpi`); `check_release_state.sh` SUBS += `geom`, DIST += `[geom]=peclet-geom`, and its consumer-includes loop covers `geom/python` (today it greps `$s/include $s/src`); `check_docs_snippets.py`: `INSTALLED_MODULES += ["peclet.geom", "peclet.halo"]`, **`add_leaf` leaves `BUILD_GATED`** (there is a wheel now); `gen_python_api.py` → `docs/python/{geom,halo}.md`, `core.md` reduced to a pointer; `DEPLOYMENT.md`, `index.md`, `README.md`, `NAMING.md` §2 + §4, `DECISIONS.md` (§6); `tools/hpc/install_{snellius,lumi}.sh` install `peclet-geom peclet-halo` and smoke `peclet.halo` | nothing | ~½ day, mostly Sonnet-grade edits |
| **in-suite callers** → canonical names | dem: `examples/driver_distributed.py`, `tests/python/mpi/{conftest,_mpi_common,test_*}.py`, `tests/regression/state_hash.py`, `packaging/scene_particle.py` docstring; voro: `mpi/validate_voronoi*.py`, `python/test_voro.py`, `packaging/voro_scenes.py` docstring; amr: `python/state_hash.py`; flow: `scripts/compare_amr_sdflow_field.py`; `docs/notebooks/quickstart_sphere.ipynb` prose | nothing (the old names still work; this is hygiene so the suite's own CI never sees the step-2 warning) | ~2 h, mechanical |
| **peclet-examples** | the eleven pages: `from peclet import geom`; the bootstrap loses the `peclet-core` install, the `SystemExit` and the apt advice (`pip install peclet` now provides geom); `api-check.yml` drops `libopenmpi-dev` and `peclet-core`; re-freeze | nothing | ~1 h, a net deletion |

**Proof the move is faithful.** The state-hash byte gate is the instrument: the geom entries in
`state_hash_reference.json` produced by core 1.0.2's `peclet.core.geom` must be byte-identical to
those produced by `peclet-geom` 1.0.0's `peclet.geom` on the same toolchain, and the mpi entries
likewise across the `peclet.halo` rename. A changed digit is a bug in the move.

**User-visible text at step 1:** none, by rule. The old modules' docstrings name the canonical
spelling; the CHANGELOG entry reads:

> `peclet.core.geom` is now `peclet.geom` (package `peclet-geom`, wheels for Linux/Windows/macOS,
> included in `pip install peclet`), and `peclet.core.mpi` is now `peclet.halo` (package
> `peclet-halo`, sdist, `pip install peclet[mpi]`). The old spellings keep working unchanged in
> this release and gain a `DeprecationWarning` in the next; `peclet.core` is removed in 2.0.0.

### Step 2 (family 1.3.0) — warn on the old spelling

Core 1.2.0: the two shell modules gain, at import,

```python
warnings.warn(
    "peclet.core.geom is peclet.geom since peclet 1.2.0 — use `from peclet import geom`. "
    "peclet.core is removed in peclet 2.0.0.", DeprecationWarning, stacklevel=2)
```

(and the `mpi` → `halo` twin). The shell's pins move to `peclet-geom>=1.0,<2`,
`peclet-halo>=1.2,<2` — a range with a `<2` ceiling so that the frozen shell can never silently
downgrade or straddle a 2.x family (step 3). A ctest in core asserts the warning fires
(`python -W error::DeprecationWarning -c "import peclet.core.geom"` must exit non-zero), so the
ladder step is itself gated rather than trusted. Breaks nothing. Cost: an hour.

### Step 3 (2.0.0) — remove

`core/packaging/pyproject-core.toml` deleted; core's `release.yml` publishes `peclet-halo` only;
`[mpi] = ["peclet-halo==2.0.0"]`; `peclet.core` gone from the docs and from `INSTALLED_MODULES`.
**`peclet-core` on PyPI is frozen at its last 1.x, not tombstoned**: a 2.x environment that runs
`pip install peclet-core` fails loudly at dependency resolution on the `<2` ceiling with the
constraint named in the message, and the PyPI description (editable without an upload) says
"renamed: `peclet-geom` + `peclet-halo`". A pinned 1.x family keeps working forever, which is what
"someone's script imports it" requires. Breaks: `import peclet.core` on a 2.x family, after one
full release of warnings — the removal the ladder promised. Cost: an hour.

### What is worth doing now versus at the major

| now (1.2.0) | next minor (1.3.0) | next major (2.0.0) | never |
|---|---|---|---|
| `peclet-geom` wheels in the metapackage; `peclet.halo`; the shell; the C++ manifest gate; callers and gallery moved | the warnings | delete the shell; `[mpi]` → `peclet-halo` | rename `peclet::core` / `peclet/core/...`; split the C++ repo |

The defect is fixed at step 1. Steps 2 and 3 are bookkeeping the rule requires.

## 4. The interim fix — verdict

**Is the `find_package(MPI)` guard right?** In one form yes, in the other no, and the difference
is the whole answer:

- **Silent form** (make line 19 non-REQUIRED, wrap `mpi_bindings` in `if(MPI_FOUND)`): **no.** It
  converts a loud build failure into a silent partial install. `pip install peclet[mpi]` on a box
  without MPI headers would *succeed* and yield a package with no `mpi` in it; `check_docs_snippets
  --installed` skips absent modules by design ("a module that is simply absent is skipped, so CI
  must install what it wants checked or the pass silently narrows"), so the sweep would not notice
  either. That is the packaging twin of the test failure mode QUALITY_PLAN §3.D forbids ("never
  pass silently"). It would also be the first place in the suite where the *contents* of an install
  depend on what the build happened to find — precisely the class of behaviour the CPU-budget
  decision (D-register, core: "not by the visible CPU count") was recorded to prevent.
- **Loud opt-in form** (§3, step 0): **acceptable as a stopgap.** An explicit option, default ON,
  fatal with a message that says both remedies when MPI is missing. It changes no name, adds no API,
  and is deleted with the file at step 1 — it entrenches nothing, because it does not touch the
  boundary at all; it only makes today's boundary navigable.

**Is it the right first move?** Lean no. The gallery has a legible failure in place already
(`SystemExit` naming the cause, since peclet-examples `4c48344`); the loud guard improves that to
"works after a one-minute source build on Colab, via a package and an extra both named `mpi`". Step
1 improves it to "works with `pip install peclet`", which is the state the eleven pages were written
for, and costs about one working day. If a family release is more than a couple of weeks out, ship
step 0 as core 1.0.3 in the meantime; if not, skip it. Either way step 0 is not a fork in the road —
it is on the road.

**Does the interim measure already shipped entrench anything?** No. Installing `libopenmpi-dev` in
`api-check.yml` and the pages' `SystemExit` are deletions at step 1.

## 5. Rejected alternatives

| # | alternative | why rejected |
|---|---|---|
| R1 | **Do nothing but fix the build** (loud guard, keep `peclet.core.{mpi,geom}` forever) | `pip install peclet` still does not provide geom unless the metapackage pulls `peclet-core`, which drags an MPI sdist into every install (R6); every Colab visitor compiles; dem's shipped `scene_particle.build` stays unusable from the wheels; the distribution name stays a C++ layer's name. It fixes the symptom the CI saw and none of the ones users see. |
| R2 | **Silent guard** (auto-disable `mpi` when MPI is absent) | §4: silent narrowing of an install; the `[mpi]` extra would "succeed" without MPI; the doc sweep would not notice. |
| R3 | **Rename the C++ namespace / header path** (`peclet::geom`, `peclet::halo` top-level; `peclet/geom/...`) | ~330 include lines across six repos, six repins, forwarding headers that must exist at every pinned tag, `check_release_state.sh`'s include-vs-tag check rewritten — for a change no user sees. The C++ layering is already expressed by `halo/` and by the two targets. |
| R4 | **Split the C++ repo** (`peclet-geom` carrying the `geom/` headers) | `geom/` is included by flow (4), amr (8), dem (5), voro (4) at build time through the single core pin; `device_scene.hpp` and `grid_sdf.hpp` bridge geom into Kokkos consumers, so the C++ geom is *not* the pure-host subset the Python module is. Two tags to pin instead of one, and the manifest gate gives the same guarantee for free. |
| R5 | **Wheels for `peclet-core` as it is** | the halo links MPI; there is no portable MPI ABI. This is why it has been sdist-only since 0.1.0 and why the halo stays an sdist here. |
| R6 | **Add `peclet-core` (guarded) to the metapackage** | pulls a source build (compiler, ~1 min, MPI-or-opt-out) into `pip install peclet` for every user of every wheel. Wheels are the rule for anything that can be a wheel. |
| R7 | **`peclet.mpi`** as the halo's name | names where it runs, not what it is; the only package in the family named for a dependency; `halo` already names it on the C++ side. **Put to the maintainer and rejected in favour of `halo`, 2026-09-21.** |
| R8 | **Put geom's Python into `peclet-dem` or `peclet-flow`** | geom is shared by flow, dem, voro, amr and coupling; it would create the wheel-to-wheel runtime dependency the physical-units plan's D2 rejected, in the other direction. |
| R9 | **A third repo for halo, for symmetry with geom** | splits core's counted MPI battery (`test_mpi.py` np=1..8, `state_hash`) out of the repo whose headers it tests; halo has no wheel matrix to justify separate release machinery. |
| R10 | **Tombstone `peclet-core` 2.0.0** (metadata-only release depending on the new packages) | `pip install peclet-core` would then install something that does not provide `peclet.core` — a silent removal. Freezing at 1.x with a `<2` ceiling makes the same situation a loud resolver error. |
| R11 | **Keep one distribution, rename it `peclet-geom`, ship the halo inside as optional** | one distribution cannot be both a wheel and an MPI sdist; the halo would again be unbuildable from a wheel and again silently absent or loudly required. This is R1/R2 with a different label. |
| R12 | **Fix only the gallery** (apt + `SystemExit`) | shipped already as the interim measure; it makes the failure legible and fixes nothing. |

## 6. What to record in `docs/DECISIONS.md` (and `docs/decisions/core.md` / `suite-wide.md`)

Each entry in the register's form: decision, rejected alternative, reason, provenance. Provenance
for all of them: this note, `docs/CORE_BOUNDARY.md`, 2026-09-21.

**core**

- **The C++ identity of core does not follow the Python split: `peclet::core`, `peclet/core/...`,
  repo `core` and its tag lineage stay.** *Rejected:* a top-level `peclet::geom` / `peclet::halo`
  namespace and header path; splitting the header repo. *Why:* build-time-only identity, six
  consumers pin it by tag, no user-visible gain; the layering is already carried by `halo/` and the
  `peclet::core` / `peclet::halo` targets.
- **The MPI boundary in core is "includes `common/mpi.hpp`", and the manifest is `halo/*.hpp` +
  `decomp/grid_redistribute.hpp`, gated in CI.** *Rejected:* an implicit boundary (the audit of
  2026-09-21 miscounted `grid_redistribute.hpp`); relocating `grid_redistribute.hpp` with a
  forwarding header. *Why:* a grep gate is cheaper than the next audit; flow includes the header at
  its current path across a tag pin.
- **The `peclet-geom` closure is `geom/{primitives,scene,scene_builder,scene_query,quadrature,body_properties}.hpp`
  + `common/{types,portable}.hpp`, and it compiles with neither Kokkos nor MPI on the include path.**
  *Rejected:* "the MPI-free part of core" as the wheel's definition. *Why:* MPI-free is not
  dependency-free (`python/*`, `solver/graph_amg_device`, `common/view` need Kokkos); the closure is
  what makes the wheel a one-minute host build on four platforms.
- **Kokkos + no-MPI is not a supported core configuration.** *Rejected:* extending `mpi_stub.hpp` to
  cover the Kokkos `GridHalo`. *Why:* never valid, never tested (CI's `no-mpi` job has no Kokkos;
  `amr/CLAUDE.md:19-20`); recorded so it is not "fixed" without a decision.
- **An MPI-requiring Python module is built, or the build fails loudly, or it is disabled by an
  explicit option — never skipped because MPI was not found.** *Rejected:* `if(MPI_FOUND)` around
  `mpi_bindings`. *Why:* a silent partial install; `pip install peclet[mpi]` must not succeed
  without MPI; the doc sweep skips absent modules by design.

**suite-wide**

- **A Python distribution is cut at its install-time requirement and named for the one thing a user
  installs it to get; a distribution is never named for a C++ layer.** *Rejected:* one PyPI
  distribution per C++ repo as a rule. *Why:* `peclet-core` bundled a wheel-able geometry API with
  an MPI sdist under an MPI-named extra, and the geometry became uninstallable without an MPI
  toolchain for that reason alone.
- **`peclet-geom` ships wheels and is a dependency of both metapackages; there is no `-cu13`
  variant.** *Rejected:* adding `peclet-core` to the metapackage; a CUDA twin. *Why:* host-only,
  no Kokkos; one wheel serves both families.
- **No method wheel depends on `peclet-geom` or `peclet-halo` at runtime; coupling is through the
  encoded arrays (`SceneBuilder.encode()` → `flow.set_scene` / `dem.add_scene_shape`).** *Rejected:*
  `peclet-dem` depending on `peclet-geom` for `scene_particle`. *Why:* the physical-units plan's D2
  reasoning — a wheel must not acquire a cross-wheel dependency — holds even now that geom is a
  wheel; the array contract is the interface.
- **`peclet-core` on PyPI is frozen at its last 1.x with a `<2` ceiling at 2.0.0, not tombstoned.**
  *Rejected:* a code-free 2.0.0 depending on the new packages. *Why:* a loud resolver error beats a
  silent import failure.
- **The halo package is `peclet.halo`, not `peclet.mpi`** — maintainer's decision, 2026-09-21.
  *Rejected:* `peclet.mpi`. *Why:* names what it is, not where it runs; `mpi` names a dependency,
  and it would be the only package in the family named for what it links against; `halo` is already
  the thing's name on the C++ side (`peclet::halo`, `halo/`, `GridHalo`, `ParticleHalo`).

## 7. What to record in `docs/NAMING.md`

**§2, the `peclet.core` table** gains (and the heading becomes "peclet.geom, peclet.halo, and
peclet.core (`peclet.core.geom` / `peclet.core.mpi` until 2.0.0)"):

| former | canonical | status |
|---|---|---|
| `peclet.core.geom` (dist `peclet-core`, sdist behind `[mpi]`) | `peclet.geom` (dist `peclet-geom`, wheels, in `pip install peclet`) | **aliased 1.2.0** → warns 1.3.0 → removed 2.0.0 |
| `peclet.core.mpi` (dist `peclet-core`) | `peclet.halo` (dist `peclet-halo`, sdist, `pip install peclet[mpi]`) | **aliased 1.2.0** → warns 1.3.0 → removed 2.0.0 |
| `from peclet.core import geom, mpi` | `from peclet import geom, halo` | same ladder |
| extra `[mpi]` | — | **canon** — it names the *requirement* of what it pulls, which is what an extra is for; it pins the shell through the ladder and `peclet-halo` from 2.0.0 |

**§0** needs no change — this is the ladder it prescribes. **§4 (history)** gains one line at step 1:

> 2026-MM-DD — **`peclet.core` split by install-time requirement** (CORE_BOUNDARY.md): `peclet.geom`
> (`peclet-geom`, the family's first host-only wheel) and `peclet.halo` (`peclet-halo`, sdist);
> `peclet.core.{geom,mpi}` bound beside them unchanged, warning from 1.3.0, gone at 2.0.0. The C++
> `peclet::core` is untouched.

## 8. How the answer is verified (extends the brief's §7)

1. In a venv on a host with **no MPI dev headers**: `pip install --only-binary=:all: peclet-geom`
   succeeds (the `--only-binary` flag turns "installs" into "installs the *wheel*"), and
   `python -c "from peclet import geom; geom.SceneBuilder()"` runs. Today this fails at
   `find_package(MPI REQUIRED)`.
2. The eleven gallery pages run from PyPI on a bare Colab-like environment with the simplified
   bootstrap (no apt, no `peclet-core`).
3. **Byte gate across the move:** the geom entries of `state_hash_reference.json` are identical
   between core 1.0.2 (`peclet.core.geom`) and `peclet-geom` 1.0.0 (`peclet.geom`); the mpi entries
   identical across `peclet.core.mpi` → `peclet.halo`. Same toolchain key, same bytes.
4. `peclet.core.geom.SceneBuilder is peclet.geom.SceneBuilder` and
   `peclet.core.mpi.ParticleMigrator is peclet.halo.ParticleMigrator` are `True` with the shell
   installed; both old imports emit no warning at 1.2.0 and a `DeprecationWarning` at 1.3.0
   (the latter asserted by a ctest, not by inspection).
5. All eight repos configure and build against core 1.1.0; `tools/release/check_release_state.sh`
   passes with `geom` in `SUBS`, including the consumer-includes-vs-pinned-tag check over the geom
   repo's binding source.
6. Core's battery unchanged: 54 plain / 69 Kokkos (host and CUDA) / 6 Python, np 1–8 — the six
   Python ctests now importing `peclet.halo`. dem's `tests/python/mpi` and voro's `mpi/validate_*`
   pass on `peclet.halo`.
7. The manifest gate: a scratch commit adding `#include "peclet/core/common/mpi.hpp"` to
   `geom/scene.hpp` fails core's `quality.yml`; reverting it passes. The geom repo's CI has no MPI
   and no Kokkos installed, so the closure is proved by construction on every push.
8. `pip install peclet[mpi]` in an environment **without** MPI still fails, loudly, at every step of
   the ladder (the invariant R2 protects).

## 9. Corrections to the brief, for the record

- §3.4: the MPI surface is `halo/` **plus `decomp/grid_redistribute.hpp`** (includes the shim at
  line 23; used by `flow/src/mac_cutcell_mg.hpp`). `solver/csr_bicgstab.hpp` mentions MPI only in a
  comment and takes the reduction as a callable — MPI-free by design. Counts: 36 MPI-free, 9
  MPI-bound, 2 shim.
- §3.5: `dem/packaging/scene_particle.py` imports nothing from `peclet.core` — the builder is
  duck-typed and the `from peclet.core import geom` is in its docstring example. That makes the case
  *stronger*: a feature shipped in the dem wheel is unusable today without an MPI toolchain,
  because its only input comes from `peclet.core.geom`.
- §3.5: `voro/packaging/voro_scenes.py` was written specifically to avoid importing `peclet.core`
  (its docstring says so) — evidence the boundary was already costing the suite workarounds.
- §4: the `peclet-cu13` metapackage carries the same `[mpi]` extra and needs the same edits.
- The top-level `core/CMakeLists.txt:4` comment ("Wheels exist for Linux, Windows x64 and macOS
  arm64") describes the family after the §11.2 probe, not `peclet-core`, whose `release.yml` is
  sdist-only. The brief was right; the comment is misleading and should be reworded at step 1.
