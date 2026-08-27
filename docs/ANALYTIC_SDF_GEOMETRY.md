# Analytic SDF Geometry — inventory & plan

> Status: design note (living), 2026-08-26. Goal: **one device-callable analytic-SDF layer** shared by
> `flow`, `dem` and `voro`, good enough to carry (a) high-accuracy IBM geometry in the CFD, (b)
> non-spherical DEM particles as analytic shapes, (c) static and moving objects (stirrers, drums,
> impellers), and (d) resolved CFD-DEM where a particle *is* an analytic SDF — on multithreaded CPU,
> GPU, and under MPI. Companion to [ARCHITECTURE](ARCHITECTURE.md), [CONVENTIONS](CONVENTIONS.md),
> [INTERFACES](INTERFACES.md), [MULTIPHYSICS_PLAN](MULTIPHYSICS_PLAN.md).
>
> **Design decisions 1 and 4 RESOLVED 2026-08-26** (§7): two-layer dispatch (compile-time leaves +
> runtime node/scene), and core-defined types with per-code ownership via a non-owning `SceneView`.
> §6 Layer 0 is now an executable spec (rungs + gates); an executor needs only this document.
> **Rungs 0-2 SHIPPED** (core `e5815b7`, `7f21d72`, `7da12f0`): leaves + `PECLET_HD`/`Vec3`, the
> runtime node layer (transforms, iterative CSG, grid leaf), and the extended vocabulary +
> gradients; **rungs 3-4 SHIPPED** (dem `638727e`, voro `fc7a6ad`) — dem's and voro's SDF layers
> now delegate to core, bit-identical on host-openmp and CUDA. Core 92/92, dem 8/8 (both backends)
> + 24/24 MPI, voro 10/11 (matching its pre-port baseline). **Measured exactness table in §6.1.**
> Next: rung 5 (scene encoding contract) — the last rung of Layer 0.
>
> `file:line` references are snapshots of the audit — **re-grep before acting**.

## Why this note exists

For high-accuracy IBM in `flow`, analytic SDFs beat sampled ones: exact wall crossings and exact face
apertures remove the O(h) / O(h²) geometric bias that the trilinear field imposes as a ceiling. But
today the CFD only *consumes* sampled grids, and the analytic accuracy it does get arrives as override
arrays computed in Python, single-rank. Meanwhile `dem` has a perfectly good device-side analytic SDF
evaluator that `flow` cannot use, and `voro` has a third one. This note inventories what exists, names
the gaps precisely, and proposes a dependency-ordered plan.

---

## 1. Inventory: three separate SDF stacks, none shared

| Where | Device-callable? | Analytic shapes | Sampled (grid) SDF | Consumers |
|---|---|---|---|---|
| `core/include/peclet/core/geom/sdf.hpp` | **No** — host-only (`double`, `std::vector`, no `KOKKOS_INLINE_FUNCTION`) | `Sphere`, `Box`, `HollowCylinder`, `Complement`, generic finite-difference `gradient()`, `Sdf` concept | `grid_sdf.hpp` → `GridSdf` + `sample()` baker; `vti_io.hpp` | nothing on-device — it is the *nominal* contract only |
| `dem/src/dem_portable.hpp:77-115` | Yes (Kokkos, all backends) | `sdfSphere` / `sdfHollowCylinder` / `sdfBox`, runtime dispatch `sdfEval(p, type, F4 params)` | `narrowphase.hpp:104` `sampleGridSdf` (canonical body space), `sampleWallSdf` (world space) | dem narrow-phase, Hertz force law, SDF export |
| `voro/include/peclet/voro/sdf.hpp` | Yes (Kokkos) | `SdfSphere`, `SdfBox`, `SdfHollowCylinder`, **`SdfSpheres`** (multi-object), compile-time provider template `class Sdf` | `SdfGrid` | voro cell clipping, mesh-optimizer wall force |

`flow` has **no SDF evaluator at all** — geometry only ever reaches it as an already-sampled field.

The core header states it exists so solvers "consume analytic and sampled geometry through one
interface". In practice `dem` and `voro` each re-implemented the same three primitives with
`KOKKOS_INLINE_FUNCTION`, and neither includes core's version. Removing that duplication is the
precondition for everything below.

### Sign convention (already consistent — keep it)

`sdf < 0` inside solid, `> 0` in fluid/void, gradient points outward. Holds in core, dem's shape SDFs,
voro, and flow's `set_solid`. One deliberate exception: `dem`'s **wall** SDF (`WallSdf`) is a
*container* — positive in the void where grains live, negative inside the wall — and its off-grid
extension **subtracts** the clamp residual where the object convention adds it
(`narrowphase.hpp` `sampleWallSdf`). That asymmetry is load-bearing (a grain pushed past the stored box
must read "deeper into wall", not "clear"); any unification must preserve it explicitly rather than
regularise it away.

### TRAP: the three stacks do not even agree on the hollow cylinder

Found during the design pass — consolidation is **not** purely mechanical:

- `dem`'s `sdfHollowCylinder` (`dem_portable.hpp:83-93`) is the **distance-exact** tube: 2-D box
  distance in the (r, y) cross-section, axis fixed to **y**, parameters (r_outer, h, thick).
- `core`'s `HollowCylinder` (`geom/sdf.hpp`) and `voro`'s `SdfHollowCylinder` (which ports it
  "verbatim") are the **max-of-halfspaces** form `max(r−rOuter, rInner−r, |z|−h/2)` — sign-exact but
  **not a distance** (wrong magnitude at edges/corners and inside the shell), axis-parameterised,
  parameters (rOuter, rInner, height, axis).

Same name, different function. dem's contact distances and voro's mesh-optimizer wall force would both
shift if either were silently swapped for the other. Layer 0 therefore ships **both forms** as
distinct primitives (see §6) and unification, if ever, is a later measured change.

---

## 2. `dem` — analytic SDF particles

**Analytic SDFs already are the primary collision path.** Contact detection is point-shell-vs-field:
body A's surface points are transformed into B's canonical frame and probed against B's SDF
(`narrowphase.hpp:208-265`, mirrored in `solver_hertz.hpp:520-545`). Analytic shapes evaluate in closed
form; a sphere is a single probe with a `pointRadius` shortcut (`numPoints == 0`). It runs on every
Kokkos backend, and `shapeId` is already carried across ranks by the migrator
(`mpi_halo.hpp:169, 216`).

So the answer to "can analytic SDFs be used for the particle, and is there efficient support?" is
**yes** — with these specific limits:

1. **One shape per simulation.** `P_.shapes` is a View and `shapeId` is per-particle
   (`particles.hpp:32, 279-286, 432`), but `shapeId(i)` is **never assigned** — it stays 0, and both
   `Simulation::initializeShape` (`sim.hpp:511`) and `setSdfShape` (`sim.hpp:597`) overwrite slot 0.
   There is no `set_shape_ids` binding. Per-particle `scale` is the only polydispersity available.
   *The infrastructure is ~90 % present; the shape table and its setter are what is missing.*
2. **Vocabulary is three primitives in a four-float blob.** `F4 params` caps a shape at four
   parameters — no ellipsoid, superquadric, capsule, cone, torus, rounded/offset shapes, no CSG, and no
   per-shape affine transform (only the per-particle quaternion + *isotropic* scale).
3. **Normals are 6-point central differences even for analytic shapes** (`narrowphase.hpp:235-241`;
   same in `solver_hertz.hpp:529-534`): **7 SDF evaluations per shell point per contact** where an exact
   analytic gradient costs 1. `eps = 1e-4` is hard-coded in canonical units, so accuracy degrades for
   features below that scale or for `scale` far from 1. This is the largest single efficiency item on
   the analytic path.
4. **Contact geometry is asymmetric** — A's shell against B's field, so the manifold depends on which
   body is A. Standard for this method, but it bounds achievable non-spherical accuracy.
5. **Point-shell generators exist only for cylinder and box** (`shapes_portable.hpp`
   `genCylinderShell` / `genBoxShell`). A new analytic shape has no shell; the fallback is
   marching-cubes via `packaging/particle_builder.py`.
6. **Static/moving objects exist — but grid-only.** `WallSdf` (`narrowphase.hpp:59-81`) is a
   world-space sampled field carrying a rigid-body surface velocity
   `v(x) = linVel + angVel × (x − center)` and its own binary material. **A rotating drum or stirrer
   therefore already works in dem today** — at voxel accuracy, with `wallGrid` fully replicated on every
   rank. `addPlane` covers half-spaces. There is no analytic wall variant.

### The existing DEM → CFD geometry bridge

`dem/src/output_sdf.hpp` `generateSdfKokkos` is physically the right thing: each particle splats its
**exact transformed analytic SDF** over its AABB band by `atomic_min`, then a Jacobi–Eikonal sweep fills
the far field, periodic-wrapped, on device, on any backend, in flow's sign convention. Exposed as
`get_sdf_grid` and described in the binding as "the get_sdf_grid pipeline for CFD".

Two things make it offline-only, plus one discrepancy worth fixing regardless:

- it returns a host `std::vector<float>` over the **whole domain** (`sim.hpp:1154`);
- it has **no MPI awareness**;
- the splat uses `scale(i)` **without `globalScale`**, unlike the narrow-phase, which folds
  `scale * globalScale` into every canonical↔world map. Any non-unit `global_scale` makes the exported
  SDF disagree with the simulated geometry.

---

## 3. `flow` — geometry is a sampled field, full stop

`Solver::setSolid(const std::vector<double>& sdfInner, bool cutcellPressure)` (`flow_ibm.hpp:709`),
bound to a **host** f-contiguous NumPy array (`flow_bindings.cpp:364`). Under MPI each rank passes its
local inner block and flow halo-exchanges the ghosts.

The analytic accuracy in use today is **override arrays computed in Python**, not analytic geometry in
the solver:

| Hook | What it overrides | Constraint |
|---|---|---|
| `setExactCrossings` (`flow_ibm.hpp:290`) | 9·nx·ny·nz exact wall-crossing fractions θ, in both the momentum cut-cell overlay and the ghost-projection closures | **single-rank only** (`flow_ibm.hpp:300`) |
| `setOpennessOverride` (`flow_ibm.hpp:316`) | exact face apertures feeding the cut-cell projection | **single-rank only** (`flow_ibm.hpp:327`) |
| `setApertureOrder(2)` (`flow_ibm.hpp:484`) | in-solver marching-squares apertures, O(h²) | ceilinged by the trilinear field |

Producer: `flow/scripts/exact_apertures_spheres.py` — NumPy, **spheres only**; its own docstring names
Saye implicit quadrature (SIAM J. Sci. Comput. 37(2), 2015) as the general answer and states it is not
implemented.

Three hard constraints follow:

- both override hooks are **single-rank**, so the most accurate geometry path cannot be used in any
  distributed run;
- both **disable the AUTO collocated scheme**, forcing the gauge-exact fallback
  (`flow_ibm.hpp:720`, on `hasExactCross_ || hasOpenOverride_`). Today "exact analytic apertures"
  and "the shipped ghost-projection default" are mutually exclusive;
- the geometry is produced host-side in Python, so it cannot participate in a per-step device pipeline.

### Moving boundaries: machinery built, not connected

`ibmModifyStencil` already takes a wall velocity and accumulates `Nbc · u_bc · vnb` into the row
inhomogeneity (`cut_cell_ibm.hpp:289, 309`) — and **every call site passes a hard-coded `0.0f`**
(`flow_ibm.hpp:1561, 1968, 2015`). The ghost projection computes and stores the `w_bc` weights, then
drops them: *"u_bc = 0 (v1); w_bc kept in the overlay for moving walls"* (`ghost_projection.hpp:35,
316-317`).

What is genuinely absent:

- a per-cut-face wall-velocity **field** rather than one global scalar;
- the **pressure-side wall flux** — the cut-cell divergence constraint assumes `∮ u_w·n dA = 0`, which
  is false for any moving body.

### Cost of changing geometry

`setSolid` re-derives openness, the IBM overlay, the momentum stencils, and the **entire cut-cell MG
hierarchy including the graph-AMG bottom**, on top of a device→host→device round trip of an
`nx·ny·nz` float64 array. Acceptable once; **not** a per-timestep operation. This is the dominant cost
barrier for any moving object.

---

## 4. `coupling` — unresolved only, and shape-blind

`peclet.coupling` is wall-aware trilinear P2G/G2P (`core/interp/particle_grid.hpp`), the drag laws, and
the implicit-β feedback. Every closure in `coupling/src/drag.hpp` takes a **single scalar radius `r`**
and uses `Vp = 4/3 π r³` — no sphericity, no aspect ratio, no orientation, no equivalent diameter.

So "non-spherical particles in unresolved CFD-DEM" today means: `dem` simulates a non-spherical grain,
and the fluid sees a sphere of the radius handed to the driver. Nothing in the exchange is shape-aware.

---

## 5. Gap summary

| Capability | Today | Gap |
|---|---|---|
| Device-callable analytic SDF | dem + voro, duplicated; core host-only | one shared `core` layer, `Real`-templated, exact gradients |
| Shape vocabulary | sphere / box / hollow cylinder, 4 params | ellipsoid, superquadric, capsule, cone, torus, rounding, CSG, affine transform |
| Analytic gradient | none — 6-point FD everywhere | exact `grad()` beside `eval()`; FD only for grid fields |
| Mixed shapes in one DEM run | impossible (`shapeId` always 0) | fill the shape table + `set_shape_ids` / `add_shape` |
| Analytic static/moving object | grid-only `WallSdf` (works, voxel-accurate, replicated) | analytic wall provider + CSG scene |
| Analytic geometry in the CFD | Python override arrays, spheres, single-rank | device-resident scene; in-solver exact crossings + apertures; Saye quadrature for general shapes; MPI-capable |
| Moving wall BC in the CFD | `u_bc` hard-coded 0; `w_bc` computed and discarded | per-face wall-velocity field + pressure-side wall flux |
| Geometry update cost | full openness + overlay + MG rebuild, host round trip | incremental rebuild over changed cells; device `set_solid` overload |
| Resolved CFD-DEM | absent | shared scene, hydrodynamic force/torque integration, geometry halo |
| Shape in unresolved closures | absent (scalar radius) | sphericity / equivalent diameter / orientation-aware drag |

---

## 6. Plan — five layers, dependency-ordered

Each layer is independently useful and independently shippable.

### Layer 0 — one device-callable SDF library in `core` (SPEC — decisions resolved, ready to execute)

The keystone; everything else is a consumer. The architecture is **two layers over one set of
formulas** (resolved decision 1, §7):

```
  compile-time LEAVES            runtime NODES / SCENE
  ------------------            ----------------------
  Sphere<Real>, Box<Real>,      ShapeNode<Real>  (tagged union: kind + params + transform
  HollowCylinder<Real>, ...       + child indices for CSG)  — stored in Kokkos Views
  eval() + grad(), PECLET_HD    SceneView<Real>  (non-owning bundle: node table, pools,
  = the ONLY formula bodies       instance arrays)          — evaluated by switch → leaf calls
     ▲                              ▲
     │ voro provider template       │ dem shapes View, flow scene, resolved CFD-DEM
```

The leaves are the single source of truth; the runtime layer contains **no formulas**, only dispatch.
voro keeps its zero-overhead compile-time path; dem and flow get the runtime scene their
Python-driven heterogeneity requires (dem already pays a per-probe `switch` in its hottest kernel
today — few distinct shapes per run makes it warp-coherent).

**New headers** (content-based names — no `Device*`/`*Kokkos` names, per the suite naming rule):

- `core/include/peclet/core/common/portable.hpp` — `PECLET_HD` macro **and** a device-safe
  `Vec3<Real>`. Copy the three-branch structure of morton's `MORTON_HD`, which lives in
  **`morton/include/morton/hd.hpp:21-29`** (not `kokkos.hpp`, which only documents it):
  `KOKKOS_FUNCTION` under `MORTON_ENABLE_KOKKOS && KOKKOS_VERSION` → `__host__ __device__` under
  `__CUDACC__ || __HIPCC__` → empty otherwise, the whole thing wrapped in `#if !defined(...)` so a
  build can override it. Use `KOKKOS_INLINE_FUNCTION` rather than `KOKKOS_FUNCTION` for the Kokkos
  branch (these are header-only templates that must inline). This keeps the geometry usable in
  host-only core builds (core's Kokkos is per-header opt-in — see `common/view.hpp`).

  **`Vec3<Real>` must be new — do not reach for `core::Vec<3>`.** `common/types.hpp:26` defines
  `Vec<Dim> = std::array<Real, Dim>` with `Real` a **fixed `double` typedef** (`types.hpp:18`), so it
  is neither `Real`-templated nor a natural device type. Define a plain POD
  `template <class Real> struct Vec3 { Real x, y, z; };` — this is exactly what dem's `F3` becomes,
  and what voro's loose `Real x, y, z` parameters collapse into.
- `core/include/peclet/core/geom/primitives.hpp` — the leaves. `Real`-templated POD structs with
  `PECLET_HD Real eval(Vec3<Real>)` and `PECLET_HD Vec3<Real> grad(Vec3<Real>)`, over the `Vec3`
  from `portable.hpp`; C++17-clean (CUDA TUs), matching `types.hpp`'s own C++17 pledge.
- `core/include/peclet/core/geom/scene.hpp` — `ShapeNode<Real>`, grid descriptors, instance records,
  `SceneView<Real>`, the node evaluator, host-side `SceneBuilder`.

The existing `geom/sdf.hpp` / `grid_sdf.hpp` stay as the host concept + I/O; their `eval` bodies
delegate to the `double` leaf instantiations (no behaviour change to host consumers).

**Binding contracts (each with its reason — do not re-derive):**

1. **Transforms are conformal only** — translation + quaternion + *isotropic* scale, on nodes and
   instances (identity default). Non-uniform scaling destroys the signed-distance property
   (`d_world = s · d_canonical` holds only for conformal maps). Anisotropy lives in primitive
   parameters (ellipsoid semi-axes, box half-extents). This is also exactly dem's existing
   `scale × globalScale` contract, so the dem port is faithful by construction.
2. **Exactness is a per-primitive annotation.** Exact distance: sphere, box, capsule, torus,
   `HollowCylinder` (dem form). Sign-correct **lower bound** only: ellipsoid, superquadric, CSG
   min/max near edges, smooth-union everywhere. Consumers needing wall crossings must bracket +
   root-find on `eval` along the segment (needs only sign correctness) — never assume metric
   exactness. This keeps the whole vocabulary usable for flow's exact-crossing path (Layer 2).
3. **Canonical frames are adopted from dem verbatim** (hollow cylinder about **y**). Canonicalising
   to z would insert a rotation whose float rounding breaks the bit-exact dem port. Documented wart;
   new orientations go through the transform.
4. **Both hollow-cylinder forms ship as distinct primitives**: `HollowCylinder` (distance-exact, dem
   form) and `HollowCylinderShell` (max-of-halfspaces, core/voro form) — see the §1 trap. Each
   consumer's port keeps its own numerics unchanged; unification is a later, deliberate, measured
   change.
5. **CSG is a flat node array with child indices**, evaluated iteratively with a fixed-depth explicit
   stack (cap ~16; no device recursion). A stirrer = shaft cylinder ∪ transformed blade boxes — a
   handful of nodes. `ShapeNode` params: fixed inline `Real params[8]` (superquadric ≈ 7 is the max)
   plus two int aux slots (CSG children / grid-descriptor index).
6. **The grid SDF is one more leaf**, referenced by descriptor (dims, origin, inverse spacing, pool
   offset) into a shared sample pool — generalising dem's `ShapeDesc` grid fields — with the
   **object/container off-grid extension policy as an explicit enum** on the descriptor (+residual =
   object, −residual = container; the `sampleGridSdf` / `sampleWallSdf` asymmetry of §1 becomes a
   named policy, not two divergent functions).
7. **An instance is `{shapeRoot, transform, linVel, angVel, center, materialId}`** — dem's per-particle
   (pos, quat, scale, shapeId) maps onto it directly, and it generalises `WallSdf`'s rigid-body
   surface-velocity field to *every* object, which is what Layer 3's moving-wall BC and Layer 4's
   resolved coupling need.
8. **Precision:** leaves are `Real`-templated; dem instantiates **float** (bit-exact port), flow
   **double**. Cross-precision happens at the `SceneView` boundary (a double consumer reading a
   float-authored scene computes in double — the established coupling-kernel pattern).
10. **The leaves live in `peclet::core::geom::prim`, not `peclet::core::geom`** (found in rung 0).
   `geom/sdf.hpp` already owns non-template host shapes named `Sphere`, `Box`, `HollowCylinder` and
   `Complement`, and `refineToSdf` / the AMR + diffusion tests / the VTI path depend on them — so the
   templated leaves collide unless nested. The host shapes stay as the host-facing concept layer and
   **delegate into `prim`**; rungs 3-4 port dem and voro onto `geom::prim::*`. The shell leaf also
   exposes `evalRZ(r, z)` so an axis-parameterised wrapper can permute coordinates and reuse the body
   (this is how `geom::HollowCylinder` keeps its `axis` parameter with no formula of its own).
9. **Scene queries take per-cell candidate lists** (from AABB binning — the `generateSdfKokkos`
   band-splat pattern), not a hard-wired min-over-all-instances, so acceleration is pluggable when
   N_instances × N_cells grows. (The binning itself is a Layer 2 deliverable; Layer 0 only fixes the
   API shape.)

**Rung ladder (commit per rung; every rung ends green):**

- **Rung 0 — leaves, faithfully. ✅ DONE** (core `e5815b7`).
  Extract dem's `sdfSphere` / `sdfBox` / `sdfHollowCylinder` + voro/core's shell form into
  `primitives.hpp` as `Real`-templated structs, formulas byte-faithful to
  `dem_portable.hpp` (the CUDA-heritage reference). Gate: new core ctest comparing `float` leaves
  against the dem originals **bit-exact** over a point cloud (inside/outside/edge/corner), `double`
  leaves against `geom/sdf.hpp` where formulas coincide; host-only build still compiles (no Kokkos).
  *Outcome:* 6216 points bit-exact (lattice + feature points + deterministic pseudo-random tail);
  `geom/sdf.hpp` rewired to delegate; a guard test asserts the two cylinder forms still disagree off
  the rim; core 90/90 ctests np 1-8; leaves separately compiled and run inside a Kokkos
  `parallel_for` (host-openmp) with device result == host result. The bit-exact oracle is a verbatim
  transcription of `dem_portable.hpp:79-103` into the test — the cross-check against dem's own
  compiled code is rung 3's gate.
- **Rung 1 — node layer + grid leaf. ✅ DONE** (core `7f21d72`).
  `ShapeNode`, transform stack, iterative CSG eval, grid-descriptor leaf with both extension
  policies. Gate: node-wrapped single primitives == direct leaf calls bit-exact; CSG stirrer
  fixture vs brute-force composed eval; grid leaf reproduces `sampleGridSdf` and `sampleWallSdf`
  bit-exact on their own fixtures.
  *Outcome:* all four met (3000 pts x 4 kinds bit-exact; stirrer depth 3 to 1e-14; 5000 grid probes
  with 4723 off-box). Added beyond spec: malformed-scene hardening (bad index / over-depth -> 1e9),
  and `ShapeKind`'s first four values pin dem's numbering so its Python `shape_type` integers
  survive rung 3 with no remap table (static_assert in the gate). Verified on **nvidia-cuda** as
  well as host-openmp — device results bit-identical to host, which is what clears `evalTree`'s
  on-stack frame array for device use.
- **Rung 2 — extended vocabulary + exact gradients. ✅ DONE** (core `7da12f0`).
  Ellipsoid, superquadric, capsule, cone, torus, rounded/offset; closed-form `grad` where it exists,
  generic FD fallback otherwise. Gate: a-priori property tests — sign correctness on analytic
  inside/outside sets, `|∇f| ≈ 1` sampled for distance-exact primitives, `grad` vs FD to tolerance,
  lower-bound property (`eval ≤ true distance`, Monte-Carlo) for the bound-only primitives.
  *Outcome:* all met; measured table in §6.1. Two defects the gate caught — a superquadric centre
  singularity (Lipschitz **779**, estimates 4× too deep; fixed by clamping at the inradius → 0.752)
  and a wrong rounded-box surface sampler in the gate itself (eikonal 4e-9 against metric 0.10 is
  what exposed that the field was right and the sampler wrong). One assertion was wrong rather than
  one leaf: 1-Lipschitz is a theorem about *true distances*, so it is now asserted only for
  `exact_distance` leaves and measured for the rest.
- **Rung 3 — dem port (relocation only). ✅ DONE** (dem `638727e`).
  Re-express `dem_portable.hpp`'s SDF section and `narrowphase.hpp`'s two samplers over the core
  leaves; **keep the FD normal path and every formula bit-identical**. Gate: full dem ctest suite
  (host + CUDA), 24 MPI ctests, plus a **bit-capture oracle** (76 000 evaluations run before the
  port and compared byte-for-byte after, on both backends) — sharper than the ctests, which carry
  tolerances.
  *Outcome:* byte-identical on host-openmp and CUDA; dem 8/8 both backends, 24/24 MPI; `sim.hpp` +
  `output_sdf.hpp` compiled and run in a standalone TU (the module build needs nanobind, absent
  locally). **The two grid samplers collapsed onto one core routine with the extension policy as a
  named setup-time field** — contract 6 realised.

  > **TRAP for future ports — descriptor marshalling moves CUDA results.** The first attempt built
  > a core `GridDesc` from dem's loose fields *inside* the sampler. Analytic leaves stayed
  > bit-exact, but 526/8000 CUDA grid samples moved ~1 ULP (max rel 1.4e-4, concentrated where
  > `val + residual` cancels). Bisecting seven variants in one kernel cleared the math shims, the
  > named-residual + ternary ending, and the cast in the `at` lambda; the cause was the extra
  > in-function setup shifting **nvcc's FMA contraction** in the trilinear chain. Fix: `ShapeDesc`
  > and `WallSdf` now *carry* a `GridDesc<float>`, filled once at setup. Build descriptors at
  > setup, never per call, in any hot kernel this layer touches.
- **Rung 4 — voro port (relocation only). ✅ DONE** (voro `fc7a6ad`).
  voro's leaf structs delegate to core's (`SdfHollowCylinder` → `HollowCylinderShell`, preserving its
  max-form numerics). Gate: voro ctests; clang-format clean.
  *Outcome:* byte-identical on host-openmp AND CUDA **first attempt** (84 000-word capture covering
  the three analytic providers over all three cylinder axes, the shared central-difference gradient,
  plus `SdfSpheres`/`SdfGrid` to prove the un-ported providers were untouched). voro ctests 10/11,
  exactly the pre-port baseline — the single failure (`test_voro_python`) is **pre-existing and
  unrelated**: the repair-stats dict gained `extra`/`surgical`/`verify_passes` and the test's strict
  set-equality was never updated. clang-format 18.1.8: 22 violations before, 22 after — zero
  introduced (all pre-existing unicode-in-comment lines).
  **`SdfGrid` deliberately NOT ported** — it is a different function from core's `sampleGrid`: it
  stores *spacing* and divides where `sampleGrid` stores the inverse and multiplies
  (`a/s ≠ a·(1/s)`), and it clamps flat off-grid where `sampleGrid` applies a signed residual.
  Unifying needs a third `GridExtension` policy (`kClamp`) plus a divide-form option — a deliberate
  numerics change, not a relocation. `SdfSpheres` is a composite, not a leaf.

  > **Note on the rung-3 FMA trap:** it did *not* recur here. voro's providers build tiny value-type
  > leaves from already-loaded members with no long contraction chain, unlike dem's per-call
  > descriptor marshalling into a trilinear sum. The trap is specific to constructing a
  > multi-field descriptor inside a hot kernel, not to delegation as such.
- **Rung 5 — scene encoding contract.** Document the flat node/instance array encoding (the
  Python-facing composition format) + host `SceneBuilder`; core ctest round-trips build → evaluate.
  Per-code bindings that *accept* the encoding are Layers 1–2.

> **Migration discipline** (the suite's faithful-port rule): rungs 3–4 are relocations with bit-exact
> gates. Any numerics improvement (exact normals in contacts, unified hollow cylinder) lands *after*,
> as its own attributable change. Otherwise every regression moves at once and nothing is
> attributable.

#### 6.1 Measured leaf properties (rung-2 gate, `ctest geom_properties`)

Re-run the gate to regenerate; these are measurements, not targets.

| Leaf | `exact_distance` | eikonal err | Lipschitz | `eval` / true distance |
|---|---|---|---|---|
| `Sphere` | ✅ | 5.4e-10 | 1.000 | [0.992, 1.000] |
| `Box` | ✅ | 1.5e-08 | 0.999 | [0.994, 1.000] |
| `HollowCylinder` (dem form) | ✅ | 7.3e-10 | 0.999 | [0.993, 1.000] |
| `Capsule` | ✅ | 5.4e-10 | 1.000 | [0.991, 1.000] |
| `Torus` | ✅ | 5.6e-10 | 1.000 | [0.996, 1.000] |
| `Cone` (frustum) | ✅ | 7.6e-10 | 0.999 | [0.997, 1.000] |
| `Rounded(Box)` | ✅ (inherited) | 3.8e-09 | 0.999 | [0.981, 1.000] |
| `HollowCylinderShell` | ✗ bound | — | 1.000 | **[0.709, 1.000]** |
| `Ellipsoid` | ✗ bound | — | **1.026** | **[0.765, 0.999]** |
| `Superquadric` (e=4) | ✗ bound | — | 0.752 | **[0.239, 0.801]** |

Three facts Layer 2 must build on:

1. **Every bound-only leaf UNDER-estimates** (ratio ≤ 1). That is the safe direction: a conservative
   step never jumps the surface. It was measured, not assumed.
2. **The superquadric is safe but loose** far from the surface (down to 0.24× the true distance).
   Fine for sign-based bracketing; a poor stepping oracle. Near the surface it is first-order exact.
3. **`Ellipsoid` is not 1-Lipschitz (1.026).** Sign-based bracket-and-root-find is fine; naive
   sphere-tracing is not guaranteed. Prefer `Sphere` under a conformal transform whenever the body
   is genuinely a sphere — that path is exact.

### Layer 1 — `dem` consumes it

- Fill the shape table; expose `add_shape` / `set_shape_ids` → mixtures of **shapes**, not just sizes
  (keep the existing Python `shape_type` integer values 0–3 stable at the binding).
- Switch analytic normals to exact gradients: 7 evaluations → 1 per probe (**measured change**, after
  Layer 0 rung 3's bit-exact relocation).
- A general point-shell generator driven by the SDF itself (so a new primitive needs no bespoke
  generator).
- An **analytic wall** variant: a stirrer becomes a scene instance (CSG expression + rigid-body
  velocity) rather than a voxel grid — removes the per-rank replicated `wallGrid` and its
  resolution-bound accuracy.
- Fix the `globalScale` omission in the `generateSdfKokkos` splat.

### Layer 2 — `flow` consumes it

Where the CFD accuracy motivation lands. Give `flow` a device-resident **scene** (a `SceneView` it
owns, rank-replicated — see decision 4, §7) and derive geometry *in-solver* instead of importing
arrays from Python:

- exact wall crossings and exact apertures computed on device from the analytic scene — which by
  construction removes both the single-rank restriction and the AUTO-scheme incompatibility that the
  current Python override path carries (a replicated static scene needs **zero** new communication:
  every rank evaluates over its own block);
- crossings via bracket + root-find on `eval` along each stencil segment (exactness annotation,
  contract 2) — exact for spheres, sign-robust for every primitive;
- for general (non-sphere) apertures this is where **Saye-style high-order implicit quadrature**
  belongs — the general replacement for `exact_apertures_spheres.py`;
- the per-cell candidate binning of contract 9 (band-splat over instance AABBs);
- a `set_solid` overload taking a device View, so geometry never round-trips through the host.

### Layer 3 — moving geometry

Two pieces, one small and one large:

- **Kinematic BC (small).** Replace the scalar `u_bc_val` with a per-cut-face wall velocity evaluated
  from the instance velocity record (contract 7), and connect the `w_bc` weights the ghost projection
  already computes. Add the wall-flux source `∮ u_w·n dA` to the cut-cell divergence constraint.
- **Incremental rebuild (large).** `setSolid` needs a path that touches only cells whose openness
  actually changed and re-derives the MG hierarchy incrementally. Without it, a stirrer costs a full
  hierarchy build every step. **Measure the actual per-step rebuild cost before committing to a
  design** — this is the biggest single engineering item in the note and deserves a prototype first.

### Layer 4 — resolved CFD-DEM

Once 0–3 exist this is mostly composition:

- the dem particle scene **is** the flow geometry scene — dem adapts its SoA into a `SceneView`
  (decision 4) and hands it to flow zero-copy on the same device; no rasterization step;
- particle rigid-body velocities feed the Layer-3 wall BC through the instance velocity record;
- the fluid returns hydrodynamic force and torque by integrating stress over each object's cut faces —
  a new kernel, but a local one;
- `generateSdfKokkos` demotes to a fallback / visualisation path rather than the bridge.

**MPI is the real constraint here.** `flow`'s block decomposition and `dem`'s particle ORB are
independent, so a particle straddling a fluid block boundary must be visible to **every rank owning a
cut cell it touches** — a *geometry halo* distinct from both the grid halo and the particle halo.
With decision 4 this reduces to shipping **instance records** (transform + shapeId + velocity; the
shape tables are already replicated) to ranks whose block overlaps the instance AABB — a
`gatherGhosts`-style predicate over small PODs, naturally a `core` facility (see open decision 3).

### Orthogonal (does not block the above)

Shape-aware **unresolved** closures: sphericity / equivalent diameter / orientation-dependent drag in
`coupling/src/drag.hpp`, so non-spherical grains are non-spherical to the fluid as well.

---

## 7. Decisions

### Resolved (2026-08-26)

1. **Dispatch style — RESOLVED: two layers, not either/or.** Compile-time leaf primitives (POD,
   `Real`-templated, `eval` + `grad`, `PECLET_HD`) are the single source of the formulas; a runtime
   tagged-union `ShapeNode`/`SceneView` layer is built on them and contains no formulas of its own.
   Runtime is the primary interface for `flow`/`dem` scenes; the compile-time provider path stays
   primary for `voro`'s inner loops. *Why:* the formulas are pure functions with no reason to know
   about dispatch; the heterogeneity in dem/flow is runtime data (Python-composed scenes, per-particle
   shape ids) that no template can express; the per-probe `switch` is already paid in dem's hottest
   kernel today and is warp-coherent (few distinct shapes per run); flow's geometry derivation is
   setup-phase, where dispatch cost is irrelevant. Sub-decisions (conformal transforms, exactness
   annotations, canonical frames, dual cylinder forms, flat CSG, grid-leaf policy enum, instance
   record, precision) are binding contracts 1–9 in §6 Layer 0, each with its rationale inline.
4. **Where the shape table lives — RESOLVED: core defines the types and kernels; ownership stays with
   the method code; sharing is a non-owning `SceneView`.** dem *adapts* its existing SoA into a
   `SceneView` (zero-copy, same device); flow owns a small one for static scenes; resolved CFD-DEM is
   dem handing its `SceneView` to flow. *Why:* the suite architecture (methods stay separate, Python
   composes) forbids a shared scene *object* coupling dem's migrating SoA to flow's block-resident
   state — and Layer 4 only needs the *representation* shared, not the ownership. The MPI story falls
   out: node/shape tables are KBs → always rank-replicated; static scenes (stirrer, container) are
   replicated instances with **zero** new communication, so Layer 2 removes flow's single-rank
   restriction immediately; only particle-instanced scenes (Layer 4) need the geometry halo, and it is
   then a small exchange of instance PODs.

### Open

2. **Resolved coupling discretisation.** Reuse the existing cut-cell IBM for moving bodies, or a
   distinct sharp-interface treatment? This decides how much of Layer 3 must be built and how general
   the incremental-rebuild path has to be.
3. **Geometry-halo ownership.** Decision 4 tilts this firmly toward `core` (the halo is a
   `gatherGhosts`-style predicate over instance records, beside `GridHalo` and `ParticleMigrator`),
   but it is a Layer 4 item — settle it when Layer 4 starts, and revisit only if Layer 2's scene API
   turns out to need it earlier.
