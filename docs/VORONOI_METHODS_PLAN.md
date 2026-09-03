# Voronoi / convex-cell methods plan — one differentiable cell complex, many methods

Status: **APPROVED 2026-09-03** (draft 2026-09-02; the §12 questions were answered — see §12 for
the rulings that changed rungs B3, C2, D0/D1, F1 and A4). Companion to [ARCHITECTURE](ARCHITECTURE.md),
[MULTIPHYSICS_PLAN](MULTIPHYSICS_PLAN.md), [VOF_PLAN](VOF_PLAN.md),
[ANALYTIC_SDF_GEOMETRY](ANALYTIC_SDF_GEOMETRY.md) and the voro design notes in
`voro/docs/` (`free_surface_design.md`, `power_cell_solver_spec.md`,
`voronoi_gpu_research_program.md`). Written the way the VoF plan was written: an inventory
first, a verdict on the architecture second, then rungs with a-priori gates an executor can
run. `file:line` references are snapshots — **re-grep before acting**.

The suite directives that shape every rung here: device-first and MPI-distributable from the
start (host = oracle only); first principles over literature (derive, then use the literature as
a cross-check, never port-and-rationalise); measure with a-priori tests; match or exceed the best
massively-parallel codes in every component including setup; Python bindings everywhere.

---

## 0. The thesis

`voro` today is a **differentiable convex-cell complex**: a power/Voronoi tessellation of moving
seeds, clipped by SDF solids, whose per-cell volumes, per-facet area vectors and their derivatives
with respect to the seed positions and power weights are published every step, incrementally on
the GPU and under MPI. Every application the brainstorm listed — body-conforming grid generation,
a Navier–Stokes solver on that grid, semi-Lagrangian fluids whose cells travel with particles,
interfaces and wetting from interfacial energies, deformable droplets and bubbles, contact
detection for polydisperse spheres, and a particle-centred pore-network CFD-DEM — is **the same
object with a different functional on top and a different rule for how time enters**:

| application | DOFs | functional / constraint | time |
|---|---|---|---|
| grid generation (B) | seeds `x`, optionally weights `w` | volume targets + facet tension + centroidal term + wall fit | static minimisation |
| NS on the static grid (C) | face fluxes, cell pressures on a **fixed** complex | incompressible NS | Eulerian |
| moving-cell fluid (D) | `x` (material), `w` (pressure) | kinetic + `Σσ_ij A_ij + Σσ_s A_wall − Σ p_i (V_i − V_i⁰)` | Lagrangian, variational |
| droplets with a free outer surface (E) | `x`, `w` of the liquid cells only | cap-area energy of the union of balls + volume constraint | Lagrangian |
| contact detection (F) | `x`, `w = r²` | none — read the facets | per DEM step |
| cell-network CFD-DEM (G) | pressures on the particle cells | Darcy/Poiseuille network on the facets | quasi-steady per DEM step |

The unifying piece of design work is therefore small and shared: a **cell free energy**
`F(x, w) = Σ_ij σ_ij A_ij + Σ_i σ_s,i A_wall,i + Σ_i e_i(V_i)` with its exact gradient routed
through the existing `chainToDofs<Policy>` seam, a **volume constraint solved in weight space**
(the graph Laplacian `L_ij = A_ij / 2d_ij` that `ot_optimizer.hpp` already assembles is *exactly*
the pressure Poisson operator of the moving-cell fluid), and one **time-integration layer**. Build
that once and the six applications are consumers. That is also where peclet's uniqueness lies:
no other code carries mesh generation, a body-fitted solver, a Lagrangian multiphase solver and a
DEM coupling on one incremental GPU power diagram with derivatives.

---

## 1. What already exists (re-grep before acting)

### 1.1 Engine (`voro/include/peclet/voro/`)

- **ConvexCell** dual-triangle cells (`convex_cell.hpp`): a vertex is a triple of plane indices,
  ≈ 3.5 KB per cell; clip closest-first with a security-radius early-out. Per-vertex scatter
  geometry: volumes, facet area vectors, first moments, `∂V/∂n_k`, `∂A_k/∂n_l`
  (`geomVolumeAreaGrad`), `sectionPolygon(p0,u)`.
- **Plane policies** (`plane_policy.hpp`): `Voronoi`, `Power` (`n = αr`, offset
  `d = ½(|r|² + w_i − w_j)`), `chainToDofs<Policy>` = the normal-to-DOF Jacobians, FD-validated.
  Power cells are exact in the **small-weight regime** (`d > 0`); a seed-excluding live face
  (`d < 0`) is unrepresentable in the foot-point form, and the periodic **min-image** power diagram
  is not an exact partition at large weight spread (`test_power_cells` `oracleFill`, ~1–4 %).
- **Cold build** (`tessellator.hpp`): Morton counting-sort grid + presorted worklist gather; the
  publish step fills the read-only `TessellationView` CSR (`tessellation_view.hpp`: volumes,
  `facetNbr`, `facetArea`, `facetConnect` = `dV/dn`, `cellFacetCount`); wall facets carry the
  `kBoundaryFacet = −2` sentinel and *do* get area vectors.
- **Incremental update** (`repair.hpp` `MovingTessellation`, `topology_store.hpp`,
  `verlet_skin.hpp`, `reeval_tessellation.hpp`): two-pass repair under a Verlet-skin worklist,
  power-aware, `fellBack = 0`, `step()` reproduces the cold rebuild to 5e-16. **Hard-wired
  `NoSdf`** at both build sites (`repair.hpp:202`, `:437`).
- **SDF clipping** (`sdf.hpp`): `SdfSphere/SdfBox/SdfHollowCylinder` (delegating to
  `peclet::core::geom::prim`), `SdfGrid` (core `sampleGrid`), `SdfSpheres` (periodic union of
  balls), and since 2026-09-01 **`SdfScene`** wrapping core's `evalTree` — capsule, torus, cone,
  ellipsoid, superquadric, CSG, per-node transforms, sampled grids — for the clipper and the
  optimisers. Iterative tangent-plane clip (`maxCuts`), which **recedes** from curved walls (the
  ~7 % cross-section rim in the packed-bed example). `addSdfWallForce` + `sdfHessian`: the
  differentiable wall, exact for flat walls, first-order on curved ones (sphere 1e-2 in
  `test_sdf_policy`).
- **Optimisers**: `mesh_optimizer.hpp` — `meshVolumeOptimize` (host; relative volume energy,
  log-barrier, ideal-gas free energy `−V_ref log V`, Gauss–Newton with Jacobi / coloured GS /
  **GraphAMG** / steepest descent, Armijo), `meshVolumeOptimizeDevice` (device, with the wall
  term from published wall-facet areas), `interfaceMinimize` (Surface-Evolver-style
  `Σ_{type_i≠type_j} σ A_ij`, host + device, **reconstructs each cell** because `∂A/∂n` is not
  published); `ot_optimizer.hpp` — semi-discrete OT volume control on the weights, Newton on the
  facet Laplacian using core's `MomentumOp`/BiCGStab (plateaus at the periodic ~1 % floor).
- **Physics** (`physics/`): `ExplicitEuler` velocity-Verlet with EOS pressure (atomic-free
  gather) and the viscous NS term, full rebuild or repair per step; `interfaceEnergy` is energy
  only — **no interfacial force on the published path**.
- **MPI** (`mpi/`): `VoronoiHalo` (core decomposition + NBX ghosts) and
  `DistributedMovingTessellation` (global Allreduce trip test, re-gather + cold rebuild, else local
  repair); 1-ring halo closes cells, **2-ring** needed for the dynamics. ctests np = 1, 2, 4.
- **Python** (`src/voro_bindings.cpp`): `Tessellation` (box, build, step, volumes, neighbour
  counts), `Simulation` (Euler/NS), `VoronoiHalo`, free functions `optimize_volume_mesh`,
  `optimize_pore_mesh` (spheres only), `sdf_voronoi_cells`, `sdf_voronoi_section`,
  `minimize_interface`. **No scene geometry, no weights, no SDF on the two classes.**
- **Tests**: 12 device ctests (invariants, power cells, SDF policy, SDF scene, mesh optimiser,
  ConvexCell unit/adjacency/per-vertex, benches) + 2 MPI benches × 3 np; a Python smoke test.

### 1.2 Elsewhere in the suite that this plan leans on

- `core/include/peclet/core/geom/` — the analytic SDF layer (Layers 0–4 complete): primitives,
  scene tree + `SceneQueryDevice`, `bodyProperties`, quadrature apertures, `peclet.core.geom`
  Python authoring. Moving geometry (kinematic wall velocity) shipped for `flow`.
- `core` solvers — `GraphAMG` / `GraphAMGDevice` (mesh-agnostic SA-AMG), `MomentumOp` /
  `MomentumSolver` (sparse operator + Krylov) — the algebra for every Poisson solve below.
- `flow` — the validated cut-cell IBM NS + VoF (Laplace, Cox–Voinov, capillary rise, imbibition
  pages E1–E8): the **reference solutions** for cross-code gates in tracks C and D.
- `dem` — XPBD + Hertz–Mindlin, ArborX broad-phase, Lubachevsky–Stillinger packings
  (`dem/pack.py`): the polydisperse packings and the contact oracle for track F, the particle side
  of track G.
- `coupling` — `CfdDem` (unresolved point-particle CFD-DEM, Python composition of flow + dem):
  the host of the deformable droplets in track E and the Eulerian comparison for track G.
- `pnm` — the Voronoi-PNM lineage (`pore_extraction.hpp:464`: throat flux through Voronoi facets,
  pore pressure at Voronoi vertices): the throat/pore vocabulary for track G.

### 1.3 The droplet brainstorm — what could be recovered

The session transcript is not retained on this machine; the *outcome* survives in
`voro/docs/free_surface_design.md` and `power_cell_solver_spec.md`, and in a memory note that
the power-cell solver physics was deliberately parked until that brainstorm. Reconstructed
content, treated as the design of record for track E:

1. A droplet (or bubble) is a **cluster of power cells** whose seeds are the liquid "particles";
   the surrounding gas need **not** be meshed.
2. Its **outer surface is read off the same power diagram**: the union of balls
   `B_i = ball(p_i, √w_i)` has boundary equal to the dual of the power diagram restricted to that
   union (the weighted alpha shape). Arcs live in the radical planes the cell already stores,
   triple points are the cell's dual vertices, a *buried* cell (`d ≤ 0`, already detected) is an
   interior particle. So the surface is a **post-geometry consumer**, not a second geometry engine.
3. The one new primitive is spherical: the Girard cap area `A_i = r_i² Ω_i` and its derivative
   `∂A_i/∂n_k ∝ arc length`, routed through the unchanged `chainToDofs<Power>`.
4. Surface tension = `γ ΣA_i`; the volume constraint (Laplace pressure) lives in the weights, as in
   the moving-cell fluid. An eight-point acceptance scaffold ending in a Gauss–Bonnet identity.
5. Alternatives for the outer surface (an explicit triangle/spline mesh, or gas cells) were the
   fallback, not the primary.

Everything else in this document is new.

---

## 2. Verdict on the architecture (the decisions this plan makes)

**V1. One free-energy layer, not per-application forces.** Add `voro/include/peclet/voro/energy/`
holding the terms `Σσ_ij A_ij`, `Σσ_s A_wall`, `Σ e_i(V_i)` (volume target / log-barrier /
ideal-gas), the Lloyd/centroidal term, and the cap-area term of track E, each returning energy +
`∂/∂n_k` per facet, combined by the existing chain. Track B's optimiser, track D's forces and track
E's surface tension all call it. The existing `interfaceMinimize` and the optimiser wall block
migrate into it (no numerics change: bit-capture gate, as the SDF relocation did).

**V2. Publish `∂A_k/∂n_l` in the facet CSR.** `interfaceMinimize` reconstructs cells because area
Jacobians are not published; the interfacial force, the wall energies and the free surface all
need them every step. The per-vertex scatter family already computes them inside the build/repair
kernel — publish them (opt-in flag like `withForceGeom`) and delete the reconstruction path.

**V3. Volume constraints are solved in weight space.** Incompressibility, Laplace pressure and
equal-volume grids all become `L(w) δw = V_target − V(w)` on the facet Laplacian, preconditioned by
`GraphAMGDevice`. This requires an **exact-partition power diagram** at the weight spreads those
applications need — so the periodic min-image floor and the `d < 0` limitation stop being "deferred
notes" and become rung A2, a hard prerequisite for tracks D, E, F, G.

**V4. The static NS solver comes in two variants on one operator layer: staggered covolume
(Perot/Nicolaides) AND collocated with the ABC approximate projection — the Almgren–Bell–Colella
scheme `flow`'s collocated solver already uses, NOT Rhie–Chow (user ruling 2026-09-03).**
A Voronoi facet is perpendicular to its seed connector *by construction*, and a power facet keeps
that property; the two-point flux `(φ_j − φ_i) A_ij / d_ij` is therefore consistent with no
non-orthogonal correction, and the pressure Laplacian is the same `L` as V3. Put normal fluxes on
facets and pressure on seeds (the discrete-exterior-calculus form): exactly divergence-free,
kinetic-energy conserving in the inviscid limit, and the same operator carries over unchanged to
the moving mesh of track D. The collocated variant stores the velocity vector at seeds and uses
`peclet.flow`'s approximate projection exactly as SolverColocated does (the method reference is
flow, not Basilisk — user ruling 2026-09-03): the cell pressure gradient is the exact TRANSPOSE
of the centre→face constraint (flow's gauge-exact gradient), used in the incremental predictor and
in the cell correction alike so the pressure does no work on the constraint manifold; the FACE
field is projected exactly with the same two-point `L` and transports the momentum. On the
unstructured mesh the constraint is made second order by extrapolating each cell to the face
centroid (skew correction with the Gauss-exact gradient factor `(I − S)⁻¹`) and the transpose
follows — the same staggered-vs-collocated pair `flow` carries
(`docs/studies/staggered_vs_colocated.md`), so the two variants are gated against each other on
every C case, and the collocated one needs no Rhie–Chow compatibility term at all. **Measured
2026-09-03:** the collocated pair is second order on jittered and centroidal Voronoi meshes (2.11 /
2.08) where the covolume flux is first order (the Perot reconstruction). The remaining mesh-quality error is **skewness** (facet centroid off
the connector), which the centroidal term of V1 minimises — grid generation and solver accuracy
are the same optimisation problem, which is the argument for building B and C together.

**V5. The moving-cell fluid is derived, not ported — and BOTH integrators are built.**
`power_cell_solver_spec.md` sketches a Hamiltonian with a consistent mass matrix and an implicit
midpoint rule. Rung D0 derives the discrete Lagrangian from the cell free energy + kinetic energy
(lumped and consistent-mass forms), checks it against the literature scheme (de Goes et al. 2015
"Power Particles") *as a cross-check*, and D1 implements two integrators behind one interface:
velocity-Verlet + weight projection (explicit, cheap) and implicit midpoint with the consistent mass
matrix (symplectic, non-separable). Both have merit (ruling 2026-09-03); the a-priori gates (energy
drift, volume drift, TGV decay, cost per step) document where each wins rather than picking one.

**V6. Ordering.** Foundation (A) → grid + static solver (B, C) → moving-cell fluid with interfaces
(D) → power-cell contacts and the cell-network CFD-DEM (F, G) → free-surface droplets in `CfdDem`
(E). C validates the geometry with an Eulerian solver whose reference solutions the suite already
has; D reuses C's operators and V1's energies; F and G are the shortest path to a DEM result and
only need A2 + the published radii; E has the most new geometry and the most open modelling
questions, so it goes last but its design doc is already done.

---

## 3. Track A — foundation hardening (prerequisite for everything)

| rung | deliverable | a-priori gate | size |
|---|---|---|---|
| **A0 SDF in the dynamic path + Python geometry** — **LANDED 2026-09-03** | `MovingTessellation<…, Sdf>` / `DistributedMovingTessellation<…, Sdf>`: every gather clips against the provider, wall planes are persisted per cell (`WallStore`, form (û, h) restored for the seed's displacement), and the certificate gained a **boundary watch** (moved wall cell ⇒ re-clip, exact mode; wall-free cell ⇒ `sdfWouldClip`, the cold build's own decision; empty cell re-entering the fluid; seed crossing its own wall plane). Python `Tessellation.set_geometry/set_weights/set_wall_mode/wall_counts`, `Simulation.set_geometry` (flat node encoding of any analytic core scene). **Found and fixed on the way:** the SDF clip committed a vertex-foot tangent plane that excluded the seed (offset ≤ 0, routine on curved walls) on the WRONG side, re-found the vertex up to 24 times and overflowed the cell into a silent zero-volume "dead cell" — the pore-meshing collapse. Now a chord-plane fallback + `ConvexCell::compactPlanes`; overflowed/empty cells persist as empty topology. | `test_sdf_dynamic` (host + CUDA): repair == cold SDF build through a sphere ∪ torus scene, 400 steps, to the **wall-free repair's own accuracy** (measured 1.6e-3 per cell at tol 1e-4·spacing, both paths; the wall-free repair does not tighten with tol — recorded for A4); emptiness agrees cell-for-cell; no fallback. `repair_sdf_mpi_np{1,2,4}`: distributed cold SDF == single-rank cold SDF to 1e-9. Python smoke: sphere scene on Tessellation + Simulation, zero/equal/random power weights. | M |
| **A1 Curved walls to second order** — **VOLUME HALF LANDED 2026-09-03**, force half open | Landed: (i) the dead-cell rescue came with A0 (the chord-plane fallback: the tangent plane at a violating vertex's foot could exclude the seed, was committed on the wrong side, and overflowed the cell); (ii) **second-order wall placement**: after the multi-plane tangent clip, `clipCellAgainstSdf` re-clips the un-cut cell with every wall plane translated into the solid by the sagitta of its FINAL face, `δ = ½ tr(H·M)/|∇φ|/A` (M = the face's second moments about the tangency point, H = ∇²φ) — a re-clip, so the cell stays a valid convex clip and the incremental certificate is untouched; flat walls are bit-identical to the tangent clip (shifts below the Hessian stencil's round-off are zeroed); `TangentOnly<Sdf>` keeps the first-order cut. **Force half, landed 2026-09-03:** the exact in-kernel FD wall Jacobian (`sdfWallFD`, published per cell as `cellWallDV`/`cellWallDA` with `withWallFD`; used by the energy layer's volume and wetting terms) — sphere wall 1194/1200 components at 1e-4 (`test_sdf_policy` (D)), flat wall 894/899 at 1e-5, energy-layer FD on a sphere wall 6e-7 / 9e-7. **Still open:** the sagitta placement's dependence on the neighbour planes through the face polygon's second moments (a cross term the per-plane chain does not see; `test_sdf_policy` (D2) measures it) — until derived, wrap the provider in `TangentOnly` where gradient consistency matters (optimiser at curved walls); the 24-cut cap / chord-plane floor on concave walls; the packed-bed coverage figure was not re-measured. | `test_sdf_curved` (host + CUDA), seeds in the fluid: sphere R=0.25 fluid-volume error tangent 2.0e-3 / 9.8e-4 / 5.5e-4 → sagitta **2.3e-5 / 1.7e-5 / 3.2e-5** at N = 4k / 12k / 32k (88×, 57×, 17×); concave cavity: both methods at a non-monotone 1e-5..1e-4 floor (the vertex cuts already circumscribe), the re-clip stays below 2e-4. **Measured on the way:** with UNIFORM seeds the fluid nearest an in-solid seed belongs to no cell — a first-order deficit of the seeding (0.7 % sphere, 5 % cavity), not of the wall; seed in the fluid only (as graded seeding does). A0's dynamic gate and A3's energy gates unchanged-green. | M |
| **A2 Exact power diagram at large weights** — **RE-SCOPED 2026-09-03** (`voro/docs/power_large_weights_plan.md`) | **Measured:** with `w = r²` of a NON-OVERLAPPING polydisperse packing (RSA, φ = 0.25, radius ratio 1/2/5/10) the power diagram is an exact partition (Σ V − 1 = 0, no buried cells) — by algebra, `d_ij ≥ r_i(r_i + r_j) > 0` for non-overlapping spheres; buried cells (which the engine wrongly empties) need a centre INSIDE another sphere (uniform-random overlapping balls lose 2.5–9 % of the volume at ratio 2–10). So tracks **D, E, F, G do not depend on A2**. **A2a landed 2026-09-03** (`StatusBit` kBuried / kReachExceeded, `MovingTessellation::report()`, Python `build(strict=)` warns/raises + `build_report()`; the Python smoke test's "small" random weights bury exactly one cell — the source of its 8e-5 floor). Remaining: A2b the general `(û, d)` half-space so a buried seed still gets its cell (L, only for overlapping-ball weights), A2c the multi-image gather for reach > L/2 (M, small boxes). | RSA rows: Σ V − 1 = 0 at ratio 1…10 (the plan's `oracleFill` gate, met on packings); uniform-random rows are the A2b gate (Σ V − 1 → 1e-12, empty → 0) | S + (L, M deferred) |
| **A3 Published area Jacobians + energy layer** — **LANDED 2026-09-03** | `buildTessellation(withAreaGrad)` publishes a facet-edge CSR of `∂A_f/∂n_l` (self + edge partners; written by the build kernel from `geomVolumeAreaGrad`, one atomic reservation per cell). `energy/route.hpp` routes a cell's per-facet gradient to the DOFs on the view (Voronoi/Power chain; wall planes via the ONE `sdfWallChain`, now the single source for `addSdfWallForce` and both optimiser wall blocks — the |∇φ|-independent form). Terms: `energy/interface.hpp` (Σσ(t_i,t_j)A), `energy/wall.hpp` (per-species wetting Σσ_s(t)A_wall — a uniform σ_s on a closed wall is a constant), `energy/volume.hpp` (Σe_i(V_i): target / log-barrier / free energy). `interfaceMinimize` rewired onto it; the reconstruction path kept as the test oracle. | `test_energy_layer` (host + CUDA): published Jacobians == per-cell reconstruction to 4e-15 (48k blocks), new interface gradient == old to 6e-16, FD-exact: interface 7e-8 (Voronoi) / 8e-9 (Power, positions AND weights), wetting 1e-8, volume 4e-7 (with a flat wall 2e-7). `test_mesh_optimizer` / `test_sdf_policy` unchanged-green with the shared chain. The incremental path publishes the same CSR (`reevalPublish(..., withAreaGrad)`, prefix-sum reservation; gate (F): 289k blocks == cold build to 5.5e-14, facets matched by neighbour id because the counting-sort grid can permute a cell's plane order between builds). Forces on ghost seeds are not reduced under MPI (D4). | M |
| **A4 Update-throughput harness** — **BASELINE MEASURED 2026-09-03** ([studies/voro_update_throughput.md](studies/voro_update_throughput.md)) | Single-node baseline with the production path (`bench_report --repair 200000 8`): host-openmp 8 threads 5.5 Mcells/s = **12.6×** its cold build at 1e-4 spacing/step; RTX 5080 only 3.4 Mcells/s = **3.2×** (slower than the host!) although its cold build is 2.5× faster — the GPU update path is latency-bound (launch/sync structure of `MovingTessellation::step`, host round-trip counters, per-step grid rebuild). Cold build 1.1–1.4 Mcells/s FP64, flat 100k–1M. **The repair missed ~250 gained neighbour relations per step (0.1 %) on both backends** — the source of the 1e-3 long-run volume error — **fixed the same day** by the near-miss certificate (every (re)build records the candidates whose plane missed the cell by less than ½ skin; the certificate re-tests them each step): wall-free repair exact to 5.5e-11 / 1.2e-15 over 400 steps (tol 1e-4 / 1e-7), SDF path 5.9e-8, at ~77 % of the previous host speedup (9.7× vs 12.6×; RTX 5080 2.6× vs 3.2×) — the gate's rebuild stays at 0.86× cold (lazy emission, the adjacency's pattern). Still to do: the kernel-level split (certify / re-eval / re-clip), fusing the compacts, MPI weak scaling np ≤ 32 on Snellius (**approved 2026-09-03**; right-size `--gpus-per-node`, follow [SNELLIUS](SNELLIUS.md)), a host regression gate in CI | throughput table in `docs/studies/` (done); regression gate (open) | S–M |

A0 and A3 are the first two things to do; A1 and A2 can run in parallel with B/C once A3 is in.

---

## 4. Track B — grid generation (static, body-conforming)

Goal: a polyhedral mesh of the fluid region of any SDF scene, wall-fitted, with controllable size
grading, whose quality is set by minimising one energy.

| rung | deliverable | gate | size |
|---|---|---|---|
| **B1 Energy library for grids** — **LANDED 2026-09-03** | `energy/lloyd.hpp`: the centroidal (CVT) energy with its exact gradient `2V_i(x_i − c_i)` (the shape-variation terms cancel on the bisectors — no area Jacobians needed), the energy value from the facets' second moments published on request (`withMoments`; `ConvexCell::faceMoment2`, signed fan about the foot point, also on `reevalPublish`); `energy/tension.hpp`: uniform facet tension `σ Σ A_f` on the area-Jacobian CSR; the volume target / log-barrier / free energy were A3's. Python `energy_forces(lloyd=, facet_tension=)`. | `test_energy_layer` (H): Lloyd energy on a cubic lattice == h⁵/4 per cell to 1e-16 with zero gradient, FD-exact on a random mesh (4.6e-8); facet tension FD 9.4e-7. `test_grid_relax` (host + CUDA): 40 Lloyd steps on a random N = 4000 grid — **skewness 0.228 → 0.041, volume CV 0.42 → 0.058, Poisson residual consistency 0.17 → 0.044** (the two-point operators' truncation error follows the skewness, as C1 predicted). Not done: the wall-fit term (graded `V_ref` covers it) and weights as extra DOFs on this path (the optimiser has them). | M |
| **B2 Global redistribution** — **LANDED 2026-09-03** (`peclet.voro.redistribute_pore_mesh`, `sphere_union_scene`; `test_voro.py::test_redistribute`) | the loop the position-only optimiser cannot do: ABSOLUTE graded targets `V_ref = s(φ)³`, `s(φ) = clip(s_lo + slope (φ − s_lo), s_lo, s_hi)` (the seed count adjusts until Σ V_ref = the fluid volume — a renormalised target is a moving goal); per round split cells with `V > β V_ref` (wall cells split ALONG the wall: an outward child is merged away), remove cells with `V < V_ref/β` and dead cells, thresholds tightening toward the tolerance, ≤ 10 % of the seeds changed per round; relax with a Lloyd blend (shape) + the graded volume descent (size: `dE/dV = 2r/V_ref` through `energy_forces(dEdV)`, Newton-like step `−r s`); the wall layers re-seeded by the graded-shell heuristic; the best state kept | **Measured (6 random spheres, φ_s = 0.11, from a 2× mismatched uniform start, 40 rounds ≈ 6 s):** uniform target s = 0.10: max |V/V_ref − 1| 0.10–0.14, rms 0.035–0.05, zero dead cells — the plan's < 0.1 gate met at rms level and within 1.4× at max; graded slope 0.3 (s 0.08 → 0.25): rms 0.07–0.08, max ≈ 0.5 (the first wall shell's cells sit 1.5× above target — its radial extent); the example's `clip(φ)` target (slope 1) is unresolvable by any mesh — neighbouring targets differ 8× — rms 0.3–0.5. The position-only optimiser cannot polish from here (it collapses cells: n_empty 26–200); its `sw = 6` on a few hundred seeds read out of the search grid and segfaulted — the grid now clamps the window (`tess_grid.hpp`). No quarto in this environment: the example page is NOT re-rendered (the routine is ready for it). | M |
| **B3 Internal `PolyMesh`** — **LANDED 2026-09-03** (`fv/polymesh.hpp`) | shared vertices (periodic-aware quantised keys), CCW face polygons from the store's re-evaluated cells, owner/neighbour, wall/box patches, cell→faces CSR, the VTU (VTK_POLYHEDRON) writer; no OpenFOAM writer (ruling). **Found on the way, a latent engine bug:** a large cell's worklist (block-rounded, extended by the near-miss margin) can reach a SECOND periodic image of a neighbour and the clip committed both planes; the store then re-evaluated to a different cell (1.24e-3 vs 2.3e-4 on a wall-hugging cell) — the single-domain gather now skips an already-clipped id (the first, nearest image is the min-image the re-evaluation rebuilds). | `test_polymesh` (host + CUDA): periodic random mesh — every interior face once, Euler `V − E + F = 2` on every cell, assembled volumes == engine to 2.4e-15; with a sphere wall the same off the wall layer. **Measured limitation:** along a CURVED wall the mesh is not watertight — each cell clips its wall-adjacent faces with its own tangent plane, so the two cells' copies of such a face differ (107 of 137 wall cells fail Euler); a conforming wall needs one plane per wall EDGE — the B3 follow-up. The quality report is B4's. | M |
| **B4 Grid quality is solver quality** — **MEASURED 2026-09-03** (`test_grid_quality`) | Poisson (C1) on jittered lattices relaxed by 0/3/10/30 Lloyd steps at fixed h = 1/16, and on relaxed 8³/16³/32³ grids | **Result, first principles:** the cellwise residual consistency of the two-point Laplacian tracks the skewness (0.106 → 0.043 as skewness 0.121 → 0.041), but the Poisson SOLUTION error at fixed h does not (3.0e-2 → 2.9e-2, non-monotone) — the solution error is h-limited (order 2.05 on relaxed grids, 2.03 on unrelaxed), i.e. second order by supra-convergence regardless of skewness. So "error ∝ skewness at fixed h" holds for the FLUX / gradient consistency (what transport and the collocated ABC gradient feel), not for the pressure solve; the centroidal weight in the combined grid energy is set by transport accuracy, not by the pressure Poisson equation. Gate as measured: residual monotone in skewness and ≥ 2× lower over the sweep; solution order ≥ 1.8 on relaxed grids. | S |

Deliverable: `peclet.voro.generate_mesh(scene, size_fn, energy_weights) → PolyMesh` in Python,
distributed (the optimiser's Newton system already runs on `GraphAMGDevice`; the tessellation
runs on `DistributedMovingTessellation`).

---

## 5. Track C — Navier–Stokes on the static polyhedral grid

| rung | deliverable | gate | size |
|---|---|---|---|
| **C1 Discrete operators on `TessellationView`** — **LANDED 2026-09-03** | `fv/mesh.hpp` (`FaceMesh`: one record per geometric face, owner/neighbour, area, unit normal, seed distance, both seed-plane distances, face centroid from the published dV/dr, cell→faces CSR with orientation) and `fv/operators.hpp` (divergence of face-normal fluxes, two-point face gradient, `L = div grad`, Green–Gauss gradient, Perot reconstruction, face projection, the V- and F-inner products, a matrix-free Poisson CG with mean deflation). | `test_fv_operators` (host + CUDA): Σ V div = 0, adjointness 1.3e-16, symmetry 0, `L` == the graph Laplacian A_f/d_f 2.8e-16; Perot returns a uniform field to 3e-14. **Measured, first principles:** on a jittered lattice (0.15 h) the Poisson SOLUTION converges at order 2.03 (3.9e-2 → 2.4e-3), while the cellwise residual `L p − f` is inconsistent (order 0.2, ~6 %) — the two-point flux is sampled at the connector midpoint, not the face centroid; that is the skewness term the centroidal energy (B1) removes and B4 quantifies. The plan's "second-order `div grad`" gate was the wrong metric for this scheme; the solution-error gate replaces it. | M |
| **C2a Covolume projection** — **LANDED 2026-09-03** (`fv/covolume.hpp`, `test_covolume_ns`) | face fluxes + cell pressure; face momentum = the exact TRANSPOSE of the Perot reconstruction (⟨Ru,a⟩_V = ⟨u,Rᵀa⟩_F to 1e-15), cell-centred convection with the arithmetic face mean (skew-symmetric to 1e-16 for div-free fluxes — on a Voronoi mesh the face is the bisector so this is also the distance-weighted mean), two-point viscous term on the reconstructed field; SSP-RK3 with a projection per stage; pressure PCG with core's `GraphAMGDevice` on −V L (12 vs 76 CG iterations, coarsest level by smoother sweeps because the Neumann Laplacian is singular) | **Measured:** inviscid TGV energy drift is purely temporal (dt-order 2.96), max div 6e-14; viscous TGV on the cubic lattice order 1.93/1.98 (gate ≥ 1.8 ✓). **On unstructured Voronoi meshes the scheme is first order:** 0.2h-jittered 0.96/0.82 (Stokes-only 0.62/0.59), Lloyd CVT 1.43/1.28 (Stokes-only 1.15/0.85) — grid quality helps as claimed, but the Perot reconstruction is only first-order consistent on non-symmetric cells (the face midpoint rule misses the facet second moments) and Rᵀ Δ₂ R inherits it; the viscous term limits. **C2a′ DEC viscous term — BUILT AND MEASURED 2026-09-03, NOT a remedy** (`fv/dec.hpp`, `test_covolume_dec`; the view now publishes the Voronoi edge lengths `edgeLength` with the facet-edge CSR): Δu = grad div − curl curl with ⋆₁ = A/d, ⋆₂ = ℓ_ε/|t| is symmetric to 4e-14 and dissipative to round-off on random meshes (its virtue), but (i) it is first-order consistent on skewed meshes exactly like Rᵀ Δ₂ R — the face flux is a face AVERAGE while the DEC 1-form wants the connector-MIDPOINT value, the same skewness offset (linear-field residual order 1.0 / 0.93 vs 0.58 / 0.56, similar magnitude on the CVT); (ii) it is INCONSISTENT on the degenerate cubic lattice (cospherical Delaunay: the dual triangles' loops do not close, residual ×h² ≈ 2); (iii) its explicit stability constant is ~8× the two-point Laplacian's (sliver Delaunay triangles, weights ℓ/|t| up to 5.7/h), the RK3 TGV diverges even at dt/8. Verdict: the covolume scheme's second order on unstructured meshes needs skew-free (centroidal) meshes — the B-track's job, and the V4 argument — or the collocated scheme; a DEC viscous term would have to be implicit on the face space. The operator stays available (track D's DEC Lagrangian). | L |
| **C2b Collocated projection (flow's approximate projection)** — **LANDED 2026-09-03** (`fv/collocated.hpp`, `test_collocated_ns`, study `docs/studies/voro_covolume_vs_collocated.md`) | `peclet.flow`'s SolverColocated structure transferred to the Voronoi mesh (user ruling 2026-09-03: flow is the method reference, not Basilisk; the face-acceleration route flow rejected is not used): incremental predictor with the cell pressure gradient = the EXACT TRANSPOSE of the centre→face constraint (flow's gauge-exact gradient = transpose of centerToFace), centre→face constraint `T`, exact face projection with the same `L`, cell correction with the same transpose gradient, `P += φ`. Unstructured extension: the plain `T` interpolates at the connector foot (off the centroid by the skewness), the default `skewCorrected` pair extrapolates each cell to the face centroid with the Green–Gauss gradient times the per-cell factor `(I − S)⁻¹`, `S = (1/V) Σ A t⊗n` (exact for linear fields on ANY polyhedron — Gauss identity), and `G` is the exact transpose of THAT (`faceInterpTranspose`). | **Measured:** adjointness 1e-15 (both pairs), linear field at the face centroid exact (5e-16, skewness 0.24 random mesh); inviscid TGV energy drift O(dt·h²) (−9.7e-4 → −4.9e-4 with dt/2; h-order 2.0), face divergence 3e-14; viscous TGV order: lattice 1.97, **jittered 2.11, Lloyd CVT 2.08** (Stokes-only 2.02/2.01) vs plain pair 1.72/1.17 and covolume face 0.82/1.29 — **the collocated skew-corrected adjoint pair is second order on unstructured Voronoi meshes; it is the default.** Cost: +1 vector Green–Gauss + transpose per projection. Comparison page written; Poiseuille/C4 columns follow with C3/C4. | M |
| **C2c Semi-implicit step (flow's)** — **LANDED 2026-09-03** (`CollocatedNS::implicitDiffusion`, `PressureSolver::setupVelocity`, Python `set_implicit_diffusion`) | flow's step on the Voronoi mesh: explicit convection, backward-Euler viscous solve per component with the two-point Laplacian and the two-point wall term implicit (SPD, GraphAMG-PCG on `V/Δt + ν Σ_wall A/h_A − ν V L`) and the quadratic wall-gradient correction lagged (deferred correction), then the approximate projection with the incremental pressure and the optional rotational update `P += φ − ν div u*` (Timmermans, flow's `rotationalP_`). No diffusive Δt limit: Stokes marches take Δt = 10–20 h²/ν (50–100× the explicit RK3 limit). MPI: the velocity solves use the same hooks (`flow_mpi_implicit_np{1,2,4}`). | **Measured:** Poiseuille reaches the exact parabola to 4e-13 in 154 steps at Δt = 20 h²/ν (plain and rotational alike); the sphere-array drag ladder gives K identical to four digits with 340 / 270 / 260 steps at n = 16 / 24 / 32 against 1100 / 2200 / 3700 explicit (the n = 32 rung now ≈ 3 min, the ctest runs it); MPI np = 1 bit-exact, np = 2 / 4 velocity 2e-11, energy 2e-14 (three PCG solves per step at 1e-12); TGV at CFL ≤ 0.2: the first-order time error sits below the spatial error (2.97e-2 → 2.94e-2 for Δt/4). Second-order time (Crank–Nicolson / BDF2 with AB2 convection) is a follow-up if a transient case asks for it. | S |
| **C3 Body-fitted boundaries** — **no-slip / prescribed wall velocity LANDED 2026-09-03** (`setWallVelocity` on both solvers, `test_body_fitted`) | wall faces of the SDF-clipped cells carry the prescribed velocity: the constraint `T` returns `U_wall·n` on them, the viscous wall flux is the two-point `ν A (U_wall − U_i)/h_A`, the convective wall flux carries `U_wall`, the pressure is Neumann (flow's structure: the wall enters the constraint and the momentum with one operator family). Slip / inflow-outflow patches: follow-up. | **Measured:** Poiseuille between SDF slabs, body force, cubic lattice with the walls halfway between seed rows — the interior Stokes residual of the exact parabola is round-off (4e-16), the wall row's is exactly f/4: the two-point wall flux is the derivative at h_A/2, not at the wall, so the profile is NOT exact — the plan's "exact to round-off" was wrong. With the two-point wall flux the steady state converges at **order 2.00** for both solvers (relative error 8.5e-2 / 2.1e-2 / 5.3e-3 at 4/8/16 cells across the gap). **The wall-anchored QUADRATIC wall gradient (`wallGradientLS`, default on both solvers — flow's `centerToFaceWallAware` idea on the unstructured mesh: least-squares quadratic through the wall value, the cell and its neighbours, tangential variation removed with the cell gradient) makes the parabola the exact discrete steady state: wall-row residual 5e-11, march error 7e-6 at every n** — so the plan's original claim holds with the right wall flux. Wall flux 0, divergence 3e-16; on the lattice the two solvers coincide to the digit. Engine facts found: the tessellator's periodic gather needs every box extent > 2× its coverage radius (a 0.25-thin box segfaults the cell builder — documented in the test); the degenerate cubic lattice produces zero-area non-reciprocal facets that the face mesh now drops (`nDropped`) instead of treating as walls; the pressure CG needs a zero-RHS guard (0/0 on a quiescent start). | S |
| **C4 Cross-code gate** — **LANDED 2026-09-03** (`test_permeability`) | Stokes drag of the simple-cubic sphere array (φ = 0.216, Zick–Homsy K = 7.442) on the body-fitted Voronoi mesh: 0.15h-jittered lattice seeds clipped by the sphere SDF (fluid volume exact to 2e-5), seeds within 0.4 h of the wall dropped, collocated solver with the quadratic wall gradient, Stokes, tight steady-state stop | **K −2.43 % / −0.96 % / −0.37 % at 16 / 24 / 32 cells per box edge (12 / 18 / 24 per diameter) — second order, on par with flow's cut-cell IBM (−0.49 % at N = 32): the cross-code target is met at n = 32 (1 %) and n = 24 (3 % gate in the ctest).** With the two-point wall flux the same meshes gave −13.4 / −7.5 % (order 1.4): the fat wall cells' two-point shear was the limit, not the geometry. Facts: an unjittered cubic lattice around a sphere is degenerate and overflows the clipper (non-deterministic volumes) — jitter the seeds; `kIncomplete` fires on every wall cell facing the sphere (unclipped extent beyond the gather coverage), harmless when the fluid volume is exact; a seed shell at h/2 overflows the 64-plane cell cap `kMaxP`; φ = 0.45 at n = 32 overflows 2 cells in the thin gaps (dense case open); the explicit march is dt ≤ 0.15 h²/ν (n = 32 ≈ 3 min on 8 host threads). Packed bed + B2 grading: follow-up. | M |
| **C5 MPI + Python** — **LANDED 2026-09-03** (Python: `peclet.voro.FlowSolver(tessellation, viscosity, layout='collocated'|'covolume', amg=True)` with `set_body_force`, `set_stokes`, `set_skew_corrected`, `set_wall_gradient_quadratic`, `set_wall_velocity`, `set_velocity`, `step`, getters; `test_flow_solver`. MPI: `fv/distributed.hpp` `GhostExchange` over `VoronoiHalo` (core ORB + particle halo, host forward of any per-owned array) installed on `CollocatedNS`/`PressureSolver` through hooks; `buildFaceMesh(view, aux, nOwned)` keeps facets toward ghosts as interface faces owned locally; cell fields sized owned+ghost, refreshed per stage (predictor, gradient, transpose moments, pressure); PCG with exchanged search direction, all-reduced dots, per-rank block-Jacobi AMG; `tests/kokkos_mpi/test_flow_mpi` = `flow_mpi_np{1,2,4}`) | **Measured (12³ jittered lattice, TGV, 20 steps):** np = 1 bit-exact to the single-rank reference; np = 2 / 4 agree to **3e-15** in velocity and **2e-16** in energy (the flow standard asks ~1e-12), face divergence 2e-14, PCG 28 / 36 iterations vs 11 single-rank (block Jacobi). The isolated-solve gate (true residual == recursive residual, K·1 = 0, symmetry, ghost order) caught the one bug: the mean deflation used the rank-local total volume (setup ran before the hooks), which makes the deflated RHS not globally mean-free and CG on the singular Neumann system diverges. Open: the covolume solver's hooks (same pattern), a device-resident halo (the exchange round-trips through the host), Python `FlowSolver` over a distributed tessellation. | M |

Where it sits versus `flow`: `flow` stays THE Eulerian solver; C is the body-fitted alternative
for geometries where cut cells pay (thin gaps, very high accuracy near curved walls) and the
Eulerian half of track D. Reuse core's algebra; do not reuse `flow`'s MAC kernels.

---

## 6. Track D — moving-cell (semi-Lagrangian) fluid with interfacial energies

The cells are the fluid parcels; seeds move with the material velocity, so there is no advective
flux across a material facet, interfaces stay sharp by construction, and each species' volume is
the sum of its cells' volumes. Incompressibility is the constraint `V_i = V_i⁰` enforced through
the weights (V3).

| rung | deliverable | gate | size |
|---|---|---|---|
| **D0 Derivation + design doc** | discrete Lagrangian from the V1 free energy + kinetic energy in both the lumped and the consistent-mass (spec §1.1) forms; equations of motion incl. the metric force; the weight projection as the Lagrange multiplier; viscous dissipation on the moving mesh (existing `viscous.hpp` re-derived on the covolume form); cross-check against Power Particles | a written doc `voro/docs/moving_cell_fluid.md` with the a-priori gates below fixed **before** code; user review | S |
| **D1 Incompressible moving-cell solver, two integrators** | `MovingCellFluid` with `integrator = verlet_projection` (predictor on `x`, `L(w) δw = V⁰ − V` with `GraphAMGDevice`, corrector) and `integrator = implicit_midpoint` (consistent mass matrix `M(q)`, Newton on the midpoint system with the same AMG-preconditioned Krylov); single species | both: volume drift ≤ 1e-10 per step, TGV decay second order, Poiseuille steady state matching C3 on the same seeds; midpoint: energy drift bounded and oscillation-free over 1e4 steps where Verlet drifts; cost-per-step table — the ruling is that both are kept, the gates say which to default | L |
| **D2 Interfaces and wetting** | species tags; `σ_ij A_ij` forces from the published `∂A/∂n` (A3); solid–liquid `σ_s A_wall` through the wall chain (A1); Young's angle emerges from `cos θ = (σ_sg − σ_sl)/σ_lg`, nothing imposed | static droplet: Laplace `Δp = 2σ/R` from the cell pressures, spurious velocity ≤ 1e-8 `σ/μ`; droplet on a flat SDF wall: equilibrium angle vs Young within 1°; capillary rise in an SDF tube vs Jurin; Rayleigh oscillation frequency of a droplet | L |
| **D3 Porous-media two-phase** | imbibition/drainage in a sphere pack (the VoF E7/E8 cases) on the moving cells; topology changes (coalescence = cells of one species become facet-adjacent; breakup = a species cluster disconnects) with an explicit rule for film rupture | breakthrough capillary pressure vs the VoF page and vs the pore-throat estimate; mass of each species conserved to round-off | L |
| **D4 MPI + Python** | `DistributedMovingTessellation` carries the weights and the species; ownership migration of seeds (core `ParticleMigrator`) | np = 1, 2, 4 identical to the repair tolerance; Python drives D2/D3 | M |

Subtleties to settle in D0 (the "quite some subtleties" of the brief): the seed velocity is
the *cell* velocity, but with Lagrangian cells the seed drifts from the centroid — a Lloyd term or
periodic re-centring with a remap; cell-size dispersion over long runs (needs cell split/merge, the
same machinery as B2); the pressure at an interface facet is discontinuous — which the cell-wise
pressure carries naturally; wall slip at the contact line comes from the wall energy, not from a
Navier length; and viscosity at a species facet (harmonic mean of the two cells, as in `flow`).

---

## 7. Track E — droplets and bubbles with a free outer surface (in `CfdDem`)

Recovered design (§1.3), executed in the order `free_surface_design.md` §7 gives:

| rung | deliverable | gate | size |
|---|---|---|---|
| **E1 `free_surface.hpp`** | arcs from radical faces, triple points from dual vertices, Girard cap area, gate `h_ij < r_i`; `SurfaceView` SoA | closure, volume, orientation, seam, equal-weights regression, lens closed form (criteria 1–4, 6, 7 of the design doc) | M |
| **E2 Cap-area gradient** | `∂A_i/∂n_k` (spherical), routed via `chainToDofs<Power>`; wall contact via the wall chain | Gauss–Bonnet identity to round-off; FD `∂A/∂x, ∂A/∂w` ≤ 1e-4 (criterion 8); continuity at arc birth/death (criterion 5) | M |
| **E3 Deformable droplet** | a `Droplet` = cluster of liquid cells with `γ ΣA_i` + volume constraint in `w`, internal hydrodynamics from D1; the gas is *not* meshed | Laplace pressure, Rayleigh modes, contact angle on a wall (the same gates as D2, now with no gas cells) | L |
| **E4 In `CfdDem`** | each liquid cell is a point particle to the unresolved fluid (drag, void fraction); the droplet's shape responds through E3 | Taylor small-deformation `D(Ca)` in simple shear (drag-only coupling, deviation documented); bubble terminal velocity vs correlations; droplets through a packed bed | L |
| **E5 Outer-surface alternatives** | evaluate an explicit triangulated surface against E1–E3 on the same gates; keep whichever wins, record the verdict | decision doc | S |

---

## 8. Track F — power cells as the contact structure of polydisperse spheres

With `w_i = r_i²`, sphere `i` pokes through its own radical plane to neighbour `j` exactly when
`h_ij < r_i`, i.e. when the two spheres overlap — the same scalar test that gates the free
surface. So the power neighbour list is a candidate set that is a **structural** property of the
packing, refreshed incrementally by the repair path, ~15 candidates per particle independent of
polydispersity — where an AABB broad-phase's candidate count grows with the radius ratio. **The
target regime is dense** (ruling 2026-09-03): slowly rearranging, highly polydisperse packings,
where the topology persists between steps and the repair path does almost no re-clipping.

| rung | deliverable | gate | size |
|---|---|---|---|
| **F0 A-priori proof** | the condition under which every overlapping pair shares a power facet (the overlap lens of `i, j` inside a third ball `k` needs `k` to penetrate both by more than half the overlap — state and prove the bound for a maximum-overlap packing; fall back to the 2-ring for the residual) | written proof + a brute-force counter-example search on LS packings at radius ratio ≤ 10 | S |
| **F1 Contact detection from the power diagram** | `dem` broad-phase provider on `MovingTessellation` (A2 required); contact list = facets with `h_ij < r_i` (+ 2-ring residual) | contact set **identical** to ArborX + brute force on LS packings, ratio 1…10, 1e5–1e6 particles; per-step cost vs ArborX on the same GPU in the **dense** regime (quasi-static compaction, shear of a jammed packing) is the primary table, dilute-fast a secondary honesty check | M |
| **F2 Packing structure for free** | per-particle local solid fraction `V_p/V_i`, coordination, the contact network and the "next-neighbour" ring published to Python | matches the pnm/dem post-processing on the same packings | S |

---

## 9. Track G — cell-network CFD-DEM (particle-centred pore network)

Each sphere owns its power cell; the pore volume around particle `i` is `V_i − V_p,i`, the
facet between `i` and `j` is the throat between their pore volumes (open area
`A_ij − π ρ_ij²` when they touch), and pressures live on the cells. This is a Lagrangian,
grid-free CFD-DEM: the void fraction `ε_i = 1 − V_p,i / V_i` is exact, there is no
scale-separation problem between grid and particle, and the network moves with the particles
through the incremental repair. First-principles closure first (Poiseuille conductance from the
throat's hydraulic radius, derived), then calibrated against `flow`'s cut-cell DNS on the same
packing — the suite can generate its own closure. The literature analogue (DEM-PFV, Chareyre et
al. 2012, on a regular triangulation) is the cross-check, not the source.

| rung | deliverable | gate | size |
|---|---|---|---|
| **G1 Network operator** | conductances `g_ij` on facets, network Laplacian, Dirichlet/periodic pressure drive, `GraphAMGDevice` solve; throat flux and pore pressure fields | on a static packing: Darcy permeability vs `flow` cut-cell IBM and vs Ergun within the closure's stated accuracy; conductance closure derived and its DNS calibration documented | M |
| **G2 Forces on particles** | `F_i = −V_p,i ∇p_i` (Green–Gauss over the facets) + viscous drag consistent with the network's own Darcy law | force balance on a fixed bed = `ΔP · A` to round-off (the discrete identity); fluidisation onset vs `coupling`'s Eulerian CFD-DEM on the same bed | M |
| **G3 Moving network** | pressures and conductances updated on the repaired tessellation each DEM step; pore-volume change rate as a source term (the particles' motion pumps the fluid) | sedimentation / fluidised bed vs `coupling` and vs experiments (Dosta-style benchmark pages); mass conservation to round-off | L |
| **G4 MPI + Python** | `dem.enable_mpi_step` + `DistributedMovingTessellation` share the ORB and the migration | np = 1, 2, 4 forces identical; Python driver `peclet.voro.CellNetworkCfdDem` | M |

---

## 10. Cross-cutting

- **Python object model** (`peclet.voro`): `CellComplex` (build/step/geometry/weights/species/
  scene), `Energy` terms, `MeshOptimizer`, `PolyMesh`, `FlowSolver` (C), `MovingCellFluid` (D),
  `Droplet` (E), broad-phase provider (F), `CellNetworkCfdDem` (G). Zero-copy on core's bridge,
  array shapes per [CONVENTIONS](CONVENTIONS.md) §6.
- **Docs and gallery**: one Quarto page per gate that produces a figure (the VoF campaign's E-page
  model); `docs/studies/` entries for the throughput and cross-code tables.
- **Performance yardsticks** (SOTA directive): Voro++ and the 2026 GPU power-diagram paper for the
  build; Power Particles for the moving-cell fluid; Yade DEM-PFV for track G; OpenFOAM polyhedral
  for track C at matched cell count; ArborX for track F. Report per component including setup.
- **CI**: every rung adds a ctest on host-openmp; CUDA parity in the local batteries
  (`OMP_NUM_THREADS=8 OMP_PROC_BIND=false`); MPI np = 1, 2, 4 for anything distributed.

---

## 11. Milestone summary and dependency order

| milestone | contents | unlocks |
|---|---|---|
| **M0 Foundation** | A0, A3, then A1, A2, A4 | everything |
| **M1 Body-fitted grids + solver** | B1–B4, C1–C5 | the cross-code harness; publication P2 |
| **M2 Moving-cell multiphase** | D0–D4 | publication P3 |
| **M3 Power-cell DEM** | F0–F2, G1–G4 | publication P4 (+ P6 if F1 wins a regime) |
| **M4 Droplets in CfdDem** | E1–E5 | publication P5 |

Publication units this plan is shaped to produce: **P1** the incremental GPU power diagram with
derivatives under MPI (the engine, A4's tables); **P2** orthogonal polyhedral meshes from
energy-minimised power diagrams and a body-fitted NS solver on them; **P3** a Lagrangian
power-cell multiphase solver with wetting from interfacial energies, validated on pore-scale
cases against VoF; **P4** a grid-free cell-network CFD-DEM at GPU scale; **P5** deformable
droplets and bubbles as power-cell clusters inside unresolved CFD-DEM; **P6** power-diagram
contact detection for polydisperse packings.

Sizes: S = one session, M = a few sessions, L = a campaign (a week or more with gates); M0 ≈ 2–3
weeks, M1 ≈ 5–7 (two solver variants), M2 ≈ 5–7 (two integrators), M3 ≈ 3–5, M4 ≈ 4–6, with M1
and the A1/A2 half of M0 overlapping.

---

## 12. Rulings (2026-09-03)

The six questions the draft raised, and the answers that fixed the rungs above:

1. **Grid export.** Internal `PolyMesh` only for now; VTU for viewing. No OpenFOAM writer (B3).
2. **Track C scope.** Build **both** the covolume and the collocated solver on one operator layer
   (C2a, C2b), gated against each other. The collocated one uses the ABC approximate projection,
   as `flow`'s collocated solver does — not Rhie–Chow (added ruling, 2026-09-03).
3. **D0 integrator.** Both have merit: velocity-Verlet + projection and implicit midpoint with the
   consistent mass matrix are both implemented behind one interface (D1); the gates decide the
   default.
4. **Track F.** The dense regime is the interesting one; F1 targets it.
5. **Ordering.** As proposed: D before E.
6. **Snellius.** The scaling campaigns are needed and approved; each run still right-sized
   (billed per allocated GPU).

## 13. Risks

- **A2 was thought to be the load-bearing rung**; measured 2026-09-03 it is not: with `w = r²`
  of non-overlapping spheres the power diagram is already an exact partition (buried cells need
  a centre inside another sphere), so D, E, F, G proceed on the current engine. The general
  half-space (A2b) stays a deferred correctness item for overlapping-ball weights.
- **Curved-wall fidelity (A1)** decides whether B/C meshes are body-*fitted* or body-*approximate*;
  the packed-bed rim is the measured symptom.
- **Topology changes in D3** (rupture/coalescence rules) are modelling choices, not numerics; keep
  them explicit, switchable and gated against VoF.
- **Track G's closure** is the physics risk; the DNS calibration path inside the suite is the
  mitigation and, done well, a result in itself.
