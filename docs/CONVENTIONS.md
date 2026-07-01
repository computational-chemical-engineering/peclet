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

- `peclet::core::Real` — default floating type alias (a build option; double on host, float on device kernels).
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

- **Mechanism:** **nanobind** for every compiled solver (flow + `pnm`, dem `dem`, core
  `tpx_mpi`/`tpx_amr`, voro's device module), built through **scikit-build-core**. nanobind is
  chosen over pybind11 because its `nb::ndarray` carries a DLPack device tag and arbitrary strides,
  which is what makes the zero-copy GPU path below possible. morton's lightweight ctypes/C-ABI shim
  stays as is (dependency-free by design, ships portable PyPI wheels) — the deliberate exception.
- **The array bridge:** all Kokkos-backed modules cross the C++/Python boundary through one shared
  header, `peclet::core::python` (`core/include/tpx/python/ndarray_interop.hpp`), provisioned via
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
- **Array shape/order:** Python sees grids as shape `(nz, ny, nx)`; round-trip to the C++ x-fastest
  layout with `numpy.reshape(..., order='F')` on `(nx, ny, nz)`. The bridge preserves this naturally:
  an x-fastest `peclet::core::Field3D` (LayoutLeft) exports as a Fortran-order `(nx, ny, nz)` array with element
  strides `{1, nx, nx*ny}`. Document it once per module and keep it identical across modules.
- **Particle arrays:** shape `(N, 3)` for vector quantities, `(N,)` for scalars, contiguous float/
  double matching the solver's precision.
- **Lifecycle:** `Solver(...)` construct → `initialize(...)`/`set_*` config → `step(dt)` → `get_*`
  accessors returning numpy arrays. Keep verb names identical across modules (`step`, `get_positions`,
  `get_u`, …). Kokkos is initialized at import and finalized via a Python **atexit** hook — this is
  required on CUDA (without it, Kokkos's device state is torn down by static destructors *after* the
  CUDA runtime unloads → `cudaErrorCudartUnloading` at exit). To avoid the opposite abort ("deallocated
  after `Kokkos::finalize`"), the hook first releases any live View-holding objects, then finalizes:
  modules with simulation objects keep a registry and do `releaseAll()` → `finalize()` (dem, voro,
  tpx_amr); modules whose objects are short-lived just `finalize()` (flow, pnm) and document that a
  Solver kept alive to interpreter exit must be released first (`del s`). Getters return host
  `vector_to_ndarray` arrays (no device Views), so they never block finalize; a zero-copy *device*
  export (`view_to_ndarray` to CuPy) must be released before exit. Build note: pass `NOMINSIZE` to
  `nanobind_add_module` for Kokkos modules — nanobind's default `-Os` is rejected by `nvcc`.

## 7. Units

Codes are dimensionless/consistent-unit: the caller supplies `spacing`, `L`, `rho`, `mu`, forces in a
self-consistent system; the core stores and moves values without imposing SI. Document the unit system
at the *method* level (each solver's README), not in the core.
