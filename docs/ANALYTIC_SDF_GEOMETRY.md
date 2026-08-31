# Analytic SDF Geometry — inventory & plan

> Status: design note (living), 2026-08-26. Goal: **one device-callable analytic-SDF layer** shared by
> `flow`, `dem` and `voro`, good enough to carry (a) high-accuracy IBM geometry in the CFD, (b)
> non-spherical DEM particles as analytic shapes, (c) static and moving objects (stirrers, drums,
> impellers), and (d) resolved CFD-DEM where a particle *is* an analytic SDF — on multithreaded CPU,
> GPU, and under MPI. Companion to [ARCHITECTURE](ARCHITECTURE.md), [CONVENTIONS](CONVENTIONS.md),
> [INTERFACES](INTERFACES.md), [MULTIPHYSICS_PLAN](MULTIPHYSICS_PLAN.md).
>
> **Design decisions 1 and 4 RESOLVED 2026-08-26** (§8): two-layer dispatch (compile-time leaves +
> runtime node/scene), and core-defined types with per-code ownership via a non-owning `SceneView`.
> §6 Layer 0 is now an executable spec (rungs + gates); an executor needs only this document.
> **Rungs 0-2 SHIPPED** (core `e5815b7`, `7f21d72`, `7da12f0`): leaves + `PECLET_HD`/`Vec3`, the
> runtime node layer (transforms, iterative CSG, grid leaf), and the extended vocabulary +
> gradients; rungs 3-4 (dem `638727e`, voro `fc7a6ad`) delegating both consumers to core; the
> grid-SDF consolidation (§6.0); and **rung 5** (core `789d2ea`) — the scene encoding contract.
> **LAYER 0 IS COMPLETE.** Core 93/93, dem 8/8 both backends + 24/24 MPI, voro 12/12.
> **LAYER 1 COMPLETE** (dem `e90a5d1`, `9b1de61`, `eb8de1c`, `608916b`, `7edb05d`; core `a78d0f0`).
> **LAYER 2 (flow) largely SHIPPED** (flow `553524b`, `0706196`): device scene via core
> SceneQueryDevice, native periodicity, in-solver exact crossings (staggered AND collocated
> placement). **MPI scene demo DONE 2026-08-30** (gated at np = 1, 2, 4: k identical, per-rank cut
> ownership exactly the single-rank field restricted to the block — see Layer 4 rung 4, which the
> same gate closes). **Quadrature apertures DONE 2026-08-30** in core `geom/quadrature.hpp` (§6.4):
> face apertures to 4e-12 mean against the closed form, against 4e-02 for the sampled-SDF linear
> estimator, explicitly NON-CERTIFIED. Still open: the AUTO-guard relaxation, and wiring the
> quadrature apertures into flow's openness.
> **LAYER 3 (moving geometry) COMPLETE 2026-08-30** — cut ownership, kinematic wall velocity in the
> momentum operator, the wall's own volume flux in the projection, and the moving-step driver
> (core `318d651`, `81a3f7c`; flow `1b00405`, `7f87b21`). Opt-in throughout: the fingerprint
> `u_sum 6.74193610583927948e+05` is bit-identical with no moving instance. **Galilean gate passes**
> — `u_B + V == u_A` to 2.3e-05 (N=32, 260 steps), 2.6e-06 (800 steps), 6.3e-06 (N=64 CUDA), while
> the same runs with the wall-flux term off sit at 2.2e+00 and do not converge. **Rotlet order 1.97
> then 1.51** once measured against a trustworthy reference. A full per-step geometry rebuild costs
> **9.3 ms at 64³ / 37.0 ms at 128³ on an RTX 5080 — 1.5-1.6× a static step**, which is far cheaper
> than the 339 ms host datum that motivated deferring incremental rebuild.
> **BODY-PROPERTY TOOLING + PYTHON AUTHORING + COMPOSED PARTICLES shipped 2026-08-30** (§6.5;
> core `d4d3a60`, dem `fd371e1`): `geom::bodyProperties` (mass/COM/full tensor/principal moments +
> QUATERNION by implicit quadrature — no bound-leaf bias, 1.7e-05 where the voxel builder is
> +3.5e-02), `SceneBuilder::addReframed` (exact principal-frame re-expression, one composed
> transform), the `peclet.core.geom` Python module (authoring + encode + bake + body_properties),
> dem `SHAPE_SCENE` (a particle whose collision field IS a composed analytic tree; gated
> tree-vs-fine-grid on OpenMP and CUDA), and `peclet.dem.scene_particle` gluing it into one call.
> **LAYER 4 (resolved CFD-DEM) COMPLETE 2026-08-30 — the coupling force is the DISCRETE REACTION
> (route (b), flow `fc54f4a`, coupling `c69b5d9`).** `hydro_force_torque_reaction` sums, per owner
> region, the momentum the fluid actually lost — R_i = ρ/dt(u−uⁿ) − f_c − Σ_fluid-nbrs μ(u*_nb −
> u*_i), no pressure field read (it telescopes inside owner regions to the control-volume budget).
> Gated as the review demanded: the identity ΣF = f·N_fluid holds to **−8.8e-15** at steadiness
> (the approach is the genuine unsteady term: −3.1e-03 / −1.0e-05 / −1.2e-10 / −8.8e-15 at
> 200/400/800/1600 steps), frame invariance **0.999999993** (traction: 1.030), MPI per-instance
> forces cross-np to 4.1e-15, and the settling gate now **PASSES at 0.9988** (was 1.13) with the
> momentum leak gone (44× smaller residual, of setup origin). The reconstructed traction
> (`hydro_force_torque`) remains as the DIAGNOSTIC that keeps its own 29% resolution-independent
> under-read visible — localised to the central-difference gradient (§7 item 1 has the full
> history, including the masked-solid-cell sign bug the frame-invariance check caught, §7 item 2).
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
formulas** (resolved decision 1, §8):

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
  **`SdfGrid` was deferred here and consolidated immediately after** — see §6.2.

  > **Note on the rung-3 FMA trap:** it did *not* recur here. voro's providers build tiny value-type
  > leaves from already-loaded members with no long contraction chain, unlike dem's per-call
  > descriptor marshalling into a trilinear sum. The trap is specific to constructing a
  > multi-field descriptor inside a hot kernel, not to delegation as such.
- **Rung 5 — scene encoding contract. ✅ DONE** (core `789d2ea`).
  Documented the flat node/instance array encoding (the Python-facing composition format) + host
  `SceneBuilder`; core ctest round-trips build → evaluate. Per-code bindings that *accept* the
  encoding remain Layers 1–2.
  *Outcome:* `Instance` and `SceneView` land as decision 4 specified — `SceneView` is **raw
  pointers**, so it is POD, captures into a Kokkos lambda, and works host or device from
  `View::data()`. `evalCandidates` makes contract 9 real (union over a caller-supplied list, so AABB
  binning plugs in later with no API change). The flat encoding has compile-time strides — 3 ints +
  16 reals per node, 2 ints + 17 reals per instance — so a nanobind layer is numpy-in, POD-out with
  no per-field code. Gate: 20 000 probes × 3 instances round-tripped with **zero** bit mismatches,
  plus transform/union/candidate-list/velocity semantics and four malformed-scene rejections.

  > **Host vs device is not bit-exact for long expressions — and that is fine.** A `SceneView` built
  > from `View::data()` matches the host builder exactly on host-openmp (same compiler) but differs
  > on CUDA at up to **4 ULP** (6.9e-16 relative) over a depth-3 CSG scene, with **zero sign
  > disagreements**. That is nvcc contracting multiply-adds differently, not a defect. Note the
  > distinction from the rungs 0-4 gates: those compared *before vs after on the same backend*,
  > which must be exact; a host-vs-device comparison must be judged on sign agreement and a ULP
  > tolerance instead.

> **Migration discipline** (the suite's faithful-port rule): rungs 3–4 are relocations with bit-exact
> gates. Any numerics improvement (exact normals in contacts, unified hollow cylinder) lands *after*,
> as its own attributable change. Otherwise every regression moves at once and nothing is
> attributable.

#### 6.0 Grid-SDF consolidation (post-rung-4; core `525d996`, voro `40e21e1`)

The suite carried **three** trilinear grid-SDF implementations, not two: core's device
`sampleGrid` (inverse-spacing multiply, signed clamp residual), core's **host** `GridSdf::eval`
(spacing divide, flat clamp), and voro's `SdfGrid` (spacing divide, flat clamp). All three are now
one routine.

- `GridExtension` gains **`kClamp`** — nearest-valid-sample extrapolation, the field flattens at the
  box face. Its early return is hoisted above the residual so it also skips three unused divisions.
  `kClamp` has by construction the failure mode that cost dem 71k grains, so it is only for fields
  whose stored box genuinely bounds the domain.
- Unified on **multiply-by-inverse**, because that is what dem's bit-exactness contract is written
  against and it is cheaper on device. The host `GridSdf` and voro's `SdfGrid` therefore move ~1 ULP
  (2.2e-16 relative in the lattice coordinate; on CUDA, 81/3000 voro probes at max 1.3e-15).
  dem is untouched and byte-identical on both backends; core 92/92; voro 12/12.
- **A fixture can silently fail to detect this.** Spacing `0.3` gives bit-identical results for
  `(p−o)/s` and `(p−o)·(1/s)` on every probe tested — the first capture showed zero difference and
  looked like proof of no change. Other spacings differ on 8–37 % of coordinates. Pick the fixture
  value deliberately when testing a divide↔multiply change.

**voro now consumes the whole shared vocabulary** via a new `SdfScene` provider wrapping
`evalTree`: capsule, torus, cone, ellipsoid, superquadric, both cylinder forms, CSG, transforms and
grids all reach the cell clipper and mesh optimiser through the `eval(x,y,z)` + `gradH()` interface
it already expects, with voro owning no geometry code (ctest `test_sdf_scene`).

> **TRAP — a host function in a device lambda can corrupt a kernel silently.** `SdfGrid::fromSpacing`
> was first a plain static member. Called inside a `KOKKOS_LAMBDA`, nvcc accepted it **without any
> error or warning** and corrupted the whole kernel: `SdfSpheres`, which that change did not touch,
> moved by O(1) in the same kernel. Only the bit-capture caught it — the analytic block was clean
> while two providers sharing one kernel were both wrong, which localised it at once. Annotate every
> helper a device path might reach.

#### 6.0b MEASUREMENT RULE — pin the thread count when comparing dem numerically

**dem's `step()` is nondeterministic under multithreaded OpenMP.** Three runs of the *same binary*
give three different 120-step trajectories: contact slots are claimed with `atomic_fetch_add`, so
the buffer order varies with thread scheduling, and the position solve iterates that buffer in slot
order. At `OMP_NUM_THREADS=1` it is deterministic.

Consequence for every before/after comparison in this plan: **run dem single-threaded, or you are
measuring scheduling noise.** A multithreaded run of the Layer-1 shape-registry comparison reported
a confident "regression" (positions diverging 2.8e-2) that did not exist — the same comparison at
one thread was bit-identical at 1, 5 and 120 steps. The tell was the signature: positions differed
while velocities and inertia were identical, the static geometry probe agreed to 9 significant
figures, and contact *counts* matched exactly.

This is pre-existing behaviour, not something Layer 0/1 introduced. It also means multithreaded dem
runs are not reproducible run-to-run, which is worth knowing before trusting a benchmark delta.

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

### Layer 1 — `dem` consumes it ✅ COMPLETE

All five items shipped. Existing single-shape behaviour is bit-identical except where a numerics
change was the deliberate point (exact gradients).

- ✅ **Shape table + `add_shape` / `add_sdf_shape` / `set_shape_ids` / `num_shapes`** (dem
  `9b1de61`). Shape state moved to a host registry; `uploadShapes()` rebuilds the device Views and
  assigns each shape its `shellOffset` and grid offset. Broad-phase band and contact-buffer sizing
  now take the **max** over shapes. `initialize_shape` keeps its "shape 0 becomes this" reset.
- ✅ **Exact analytic contact normals** (dem `eb8de1c`) — the measured change. Accuracy: FD's fixed
  `eps = 1e-4` is a *real length in canonical space*, so its normal degraded as the shape shrank
  toward it (0.8° error at r = 3e-4); the exact gradient is flat across four decades, and
  `| |∇f|−1 |` drops 1.5e-3 → 1.2e-7. Speed: the gradient kernel alone is **11×**, the **narrow
  phase 26%** (matched work, identical 8096 contacts). End-to-end is *not* cleanly measurable —
  changing normals diverges the trajectory, so the builds solve different configurations with
  different contact counts and adaptive solver stopping; a naive end-to-end run reported the new
  code 17% "slower" while comparing 7043 contacts against 7245.
- ✅ **General SDF-driven surface-point generator** (core `a78d0f0`) + dem auto-shell (`608916b`).
  A grid-SDF particle registered with an **empty** shell now generates one from its own zero level
  set, so an SDF alone defines a colliding body. Deliberately lattice-and-project, not ray casting
  from a centre — a torus and most CSG results are not star-shaped.
- ✅ **Analytic walls** (dem `7edb05d`). `WallSdf` gains `{nodes, nodeCount, shapeRoot, sign}` and
  `add_analytic_wall` consumes rung 5's **flat node encoding** directly, so the whole vocabulary
  plus CSG reaches a dem wall with no new binding machinery.
- ✅ **`globalScale` in the `generateSdfKokkos` splat** (dem `e90a5d1`). The export described
  different geometry than the simulation whenever `global_scale != 1` (5.1 voxels of radius error at
  `gs = 2`); `gs = 1` is bit-identical, which is why it hid.

> **TRAPS for analytic walls.** (1) *Sign*: a wall reads positive in the void, core's leaves are
> negative-inside-solid. A stirrer wants `invert=False`; a container wants a **solid** body inverted
> (a solid cylinder for a drum), so everything beyond the barrel reads as wall. Inverting a thin
> **tube** is wrong — its bore is already void. (2) *Position*: an analytic wall is placed by its
> node **transform**; unlike `add_sdf_wall` there is no grid origin doing it implicitly, so an
> identity transform sits at the domain corner. This failure looks exactly like a sign error, and it
> is what actually caused the grain escapes seen while developing the feature.

### Layer 2 — `flow` consumes it

Where the CFD accuracy motivation lands. Give `flow` a device-resident **scene** (a `SceneView` it
owns, rank-replicated — see decision 4, §8) and derive geometry *in-solver* instead of importing
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

#### 6.4 Implicit-quadrature apertures (core `geom/quadrature.hpp`, shipped 2026-08-30)

The general replacement for `flow/scripts/exact_apertures_spheres.py`: given any device-callable
field (a `SceneQueryView`, a leaf, a lambda), the fluid fraction of an axis-aligned face
(`faceAperture`) or box (`cellVolumeFraction`). Saye's dimension reduction at its simplest useful
level — pick a height direction, integrate the transverse directions with Gauss–Legendre, and take
the 1-D measure along each height line by bracketed bisection (exact to rounding). It lives in
**core geom** so AMR gets it for free through the same `SceneQueryView`.

**The one non-obvious thing, and it is worth 8 orders of magnitude.** `L(t)`, the positive length
as a function of the transverse coordinate, has a **kink wherever the interface crosses an EDGE of
the face**. Integrating straight through those pins the error near 1e-3 *at every resolution* —
because an aperture is a **fraction**, so a fixed kink in a fixed normalized integrand costs a fixed
amount and refining the grid does not help at all. Locating those crossings on the two edge
functions (two bracketed bisections each) and running the Gauss rule piecewise removes the
obstruction entirely.

*Gate (`ctest geom_quadrature`), sphere R=0.3, against the closed-form disk-rectangle overlap:*

| N | cut faces | quadrature (split) | **unsplit** | sampled-SDF linear |
|---|---:|---:|---:|---:|
| 16 | 276 | **3.93e-12** | 8.55e-04 | 3.78e-02 |
| 32 | 1172 | **4.10e-12** | 9.89e-04 | 5.19e-02 |
| 64 | 4612 | **3.89e-12** | 5.40e-04 | 4.67e-02 |

Mean absolute error over the cut faces. The split buys 2e+07 to 1e+08; the unsplit column is the
evidence for the paragraph above — it barely moves across a 4× refinement.

*Convergence is in the NODE COUNT, not in h* (N=32, all cut x-faces): order 2 → 3.21e-06,
3 → 1.60e-08, 4 → 2.10e-10, 5 → 4.10e-12, 8 → 1.21e-14. Geometric, as a Gauss rule on a smooth
integrand should be once the kinks are removed.

*Volume fractions are weaker*: 7.50e-07 relative on a sphere at 24³, because the outer rule there is
two-dimensional and its kinks are **curves**, not points, so the same subdivision does not apply.
More nodes is the lever.

> **NOT CERTIFIED — and the failure modes are structural, not rounding.** Unlike the candidate-grid
> pruning of §6.2, this carries no exactness guarantee. (1) A feature thinner than the initial
> bracketing stride is invisible. (2) Where the interface is not a graph over the height direction
> the premise fails outright. (3) The height direction is chosen once per face from the gradient at
> its centre, so a face whose interface turns across it loses accuracy. The gate therefore also
> measures a **torus**, where a line through the hole crosses four times: results stay in [0,1] (0
> of 288 cut faces out of range) and the volume lands within 8.6e-06 relative — bounded and
> consistent, with **no order claimed**. Consumers must keep the sub-resolution aperture floor the
> cut-cell pressure operator needs (α ~ 1e-12 rows destroy its conditioning — measured) and must not
> build a conservation argument on these numbers.

#### 6.2 Layer 2-for-core: accelerated queries (shipped 2026-08-29)

Driven by the AMR consumer's measured requirements (docs/AMR_GEOMETRY_SETUP_REQUIREMENTS.md; 94%
of `AmrFlow::setSolid` was brute-force SDF evaluation). New in `geom/`:

- **`scene_query.hpp`** — `PeriodicBox`/`minImage` (min-image periodicity), `SphereUnionView` with
  an equal-radius one-sqrt path, `CandidateGridView` + `buildSphereCandidateGrid` (uniform-lattice
  bins, geometry-driven splat, exact U-bound pruning: keep i iff `lower_i(B) ≤ min_j upper_j(B)` —
  the list is a superset of the argmin set for every point of the bin, so min over it IS the brute
  min, bitwise), and `SphereBedQuery`, the callable that slots into `AmrFlow::setSolid`'s
  templated parameter. Empty-bin / out-of-coverage queries fall back to the full scan: exact.
- **`device_scene.hpp`** — `DeviceScene<Real>`, the OWNING device scene (the type flow/dem/voro
  are meant to retrofit onto instead of hand-rolled decode+upload), plus the batched drivers
  `evalSphereUnionPoints` / `evalScenePoints` (device Views in/out) and `*Host` forms.

Prunability for general scenes: bound-based pruning needs `eval ≥ dist-to-bounding-ball`, which
exact-distance leaves satisfy and CSG preserves (union: all children; intersection/difference:
the LEFT child's ball and certificate suffice, since `max(a,·) ≥ a`). Under-estimating leaves
(ellipsoid, superquadric, `HollowCylinderShell`) and grid leaves are never pruned — they ride an
always-list.

> **TRAP, now a PRESCRIPTION — fma-canonicalise any expression that must be bitwise host ≡
> device.** nvcc FMA-contracts `x*x + y*y + z*z` (22 001/200 000 CUDA probes off by 1 ulp at the
> sqrt magnitude); no portable flag disables it per-expression. Writing the chain as explicit
> `fma(z,z,fma(y,y,x*x))` (and `fma(-nearbyint(d/L), L, d)` for min-image) is correctly rounded
> by IEEE on every backend and cannot be re-contracted: after the change, 0/200 000. This
> upgrades the rung-3/rung-5 observations (contraction shifts results; judge host-vs-device by
> sign+ULP) into the constructive rule: where bitwise parity is REQUIRED, make fma explicit and
> gate it (`geom_batch_device`). Cost on hosts built without `-mfma`: `std::fma` is a libm call
> (~+15% here) — a build-flag fix, not a design cost.

> **TRAP — speedup estimates don't multiply.** The requirements modeled candidates ~30× ×
> equal-R ~3×. Measured: ~30-40× total. Equal-R's 3× assumed the sqrt dominates a 180-long loop;
> once candidate lists are 3.75 long, the min-image divides dominate and the equal-R path saves
> only the 2.75 extra sqrts. Multiplicative factor estimates are only valid against the SAME
> baseline denominator.

#### 6.5 Body-property tooling + Python authoring + composed particles (shipped 2026-08-30)

The pipeline the campaign was building toward, closing three gaps at once (core `d4d3a60`, dem):

- **`geom/body_properties.hpp`** — mass, COM, full inertia tensor, and the principal decomposition
  as three moments **plus a quaternion**, by composite implicit quadrature. Only signs and
  bracketed roots are consumed, so bound-only fields (ellipsoid, superquadric, CSG — the
  non-certified leaves) carry **zero systematic bias**: measured 1.7e-05 on the ellipsoid where
  the voxel integrator (`peclet.dem.particle_builder`) is +3.5e-02. Grade ~O(n⁻²) (transverse-rule
  kink *curves*, the `cellVolumeFraction` obstruction, honestly stated in the header): sphere
  inertia 1.7e-04 / 2.5e-05 / 4.0e-06 at n = 8/16/32; a rotated+offset box recovers its COM to
  2.4e-05 and its unique principal axis to 0.0042°. Gate: ctest `geom_body`.
- **`SceneBuilder::addReframed` + `composeTransform`** — deep-copy a subtree and pre-compose a
  transform on the copied root: `eval_new(p) = eval_old(toLocal(W, p))`, exactly. With the inverse
  principal transform this puts a shape's canonical frame ONTO its principal frame in one node, no
  resampling — **the resolution of the "reference frame ≠ principal frame" question**: supported
  at preprocessing by construction, so dem's diagonal-inertia contract is met without carrying a
  runtime reference quaternion. Round-trip gated (com 9.0e-06, frame deviation 0°).
- **`peclet.core.geom`** (new Python module, host-only) — `SceneBuilder` with string-kind leaves,
  CSG, quaternion transforms, instancing; `encode()` emitting exactly the flat arrays
  `flow.set_scene` / `dem.add_analytic_wall` / `dem.add_scene_shape` consume; `eval`/`eval_root`
  batch evaluation; `bake` (x-fastest float32 lattice, dem's grid layout); `body_properties`;
  `principal_frame` (measure + reframe in one call). Ends the hand-assembled node-array era.
- **dem `SHAPE_SCENE`** — a particle whose collision field IS a composed analytic tree
  (`Simulation.add_scene_shape`), the particle sibling of the Layer-1 analytic walls: same flat
  encoding, same pooled device node table (`P_.shapeNodes`, absolute indices), evaluated by
  `evalTree` in canonical body space. The shell still comes from a bake (the point-shell model
  needs probes; probe spacing, not the field, bounds contact resolution).
- **`evalTreeGrad`** (core, same-day follow-up) — the runtime tree's **analytic gradient**, one
  traversal carrying (value, gradient): leaves use their closed-form `.grad()`, transforms cost
  one quaternion rotation each (the conformal scale cancels in the chain rule), and CSG selects
  the ACTIVE branch's gradient by the same comparison the value makes. Gate `geom_tree_grad`:
  value bitwise `evalTree`'s (0/50000), chain rule exact to 0.0 under rotated+scaled transforms,
  O(h²) against FD on smooth regions — and **at a drilled-box rim the analytic normal is the flat
  face's exact +z at every distance while the central difference smears 39° once the ridge enters
  its stencil**. Also 3.2× faster than the eval+FD it replaces (184 vs 592 ns/probe). Consumers:
  dem `SHAPE_SCENE` contact normals AND analytic-wall normals (the deliberate numerics change,
  mirroring Layer 1's exact particle normals; grid shapes/walls keep FD), and Python
  `eval_root_grad`. voro's provider contract (`eval + gradH`, FD by design) is the recorded
  non-consumer — switching it is a provider-contract change for that campaign to take.
- **`peclet.dem.scene_particle.build`** — the one-call pipeline: author tree → measure → reframe
  to principal → bake shell → `register(sim)`; the same reframed tree feeds flow analytically.

*Gate (`scene_particle_gate.py`, OMP_NUM_THREADS=1):* an asymmetric dumbbell (real COM shift
−0.152, recentred to 1e-06 by `principal_frame`) run as a tree particle vs the SAME shape baked to
a 96³ grid particle: relaxed-contact separation errs 4.9e-03 for BOTH (the shared shell
decimation — they agree with *each other* to 1e-05), and 400 colliding steps track to 0.0126
against the grid's own 0.019 resolution. dem 8/8 kernel + 24/24 MPI stay green (the new kind is a
new branch; existing shapes untouched). A pipeline smoke (box ∪ angled capsule) shows composed
grains exchanging contact TORQUE — dem's internal rotational contact dynamics work for trees; only
the EXTERNAL torque API (§7 item 5) remains missing.

> **TRAP (bit dem again): `set_positions` resets every particle to shape 0.** A probe that
> re-positions after `set_shape_ids` silently relaxes placeholder spheres — the static-contact
> gate measured exactly nothing until the ids were re-applied after positioning.

### Layer 3 — moving geometry ✅ COMPLETE (rungs 1-4 shipped 2026-08-30)

Shipped: core `318d651` (cut ownership), `81a3f7c` (rigid-body motion + wall point); flow
`1b00405` (per-cell owner), `7f87b21` (rungs 2-4). Everything is **opt-in**: with no moving
instance the fingerprint is bit-identical, gated before each commit.

Measured inputs that shaped it (flow `0706196`): a full geometry rebuild at 128³ host-4T is
**339 ms** — ~65% momentum/IBM stencils, ~35% pressure/MG, scene sampling in the noise. That
motivated deferring incremental rebuild. **The GPU measurement changes the picture** (rung 4
below): a full rebuild is 37 ms at 128³ on an RTX 5080, i.e. **1.5× a static step**, so per-step
full rebuild is affordable and incremental rebuild is not urgent. Decision still Frank's.

- **L3-R1 — cut ownership ✅.** `SceneQueryView::evalOwner(p, own)` / `owner(p)` in core: one
  traversal returns bitwise `eval`'s value plus the argmin instance. Ties break to the **lowest
  index by the comparison itself**, not by scan order — necessary because a point can be answered
  through a candidate list, the always-list ∪ candidate list, or the full-scan fallback, which
  visit indices in different orders. flow fills a per-inner-cell `cutOwner_` inside
  `set_solid_from_scene`, free because it rides the sample it already takes.
  *Gates:* ctest `geom_owner` — RCP-180 60k probes, poly-120 40k, the flow 4-sphere bed 40k, all
  0 mismatches against an independent brute-force argmin; 30k probes invariant under per-bin
  candidate reordering; exact ties (coincident spheres, exact mid-plane) resolve to the lowest
  index; owner **host ≡ device** 0/50000 on OpenMP *and* CUDA (`geom_batch_device`). flow-side:
  0/1560 cut cells and 0/32768 cells disagree with a numpy argmin, with 2948 exactly-tied lattice
  cells present so the tie rule is exercised, not assumed away.

- **L3-R2 — kinematic wall velocity in the momentum operator ✅** (staggered only).
  `ibmModifyStencil`'s scalar `u_bc` became an optional per-cell View; an empty View keeps the
  scalar path with the same three roundings in the same order. Filled from the scene at each
  component's **own** staggered point: `n̂` from a central difference of the sampled `sdf_`,
  `w = p − sdf(p)·n̂` via core's `geom::wallPoint`, `uBc = instanceVelocity(owner(p), w)·ê_c`.
  The owner is queried **at p**, not read from the cell-centred `cutOwner_`: at a contact between
  two bodies the staggered point and the cell centre can belong to different ones.
  Collocated ghost-projection `w_bc` remains **DEFERRED**; ghost-projection / porous /
  variable-density are refused loudly rather than silently mis-walled.

- **L3-R3 — wall flux in the divergence constraint ✅.** `A_wall = −(oE−oW, oN−oS, oT−oB)` in
  h=1 units (divergence theorem on the cell's fluid region; the open-face terms telescope), folded
  into `div_` before the negation and into `max_open_divergence` so the diagnostic still measures
  the residual of the constraint actually solved.

- **L3-R2/R3 GATE — Galilean invariance. PASSES, and rung 3 is load-bearing by 10⁵.**
  Stokes bed with body force, solved in the lab frame and in a frame boosted by `V = 0.7` (every
  sphere given `linVel = −V`, geometry identical); claim `u_B + V == u_A` in every fluid unknown.

  | run | rung 3 ON | rung 3 OFF |
  |---|---|---|
  | N=32 host-OpenMP, 260 steps | **2.313e-05** | 2.224e+00 |
  | N=32 host-OpenMP, 800 steps | **2.591e-06** | 2.224e+00 |
  | N=64 CUDA, 400 steps | **6.321e-06** | 5.582e-01 |

  (max |u_B + V − u_A| / max|u_A| over all fluid unknowns; the cut band and the deep field give the
  same order, which is itself evidence the residual is not a wall-treatment error.) Tripling the
  solver work shrinks the ON error 8.9× and leaves the OFF error where it was — so the ON residual
  is **convergence level**, and the OFF error is a real, non-vanishing wrong answer. Wall-flux
  imbalance (Σ u_w·A_wall, the singular problem's compatibility datum) measured 1.6e-13 at N=32 and
  8.9e-16 at N=64: exactly zero for translation, as the telescoping predicts.

- **L3-R2/R3 second gate — rotlet. PASSES at order ~2 once the reference is trustworthy.**
  A single sphere spinning in Stokes flow; error in a shell 1.15–2 R from the surface against
  `u = (R/|r|)³ ω×r` summed over a 9³ image block. **The reference, not the solver, decides
  whether this is measurable**, and that took a dedicated experiment to establish:

  At **R/L = 0.10** the near-shell error stalls — 2.481e-02, 1.476e-02, 1.355e-02 at N=48/96/144 —
  and turning on exact scene crossings gives 1.656e-02, 1.259e-02, 1.255e-02. *Two different
  discretisations descending to the same ~1.25e-02 floor* is the signature of a wrong reference,
  not a wrong solver: the naive real-space image sum of a 1/r² field is conditionally convergent.

  **The decisive experiment** (`ROTLET_MODE=refprobe`): hold R fixed at 7.2 **cells** — so the
  discretisation error cannot move at all — and change only the box. Halving R/L dropped the
  near-shell error 1.736e-02 → 7.457e-03, a factor 2.3. Solving `d + x = 1.736e-2`,
  `d + x/8 = 7.46e-3` (the image term scales as (r/L)³) gives image ≈ 1.13e-02 and discretisation
  ≈ 6.2e-03: at R/L = 0.10 the error is **~65% reference**.

  Re-run in the regime where discretisation dominates (R/L = 0.05):

  | N | R (cells) | near-shell L2 rel err | far shell (2–3.5 R) |
  |---|---|---|---|
  | 96 | 4.8 | 1.660e-02 | 1.925e-02 |
  | 144 | 7.2 | 7.457e-03 | 1.415e-02 |
  | 192 | 9.6 | 4.823e-03 | 1.185e-02 |

  **Near-shell order 1.97 then 1.51** — the "~2 expected" the spec asked for, comfortably past the
  ≥1 requirement. The far shell still reads 0.76/0.61 because that is where the residual image
  correction lives, which is the same effect, now isolated rather than confounding. Exact scene
  crossings improve the coarsest grid by 33%, which is the Layer-2 machinery doing what it is for.

- **L3-R4 — the moving-step driver ✅.** `set_instance_transform(i, translation, quat)` +
  `rebuild_geometry()`; `set_instance_motion(i, lin_vel, ang_vel, center=None)`. The rebuild
  re-derives SDF, overlay, apertures and pressure operator, and **saves and restores u and P**
  around it — `set_solid` zeroes `u/phi/P` by design, which would reset the flow every step.
  Crossings are re-derived *before* the solid so a moving step costs one rebuild, not two.
  *Gate — it marches:* N=48, 40 rebuilds — the sphere moved 1.60 cells against 1.60 expected, the
  near-wake fluid was dragged along at +1.95e-02 for a wall speed of +0.08, max|div| stayed at
  6.9e-08 over the whole march, and the field accumulated across all 40 rebuilds instead of
  resetting.
  *Cost (CUDA, RTX 5080, measured):*

  | N | static | moving, no rebuild | moving + rebuild | rebuild alone |
  |---|---|---|---|---|
  | 64 | 13.9 ms | 12.8 ms | 22.1 ms | **9.3 ms (1.6× a static step)** |
  | 128 | 74.2 ms | 73.0 ms | 110.0 ms | **37.0 ms (1.5× a static step)** |

  Rungs 2-3 cost **nothing** at run time. A full per-step rebuild is ~0.5× a step on GPU.

#### 6.3 TRAPS from the Layer-3 execution (all cost real time; all are gate-side, not solver-side)

> **A benchmark whose baseline solves nothing.** The first rung-4 cost run had **no body force**,
> so the static case had `u ≡ 0` forever and its pressure PCG converged on a zero right-hand side.
> It reported the moving path at 2.8× a static step; with a body force the same comparison is
> 0.9×. Any A/B of solver cost must check that the A side is doing work.

> **`set_pressure_multigrid(True, levels=1)` costs 920 ms/step at N=64 on CUDA** against 19.5 ms
> at depth 4 — the "coarse" solve is left on the full grid. `verify_periodic_spheres_sdflow.py`
> uses `levels=1` deliberately (it is pure RB-GS, keeping the operator) and that is fine on CPU;
> on GPU it silently turns a 20-second study into a 20-minute one.

> **Compare staggered fields at staggered points.** Two separate gates were wrong the same way.
> (1) A fluid mask taken at CELL CENTRES reported a Galilean error of exactly `V / max|u_A|`,
> because a cell whose centre is fluid can have its u-point inside the solid, where both runs store
> a masked 0. (2) The rotlet compared `get_u/get_v/get_w` — which are MAC FACE values at
> (i−½,j,k), (i,j−½,k), (i,j,k−½) — against the analytic field at cell centres, an O(h) offset that
> caps the measured order at 1 no matter how good the scheme is (it reported 0.93 and looked like a
> real first-order result).

> **The flow fingerprint is OpenMP thread-count sensitive** in `p_sum` and `u_l2` (not in `u_sum`
> or `u_absmax`): at 4 threads all four golden digits reproduce, at 8 threads the last digits of
> those two move. Pre-existing host-reduction behaviour. Run `flow_probe.py` at **4 threads**, or
> compare only `u_sum` / `u_absmax`.

> **`rebuild_geometry` must preserve the flow.** `set_solid` is a setup entry point and zeroes
> `C[c].u`, `phi_` and `P_`. A moving-geometry driver that calls it per step without saving and
> restoring them silently resets the solution every step and still "runs".


- **L3-R6 — `refresh_wall_velocity()`: a moving BC without a geometry rebuild ✅ (flow `23a8c82`,
  2026-08-30).** The linearised moving-boundary problems change an instance's VELOCITY every step
  while the geometry never moves — an oscillating body at vanishing amplitude, a shear cell driven
  by counter-moving plates. `set_instance_motion` does not reach the fields those need: `uBc_` (the
  momentum operator's no-slip datum) and `uwCell_` (the cut-cell projection's wall flux) are built
  inside `set_solid_from_scene`, so such a driver had to call `rebuild_geometry()` every step and
  pay a full geometry re-derivation to update a boundary condition. `refreshWallVelocity()` runs
  `buildWallVelocity()` + `rebuildStencils()` and nothing else, and **refuses** when
  `sceneDirty_` — it does not re-sample the SDF, the apertures, the ownership field or the pressure
  operator, so on a body that had actually moved it would silently continue on stale geometry.

  *Gates* (`refresh_wall_gate.py`, N=48, 60 steps of a cos-driven wall velocity):

  | claim | measured |
  |---|---|
  | u, v, w, P vs `rebuild_geometry()` | **bitwise identical**, max\|diff\| 0.000e+00 (all four) |
  | reaction force vs `rebuild_geometry()` | 3.7e-15 relative — the documented atomics floor |
  | the call itself, CUDA at N=48 | 4.0 ms → **1.4 ms**, 2.8× cheaper |
  | the driver's per-step total | 16.5 → 13.9 ms, **1.19×** (a bare step is 12.4 ms) |

  Both cost numbers are quoted: the refresh still rebuilds the momentum stencils, which are the bulk
  of a geometry rebuild, so the 2.8× on the call alone would overstate what a caller saves.

  *A latent bug it surfaced, live on the `rebuild_geometry` path too.* `buildWallVelocity` returned
  early when `hasMotion_` went false, leaving previously-built `uBc_`/`uwCell_` **stranded** — and
  `wallVelView()` keys off the field's extent, not `hasMotion_`, so a body whose velocity the caller
  set back to zero kept its old wall velocity folded into the momentum operator indefinitely. The
  fields are now zeroed instead of stranded; allocation state is unchanged, so a run that never
  moves stays bit-identical. Gated: a body stopped and refreshed is bitwise identical to one that
  never moved, while the same run *without* the refresh differs by 1.9e-02 in u and 5.2e-02 in P.

- **L3-R5 — rigid PLACEMENT of an analytic dem wall ✅ (`set_wall_transform`, dem, 2026-08-30).**
  `set_wall_velocity` gives a static wall a rigid-body surface-velocity field, which is the whole
  story for a body of revolution (a drum barrel looks the same at every angle) and no story at all
  for a stirrer blade, whose geometry has to sweep. `set_wall_transform(wall_index, translation,
  quat)` composes the world placement onto the wall tree's **AUTHORED** root transform (kept at
  `add_analytic_wall` time) via `SceneBuilder::composeTransform`, and re-uploads the KB-sized
  `wallNodes` View — that upload is the whole cost. Composing onto the authored transform, not
  onto the previous frame's result, is what makes calls absolute rather than compounding. The
  caller drives `set_wall_transform` and `set_wall_velocity` together each step; neither is
  inferred from the other. A companion `wall_sdf_at(wall_index, points)` returns exactly what the
  narrow phase reads, so a placement can be checked (and a stirrer drawn) without a contact.

  *Gates* (`wall_transform_gate.py`, OMP_NUM_THREADS=1):

  | claim | measured |
  |---|---|
  | placed (q,t) vs the SAME tree AUTHORED at (q,t), 4000 probes | **bitwise identical** (max diff 0) |
  | 100 identical calls; then return to identity | **bitwise stable / bitwise home** |
  | the placement is not a no-op | max\|placed − home\| = 3.13 |
  | self-axis rotation of a barrel (analytically the identity) | max\|ΔSDF\| **2.4e-06** = the float32 re-rounding floor |
  | drum bed, 600 settle + 400 driven steps, bulk centre of mass | **6.1e-05 grain radii** |
  | per-grain spread, static vs rotated geometry | 1.0e-02 grain radii, **bounded by** the rotated-vs-rotated control at 1.1e-01 |

  The bitwise claim is real, not a tautology: it holds because `composeTransform(W, identity)`
  reduces to `W` exactly (`mulQuat` with the identity quaternion and `rotate()` of the zero vector
  are exact in floating point). The last row is the honest reading of a *chaotic* control: two runs
  that BOTH rotate the geometry differ by more than static-vs-rotated does, so the per-grain spread
  is float32 rounding amplified by the cascade, not an effect of moving the wall.

### Layer 4 — resolved CFD-DEM (rungs 1-2 shipped, rung 3 measured, rung 4 open)

Python-composed like `peclet.coupling` (no C++ link between dem and flow — the suite's
architecture): `ResolvedCfdDem` in `coupling/python/peclet_coupling/resolved.py`. It is pure
Python and needs no compiled kernels of its own, so `peclet_coupling/__init__.py` now tolerates a
missing `_coupling` extension (which only the UNRESOLVED driver uses).

- **L4-R1 — dem→scene bridge ✅.** Per coupling step: pull dem positions / quaternions /
  velocities / angular velocities, build the flat instance encoding (one `kSphere` node, N
  instances), push transforms + rung-2 motion, `rebuild_geometry()`. float32→float64 at the
  boundary — "zero-copy" is not literal across that divide and does not need to be: the instance
  array is a few hundred bytes per grain against a rebuild measured in tens of ms.

- **L4-R2 — hydrodynamic force/torque ✅ COMPLETE: the coupling force is the DISCRETE REACTION
  (`hydro_force_torque_reaction`, route (b) — §7 item 1 has the derivation and the round-off
  gate); the reconstructed traction below is kept as the diagnostic that keeps its own bias
  visible.**
  Device kernel over the cells the wall passes through: `dF_body = −(σ · A_wall)` with
  `σ = −p I + μ(∇u + ∇uᵀ)`, `A_wall` from the aperture identity, posted to `cutOwner_`'s instance
  by atomics (tolerance-, not bit-reproducible — documented, like the coupling deposits), torque
  about the instance centre with a min-imaged lever arm. Returns force, torque, **and the pressure
  and viscous parts separately**, because they fail differently.

  *Gate — the momentum balance, which the solved field must already satisfy.* For a body-force
  driven periodic bed at steady state, `Σ F_hydro = f · V_fluid` exactly, with no empirical input.
  Measured (4-sphere bed, porosity 0.902, Stokes):

  | N | Σ F_hydro / f·V_fluid | pressure part | viscous part |
  |---|---|---|---|
  | 64 | **0.715** | +87.8 | +81.3 |
  | 128 | **0.709** | +668.8 | +672.8 |

  Everything structural is exact: transverse leakage 5.5e-16 / 2.1e-13 relative (symmetry), and the
  per-sphere spread over four identical spheres is 1.9e-15 / 1.0e-15 — so **owner attribution
  splits the surface perfectly**. What is wrong is the magnitude, by **29%, and it does not
  converge** (order −0.03): a modelling error, not a discretisation one.

  *Localised, in two steps.* (1) A new `wall_area_probe()` sums `Σ x_c · A_wall,x` per axis, which
  by the divergence theorem on the solid must equal `−V_solid`; measured **1.0222 at N=64 and
  1.0114 at N=128**, converging. The geometry is right to 1-2%. (2) The pressure/viscous split
  says the pressure part is roughly right while the viscous part is about half of what a 1/3–2/3
  Stokes split would need. The cause is the prescribed **central difference**: it spans 2h while
  the wall sits a fraction of a cell away, so it under-reads the wall shear by a factor that does
  not shrink with h.

  *The obvious repair was tried and is worse.* Differencing one-sidedly to the wall over the
  crossing distance θ gave the drag **17× too large**: cut cells with θ→0 make 1/θ unbounded. That
  is exactly why the momentum operator uses a Robust-Scaled reconstruction instead of a raw
  one-sided difference. The experiment was removed rather than left behind a flag whose "on" state
  is 17× wrong. **Route (b) — the discrete reaction — is now implemented and is the coupling
  force**; §7 item 1 records the derivation, the telescoping-pressure trick, and the gate that
  holds to −8.8e-15.

- **L4-R3 — motion loop. RUNS AND CONVERGES; the gate misses by 13%, and the miss is the SAME
  traction bias, now visible as a momentum leak.** Weak explicit coupling: flow force →
  `dem.set_external_forces` → dem sub-steps → new state → rebuild + flow step.

  *Gate:* a settling sphere against the terminal velocity predicted from the drag coefficient
  **measured in the same box**, so every periodicity/blockage correction cancels and no literature
  wall-correction fit is involved. (a) Sphere held fixed, body force f drives the fluid:
  `λ := F_drag / (6πμR⟨u⟩)` = **1.0111**. (b) Same sphere freed with body force `F_g` and a
  compensating fluid body force `−F_g/V_fluid` (without which the whole periodic system accelerates
  forever and there is no terminal velocity to find); prediction `|⟨u⟩ − U_p| = F_g/(6πμRλ)`.

  Measured (N=40, ρ_p/ρ_f = 5, 600 coupling steps): the slip rises 1.93e-02 → 2.26e-02 and
  plateaus, against a prediction of 2.00e-02 — **ratio 1.13**, versus the 5% the gate asks for.

  *Why, established rather than guessed.* Total x-momentum must be constant (the external forces
  sum to zero by construction) and instead grows linearly, `p_tot 8.8e-03 → 1.28e+03` over 600
  steps ≈ **0.58 F_g per unit time**. That is an action-reaction gap, and it is quantitatively the
  one rung 2 already measured: the fluid feels the TRUE reaction through the no-slip wall while the
  grain is handed the reconstructed traction, which under-reads by ~0.68-0.71. Working the arithmetic
  the other way, `F_reported = −F_g` at the particle's steady state ⇒ `F_true ≈ −1.46 F_g` ⇒ a net
  system injection of ≈ 0.46 F_g per unit time, against 0.58 measured. Same effect, same size.

  *This also corrects the spec's own reasoning.* The gate was designed as self-consistent so the R2
  bias would cancel between calibration and prediction. It does not fully cancel: calibration holds
  the sphere STATIC (no frame error) while settling moves it (a further 3% frame error, measured),
  and the momentum leak shifts the operating point as the run proceeds. Route 1(b) in §7 — take the
  force from the discrete reaction — makes action-reaction exact and closes all three symptoms at
  once (the 29% static deficit, the 3% frame error, this leak).

  **RESOLVED with route (b)** (coupling `c69b5d9`): with the reaction force feeding dem, the same
  gate gives **slip ratio 0.9988** — inside the 5% claim — and the momentum drift falls 44×, the
  remainder being the setup's own analytic-vs-discrete V_fluid mismatch plus rebuild blips, not
  the force method. Calibration and settling now use one force definition, so the self-consistency
  the spec intended actually holds.

  *Two API traps found here.* `dem.step()` with no argument advances **nothing** (`dt=0` is a
  dynamics-free relaxation step), so a driver calling it runs happily with a frozen particle; and
  dem assigns unit mass regardless of size, which makes the weak explicit exchange violently
  unstable (the run reached 1e16 in 60 steps) until a physical mass is set via `set_inv_mass`.

- **L4-R4 — MPI (replicated instances) ✅, and with it the Layer-2 MPI scene demo.** Instances are
  replicated, so each rank derives its own block's geometry from the same scene with **zero new
  communication** — that, not any new exchange, is what lifts the single-rank restriction the
  Python override path carried. Each rank integrates the wall cells inside its own block and the
  body's total is the rank sum (`MPI_Allreduce` in `hydroForceTorque`; `wallFluxImbalance` and
  `wallAreaProbe` reduce likewise).

  *Gate* (`mpi_scene_gate.py`, 4-sphere bed, N=32, np = 1, 2, 4):

  | claim | np=2 vs np=1 | np=4 vs np=1 |
  |---|---|---|
  | permeability `k = μ⟨u⟩/f` | 0.000e+00 | 1.727e-16 |
  | per-instance hydrodynamic force | 3.798e-07 | 3.798e-07 |
  | per-rank cut-owner vs the single-rank global field | **0 mismatches** | **0 mismatches** |

  The owner check is the sharp one: every rank's ownership field equals the single-rank global
  field restricted to its block, exactly, because every rank evaluates the same replicated scene at
  global coordinates. The force agrees to 4e-07 rather than bitwise, which is the documented
  consequence of atomics over an unordered traversal — not a distribution artefact.

  Still open on the driver side: `ResolvedCfdDem` does not yet allgather dem state, so the resolved
  MOVING case is single-rank; the fixed-bed case above is fully distributed.

### Orthogonal (does not block the above)

Shape-aware **unresolved** closures: sphericity / equivalent diameter / orientation-dependent drag in
`coupling/src/drag.hpp`, so non-spherical grains are non-spherical to the fluid as well.

---

## 7. OPEN FOR REVIEW (raised during the Layer 3-4 execution, 2026-08-30)

Questions the specs did not resolve and that materially affect numerics or API. The conservative
option was taken in each case and is stated; none of them is settled.

1. **The cut-cell traction needs a wall-aware reconstruction — RESOLVED 2026-08-30: route (b)
   implemented and gated to round-off.** The history: the spec's central-difference traction was
   measured **29% low and resolution-independent** (0.715 at N=64, 0.709 at N=128), with `A_wall`
   verified right to 1-2% and the deficit in the viscous part — an inconsistent estimator, since
   the near-wall gradient's relative error is O(1) in units of h ((1+θ)/2 per axis against the
   masked value at the wrong distance) on exactly the support of the integral. The one-sided 1/θ
   repair was tried and gave **17× too much** (θ→0 unbounded).

   **The fix — `hydro_force_torque_reaction()`** — takes the force from the discrete reaction:
   per fluid momentum cell, `R_i = ρ/dt(u−uⁿ) − f_c − Σ_fluid-nbrs μ(u*_nb − u*_i)` with u* the
   stashed last momentum-solve iterate, summed per owner region with sign flipped. The pressure is
   deliberately NOT subtracted: per cell R contains −∇π, which **telescopes inside each owner
   region** to exactly the control-volume boundary flux plus the wall pressure force — pressure
   counted once, in the right place, without reading a pressure field. The budget's only
   approximation is the momentum solver's residual; everything else is identity.

   *Gated as the review demanded — the balance must hold to ROUND-OFF, not percent* (single
   sphere, N=32, body-force driven, ratio ΣF/(f·N_fluid) − 1):

   | steps | 200 | 400 | 800 | 1600 |
   |---|---|---|---|---|
   | ratio − 1 | −3.1e-03 | −1.0e-05 | −1.2e-10 | **−8.8e-15** |

   The early-step residuals are the genuine unsteady term (the flow still accelerating — correct
   physics, included in the budget), decaying with the approach to steady state; the floor is
   machine precision. Sweep count does not move it (100 vs 1200 sweeps identical at fixed steps),
   confirming no term is missing. The traction integral gives 0.665 on the same run.

   *What this repairs vs hides, per the review:* the reaction is the coupling force — exactly
   conservative and inheriting the flow solution's validated 2nd-order accuracy; the traction
   integral is **kept as a diagnostic** (`hydro_force_torque`, docstring demoted) so its O(1)
   inconsistency stays visible; the momentum-balance gate is **repurposed** as the
   implementation-completeness check (round-off or a term is missing) rather than an accuracy
   gate; and local surface distributions still need the traction route — that part remains open.

   **v2 (2026-08-30): EXPLICIT ADVECTION is now carried.** The high-order advection adds exactly
   one more RHS term to the same composed step, `A_i = rho*(FOU_i − HO_i)` as `buildRhs`
   assembled it, so the budget subtracts `A_i` beside `f_c`. It is **stashed**, not recomputed:
   recomputing would read the projected `u^{n+1}` while the RHS used the Picard iterate `u^k`, and
   the two differ by the projection — a silent O(1) attribution error. The IMPLICIT upwind path
   folds advection into the MATRIX instead, so the reaction is no longer of this form and stays
   refused, along with porous / variable properties / domain BCs / ghost projection / drag /
   fluid-only star modes. See §7 item 8 for what the extension exposed.

2. **A masked solid cell is not a fluid sample — fixed, but the same class of bug may sit
   elsewhere.** The force integral read the masked 0 in solid cells as a physical velocity. Static
   geometry hides it (0 *is* the wall velocity); moving geometry does not, and the Galilean pair
   measured the integrated force at **+7.08e+01 in the lab frame and −1.71e+02 boosted** — wrong
   sign, ratio −2.42 — while the velocity field itself was frame-invariant to 7e-7. Substituting
   the wall velocity fixes it and is bit-identical when nothing moves. **Worth auditing every other
   consumer that differences the velocity field across a wall** (the advection stencils, the
   collocated face-averaging, any post-processing) for the same assumption.

3. **Centre of rotation when an encoded instance leaves `center` at the origin.** *(Partly
   softened 2026-08-30: with `principal_frame` re-expressing shapes COM-at-origin, the
   translation-as-centre heuristic is exact for any shape that went through the pipeline.)* flow uses the
   instance's own translation in that case, and the encoded `center` when it is nonzero. That makes
   `add_instance(sphere, translation=c, ang_vel=w)` do the obvious thing, but it is a heuristic: a
   body genuinely meant to spin about the world origin cannot say so by leaving `center` at zero.
   The alternative is to require `center` explicitly and ignore the translation.

4. **Fresh cells — RESOLVED 2026-08-31: seeded with the local wall velocity, and it is now the
   DEFAULT** (flow `1a01769`). The concern below was right and understated: inheriting the solid's
   value is not merely "not obviously right at larger CFL", it costs a **resolution-independent
   drag bias** on any moving body.

   The remedy is the one this item proposed. `seedFreshCells()` sets a just-uncovered staggered
   point to `uBc_` — the owning instance's rigid-body velocity at the nearest wall point, already
   computed for the no-slip datum. Bounded (no extrapolation), no new field, and exactly the old
   behaviour when nothing moves, so a static run stays bit-identical.

   *Measured* on a sphere that physically translates through the grid, oscillating at δ/R = 1,
   where the LINEARISED run (boundary condition oscillating, geometry static) is an exact internal
   reference — itself validated to 0.23% against Stokes (1851) in the gallery's
   `oscillating-sphere` page:

   | | drag bias vs the linearised answer | RMS(F_2δ)/\|F₁\| | 5-harmonic residual p2p |
   |---|---|---|---|
   | static reference (the floor) | — | 6.98e-04 | 2.29e-03 |
   | moving, seeding OFF | **+2.6 … +2.9%** | 2.1e-02 … 6.5e-02 | 3.5e-02 … 2.3e-01 |
   | moving, seeding ON | −0.04 … +0.38% | 8.2e-04 … 1.6e-03 | 3.1e-03 … 1.0e-02 |

   The bias without seeding is **+2.91 / +2.61 / +2.71% at R/h = 6.4 / 9.6 / 12.8** — flat under a
   factor-two refinement, the same signature the traction integral's 29% carries. Refinement was
   never going to fix it. The spurious oscillation falls 20–50×, and at R/h = 12.8 reaches
   8.2e-04 against the non-moving floor of 6.98e-04, i.e. within 17% of a body that is not moving.
   `RMS(F_2δ)` is the second-difference measure of Seo & Mittal (JCP 230, 2011, Eq. 12), the one
   the moving-boundary IBM literature uses; the 5-harmonic residual is kept alongside because the
   2δ operator has its own (ωΔt)² rolloff, so the two legitimately disagree on the temporal
   exponent.

   *The decisive diagnostic.* Without seeding the oscillation gets **worse** as Δt is refined
   (2.80e-02 → 4.13e-02 over 100 → 400 steps/cycle) — the literature's signature that the source is
   spatial, not temporal. With seeding it converges (3.07e-03 → 6.26e-04), so the mechanism is gone
   rather than masked.

   *Why the default flipped.* In the resolved CFD-DEM loop the settling gate's total-momentum leak
   falls **1.07e-02 → 1.13e-04** of F_g per unit time (95×) and the slip drift over the last 30
   steps 1.89e-03 → 4.48e-04. The slip ratio moves 0.9989 → 1.0076, both far inside the gate's 5%
   claim; that it moved at all is expected, since the calibration holds the sphere static while the
   settling run moves it, so the old agreement was partly a cancellation of two errors.
   `set_fresh_cell_seed(False)` restores the previous behaviour. Gate:
   `.sdf-campaign-probes/fresh_cell_gate.py`.

   *What it does NOT address.* The second mechanism the literature names — the abrupt change of the
   cut-cell stencil as the interface crosses a face — is untouched. That fresh-cell seeding alone
   recovers the non-moving floor says that term was subdominant here, which matches what the
   sharp-interface papers report, but it is a measurement on one geometry, not a proof.

   *Beyond Stokes.* With advection on, the peak drag on the same oscillating sphere converges onto
   Blackburn's spectral table (Phys. Fluids 14, 2002, Table II; A/D = 1, Re = 20, Ĉ_d = 4.29) as the
   Stokes layer is resolved: **+10.27% → +2.10% → −0.42%** at δ/h = 4.05 / 5.06 / 6.32, with the box
   independent to 0.1% between L/D = 7.5 and 10.

5. **dem has no external-torque API — RESOLVED 2026-08-30: `set_external_torques` shipped.**
   The entry point takes a **WORLD-frame** (N,3) torque — that is what every torque source
   produces — and rotates it into the body frame inside the predictor, where the gyroscopic term
   already lives, so the angular update is Euler's equation entire:
   `dw_body = invI (tau_body − w × I w) dt`. Island sleeping is disabled while a torque is set,
   exactly as it is for external forces. `clear_external_torques()` releases both.

   *Gates* (`torque_gate.py`, OMP_NUM_THREADS=1, one free body, no gravity, no contacts, three
   DISTINCT principal moments I = (0.40, 0.65, 0.90) so no symmetry can hide a frame error):

   | claim | measured |
   |---|---|
   | A. constant torque about each principal axis vs the closed form `w = tau t / I` | rel err **1.8e-05 / 2.6e-05 / 3.4e-05** at 4000 steps |
   | A. that residual is float32 accumulation, not truncation | grows with step count at fixed T: 1.3e-05 (1k) → 1.8e-05 (4k) → 5.4e-05 (16k) |
   | B. torque about a NON-principal axis vs `scipy solve_ivp` (DOP853, rtol 1e-12) on the same system | **4.9e-04** relative at dt=1e-3, order **1.00 / 0.99 / 0.94** (semi-implicit Euler) |
   | B. past the truncation/round-off crossover the ladder inverts | 2.7e-04 (dt=2e-4) → 7.3e-04 (dt=5e-5) — reported, not hidden |
   | C. `L_world(t) − L_world(0) = tau t` | 3.0e-04 … 9.3e-04 relative |

   Gate A is exact by construction (with `w` along a principal axis the gyroscopic term is
   identically zero, so the discrete update *is* the closed form), which is why the only thing left
   in it is dem's float32 state — the trap the plan flagged, measured rather than assumed.
   `ResolvedCfdDem` can now hand the reaction torque over; wiring that is example-side work.

   The kernel-level ctest `integration` now runs with a NONZERO external force **and** torque, so
   both coupling buffers are covered by host-vs-device parity rather than only by the probe.

6. **Rung 3's scope.** Moving geometry currently refuses the ghost-projection, porous and
   variable-density paths outright. That is right for v1 (the wall-flux identity assumes the plain
   cut-cell continuity, and the collocated overlay's `w_bc` slot is attractor-campaign territory),
   but the porous case in particular will want it eventually.

8. **The advection operator is not discretely conservative at a cut wall (new, 2026-08-30).**
   Extending the reaction budget to explicit advection (§7 item 1, v2) made a property of the FLOW
   SOLVER visible that the Stokes gate could not see. The full discrete identity over the fluid
   momentum cells is

       sum_bodies F_c  =  f_c*N_c + sum_i fb_i + sum_i A_i  −  sum_i (rho/dt)(u_i − u^n_i)

   — the viscous fluxes and grad(pi) telescope to zero over the whole fluid region, the last two
   terms vanish at steady state with advection off, and the Stokes form `sum F = f*N` drops them.
   With advection on, `sum_i A_i` is **not zero**: the flux form telescopes over the interior and
   leaves the advective momentum flux through the fluid region's boundary, which at a cut wall is
   reconstructed from stencils that read the masked (wall-velocity) value one or two cells inside
   the solid. In the continuum that flux is exactly zero at an impermeable wall; discretely it is
   an O(h)-class wall term.

   *Measured* (4-sphere bed, porosity 0.902, Re_d ≈ 23, `force_gate.py FORCE_ADVECT=1`, with the
   new `reaction_budget_terms()` decomposition):

   | N | `sum A / (f*N_fluid)` | unsteady term | identity residual with A carried |
   |---|---|---|---|
   | 32 | **−0.965%** | +7.1e-07 | **−6.8e-15** |
   | 48 | **−0.369%** | +7.8e-07 | **−3.7e-15** |

   So the budget itself closes to round-off — it is complete — while the naive `sum F = f*N` form
   misses by exactly `sum A`, which converges away (ratio 2.6 for a 1.5× refinement, ≈ O(h^2.4)).

   *Conservative option taken:* report `sum_i A_i` through `reaction_budget_terms()` and state the
   identity in its full form, rather than either (a) silently absorbing it, which would turn a
   solver property into an invisible force bias, or (b) "fixing" the advection stencil at cut cells,
   which is a change to the momentum operator and to every validated result that rests on it.
   **Action-reaction is unaffected**: the force handed to a body is still exactly the momentum the
   fluid lost through its own wall. What `sum A` says is that the advection scheme itself leaks a
   converging amount of momentum at cut walls — worth knowing before anyone reads a resolved
   CFD-DEM momentum budget at Re where it matters, and the natural place for a conservative
   cut-cell advection scheme if it ever does.

   *Addendum (2026-08-31, ten Cate benchmark — the leak is NOT small for a moving body).* The
   `peclet-examples` page `ten-cate-sphere` (sphere settling in the closed 100×160 mm tank,
   Re 1.5–31.9, fully coupled) turned this from a percent-class curiosity into the solver's
   sharpest open defect. Measured, all at d/h = 8 unless noted, every probe in the page's repo:

   - **Newton audit, moving sphere towed at the E4 speed (Re 32):** F_sphere + F_tank = **+0.32 W**
     (W = the buoyant weight the drag must balance) — versus −0.001 W with advection off at Re 1.5.
     The static-bed table above measured −0.4…−1%; the moving cut wall leaks two orders more.
   - **Confined finite-Re drag is creeping-valued:** the E1 (Re 1.5) settling plateau converges,
     resolution-flat (d/h = 8, 12, 16), onto u/u∞ ≈ 0.78 — the *Stokes* confined value
     (effective K ≈ 1.67) — where the experiment reads 0.947 (K ≈ 1.38): the inertial screening
     of the wall correction never develops. Independent of dt (×½), sweeps (×3.3), and SOU→Koren.
   - **Coupled high-Re trajectories are unphysical:** E3/E4 accelerate past u∞ (peaks 2.2 / 1.9 u∞),
     impossible under any drag law.
   - **Controls that pass:** the identical setup without the tank (large periodic box,
     back-pressure-compensated) settles at 1.03 of the screened expectation; towed-vs-free-fall
     internal consistency in the tank agrees to 2%; Galileo similarity to 1%.

   The "conservative option" above (report, don't fix) was the right call for the static-bed
   percent class; the moving-body numbers now motivate the momentum-operator work it deferred:
   an advective cut-wall flux consistent with the wall velocity (the moving-geometry analogue of
   the rung-3 wall-flux identity), plus its reaction-budget term. Until then, resolved coupled
   motion is quantitatively trustworthy only in the creeping regime.

   *Second addendum (2026-08-31, rung A0 EXECUTED — flow `fb1a1a7`, `469ab7f`; full gate battery
   in `flow/doc/advective_cutwall_flux_plan.md`).* The wall velocity is now fed into the momentum
   advection's inputs: `buildAdvInputs` fills scratch copies of `C[c].u` whose solid-masked rows
   carry `uBc_` (the rigid-body wall velocity the rung-2 machinery already evaluates), and the
   three explicit RHS builders, both implicit-FOU stencil builders and the velocity-MG restriction
   all read them. `maskVelocity`'s global convention is untouched, the fill is gated on
   `hasMotion_` (static scenes byte-identical: 60/60 MPI ctests, regression +0.00 % throughout),
   and `PECLET_FLOW_ADV_WALLVEL=0` is the ablation. **The hypothesis was half right, and the half
   that failed is the more interesting one:**

   | probe | before | after | target |
   |---|---|---|---|
   | Newton audit, towed E4, `sum F/W` | +0.3217 | **−0.0329** | \|<0.02\| |
   | Tow drag E4, `F/W` at 0.955 u* | 1.5421 | **1.0866** | ~1.0 |
   | Blackburn peak `Cd`, δ/h = 4.05 | +10.16 / +10.27 % | **−0.76 / −0.66 %** | 0 |
   | Blackburn peak `Cd`, A/D = 0.5 | +6.71 % | **−0.54 %** | 0 |
   | ten Cate E1 peaks, d/h = 8/12/16 | 0.781 / 0.777 / 0.749 | 0.803 / 0.797 / 0.766 | 0.947 |
   | ten Cate E3 / E4 peaks (× u_inf) | 2.16 / 1.87 | 2.03 / 1.77 | < 1 |
   | unconfined periodic control | 1.0322 | 1.0843 | ≈1.03 |

   So `sum A` at a MOVING wall was real and is now closed — the towed-E4 residual is below that
   probe's own advection-OFF floor of −0.0695 — and the 10 % excess this defect was putting on
   finite-Re moving-body drag against a spectral reference is gone. But the ten Cate benchmark
   does **not** recover: E1 is still resolution-flat at the creeping value and E3/E4 still exceed
   u_inf. **The confined finite-Re failure is therefore NOT the advective cut-wall flux**, and
   §7 item 8's diagnosis of it (the 2026-08-31 first addendum, and the `peclet-examples` ISSUES
   entry) is superseded on that point. Three concrete threads replace it: the towed and
   free-falling sphere now DISAGREE at E4 (drag 1.087 W at 0.955 u* against a fall peaking at
   1.77 u_inf, where at E1 they agreed to 2 %); the unconfined periodic control shifted 5 %, so
   the extension velocity has a bulk effect away from any confining wall; and the Blackburn ladder
   is now flat at −0.7…−2.2 % where it used to converge, i.e. a small resolution-INDEPENDENT
   deficit replaced a large resolution-dependent excess. **Rung A1 (aperture-weighted cut-face
   fluxes, D2) is NOT indicated by any of this** — nothing in the remaining symptoms implicates D2.

   *Also found en route, unrelated:* `.sdf-campaign-probes/force_gate.py FORCE_ADVECT=1` returns
   NaN at every N (`CutcellMG::solvePCG: preconditioner produced non-finite z`), which is why the
   static-bed `sum A` table above could not be re-measured. Pre-existing — the pre-A0 module
   reproduces it exactly — so it wants bisecting against the 2026-08-31 WO-M/WO-O/WO-P landings.
   `FORCE_ADVECT=0` passes at 2.2e-15 / 3.3e-15.

9. **The reaction TORQUE is not the reaction force — RESOLVED 2026-08-31 (flow `16e91ec`): the
   transposed-stress wall term, added in closed form.** The chain that closed it, kept because each
   link is load-bearing: (a) the rotating sphere measured a **structural −31%** (table below), flat
   under every refinement; (b) the cause is exact — the budget measures the Laplacian-form wall
   flux, the physical traction adds `μ(∇u)ᵀ·n`, and for a rigid no-slip wall moving with angular
   velocity Ω that missing traction is **`μ(n×Ω)` pointwise** (tangential derivatives of u on the
   surface equal the rigid-body field's `[Ω×]`; continuity kills the normal piece; verified against
   the analytic rotlet to 3e-11). Its FORCE integral is zero over a closed surface — why the
   exactly-gated force identity never saw it — and its TORQUE integral is exactly ONE THIRD of the
   Stokes torque (predicted −33.3% vs the −31% measured; Maitri et al., Comput. Fluids 175 (2018)
   111–128, same 33–34% plateau on an IBM omitting the same term); (c) the fix integrates
   `μ r×(n dA×Ω)` over cut cells with the EXACT aperture wall-area vectors — no interior
   reconstruction, no near-wall gradient, zero when nothing rotates, force untouched.

   *Gated* (`rotation_gate.py`, the new standing probe): static spin vs `8πμa³Ω` went from the
   structural −31% to **+3.47 / +2.42 / +2.19%** (N=64/96/128 at R/h=9.6) and **+2.89 / +2.61%**
   (R/h=14.4/19.2) — CONVERGING on both ladders, tracking the aperture first-moment
   discretisation, net force at 1e-13 throughout. Dynamically, `ResolvedCfdDem` with
   `apply_torque=True` decays a freely spinning sphere (physical inertia) at **1.0389×** the same
   box's calibrated rotational drag (coupling `a6f8b02`). `apply_torque` stays off by default only
   for the dem default-inertia trap. **E8 (Jeffery orbit) is UNBLOCKED.**

   Still open from this item: the TRACTION torque's linear drift (decoupled solid-centred pressure
   cells accumulate under the incremental scheme and the surface integral samples them) — the
   diagnostic route only; pinning those gauge cells to zero is the known fix, deferred because the
   pressure driver is under concurrent VoF work.

   *(the original measurement, kept as the record)* With dem's
   `set_external_torques` in place (item 5), `ResolvedCfdDem` can hand the per-instance reaction
   torque over — and doing so by default was wrong. The force is exact because the per-cell
   `−grad(pi)` **telescopes** over an owner region to the region-boundary flux plus the wall
   pressure force. That argument does not survive taking the first moment: `Σ r × grad(pi)` over
   the region does not telescope the same way, so the reported torque has no equivalent derivation
   behind it.

   *Measured.* On a body-force-driven translating sphere (N=48, 600 steps), where the true
   hydrodynamic torque is exactly zero by symmetry:

   | quantity | reaction | traction (diagnostic) |
   |---|---|---|
   | \|T\| / (\|F\|·R) | **3.2e-07** | 5.0e-14 |

   Three orders apart. The reaction torque is small, but it is at *its own* round-off floor rather
   than at the field's, and it has never been checked against a case where the torque is genuinely
   nonzero. Applying it also exposes a second trap: **dem's default inverse inertia is unrelated to
   the grain's size**, so a torque handed to a grain whose inertia was never set spins it up at an
   arbitrary rate — with `apply_torque=True` and no `set_inv_inertia`, the settling gate diverges
   to \|U_slip\| = 5.9e+09 in 600 steps.

   *Conservative option taken:* `apply_torque=False` by default (coupling `3b24934`), the torque
   still computed and reported through `torques()`, and both facts written into the class
   docstring.

   **MEASURED 2026-08-31 — it is not merely unvalidated, it is WRONG by 31%.** The clean test is a
   sphere spinning in quiescent Stokes flow: the torque is `8πμa³Ω` exactly, and a sphere is
   invariant under rotation about its own axis, so the geometry never moves and none of the
   moving-boundary machinery is in play.

   | N | R/h | c | reaction torque | traction torque | net force |
   |---|---|---|---|---|---|
   | 64 | 9.6 | 1.41e-02 | **−30.54%** | −4.22% | 1.1e-13 |
   | 96 | 9.6 | 4.19e-03 | **−31.57%** | — | 2.9e-13 |
   | 128 | 9.6 | 1.77e-03 | **−31.24%** | — | 4.0e-14 |
   | 96 | 14.4 | 1.41e-02 | **−31.04%** | +32.01% | 4.6e-13 |
   | 128 | 19.2 | 1.41e-02 | **−31.00%** | −36.92% | 1.0e-13 |

   The reaction torque is flat over a factor of 8 in box volume, 3.4 in solid fraction and 2 in
   R/h, and unchanged at 2000 steps versus 600 — a **structural** deficit, not a discretisation or
   convergence one, and not the periodic array (which must vanish as c → 0). The traction torque is
   worse: not biased but *erratic*, spanning −37% to +32%. The net force on the same runs is at
   1e-13, i.e. the run that gets the torque wrong gets the force exactly right.

   *THE CAUSE, and it is exact.* The viscous operator here is the Laplacian `∇·(μ∇u)`, not the full
   stress divergence `∇·[μ(∇u + ∇uᵀ)]`. For constant μ and a solenoidal field the two agree in the
   INTERIOR, since `∇·(∇uᵀ) = ∇(∇·u) = 0` — but not as a BOUNDARY TRACTION, and the reaction
   budget's wall term is exactly a boundary traction. For the isolated Stokes rotlet
   `u = (A×r)/r³`, on `|x| = a` with `n = x/a`,

       (∇u)·n  = −2(A×x)/a⁴          (∇uᵀ)·n = −(A×x)/a⁴

   so the transposed part is exactly HALF the plain gradient **pointwise on the surface** — one
   third of the sum before any integration. With `∮ x×(A×x) dS = (8π/3)a⁴A` and uniform pressure,
   the full traction gives `−8πμa³Ω` and the Laplacian-only traction gives exactly `−(16/3)πμa³Ω`,
   two thirds. Predicted deficit **−33.33%**, measured **−31.0%**, the gap being discretisation
   (and it deepens toward the prediction as the box grows: −30.54 → −31.58 → −31.82% at
   c = 1.41e-02 → 1.77e-03).

   *Why it hid.* The transposed term integrates to **zero in the net FORCE** (Gauss + continuity)
   but does not cancel under the `r×` weighting of the torque. A solver validated on drag alone
   never sees it — which is the argument for making the rotating sphere a standing gate.

   *Not novel.* Maitri et al., *Comput. Fluids* **175** (2018) 111–128, doi
   10.1016/j.compfluid.2018.08.018 — same group — ran exactly this a-priori test on the earlier
   Deen et al. (2012) IBM, which omits the same term, and measured **34.34 / 33.04 / 33.24 /
   33.32%** at a/h = 5/10/20/40: the same resolution-independent plateau, with the stated cause
   "the ignored transposed terms contribute 1/3 of the total analytical torque value".

   *A repair that failed, and why.* Reading `R_i = −∇π_i + F_wall,i`, one might add
   `Σ r × ∇π` back with the momentum operator's own staggered pressure gradient. Tried: it moves
   the error from −31% to **−84%**. The pressure moment is not the missing piece, because the
   missing piece is in the viscous term. Reverted rather than left behind a flag.

   *A SECOND, independent defect on the traction route.* On the same steady field the traction
   torque does not converge at all — it walks linearly with step count, −26% → +83% over 4000
   steps, crossing the exact answer on the way. Cause: the cut-cell pressure operator decouples
   solid-centred cells, nothing pins their value, the incremental scheme keeps accumulating into
   them, and the surface integral samples them. Measured split, on a velocity field steady to four
   digits from step 200: `std(P)` over FLUID cells is constant at 7.3e-07, over SOLID cells it
   grows linearly 2.5e-04 → 1.6e-03, and the traction torque tracks the solid. Every drag result is
   unaffected — this only surfaces where the physical pressure is uniform and has nothing to mask
   it.

   *Consequence.* A freely rotating resolved grain is not supported. The Jeffery orbit (E8 of the
   gallery's SDF-showcase plan) is **blocked**, not merely unbuilt — attempting it would silently
   be ~31% off. Gallery page: `examples/rotating-sphere-torque`, which carries the exact gate and
   both ladders.

10. **Per-body attribution carried the owner-boundary pressure flux — RESOLVED 2026-08-31 (flow
   `1d95260`, v4).** The spec's own words flagged it ("per-body attribution is the control-volume
   one over the owner partition; the region-boundary fluxes … cancel exactly in the total") without
   quantifying the per-body error. The gallery's ten-Cate work did: a sphere translating through a
   closed analytic tank — the first ASYMMETRIC multi-instance case — had **half its drag booked to
   the tank** (λ = 0.62 against a physical floor of 1.36, with the identical single-instance
   periodic control healthy at 1.42), and the Jeffery dry run's spheroid-between-plates torque was
   mis-attributed enough for a **−44% orbit period**. The fix removes, for every fluid-fluid
   staggered face whose two momentum points have different owners, the shared cell's π from both
   sides' telescoped sums — pairwise, so the total identity is untouched; wall faces are skipped
   (their remainder IS the wall pressure force); single-instance runs are bit-identical. Bonus:
   the 4-sphere gate's per-sphere spread was the boundary flux all along, and drops
   **4.87e-03 → 5.72e-09**. Tank drag after: λ = 1.89 decaying on the impulsive-start history
   toward the physical range.

7. **The periodic-Stokes reference.** The rotlet order claim is only decidable where the naive
   image sum is a good reference — measured as R/L ≲ 0.05. A Hasimoto/Ewald periodic rotlet would
   make the gate valid at any R/L and is the right thing if this becomes a standing regression.

## 8. Decisions

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
