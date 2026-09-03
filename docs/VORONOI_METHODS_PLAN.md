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
(Perot/Nicolaides) AND collocated (Rhie–Chow-type momentum interpolation), ruled 2026-09-03.**
A Voronoi facet is perpendicular to its seed connector *by construction*, and a power facet keeps
that property; the two-point flux `(φ_j − φ_i) A_ij / d_ij` is therefore consistent with no
non-orthogonal correction, and the pressure Laplacian is the same `L` as V3. Put normal fluxes on
facets and pressure on seeds (the discrete-exterior-calculus form): exactly divergence-free,
kinetic-energy conserving in the inviscid limit, and the same operator carries over unchanged to
the moving mesh of track D. The collocated variant shares C1's operators and `L`, stores the
velocity vector at seeds, and pays with a momentum-interpolation compatibility term — the same
staggered-vs-collocated pair `flow` carries (`docs/studies/staggered_vs_colocated.md`), so the two
variants are gated against each other on every C case. The remaining mesh-quality error is **skewness** (facet centroid off
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
| **B1 Energy library for grids** | on V1: volume target `Σ(V_i/V_ref,i − 1)²` (existing), facet tension `Σ A_ij` (roundness — existing as the two-type interface term, generalised to all facets), **centroidal / Lloyd** `Σ ∫_{V_i} |y − x_i|² dy` (second moments per cell from the per-vertex scatter — new geometry), wall-fit term; weights `w` as extra DOFs for full volume control | each term FD-exact; on a periodic box the combined energy from a random start reaches the equal-volume BCC/FCC-like state the literature reports for CVT (a-priori: volume variance → 0, skewness → 0) | M |
| **B2 Global redistribution** | the local-Newton stall (memory: "a local method cannot move seeds between pores") closed by topological moves: split cells with `V > β V_ref`, remove cells with `V < V_ref/β`, re-seed by the graded-shell heuristic (`seed_graded`) inside the loop; graded targets `V_ref = s(φ)³` | packed-bed pore mesh reaches `max |V/V_ref − 1| < 0.1` with zero dead cells, including in throats; example page re-rendered | M |
| **B3 Internal `PolyMesh`** | assemble ordered facet polygons (from dual edges, as `sectionPolygon` does) into an owner/neighbour polyhedral mesh with wall patches — the **internal** `PolyMesh` that track C consumes (ruling: no OpenFOAM writer for now); VTU polyhedra writer for viewing; quality report (non-orthogonality = 0 by construction, skewness, aspect, volume ratio) | watertightness (Euler characteristic per cell, `ΣA = 0` per cell, facet reciprocity) machine-exact; VTU round-trips volumes and facet areas to 1e-14 | M |
| **B4 Grid quality is solver quality** | a Poisson equation with a manufactured solution on B1 grids of decreasing skewness (two-point flux, V4) | second-order convergence in `h` once skewness < 0.1; error ∝ skewness at fixed `h` — the measurement that fixes the weights in the combined energy | S |

Deliverable: `peclet.voro.generate_mesh(scene, size_fn, energy_weights) → PolyMesh` in Python,
distributed (the optimiser's Newton system already runs on `GraphAMGDevice`; the tessellation
runs on `DistributedMovingTessellation`).

---

## 5. Track C — Navier–Stokes on the static polyhedral grid

| rung | deliverable | gate | size |
|---|---|---|---|
| **C1 Discrete operators on `TessellationView`** | facet-flux 1-form, divergence (exact), two-point Laplacian `L`, Green–Gauss and least-squares cell gradients, Perot velocity reconstruction; wall (`kBoundaryFacet`) and periodic facets | `div(grad φ)` on a manufactured solution second order; `L` symmetric to 1e-15 and identical to `ot_optimizer`'s Laplacian; adjointness `⟨div u, p⟩ = −⟨u, grad p⟩` machine-exact | M |
| **C2a Covolume projection** | staggered covolume scheme (V4): explicit/semi-implicit momentum on the facet normals, projection with `L`, `GraphAMGDevice`-PCG; viscous term via the reconstructed velocity or the covolume Laplacian | Taylor–Green vortex: second-order decay rate; kinetic energy non-increasing inviscid; divergence ≤ 1e-12 per step | L |
| **C2b Collocated projection** | seed-centred velocity vector, Green–Gauss/least-squares gradients from C1, Rhie–Chow-type facet-flux interpolation, the same `L` and PCG; one `FlowSolver` with a `layout` switch, as `flow` has | the same TGV gates as C2a; covolume vs collocated compared on TGV, Poiseuille and C4 at matched seeds (order, checkerboard freedom, cost per step) — a `docs/studies/` page | M |
| **C3 Body-fitted boundaries** | no-slip / slip / inflow-outflow on wall patches; pressure-driven periodic forcing as in `flow` | Poiseuille between SDF slabs: exact to round-off for the parabolic profile on a uniform Voronoi grid (the two-point flux is exact for quadratics on orthogonal meshes) | S |
| **C4 Cross-code gate** | periodic sphere array (Zick–Homsy) and the packed bed: permeability from the Voronoi grid vs `flow`'s cut-cell IBM (`verify_periodic_spheres_sdflow.py`) — the roadmap's "same SDF geometry through CFD + packing + Voronoi" harness | `k` within 1 % of Zick–Homsy and of `flow` at matched cell count; convergence with B2 grading documented | M |
| **C5 MPI + Python** | 2-ring `VoronoiHalo`, distributed `L` through core's halo; `peclet.voro.FlowSolver(mesh)` | np = 1, 2, 4 bit-exact to single rank (the flow standard); Python drives the whole C4 study | M |

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
   (C2a, C2b), gated against each other.
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
