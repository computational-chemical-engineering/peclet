# Physical domains and units — the solver takes the world in its own units

*Plan, 2026-09-06. Status: **PHASE 1 LANDED** (2026-09-06) — D1–D5 accepted as recommended.
core, flow, pnm and coupling are on main; the gate table with its numbers is
[RELEASE_PREP.md §8](RELEASE_PREP.md). Phases 2–4 are untouched and §9.4–§9.5 stand as written.*

**Two deviations from §9, both deliberate, both measured:**

1. **§9.3 U5 asked for `vofAdv_.init(..., hRef)` and it would have been wrong.** Under
   representation (B) — which §3.2 adopts and U2 implements — the colour advector runs on the same
   unit lattice as every other operator, and its Courant number `v*dt'` IS the physical `u*dt/h`.
   Feeding it `hRef` alongside index velocities converts twice. The two literal `1.0` spacings stay;
   what crosses the boundary converts instead (`sigma` in, `kappa` in 1/length out, and every TIME
   both ways: `capillary_dt`, `vof_step_limits`, `advect_vof`, `advect_vof_blocks`,
   `apply_phase_change`, `step_adaptive`).
2. **§9.3 U3's list of setters was short by four.** `set_property_model` on `rho`/`mu` (THE
   documented two-phase spelling), `enable_vof_momentum`, `set_vof_kappa_constant` and
   `set_phase_change_fit_curvature` all carry physical quantities into registered fields or frozen
   state. Without them a two-phase run at h != 1 got a density `lam^3` too high and a capillary time
   step `lam^1.5` too large — silently. The `units_vof_sigma` gate is what found it.

## 0. The decision in one paragraph

Every peclet solver is given a **physical domain** — an origin, an extent per axis, periodicity — and a
**resolution**, and it derives its own cell sizes. Material properties, time steps, forces, boundary
velocities, surface tension and geometry are stated in the user's (consistent) physical units and never
change when the grid is refined, stretched, replaced by an AMR octree or by a Voronoi mesh. Internally
the Eulerian codes keep computing on the unit lattice they are written for, with the metric folded into
per-axis constants of the operator assembly and into the conversions at the API boundary — zero
per-cell cost, and bit-identical to today when the extent equals the cell count. Cells may have three
different sizes. The user never sees `h`.

## 1. Today: where the cell size leaks into the user's problem

| code | domain / spacing today | consequence for the user |
|---|---|---|
| **flow** | grid spacing fixed at 1 (`get_spacing()` returns `[1,1,1]`); geometry, velocities, `mu`, body forces, `sigma`, `dt`, drag, contact angles' slip length all "in cell units" (35+ places in `src/` say so) | the quick start needs `mu/h²`, `F/h`, `u = h·u'`, `p = h²·p'`; refining the grid means re-deriving the inputs; `set_scene` takes cell coordinates; VoF `sigma` is in cell units; cubic cells only |
| **flow VoF** | `advect_wy`, `vof_blocks`, the CSF and the phase-change layer take a uniform `h` (always passed as 1.0); curvature reported in 1/h | ready for a uniform physical `h`; no anisotropy |
| **core AMR** | `AmrFlow::init(octree, h0, origin)` — physical, isotropic; the octree brick is cubic | already physical; `h0` is one number |
| **core halo / decomposition** | index-space (blocks, ghost widths) — unit-free by design | none |
| **core geom (SceneBuilder)** | coordinates are whatever the caller uses; flow's `set_scene` documents them as cell units | scenes built for flow are not reusable by dem/voro without rescaling |
| **dem** | positions, radii, velocities physical; `set_global_scale` for the canonical→world map | none |
| **voro** | box and seeds physical (`set_box`) | none |
| **pnm** | reads VTI `spacing`/`origin`, extracts in voxel units | pore radii, volumes, throat lengths come out in voxels |
| **coupling** | "everything in flow's grid units: cell spacing 1, cell centred at (i,j,k)"; dem positions are handed to flow unscaled | the CFD-DEM problem must be posed with h = 1, i.e. the DEM in cell units |

`docs/CONVENTIONS.md` §7 ("consistent units; the caller supplies spacing, L, rho, mu") states the right
policy; flow does not implement the `spacing` half of it, and `docs/INTERFACES.md` §1 already defines the
`Domain` concept (`length()`, `origin()`, `periodic(axis)`, plus `resolution()` for Eulerian domains)
that nothing constructs.

## 2. How other codes state a system

- **OpenFOAM.** The mesh is in metres (`blockMeshDict` vertices with a `scale` factor); every field and
  property carries a `dimensionSet` (`[kg m s K mol A cd]`) and the solver checks dimensions at run time
  (`nu [0 2 -1 0 0 0 0] 1e-06`). Cells are arbitrary polyhedra; the solver never has a "cell unit". The
  cost is ceremony and a strict SI habit; the benefit is that a wrong unit is an error, not a wrong answer.
- **AMReX / incflo.** `geometry.prob_lo`, `geometry.prob_hi` and `amr.n_cell` per direction; `dx` is derived
  per direction and may differ; properties are physical in a consistent system (no checking). AMR levels
  refine by 2 and inherit the anisotropy. This is the closest relative of peclet's core + flow.
- **CaNS.** `lx, ly, lz`, `nx, ny, nz`, `visc`, `dt` in a consistent unit system; uniform spacing per
  direction, non-uniform in z. Kernels take `dxi, dyi, dzi` (inverse spacings) as arguments.
- **Basilisk.** `L0` (box side), `origin`, `N`; every cell knows its `Delta`; properties physical and
  unit-agnostic. Cubic cells only, by construction of the quadtree/octree.
- **Xcompact3d.** `xlx, yly, zlz` with `nx, ny, nz`, stretching in one direction; physical properties.
- **LAMMPS (DEM side).** A `units` command selects one of several fixed systems (`si`, `lj`, ...); the box
  is physical; nothing is "in particle diameters".
- **FiPy.** `Grid3D(dx, dy, dz, nx, ny, nz)` — spacing per axis is the mesh's first argument.

The common shape: **domain extent + cell count per direction, spacing internal, properties physical,
anisotropy allowed.** Two policies exist for units: OpenFOAM's dimension checking, and "consistent units"
everywhere else. The research codes peclet benchmarks against (CaNS, incflo, Basilisk) all use consistent
units without checking.

**Adopted:** consistent units without run-time dimension checking (CONVENTIONS §7 as written), an explicit
domain object, spacing derived and internal, per-axis spacing allowed. Dimension checking is not worth its
weight for a Python-driven code; a unit table in the API reference does the job.

## 3. Design

### 3.1 One domain description in core, mirrored in every binding

C++ (header-only, `core/include/peclet/core/domain.hpp`, satisfying INTERFACES §1):

```cpp
struct Box      { Vec<3> origin, length; std::array<bool,3> periodic; };
struct UniformGrid { Box box; IVec<3> cells; Vec<3> spacing() const; Vec<3> cellCentre(IVec<3>) const; ... };
```

Python: the constructors take plain keyword arguments, so no package depends on another's Python types
(`peclet-core` is sdist-only and must not become a runtime dependency of the wheels):

```python
s = flow.Solver((nx, ny, nz), extent=(Lx, Ly, Lz), origin=(0, 0, 0))     # spacing = extent / cells
s.extent, s.origin, s.spacing, s.cells                                       # read-only
s.cell_centres()  ->  x, y, z 1-D arrays;   s.meshgrid()  ->  X, Y, Z  (for building SDFs and plots)
```

`extent=None` keeps today's behaviour (`extent = cells`, spacing 1) and is **bit-identical** — every existing
script, test and gallery page keeps working unchanged. A deprecation warning for the omitted extent comes
one release later (§6), so the cell-unit era ends by decision, not by breakage.

The same keywords go on `core.amr.Octree` (root spacing per axis), `pnm` (extraction honours the VTI
spacing; radii/volumes/throat lengths physical), `voro` (already `set_box`), and the coupling drivers (take
the domain from the flow solver, drop their own `h`).

### 3.2 Internal representation for the Eulerian solver: the unit lattice with a metric

Two ways to make flow physical:

- **(A) physical spacing inside the kernels** — every finite difference divides by `h_a`; clean to read,
  but the operator coefficients then carry the physical magnitudes (water at 10 µm cells: `mu/h²` ≈ 1e4
  against `rho/dt` ≈ 1e5·…), and flow stores its operators in **float** (`docs/SCALING_ISSUES.md` #1) — a
  precision risk that today's O(1) cell-unit coefficients hide;
- **(B) the unit lattice with a metric** — keep the discrete algorithms exactly as they are (they are
  index-native: red-black sweeps, cut-cell apertures, multigrid transfers, halo, PLIC) and fold the
  spacing into per-axis constants at operator assembly and into the conversions at the API boundary.

(B) is adopted. With `x_a = h_a ξ_a` and `u_a = h_a v_a` (index-space velocity, cells per time), time
unchanged, the incompressible Navier–Stokes equations become, exactly,

```
Σ_a ∂v_a/∂ξ_a = 0                                                          (unit-lattice divergence, unchanged)
ρ (∂v_a/∂t + Σ_b v_b ∂v_a/∂ξ_b) = −(1/h_a²) ∂p/∂ξ_a + μ Σ_b (1/h_b²) ∂²v_a/∂ξ_b² + F_a/h_a
```

so **anisotropic cells cost only per-axis constants**: a viscous coefficient `μ/h_b²` per derivative
direction, a pressure-gradient weight `1/h_a²` per component (the projection's Poisson operator becomes the
axis-weighted Laplacian that the semi-coarsening multigrid's per-axis `idx2` hooks already carry), a body
force `F_a/h_a`, a wall velocity `U_a/h_a`. Advection is untouched in index space, so the Koren/TVD and the
implicit FOU + deferred-correction paths do not change at all. Cut-cell apertures and wall crossings are
ratios along an axis and are unit-free; only the Robust-Scaled ghost closure, which uses the wall-normal
distance, needs the metric (`d·n_a/h_a` per axis — a normal of an anisotropic index space is `h_a ∂φ/∂x_a`
renormalised). VoF: PLIC on stretched cells is the textbook normalised-cell formulation; the height-function
curvature needs physical column heights; CSF takes `sigma` physical with `κ` in 1/length.

**Reference scales for the float operators.** To keep every stored coefficient O(1) regardless of the
user's unit system, the solver additionally non-dimensionalises with reference scales fixed at construction:
length `h_ref = min_a h_a`, density `ρ_ref` (the fluid density, or the heavier phase), time `t_ref` (the first
`dt`). Internally μ appears as the cell diffusion number `μ t_ref/(ρ_ref h_ref²)`, velocities as Courant
numbers, forces as `F t_ref²/(ρ_ref h_ref)`: exactly the dimensionless numbers that govern the discretisation,
bounded by the physics rather than by the unit system. This is the lattice-Boltzmann "lattice units" idea
applied once, at the boundary. `t_ref` is fixed at construction and does not follow an adaptive `dt`, so no
state is ever rescaled mid-run. A user who never leaves cell units with `dt = 1` sees reference scales of 1 and
byte-identical arithmetic.

### 3.3 What the user-facing API becomes (flow)

| today | after |
|---|---|
| `Solver(nx, ny, nz)` | `Solver((nx, ny, nz), extent=(Lx, Ly, Lz), origin=(...))` — old positional form kept |
| `set_solid(sdf)` in cells | `set_solid(sdf)` — physical signed distances sampled at `cell_centres()` |
| `set_scene(...)` cell coordinates | physical coordinates; `dem`/`voro`/`flow` share one scene unchanged |
| `set_mu`, `set_rho`, `set_dt`, `set_body_force`, BC velocities, `set_surface_tension`, drag, slip length | physical, unchanged names |
| `get_u/v/w/p`, `vof_geometry()['kappa']` | physical velocity, pressure, curvature in 1/length |
| `get_spacing()` = 1 | `spacing` = `extent / cells` per axis |
| `set_domain_bc_profile(face, profile)` | profile in physical velocity |
| `max_open_divergence()` | physical (1/time) |

The MPI path is unchanged: blocks are index-space; each rank knows the global domain.

### 3.4 The other codes

- **core AMR:** `Octree(cells, extent, origin)`; root spacing per axis, children inherit the aspect ratio
  (Morton codes are index-space; `h0` becomes `Vec<3>`); `AmrFlow` gets the same per-axis constants as flow.
  The mixed-level cut band's LS clouds and the sampled builders assume isotropic h today: Phase 3.
- **coupling:** the drivers take `flow.spacing`/`origin` and stop assuming h = 1; the dem↔flow bridge is a
  pure identity in physical coordinates (the resolved driver's scene bridge loses its scale factor).
- **pnm:** extraction on the physical grid; outputs physical; `extract_pore_network(sdf, spacing, origin)`.
- **dem, voro:** nothing to change; their docs gain the same unit table.

## 4. Performance

- No per-cell arrays are added; the metric enters as at most three constants per operator family, folded
  into coefficients that are computed once per (re)assembly.
- At `extent = cells` the constants are exactly 1.0 and every kernel executes the same floating-point
  operations as today ⇒ **bit-identical**, which is the gate (§5).
- Gates on throughput: the regression suite's recorded iteration counts and timings (`sdflow_regression.py`),
  the TGV 512³ single-GPU throughput (`benchmarks/`), the 1536-rank strong-scaling point — all within noise.
- The reference scaling makes the float operator storage *safer* than today, not slower.

## 5. Test gates (each phase lands with its gates)

1. **Bit-identity:** every existing ctest, MPI test, regression baseline and verify script unchanged with
   `extent=None` (36 + 103 + regression + 5 for flow; 157 core; 8 + 24 dem; 24 + 18 voro; 6 pnm; 2 coupling).
2. **Scale invariance:** the same physical problem posed at `extent = cells` and at `extent = 1e-3·cells`
   (and 1e3) reproduces the physical solution to round-off after conversion (target 1e-13 relative on the
   sphere-array Stokes case and on Poiseuille) — the proof that no `h` leaks.
3. **Anisotropic exactness:** Poiseuille between cut-cell walls with `dy = 0.3 dx`, `dz = 2 dx` is pointwise
   exact on the quadratic (the existing exactness fact, now in three spacings).
4. **Anisotropic convergence:** Zick & Homsy sphere-array drag on a `(dx, 0.5dx, 2dx)` grid converges to the
   same reference as the cubic grid; TGV on a stretched box keeps its ~2e-15 kinetic-energy budget.
5. **Float safety:** water in SI at 10 µm cells (`rho = 1e3, mu = 1e-3, dt = 1e-5`) — the sphere-array
   permeability equals the cell-unit run to the float floor of the operator (~1e-6 relative), where today's
   code would have to be run in cell units to get any answer.
6. **VoF:** the surface-tension gates (Laplace pressure, capillary wave, oscillating drop) with `sigma` in
   physical units at h ≠ 1; PLIC conservation on stretched cells (Phase 3).
7. **Coupling:** terminal velocity and fixed-bed Ergun with the DEM in metres and the fluid grid in metres.

## 6. Phases

| phase | scope | files (first order) | effort |
|---|---|---|---|
| **1. Domain + isotropic physical spacing, everywhere** | `core/domain.hpp`; flow constructor keywords, reference scales, conversions at every setter/getter, geometry (sampled SDF + scenes) in physical coordinates, VoF `h` wired to the real spacing, `sigma`/`kappa` physical; AMR `Octree(cells, extent, origin)` isotropic; pnm outputs physical; coupling takes the domain; docs + gallery quick start | `core/include/peclet/core/domain.hpp` (new), `flow/src/flow_ibm.hpp` (assembly + I/O boundary), `flow/src/flow_bindings.cpp`, `flow/src/vof/*` (h plumbing exists), `core/python/amr_bindings.cpp`, `pnm/src/pnm_bindings.cpp`, `coupling/python/peclet_coupling/*.py` | 2–3 weeks; gates 1, 2, 5, 6 (isotropic), 7 |
| **2. Anisotropic cells, single phase** | per-axis constants in the momentum operator (const-coefficient fold, cut-cell/FOU stencil, velocity MG), the pressure operator and its multigrid (aspect-ratio-aware coarsening order: coarsen the finest axis first — extends the semi-coarsening rule in `DECOMPOSITION_AND_MULTIGRID.md`), the Robust-Scaled ghost closure with the metric, domain BCs, outflow census, body forces | `flow/src/mac_bc.hpp`, `mac_cutcell_mg.hpp`, `mac_velocity_mg.hpp`, `mac_approx_projection.hpp`, `cut_cell_ibm.hpp`, `flow_ibm.hpp` | 3–4 weeks; gates 3, 4 |
| **3. Anisotropic VoF and AMR** | PLIC in normalised stretched cells, height-function curvature with physical column heights, CSF; AMR per-axis root spacing through the cut band and the sampled builders | `flow/src/vof/*`, `core/include/peclet/core/amr/*` | 3–4 weeks; gates 4, 6 |
| **4. Retire cell units** | the omitted `extent` warns, then errors; gallery pages restated in physical units (the 45 pages mostly become *shorter*: no conversions); `docs/CONVENTIONS.md` §7 rewritten; unit table in the API reference | docs, examples | 1–2 weeks |

Phase 1 alone delivers what the quick start needs. Phases 2 and 3 are independent of each other after 1.
Total 9–13 weeks of focused work; the family release that carries Phase 1 is a **minor** bump for flow, pnm,
core and coupling (new API, old form kept).

## 7. What breaks, and what deliberately does not

- Nothing in Phase 1–3: `extent=None` reproduces today bit for bit. The **documented meaning** of `sigma`,
  `set_scene` coordinates, `kappa` and `get_spacing()` changes only when an extent is given.
- The coupling drivers' `h` argument is removed (the drivers are young and unreleased outside the suite).
- `set_solid_spheres`, `set_scene`, `set_exact_crossings*` accept physical coordinates; scripts that fed
  cell coordinates keep working while `extent=None`.
- Phase 4 is the only breaking step and is a decision, one release after Phase 1.

## 8. Decisions — all five ACCEPTED as recommended (2026-09-06)

- **D1** Consistent units without dimension checking (§2) — recommended yes.
- **D2** Constructor form: `Solver((nx,ny,nz), extent=..., origin=...)` with `extent=None` = cell units for
  now, mandatory in Phase 4 — recommended yes. (Alternative: a `peclet.Domain` object shared across modules;
  rejected because it would make `peclet-core` a runtime dependency of every wheel.)
- **D3** Reference scales (§3.2) fixed at construction from `(h_ref, ρ_ref, first dt)` — recommended yes;
  they are invisible unless `PECLET_FLOW_REPORT_SCALES=1`.
- **D4** Phase order: 1 → 2 → 3 → 4, with 2 and 3 parallelisable — recommended; Phase 1 first because the
  quick start and every gallery page benefit immediately.
- **D5** Whether `pnm`'s physical outputs and `coupling`'s API change ship in the same minor release as flow's
  (recommended: yes, one family release 0.8.0 named "physical domains").


## 9. Execution guide for the implementing session

This section is written for a Claude Opus session that starts cold. It gives the order of work, the exact
anchors, the recipes, the gates, and the points at which to stop and hand a *design* question to a Fable
session (§9.6) instead of guessing. Read `suite/CLAUDE.md`, `flow/CLAUDE.md` ("Build Commands", "Running
Tests and Verification", "MPI") and `core/CLAUDE.md` first; then this file top to bottom.

### 9.1 Ground rules (non-negotiable)

- Work inside a **flow worktree** (`git -C flow worktree add ../flow-units -b units`), never in the shared
  `flow/` checkout; core edits in the shared `core/` checkout are fine if `git status` is clean there.
  Commit **named paths only** (never `git add -A`), push the submodule first, bump the umbrella pointer last.
- `OMP_NUM_THREADS=4 OMP_PROC_BIND=false` on every run; fresh build trees `build_u_*`; delete a tree before
  reconfiguring; `-DMPIEXEC_EXECUTABLE=/usr/bin/mpirun` on MPI test trees; `PATH=/usr/local/cuda-13.2/bin:$PATH`
  for CUDA.
- **Bit-identity is the first gate of every commit**: with `extent=None` every existing test must produce
  the same bytes. Run `tests/kokkos` (OpenMP + CUDA), `tests/kokkos_mpi` np=1,2,4, the regression suite
  (never `--update`) and the five verify scripts before each push. A changed digit anywhere is a bug in the
  change, not a new baseline.
- Never change numerics while adding the metric. If a kernel needs a *different* algorithm for `h ≠ 1`
  (not just a constant), stop and escalate (§9.6).
- One work order per commit; the commit message names the gate it passed and its numbers.

### 9.2 Recipes

```bash
cd /home/frankp/Codes/suite/flow-units && source ../.venv/bin/activate
export OMP_NUM_THREADS=4 OMP_PROC_BIND=false PATH=/usr/local/cuda-13.2/bin:$PATH
P=$PWD/../extern/install/host-openmp            # or nvidia-cuda
cmake -S . -B build_u_omp -DCMAKE_PREFIX_PATH=$P && cmake --build build_u_omp -j8
cmake -S tests/kokkos -B build_u_kokkos -DCMAKE_PREFIX_PATH=$P && cmake --build build_u_kokkos -j8 && ctest --test-dir build_u_kokkos --output-on-failure
cmake -S tests/kokkos_mpi -B build_u_kmpi -DCMAKE_PREFIX_PATH=$P -DMPIEXEC_EXECUTABLE=/usr/bin/mpirun && cmake --build build_u_kmpi -j8 && ctest --test-dir build_u_kmpi --output-on-failure
PYTHONPATH=$PWD/build_u_omp python tests/regression/sdflow_regression.py          # CUDA tree for the recorded baseline
SDFLOW_BUILD=build_u_omp python scripts/verify_poiseuille_flow.py                  # + periodic_spheres, channel, bfs, lid_cavity
```
Byte comparison of two Python runs: dump `get_u/get_v/get_w/get_p` to `.npz` and compare with `np.array_equal`
(the release session's `bytecmp.py` pattern); OpenMP with a fixed thread count is deterministic, CUDA is not
(atomics in voro's tessellator; flow's kernels are deterministic but compare on OpenMP first).

### 9.3 Phase 1 work orders (in this order)

**U1 — `core/include/peclet/core/domain.hpp`** (new, header-only, C++20). `Box{origin, length, periodic}`,
`UniformGrid{Box, cells}` with `spacing()`, `cellCentre(i,j,k)`, `faceCentre`, `contains`, `wrap` (min-image),
satisfying `docs/INTERFACES.md` §1 (`dim()`, `length()`, `origin()`, `periodic(axis)`, `resolution()`).
Gate: a core ctest `domain` (round trips, min-image, anisotropic spacing) — plain tree, 30 lines.

**U2 — flow constructor + reference scales.** `Solver(int,int,int)` (`flow_ibm.hpp:76`) gains an overload
`Solver(IVec3 cells, Vec3 extent, Vec3 origin)`; store `h_[3]`, `origin_[3]`, `hRef_ = min h`, `rhoRef_`,
`tRef_` (set on the first `setDt`, `flow_ibm.hpp:162`; `rhoRef_` on the first `setRho`, :160). Add
`toIndex*()/toPhysical*()` helpers: velocity component a: `v = u / h_a`, pressure `p' = p·?` — derive from
§3.2 with the reference scales and WRITE THE DERIVATION as a comment block above the helpers; the
mapping must reduce to the identity for `extent = cells, dt = 1, rho = 1`. Bindings (`flow_bindings.cpp:119`):
`nb::init` overload with `nb::arg("cells"), nb::arg("extent") = nb::none(), nb::arg("origin") = (0,0,0)`;
read-only properties `cells, extent, origin, spacing`; `cell_centres()` → three 1-D arrays;
`get_spacing()` (:2488) returns the real spacing. Gate: bit-identity with `extent=None`; a new ctest
`units_identity` constructing with `extent = cells` explicitly and checking every getter.

**U3 — setters and getters convert at the boundary.** Apply the helpers in: `setMu` (:161 — internal
`mu' = mu·tRef/(rhoRef·hRef²)`), `setRho` (:160), `setDt` (:162), `setBodyForce` (:169), `setDomainBc`
velocities (:831), `setDomainBcProfile` (:861), `setVelocity` (:2393) / `getVelocity` (:2389),
`getPressure` (:2446), `maxOpenDivergence` (:2489), `setSurfaceTension` (:7887), the drag/porous setters
(:10213–:10385), `setContactAngle`'s slip length. In the operator assembly the internal quantities are
what today's code sees, so `rebuildStencils` (:4203), `buildRhs*` (:4441–:4759), `setupBcDiffusion`
(:5688), `project` (:5758) do **not** change in Phase 1 (isotropic: `beta = mu'`). Gate: scale invariance
(§5.2) as ctest `units_scale_invariance`: the sphere-array Stokes case at `extent = cells` and at
`extent = 1e-3·cells` (mu, F, dt rescaled physically) agree in physical units to 1e-13 relative; and the
same on Poiseuille (verify script geometry).

**U4 — geometry in physical coordinates.** `setSolid` (:1475) / `setSolidDevice` (:1539) /
`setPressureGeometry` (:897): the SDF is a physical signed distance sampled at `cellCentre` → divide by
`hRef` on entry (isotropic Phase 1; document that anisotropic needs Phase 2's metric). `setScene` (:929):
node/instance reals in physical coordinates → scale translations by `1/h`, radii/params by `1/hRef`, motion
velocities by `1/h` per axis (`set_instance_motion`, :1012 comment says CELL UNITS today). `setSolidSpheres`
likewise. Gate: `units_scale_invariance` extended to the scene path (`set_scene` + `set_solid_from_scene`),
and `test_freeslip` / `test_outflow_backflow` unchanged.

**U5 — VoF on a physical h.** `vofAdv_.init(nx_, ny_, nz_, 1.0, kVofG)` (:2836) and
`vofBlocks_->init(..., 1.0)` (:7274) receive `hRef` (Phase 1 requires `h_x = h_y = h_z`; assert with a
clear message otherwise). `setSurfaceTension` physical; `vof_geometry()['kappa']` (:7802) returned in
1/length. Gate: the VoF ctests bit-identical at `extent=None`; `vof_surface_tension.py`'s Laplace-pressure
and capillary-wave gates re-run with `extent = 1e-2·cells` and physical `sigma` — same physical numbers to
the existing tolerances.

**U6 — core AMR.** `Octree(brick, lmax, origin, h0)` (`core/python/amr_bindings.cpp`) and
`AmrFlow::init(t, h0, origin)` (`amr/flow.hpp:471`): accept `cells, extent, origin`; Phase 1 keeps `h0`
scalar (assert isotropic). Gate: `core/python/test_amr.py` unchanged + one physical-units case (Poiseuille
channel with `h0 = 1/Nc` already exists there — make it the model).

**U7 — pnm and coupling.** `extract_pore_network(sdf, spacing, origin)` returns physical radii/volumes/
lengths (multiply by the VTI spacing it already reads, `pnm_bindings.cpp:88–115`); coupling drivers
(`driver.py:87 self.h`, `resolved.py` scene bridge) take `flow.spacing`/`flow.origin` and drop their own
`h`. Gate: pnm 7199 pores unchanged with spacing 1; `test_terminal_velocity`, `test_fixed_bed_ergun` at
spacing 1 unchanged, then once more with the whole problem in metres.

**U8 — docs + quick start.** `docs/CONVENTIONS.md` §7, `flow/CLAUDE.md` units paragraphs, the API
docstrings (every "cell units" string in `flow_bindings.cpp` — 8 today), the gallery quick start
(`docs/index.md`, `README.md`, `docs/notebooks/quickstart_sphere.ipynb`) rewritten without `h`. Gate:
`tools/release/check_release_state.sh` literal rule; the notebook re-executed.

### 9.4 Phase 2 work orders (anisotropic, single phase) — design points marked ⚑ go to Fable first

**U9 ⚑ derivation note** — `flow/doc/anisotropic_metric.md`: the §3.2 equations carried into every
discrete operator flow has (const-coefficient fold, cut-cell/FOU stencil with implicit FOU + deferred
correction, velocity MG restriction/prolongation, the incremental-rotational projection, the Robust-Scaled
ghost closure with an anisotropic index-space normal, domain BCs, outflow census, backflow stabilisation),
with the exact per-axis constants and where each enters. Fable writes it; Opus implements from it.

**U10 momentum** — `beta = mu_` at `flow_ibm.hpp:4204, :4998, :5365, :5689` becomes `beta_b = mu'/h_b'²`
per derivative axis (`h_b' = h_b/hRef`); `Ac = rho/dt + 2Σ_b beta_b`. Gate: anisotropic Poiseuille exactness
(§5.3) as ctest `units_anisotropic_poiseuille`.

**U11 pressure** — `CutcellMG::setOpenness(..., idx2, idy2, idz2)` (`mac_cutcell_mg.hpp:987`) already takes
per-axis factors: pass `1/h_a'²`; the projection's gradient/correction (`mac_approx_projection.hpp`) gets the
same weights. ⚑ coarsening order for aspect ratios (coarsen the finest axis first; extends the
semi-coarsening rule in `DECOMPOSITION_AND_MULTIGRID.md`) — Fable decides the rule, Opus implements.
Gate: pressure-only ctest (`cutcellmg_*`) with `(dx, 0.5dx, 2dx)` converging at the cubic rate.

**U12 ⚑ ghost closure** — the Robust-Scaled foot point and normal with the metric
(`mac_approx_projection.hpp:373–510`, `cut_cell_ibm.hpp`). Gate: §5.4 sphere-array drag on a stretched
grid; TGV on a stretched box.

### 9.5 Phase 3 (anisotropic VoF, AMR) — ⚑ throughout

PLIC in normalised stretched cells, height-function curvature with physical column heights, the CSF face
force, the phase-change layer's `V_cell`; AMR per-axis root spacing through the mixed-level cut band and
the sampled builders. Fable designs each; Opus implements against the design note's gates.

### 9.6 When to stop and hand over to Fable

Escalate (write the question + the evidence into `flow/doc/units_escalation.md`, commit, and say so) when:
1. a bit-identity gate fails and two focused attempts have not found the cause;
2. a kernel would need a different *algorithm* for `h ≠ 1` (anything beyond a per-axis constant);
3. the scale-invariance gate (§5.2) is off by more than round-off (1e-12) — that means an `h` still leaks,
   and finding it needs the equations, not more runs;
4. any ⚑ item above;
5. the regression suite's recorded **iteration counts** change at `extent=None` (they must not), or the
   reference scales change the float-operator behaviour (the SI-water gate §5.5 fails);
6. MPI np=1 stops being bit-exact to single-rank on OpenMP.

Everything else — plumbing, conversions, bindings, docs, tests, gallery pages — is Opus work.

### 9.7 Definition of done, Phase 1

All U1–U8 landed on flow/core/pnm/coupling main with the umbrella pointers bumped; every existing gate green
and bit-identical; the five new ctests (`domain`, `units_identity`, `units_scale_invariance`, its scene
extension, the VoF physical-`sigma` re-run) green on OpenMP and CUDA; the quick start on the site reads
`Solver((N, N, N), extent=(L, L, L))` with `mu`, `F`, `sdf` physical and no `h` anywhere; RELEASE_PREP
gets a "0.8.0 physical domains" section listing the gates and their numbers.
