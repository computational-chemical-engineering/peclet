# Physical domains and units — the solver takes the world in its own units

*Plan, 2026-09-06. Status: PROPOSED, awaiting the decisions in §8. Nothing implemented yet.*

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

## 8. Decisions requested

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
