# Suite naming — one spelling per concept

`peclet` is seven repos and seven shipped Python packages (`peclet.flow`, `peclet.pnm`, `peclet.dem`,
`peclet.voro`, `peclet.coupling`, `peclet.morton`, and `peclet.core`'s `mpi`/`amr`/`geom` modules). They grew separately,
so the same idea acquired different spellings — `set_domain` in dem against `set_box` in voro,
`cell_centers` beside `cell_centres` in flow, `num_particles` against `scene_instance_count`. A user
who moves between two of them pays for that every time.

This file is the **canon**: one spelling per concept, the current divergences, and the rule for
changing a shipped name. [CONVENTIONS.md](CONVENTIONS.md) §6 governs the *mechanism* of the bindings
(nanobind, the array bridge, shapes and lifetimes); this file governs the *names*.

## 0. The rule for changing a shipped name

**Until 1.0.0: one spelling, clean break.** Decision D1 of [QUALITY_PLAN.md](QUALITY_PLAN.md)
(2026-09-08): the suite has no external users, so the release that follows 0.7.2 — **1.0.0**, because it
breaks every API — *removes* every non-canonical spelling and *renames* keyword arguments outright.
Nothing is aliased. The removals are listed with their replacements in the CHANGELOG and in
QUALITY_PLAN §2; §2 below records them as **removed 1.0.0**. Two spellings of one concept must never
ship again.

**From 1.0.0 on: additive, never breaking.** A rename lands as a NEW canonical name bound beside the old one, the
old one keeps working and keeps its docstring, and the divergence table below records the pair. One
release later the old spelling gains a `DeprecationWarning`; one release after that it may go. No
release removes a name it did not first warn on. This is the same ladder the physical-units plan
uses for `extent=None` ([PHYSICAL_UNITS_PLAN.md](PHYSICAL_UNITS_PLAN.md) D2), for the same reason:
every one of these APIs is on PyPI and someone's script imports it.

A canonical name is not permission to leave the old one undocumented. If both spellings exist, the
docstring of the old one says which is canonical.

### 0.1 What an alias cannot cover: keyword ARGUMENT names

Everything above works because a method can be bound twice. A keyword *argument* cannot: nanobind
resolves `f(sphere_centres=...)` against one spelling, and adding a second means either a wrapper
that accepts both (and has to decide what a caller passing both meant) or a break. So an argument
name that is merely spelled unusually — `sphere_centres`, `extract_topology(shape=...)` — is
**recorded here and changed at the next major version**, not aliased. 1.0.0 *is* that major
version: both are renamed there (§2).

The exception is an argument that is *added* rather than renamed: `set_domain(extent=..., ...)`
beside `set_domain(lx, ly, lz)` is a new overload, and overloads are resolvable. That is why the
domain quartet could land now and the spelling fixes could not.

## 1. The canon

### 1.1 The domain quartet

Four names, and they mean the same thing in every code:

| name | is | type |
|---|---|---|
| `origin` | the lower corner of the domain | 3-tuple, physical |
| `extent` | the SIZE of the domain (not the far corner) | 3-tuple, physical |
| `cells` | the number of cells per axis | 3-tuple of int |
| `spacing` | the derived per-axis cell size, `extent / cells` | 3-tuple, physical |

- **`extent` is a size, never a corner.** The far corner is `origin + extent`. A code that takes
  `(min, max)` corners keeps that overload but names its arguments `min`/`max` and does not call
  either of them an extent.
- **The setter is `set_domain(...)`**, taking `extent=`, `origin=` and (where the code has them)
  `periodic=` as KEYWORDS. Grid codes that fix the domain at construction take the same three as
  constructor keywords (`Solver(cells, extent=..., origin=...)`) and expose the quartet read-only.
- **`spacing` is derived and read-only.** No public API takes a cell size — that is decision D3 of
  the physical-units plan, and it is what makes a script survive a change of resolution.
- **Per axis, always.** All four are 3-tuples even where the code only supports cubic cells today;
  a scalar spelling (`spacing_from_extent`) may exist beside the vector one but never instead of it.

### 1.2 Accessors: no `get_` prefix on a property

A value the object simply *has* is a bare name: `extent`, `origin`, `spacing`, `cells`, `dt`,
`periodic`, `volumes`, `positions`. A `get_`/`set_` pair is for a value that is **converted,
copied or computed** on access — `get_u()`, `get_field(name)`, `set_positions(a)` — where the call
parentheses tell the reader a transfer happens. voro's `Tessellation` already follows this
(`volumes()`, `faces()`); dem's `Simulation` and flow's `Solver` are the ones with the split.

CONVENTIONS §6 previously wrote the lifecycle as "`step(dt)` → `get_*` accessors". That stays true
of the array getters, which do copy; it was never meant to make `get_spacing()` preferable to
`spacing`.

### 1.3 Counts are `num_<plural>`

`num_particles`, `num_cells`, `num_faces`, `num_shapes`, `num_contacts`, `num_leaves`,
`num_levels`, `num_scene_instances`. Not `<thing>_count`, not `n_<thing>`. (Dictionary KEYS
returned by a diagnostics call are exempt — they are data, and renaming them breaks plotting
scripts silently rather than loudly; `vof_diagnostics()['cut_cells']` stays.)

### 1.4 Periodicity is `periodic`

A 3-tuple of bool, per axis. Passed as `periodic=` to `set_domain` or the constructor, read back as
the `periodic` property, set on its own by `set_periodic(x, y, z)`. Not `enable_periodicity`, not
`pbc_enabled`, not three separate `px`/`py`/`pz` positionals. flow's per-face `set_domain_bc(face,
0)` is the richer boundary API and stays as it is — `periodic` is the shorthand for "all six faces
of this axis are periodic".

### 1.5 The time step is `set_dt(dt)` / `dt`

Every stepper takes its time step through `set_dt` and reports it as `dt`; `step()` advances one
step of it and `step(n)` advances `n`. No `step` takes a `dt` argument — that was a second way to
configure the same value (voro's `step(n, dt)` was removed at 1.0.0).

### 1.6 Spelling: American, and one of them

`center`, `color`, `neighbor`, `normalize`. The suite's C++ is already American throughout
(`centers`, `neighbor_counts`, `coarsenOpenAvg`); the British spellings that leaked into the Python
layer (`cell_centres`, `sphere_centres`, `colours`, `vof_block_colour`) are the outliers.
The `centre`-spelled names were removed at 1.0.0 (§2).

### 1.7 Axis order is x-fastest, and a name never has to say so

Suite tuples are `(x, y, z)` and suite grid arrays are `(nx, ny, nz)` Fortran-order
([CONVENTIONS.md](CONVENTIONS.md) §1, §6). Where a module's arrays are the C-contiguous `(nz, ny,
nx)` view of the same memory instead, the triples that describe them are stated in THAT order and
carry a `_zyx` suffix saying so. The suffix is a feature, not a defect: it is what stops a reader
guessing whether `spacing[0]` is dx or dz. `pnm` is the only module in this position, and the rule
is that a module never ships both spellings — one order per module, marked.

## 2. The divergence table

Status: **aliased** = the canonical name is bound and the old one still works; **canon** = already
correct; **open** = recorded, not yet done.

### peclet.flow

| current | canonical | status |
|---|---|---|
| `extent`, `origin`, `spacing`, `cells`, `global_cells` | — | **canon** (Phase 1 of the units plan) |
| `get_spacing()` | `spacing` | **aliased** (both ship; `spacing` is canonical) |
| `get_resolution()` | `cells` | **aliased** |
| `get_ox()` / `get_oy()` / `get_oz()` | — | **canon** — NOT origin accessors: they return the per-face openness FIELDS of the cut-cell operator (a 2026-09-07 draft of this table mislabelled them; corrected 2026-09-08 when the gallery's uses were checked) |
| `cell_centres()` | `cell_centers()` | **aliased** (both already ship) |
| `scene_instance_count()` | `num_scene_instances()` | **aliased** |
| `vof_block_colour(id)` | `vof_block_color(id)` | **aliased** (one shared body, so they cannot drift) |
| `set_domain_bc(face, type)` | — | **canon** (the per-face API; `periodic=` is not a substitute) |

### dem

| current | canonical | status |
|---|---|---|
| `set_domain(lx, ly, lz, px, py, pz)` | `set_domain(extent=, origin=, periodic=)` | **aliased** — the keyword form is a third overload bound AFTER the two positional ones, so every existing call resolves exactly where it did |
| `set_domain(min, max)` | — | **canon** (a corner overload, correctly named) |
| `get_domain_min()` / `get_domain_max()` | `origin` / `origin + extent` | **aliased** (`origin`, `extent`, `periodic` properties added) |
| `enable_periodicity(x, y, z)` | `set_periodic(x, y, z)` + `periodic` | **aliased** |
| `num_particles`, `num_shapes`, `num_contacts`, … | — | **canon** |
| `get_positions()`, `get_velocities()`, … | — | **canon** (they copy) |

### peclet.voro

| current | canonical | status |
|---|---|---|
| `set_box(L)` (`Tessellation`, `Simulation`) | `set_domain(extent=, origin=, periodic=)` | **aliased** — `origin` and `periodic` are CHECKED, not ignored: this engine's box is origin-anchored and periodic on every axis, and a caller writing the suite-wide form gets an error naming that |
| `Simulation.step(num_steps, dt)` | `set_dt(dt)` + `step(num_steps)` | **aliased** (also on `FlowSolver`); `dt` is now optional and defaults to the stored value, overriding for that call only |
| `sphere_centres` (kwarg of `sdf_voronoi_cells` etc.) | `sphere_centers` | **deferred to a major** — see §0.1 |
| `Tessellation.volumes()`, `faces()`, `neighbor_counts()` | — | **canon** (the model for §1.2) |
| `Simulation.get_positions()`, `get_volumes()`, … | — | **canon** (they copy) |
| `num_cells`, `num_faces`, `num_particles`, `num_wall_faces` | — | **canon** |

### peclet.pnm

| current | canonical | status |
|---|---|---|
| `origin_zyx`, `spacing_zyx`, `global_shape_zyx`, `grad_p_zyx` | — | **canon, as the documented exception of §1.7** |
| `shape` (kwarg of `segment_volume`) | `cells` | **deferred to a major** — see §0.1 |

pnm is the one module whose Python arrays are C-contiguous `(nz, ny, nx)` rather than
Fortran-order `(nx, ny, nz)` — `SDFReader.read_vti` returns exactly that, because that is the
layout a VTI hands over — and its origin/spacing triples are stated in the SAME order as the array
they describe. The `_zyx` suffix is therefore load-bearing: it is what tells a reader that
`spacing[0]` is dz and not dx, and dropping it for a bare `spacing` would put an unmarked
order-reversal in front of every caller. **Keep the suffix wherever the triple is in array order**,
and never add a bare `origin`/`spacing` beside it in the other order — one module having two
silently transposed spellings of the same quantity is worse than one module spelling it long.
(An earlier draft of this file listed these as an open correctness item. That was wrong: they are
consistent with the array they accompany, which is what CONVENTIONS §6 asks for.)

### peclet.core (`peclet.core.amr`, `peclet.core.mpi`)

| current | canonical | status |
|---|---|---|
| `Octree(cells, extent=, origin=, periodic=)` | — | **canon** (Phase 3) |
| `spacing`, `spacings_from_extent` | — | **canon** (per axis) |
| `spacing_from_extent` (scalar) | — | **canon as a helper**; it keeps a cubic contract and says so |
| `root_cells` (kwarg of `spacings_from_extent`) | — | **canon** — an octree's ROOT cell count is a different quantity from `Octree(cells=...)`'s leaf grid, and the longer name is what says so |
| `num_leaves`, `num_levels` | — | **canon** |
| `centers` | — | **canon** |

### peclet.coupling

| current | canonical | status |
|---|---|---|
| `CfdDem(..., smooth_width=)` (cells) | `smooth_length=` (a physical length) | **aliased** (both ship; `smooth_length` is canonical) |
| `CfdDem(..., periodic=)` | — | **canon** |
| `h=` | — | derived from the flow solver by default; an explicit `h` is a test hook |

## 3. What this file does NOT rename

- **Diagnostics dictionary keys.** `vof_diagnostics()`, `phase_change_diagnostics()`,
  `contact_angle_diagnostics()`, `get_profiling_info()` and friends return dicts whose keys are
  measured quantities. Renaming a key breaks a plotting script with a `KeyError` at the end of a
  long run, and there is no alias mechanism for a dict. They stay.
- **Method-specific vocabulary.** `openness`, `aperture`, `wisp`, `Ja`, `theta`, `beta`, `kappa`,
  `mdot` mean what the literature means. Uniformity applies to the *shared* concepts, not to the
  physics.
- **`get_`/`set_` on array transfers.** `get_u()` copies a converted field; `set_positions(a)`
  uploads. The prefix is carrying information there.

## 4. History

- 2026-09-07 — file created. Canon fixed; `smooth_length` (coupling) is the first entry landed under
  it, together with flow's already-shipped `spacing`/`cells`/`extent`/`origin` quartet.
- 2026-09-08 — first alias pass. voro `set_domain`/`extent`/`set_dt`/`dt` (`Tessellation`,
  `Simulation`, `FlowSolver`); dem `set_domain(extent=, origin=, periodic=)`, `set_periodic`,
  `origin`/`extent`/`periodic`; flow `num_scene_instances`, `vof_block_color`, and the
  canonical-partner note on `get_spacing`/`cell_centres`. Every old spelling still works and every
  gate is green: voro ctest 24/24, dem tests/kokkos 8/8, flow `units_*` + the coupling battery.
  The pnm row was CORRECTED — its `_zyx` names are right, not an open item.
