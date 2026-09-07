# Suite Conventions

> Status: design document (living). The **correspondence contract** every code in the suite follows.
> Where a code diverges today, the "Current state" notes say so; reconciliation is tracked in
> [ROADMAP](ROADMAP.md).

These conventions are deliberately built on what the codes *already agree on*, then extended to cover
the gaps. Two pillars are non-negotiable because they are already shared and load-bearing:

1. **SDF sign: negative inside solid, positive in fluid/void.**
2. **Axis order: x is fastest-varying;** linear index `I = x + y*nx + z*nx*ny`.

## 1. Geometry & indexing

- **Canonical axis order:** x fastest, then y, then z. Grid linear index
  `I = x + y*nx + z*nx*ny`. (flow, block_decomposer already use this.)
- **Cell-centred vs staggered:** scalar fields (pressure, SDF, density) live at cell centres
  `(i+½, j+½, k+½)·spacing`. Staggered velocity components:
  `u` at `(i, j+½, k+½)`, `v` at `(i+½, j, k+½)`, `w` at `(i+½, j+½, k)`. (MAC grid — flow.)
- **Periodic wrap:** `wrap(x, N) = (x % N + N) % N`. Applies to grid indices and particle images
  alike. (Shared across flow, dem, voronoi, block_decomposer.)
- **Lees–Edwards shear:** an x-shift proportional to a y-offset, `xshift = shear · Ly / Lx`, applied in
  the shortest-image computation. (voronoi `BoxLE`.)

## 2. SDF (signed distance) convention

- **Sign:** `sdf < 0` inside solid, `sdf > 0` in fluid/void, `sdf = 0` on the surface.
- **Outward normal:** `n = ∇sdf / |∇sdf|` points *into the fluid* (out of the solid).
- **Sources:** analytic primitives (sphere, hollow cylinder, …) and grid SDFs interchangeably behind
  one descriptor (see [INTERFACES](INTERFACES.md) `SdfGeometry`). A scaled shape evaluates as
  `dist = sdf_canonical(p / scale) · scale`. (dem point-shell convention.)
- **I/O:** grid SDFs and fields exchange via **VTI**; particle/point data via **VTP** (ParaView/Ovito).

## 3. Numeric precision policy

Precision is chosen per role, not globally — but stated explicitly so codes match:

- **Eulerian field state** (pressure, velocity carried across projection/implicit solves): **double**.
  (flow state is double; temporaries may be float.)
- **GPU particle state** (positions, velocities, quaternions in hot SoA kernels): **float**.
  (dem.)
- **Header-only / CPU generic code:** template on `real_t` with a sensible default; pick `double` for
  accuracy-sensitive tests. (voronoi.)
- **The shared core is precision-agnostic:** decomposition/halo/geometry are templated on the payload
  type and never hard-code float vs double.

## 4. Type aliases

To stop every code inventing its own, the core `common` module defines (host side):

- `peclet::core::Real` — **`double`**, a fixed alias (`common/types.hpp`), not a build option. Where a code
  stores a *float* for speed it says so per role: flow's multigrid operator storage is `MReal = float` unless
  built with `-DPECLET_FLOW_MREAL_DOUBLE` ([SCALING_ISSUES.md](SCALING_ISSUES.md) #1 — dense beds need the
  double build), and core's ghost-projection closure weights (`scheme/ghost_closure.hpp`,
  `amr/ghost_projection.hpp`) are float by design. Turning these into typed CMake options is
  [QUALITY_PLAN.md](QUALITY_PLAN.md) G.6.
- `peclet::core::Index` — signed index type for grids/particles (`std::int64_t`; supersedes block_decomposer's
  `long int IndxT`).
- `peclet::core::Vec<Dim>` = `std::array<Real, Dim>`; `peclet::core::IVec<Dim>` = `std::array<Index, Dim>`.
- On the GPU/CUDA side, continue to use the built-in `float3`/`int3`/`float4` vector types; provide
  thin converters to/from `peclet::core::Vec`/`peclet::core::IVec` at the host boundary rather than forcing one type
  across the language boundary.

Current divergence to reconcile: voronoi's `uint0/uint1/uint2` (8/16/32-bit) are *internal* topology
labels and stay local to voronoi; they are not suite-wide types.

## 5. Domain & decomposition conventions

- The **global domain** is an axis-aligned box `[origin, origin + L)` with per-axis periodicity flags
  `std::array<bool, Dim>`.
- Decomposition partitions the **global cell grid** (Eulerian) or the **global box** (Lagrangian) into
  rank-owned **blocks** via orthogonal recursive bisection; one block per MPI rank by default.
- Each block carries a **ghost layer** of configurable width. Ghost identification (topology) is
  recomputed only on (re)build; the per-step exchange reuses it. See [INTERFACES](INTERFACES.md).

## 6. Python binding conventions

- **Mechanism:** **nanobind** for every compiled solver (`peclet.flow`, `peclet.pnm`, `peclet.dem`,
  `peclet.core.{mpi,amr,geom}`, `peclet.voro`, `peclet.coupling`'s kernels), built through **scikit-build-core**. nanobind is
  chosen over pybind11 because its `nb::ndarray` carries a DLPack device tag and arbitrary strides,
  which is what makes the zero-copy GPU path below possible. morton's lightweight ctypes/C-ABI shim
  stays as is (dependency-free by design, ships portable PyPI wheels) — the deliberate exception.
- **The array bridge:** all Kokkos-backed modules cross the C++/Python boundary through one shared
  header, `peclet::core::python` (`core/include/peclet/core/python/ndarray_interop.hpp`), provisioned via
  `cmake/SuiteNanobind.cmake`. Do **not** re-hand-roll per-module copy helpers.
  - `view_to_ndarray(View)` exports a Kokkos View **without copying**: a host View becomes a NumPy
    array referencing the View's memory; a device (CUDA/HIP) View becomes a DLPack array CuPy/PyTorch
    consume zero-copy (`cupy.from_dlpack(...)`). Lifetime is held by a capsule owning a copy of the
    (ref-counted) View. `vector_to_ndarray(std::move(v), …)` does the same for a host `std::vector`.
  - `ndarray_to_view<T>` / `ndarray_to_vector<T>` import: a host array on a GPU build is staged up
    (`deep_copy`); a device array on the build's backend is wrapped unmanaged (CuPy → device View,
    zero-copy); an array on an incompatible device raises.
- **Host vs device array contract:** a NumPy (host) array passed to a GPU-backend solver is copied up
  with the existing semantics (so NumPy-only scripts keep working unchanged); a CuPy (device) array on
  the matching backend flows in/out copy-free. Mismatched device/dtype raises rather than silently
  staging a device array through the host.
- **Array shape/order:** Python sees grids as **Fortran-order `(nx, ny, nz)`** arrays: an x-fastest
  `peclet::core::Field3D` (LayoutLeft) exports with element strides `{1, nx, nx*ny}`, so `a[i, j, k]` is
  cell `(i, j, k)` and `a[:, 0, 0]` runs along x. `pnm` is the one documented exception
  ([NAMING.md](NAMING.md) §1.7): its arrays are the C-order `(nz, ny, nx)` a VTI hands over and every
  triple that describes them carries the `_zyx` suffix. A module ships one order, never both.
- **Particle arrays:** shape `(N, 3)` for vector quantities, `(N,)` for scalars, contiguous float/
  double matching the solver's precision.
- **Names:** one spelling per concept across the whole suite — the domain quartet
  `origin`/`extent`/`cells`/`spacing`, `num_*` counts, `periodic=`, `set_dt`, American spelling,
  and `get_` reserved for a call that actually transfers. [NAMING.md](NAMING.md) is the canon, the
  table of every current divergence, and the additive-alias rule for changing a shipped name.
- **Lifecycle:** `Solver(...)` construct → `initialize(...)`/`set_*` config → `step(dt)` → `get_*`
  accessors returning numpy arrays. Keep verb names identical across modules (`step`, `get_positions`,
  `get_u`, …). *`get_*` here means the array getters, which copy — it was never meant to make
  `get_spacing()` preferable to the `spacing` property; see [NAMING.md](NAMING.md) §1.2.* Kokkos is initialized at import and finalized via a Python **atexit** hook — this is
  required on CUDA (without it, Kokkos's device state is torn down by static destructors *after* the
  CUDA runtime unloads → `cudaErrorCudartUnloading` at exit). To avoid the opposite abort ("deallocated
  after `Kokkos::finalize`"), the hook first releases any live View-holding objects, then finalizes:
  modules with simulation objects keep a registry and do `releaseAll()` → `finalize()` (dem, voro,
  `peclet.core.amr`); modules whose objects are short-lived just `finalize()` (flow, pnm) and document that a
  Solver kept alive to interpreter exit must be released first (`del s`). Getters return host
  `vector_to_ndarray` arrays (no device Views), so they never block finalize; a zero-copy *device*
  export (`view_to_ndarray` to CuPy) must be released before exit. Build note: pass `NOMINSIZE` to
  `nanobind_add_module` for Kokkos modules — nanobind's default `-Os` is rejected by `nvcc`.

## 7. Units

**Consistent units, no dimension checking, and the caller never writes a cell size.** Every solver is
given a *physical domain* — a cell count, an extent and an origin — and derives its own spacing
(`peclet::core::UniformGrid`, `core/include/peclet/core/domain.hpp`). Material properties, time steps,
forces, boundary velocities, surface tension and geometry are stated in one self-consistent system of
the caller's choosing, and they do not change when the grid is refined. Nothing imposes SI and nothing
checks dimensions (decision D1 of [PHYSICAL_UNITS_PLAN](PHYSICAL_UNITS_PLAN.md)); a unit table in each
method's API reference does that job.

```python
s = flow.Solver((nx, ny, nz), extent=(Lx, Ly, Lz), origin=(0, 0, 0))
s.spacing            # derived: extent / cells — read-only, and the user never needs it
s.cell_centres()     # the coordinates an SDF or an initial field is sampled at
```

Omitting `extent` selects the historical **cell units** (spacing exactly 1, origin 0, every length in
cells) and is bit-identical to the pre-2026-09 solvers; it warns one release after the physical form
ships and is removed one release after that.

Internally the Eulerian solvers keep computing on the **unit lattice**: the metric is folded into
per-axis constants at operator assembly and into the conversions at the API boundary, with reference
scales (`h_ref`, `rho_ref`, `t_ref`) that keep every stored coefficient O(1) whatever unit system the
caller uses. Two consequences worth knowing: at `extent = cells` with `rho = 1` and `dt = 1` every
conversion is exactly 1.0, and **the raw field registry** (`field_view` / `get_field` / `set_field`)
hands out those internal arrays, unlike `get_u` / `get_p`, which convert — a solver exposes the factors
as `unit_scales` for the few drivers that need them.

**Anisotropic cells** (a different spacing per axis) are admitted since Phase 2 of the plan, single
phase, on both `flow` grid policies: `h_ref` is then `min_a h_a`, so the FINEST axis carries exactly
1 and every stored coefficient stays bounded by its isotropic value. Three spacings that agree to
1e-12 relative are snapped to one, so an isotropic domain stays bit-identical however its extent was
written. Geometric VoF on anisotropic cells is Phase 3.
