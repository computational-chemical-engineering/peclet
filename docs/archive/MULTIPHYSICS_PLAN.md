# Peclet multiphase / multiphysics framework — implementation plan

Status: **Phases 1–8 done + validated (2026-07-05).** All 8 phases complete: the multiphysics
solver (variable ρ/μ, scalar transport, closures), single-rank CFD-DEM coupling (CUDA-validated),
and the shared-decomposition MPI integration with dynamic load balancing — flow `Solver::redistribute`
(bit-exact mid-run redistribute, np 1/2/4), dem `ParticleHalo::migrateTo` (count-conserving, np 1/2/4),
the reverse (add-reduce) halo `exchange_field_add`, and the ergonomic `rebalance_by_weights` /
`migrate_to_weights` / `CfdDem.rebalance` Python entry points (both codes rebuild the SAME weighted ORB
from one weight field). The **multi-rank coupled physics benchmark** is validated: the fixed-bed Ergun
case run distributed (`test_mpi_fixed_bed_ergun.py`) lands on the Ergun curve to 0.0% and is
bit-identical at np=1/2/4 — the distributed void-fraction deposition, the reverse-halo drag-reaction
fold, and the distributed flow solve reproduce the coupled physics exactly. **Both follow-ups are now
done:** (1) the **agglomerated GraphAMG bottom solve** (`Solver::setPressureGraphAmg`) makes the
pressure solve decomposition-agnostic + mesh-independent under a WEIGHTED ORB — the coarsest level is
assembled as a global CSR and solved by `core::solver::GraphAMG`, validated `test_graphamg_mpi` np
1/2/4 (permeability == single-rank on a weighted ORB); (2) the **moving-particle distributed coupled
path** (`CfdDem` migrates dem onto flow's partition + `dem.step_mpi` each fluid step) reproduces
single-rank across a migration window (`test_mpi_moving_suspension` np 1/2). Two dem distributed-step
limitations remain (not the coupling — every distributed coupling op is bit-identical to single-rank
in isolation): a rank with zero owned particles + an incoming ghost deadlocks the dem step, and a
sustained ill-posed dilute settling suspension is numerically unstable (seeded at np>1 by the solve's
reduction floor).
Audience: a coding agent executing this plan phase by phase. Read `CLAUDE.md` (umbrella),
`flow/CLAUDE.md`, `core/CLAUDE.md`, and `docs/{ARCHITECTURE,CONVENTIONS,INTERFACES}.md` first.

## Progress (2026-07-04)

Done, each committed in its submodule with the single-phase regression bit-exact (+0.00%) and new
ctests, on the `host-openmp` backend:

- **Phase 1 — Field registry.** `peclet::core::FieldSet` (core `58fc5e9`) + flow wiring
  (`42fa0a6`): add_field/get_field/set_field/field_view (zero-copy)/exchange_field. Tests
  `field_set`, `field_registry`.
- **Phase 2 — Scalar transport.** `flow/src/scalar_transport.hpp` + Solver addScalar/advanceScalars
  (`0367343`). Validated: diffusion operator 2nd-order (1.99/2.0), advection conservation 1.8e-16 +
  Koren TVD, adiabatic-IBM conservation 4e-16, Dirichlet steady 7e-4. Test `scalar_transport`.
- **Phase 3 — Property closures + Boussinesq.** `flow/src/property_closures.hpp` + cellForce_ +
  buildRhsForced (`94dc0b3`). Validated: closures vs numpy; de Vahl Davis heated cavity conduction
  Nu=1.0000, Ra=1e4 Nu=2.30 (2.5%) with velocity extrema ~2% vs benchmark. Tests `closures`,
  `tests/study/dvd_cavity.py`. (Also fixed: scalar Dirichlet faces re-opened after set_domain_bc.)
- **Phase 4 — Variable viscosity.** `flow/src/face_props.hpp` + `ibmBuildDiffusionVar` (`e3cb678`),
  rotational fix (`54e25b1`). Validated: two-layer Couette (10× μ jump) harmonic 0.0006% vs
  analytic, arithmetic 1.9%; **incremental-rotational KEPT under varProps** (large-dt/steady-Stokes
  retained: dt=100 conv@200 steps) — the Timmermans term is homogeneous-viscosity-only (Deteix &
  Yakoubi 2018), so the rotational coefficient defaults to the provably-stable constant χ·μ_min
  (`set_variable_rotational('min'|'full'|'off', chi)`; 'full' = pointwise μ(i), diverges at 10×;
  the fully consistent shear-rate projection = deferred upgrade). Velocity-MG off under varProps_.
  Tests `variable_mu`, `tests/study/two_layer_couette.py`.

- **Phase 5 — Variable-density projection** (`ab5ae43`; design doc
  `flow/doc/variable_density_projection.md`). One arithmetic face mean ρ_f everywhere (momentum
  time term via `VarFaceProps`, face-interpolated cell force in `buildRhsVar`/`buildAdvStencilVar`,
  projection coefficient `open_f·ρ₀/ρ_f` + `projectCorrectVar`); coefficients ride the openness
  rails (`copyBlockShifted` ρ-bridge incl. g=1 ghost ring + `setOpenness`, zero CutcellMG changes).
  **Pressure driver = Chebyshev by default under varRho** — MG-PCG stalls on ρ-scaled coefficient
  operators (transfer pair loses CG's SPD structure; 5000 its stuck vs Chebyshev ~20; MG-transfer
  symmetry fix = follow-up). Validated: hydrostatic acid test ratio 3 AND 1000 (steady max|u|
  ~1e-16, ∂P/∂z = −ρ_f g to ~4e-16, cheb ≤ 32 its); uniform-ρ reduction 2e-14; Rayleigh–Taylor
  13× monotone growth via the full transported-c → ρ-closure → gravity chain; regression bit-exact;
  all 19 kokkos ctests green. Tests `vardensity_projection`, `tests/study/rayleigh_taylor.py`.
  Staggered-only v1; collocated `set_density_mode` throws.

- **Phase 6 — CFD-DEM single-rank** (dem `a04f999`, core `5cad36a`, flow `14ad683`, new top-level
  `coupling/` component; doc `coupling/README.md`). dem: per-particle `extForce` SoA +
  set/clear/get_external_forces_view. core: `interp/particle_grid.hpp` trilinear gather/scatter
  (gather exact 1e-13, scatter conserves + adjoint 1e-11). flow: `enable_cell_force()` (external
  RHS force) + `enable_drag()` — **implicit (semi-implicit) linear drag**: a `drag_beta` field on
  the momentum diagonal, so `(ρ/dt+β)u = …+β u_p` (an explicit −βu diverges for a bed's stiff β~1e3;
  implicit is unconditionally stable). New `coupling/` (`peclet.coupling`, DLPack-only, no C++ link
  between flow/dem): `drag.hpp` (Stokes/Schiller/Ergun/DiFelice), `coupling_kernels.hpp` (ε deposit,
  drag+feedback explicit & implicit), `CfdDem` Python driver (periodic fold/fill in NumPy).
  Validated: single-particle terminal slip vs Stokes 0.10% / Schiller 1.4%; uniform fixed-bed
  (1 particle/cell, ε=0.6) Ergun ΔP 0.0% across viscous→inertial (Re_p~6). Regression bit-exact.
  Since extended with the **volume-averaged (porous) fluid** (`porous=True`: full continuity
  ∂ε/∂t+∇·(εu)=0, SIMPLE-like drag-weighted projection, Model-B β/ε drag conversion — see
  `flow/doc/porous_drag_scheme.md`; porous Ergun ΔP ~3%); the original drag-only mode
  (`porous=False`, div(u)=0, a dilute simplification — NOT "Model B") remains for suspensions.
  Atomic deposition (tolerance- not bit-exact). `coupling/` is now its own `peclet-coupling` package + submodule
  (github.com/computational-chemical-engineering/peclet-coupling); the driver is backend-agnostic
  (CuPy device / NumPy host). **CUDA-validated on an RTX 5080**: flow regression bit-exact, all
  multiphysics kokkos tests (scalar/closures/variable-mu/variable-density incl. hydrostatic ratio
  3 & 1000), core P2G/G2P, and the CFD-DEM terminal-velocity + Ergun tests all pass on GPU.

Build/test used: `flow/build_mphys` (host-openmp), `flow/build_ktest_mphys` (kokkos ctests),
`core/build_mphys`, `dem/build_mphys`, `coupling/build_mphys`. NOT yet: CUDA-backend validation,
MPI ctests for the new paths (deferred with the phases).

- **Phase 7/8 CORE PRIMITIVES** (core `0e32f3a`, validated MPI np 1/2/4):
  - **Phase 8a — `redistributeGridFields`** (`core/include/peclet/core/decomp/grid_redistribute.hpp`):
    moves N structured grid fields between two ORB decompositions (box-intersection + NBX brick
    exchange, field-major messages, bit-exact inner-cell movement). Test `test_grid_redistribute_mpi`:
    forward + old→new→old round-trip bit-exact against a known global function, with genuinely moved
    (weighted) block boundaries.
  - **Phase 7 add-reduce — `GridHaloTopology::reverseAdd`** (+ `GridFieldView::addFrom`): the adjoint
    forward-exchange with accumulate (ghost deposits fold onto owners + periodic self-fold). Test in
    `test_grid_halo` (conservation: global inner sum == global ghost count, np 1/2/4).

Remaining = the **MPI-integration WIRING** on top of those primitives:
- **Phase 7 wiring**: `Solver::initMpi` + dem `ParticleHalo::initMpi` overloads taking a shared
  `BlockDecomposer<3>` (a module-level `Decomposition` passed to both); `CfdDem` MPI path (each rank
  couples its owned block, ghost-particle deposits folded by `reverseAdd`); `coupling/tests/
  test_coupled_mpi.py` np1/2/4. Needs the `PECLET_FLOW_MPI` + `PECLET_DEM_MPI` builds of all three
  modules + the coupling under MPI.
- **Phase 8b wiring**: `Solver::redistribute(dec)` (enumerate the FieldSet, call
  `redistributeGridFields`, reallocate the G=2/g=1 blocks, rebuild halos/MG folds/stencils/IBM
  overlay from the migrated sdf, invalidate Chebyshev/warm-start — trap §7.10); dem `migrateTo(dec)`
  (split `rebalance()` into weight-ORB compute vs migration); `CfdDem` combined-weight loop
  (`w = w_fluid + γ·particle_count`). Acceptance: a mid-run redistribution matches the
  never-redistributed run bit-exactly.

Follow-ups: Phase 5 — symmetric CutcellMG transfers for arbitrary coefficients so MG-PCG works under
varRho (Chebyshev covers it meanwhile); Phase 6 — Model-A porous terms, kernel-width deposition,
drag×cut-cell-IBM interaction; Phase 7/8 — device-staged `redistributeGridFields` (mirror GridHalo).

## 1. Goal and constraints

Extend the suite from single-phase constant-property CFD to a multiphase/multiphysics
framework:

- **Variable material properties**: density ρ and viscosity μ as functions of phase
  fraction, composition, temperature, pressure.
- **Additional transported fields**: temperature, concentration, phase fractions —
  arbitrarily many, with field–field coupling (e.g. Boussinesq, T-dependent μ).
- **CFD-DEM** two-way coupling between `peclet.flow` and `peclet.dem`.
- **Hard suite directive**: every path fully on-device (Kokkos: CUDA/HIP/OpenMP) and
  MPI-distributable; host paths only as test oracles (`docs/DEVICE_RESIDENCY_PLAN.md`).
- **Zero performance/accuracy change to the existing single-phase path.** The regression
  suite (`flow/tests/regression/sdflow_regression.py` + `perf_baseline.json`) must stay
  bit-exact with identical iteration counts after every phase.
- **Shared block decomposition with dynamic load balancing**: all methods use the SAME
  ORB block decomposition; after a weighted re-decomposition, every method's data (grid
  fields AND particles) must be redistributable to the new blocks. No method may own a
  private decomposition in coupled runs.
- Simple Python interface in the suite's imperative `set_*` / `step()` / `get_*` style.

## 2. Structural facts the design rests on (verified in source)

- The hot solve loops in `flow` — RB-GS sweeps (`ibmRbgsStencilColor`), `CutcellMG`
  V-cycle/MG-PCG/Chebyshev — run on **stored** coefficient fields: the 7 per-component
  float stencil bands `AC..AT` and the face-openness fields `ox_/oy_/oz_`.
- ρ and μ are scalar members (`flow/src/flow_ibm.hpp:1179`) entering only through
  once-per-step **assembly** kernels:
  - `ibmBuildDiffusion` (`flow/src/cut_cell_ibm.hpp:215`): `A_C=(float)(idiag+6β)`,
    off-diag `=(float)(−β)`, with `idiag=ρ/dt`, `β=μ` (divided-by-dt convention).
  - `buildRhs` (`flow/src/flow_ibm.hpp:656`): `idiag·uⁿ + ρ·advection + f`.
  - `buildAdvStencil` (`flow/src/flow_ibm.hpp:707`): FOU weight `fouw = ρ`.
  - Rotational pressure update (`flow/src/flow_ibm.hpp:1131`): `P += (ρ/dt)φ − μ·div(u*)`.
- The pressure Poisson operator (`buildCutcellOp`, `flow/src/mac_pressure.hpp:23`) is
  **already variable-coefficient in geometry**: face coeff = `openness·(1/h²)`, coarsened
  through `CutcellMG` by openness averaging. ρ does not enter it today. Variable density
  = fold `1/ρ_face` into the same face-coefficient rails.
- Consequence: **variable properties change only assembly kernels**; smoothers/MG/PCG are
  untouched in both modes. This is what makes zero-overhead structural, not aspirational.
- `core`'s `GridHaloTopology` exchange is per-call and duck-typed over a `Field` concept
  (`bytesPerElem/pack/unpack`) — many fields already share one topology. The device
  `GridHalo<T>::exchange(View<T>)` is blocking, one field per call. There is **no field
  registry anywhere** in the suite.
- `core` load balancing that already exists: weighted ORB
  `BlockDecomposer<3>::init(numBlocks, globalSize, weights)` (per-cell weights,
  x-fastest), `rebalanceByParticleCount` + `ParticleMigrator` (used by dem's
  `rebalance()`), `DistributedOctree::rebalance` (AMR). **Missing**: redistribution of
  structured-grid fields between two ORB decompositions — added by this plan (Phase 8).
- dem has **no per-particle force array** (only global gravity in `predictVelocityKokkos`,
  `dem/src/integration.hpp:44`) and no drag/void-fraction/interpolation code. dem↔flow
  today share only offline NumPy SDF arrays. dem builds its **own** ORB in
  `ParticleHalo::initMpi` (`dem/src/mpi_halo.hpp`) — same deterministic algorithm as
  flow's, but a separate instance.

## 3. Architecture decisions

### 3.1 Runtime-dispatched assembly — no `Solver<Grid,Props>` template

Keep ONE `Solver<Grid>` class. Add a runtime flag `bool varProps_` (set when a property
model is registered or a ρ/μ field is written). At each of the ~6 host assembly call
sites: `if (varProps_) { new *Var kernel } else { existing code, character-for-character
untouched }`.

- The existing validated kernels are **never edited** — sibling `*Var` kernels only.
  This removes the whole codegen-drift risk class (FMA contraction, hoisting, float
  rounding) instead of hoping a `UniformProps` template instantiation compiles
  identically.
- No ×2 nanobind classes, no ×2 instantiations of the 1237-line `flow_ibm.hpp`.
- The `*Var` kernels ARE templated on a ~10-line `FaceProps` accessor
  (`KOKKOS_INLINE rho(i) / betaFace(i,f) / idiag(i)`; arithmetic vs harmonic face
  averaging as a policy) — templates at kernel level, not class level.

### 3.2 Field registry: `peclet::core::FieldSet`

Location: `core/include/peclet/core/field/field_set.hpp` (dependency-light: Kokkos View +
`std::unordered_map`), so dem/coupling can share the naming scheme.

```cpp
enum class Centering { Cell, FaceX, FaceY, FaceZ };
struct FieldRec { View<double*> data; int ghost; Centering centering; bool ownStorage; };
class FieldSet {
  FieldRec& add(std::string name, std::size_t n, int ghost, Centering c);      // allocates
  FieldRec& adopt(std::string name, View<double*> v, int ghost, Centering c);  // alias existing member
  bool has(std::string) const;  FieldRec& at(std::string);  std::vector<std::string> names() const;
};
```

FieldSet stores **no halo objects**. In `flow`, all registered fields live on the G=2
velocity block (`e_`) and exchange through the existing `velHalo_`/`velDev_` per call
(`Solver::exchangeField(name)`). The g=1 pressure-MG block stays private to `project()`.
Solver `adopt`s its existing members (`"p"→P_`, `"sdf"→sdf_`, …) so redistribution
(Phase 8) can enumerate everything.

Python: `add_field(name)`, `get_field(name)`/`set_field(name, arr)` (F-order `(nx,ny,nz)`
float64, existing `gatherInner`/`grid_in` pattern), `field_view(name)` (zero-copy DLPack
device ndarray via `core/include/peclet/core/python/ndarray_interop.hpp`),
`exchange_field(name)`.

### 3.3 Scalar transport reusing the momentum machinery

Per scalar: `{CCField c, cOld, b; 7 float bands AC..AT; D (double or field); bc[6]}` on
the G=2 block, registered in the FieldSet.

- **Diffusion**: implicit, openness-weighted 7-band stencil
  (`A_off = −(float)(open_f·D_f)`, `A_C = (float)(1/dt + Σ open_f·D_f)`), solved with the
  existing red-black machinery (`ibmRbgsStencilColor` is stencil-agnostic). IBM boundary =
  **adiabatic/zero-flux for free** (closed faces carry zero flux; solid cells decouple).
- **Advection**: explicit conservative flux-form, new `scalarAdvect` kernel reusing the
  KOKKOS_INLINE limiter helpers from `flow/src/staggered_advection.hpp` (`koren`, `tvd`,
  `fou_flux`, `sou`). Advecting velocity: staggered — the face-normal `C[c].u` directly;
  colocated — the projected face field `uf_/vf_/wf_`.
- **Domain BCs**: Dirichlet ghost `c_g = 2c_b − c_i`, Neumann-flux, periodic via halo,
  following `mac_bc.hpp`'s ghost-fill pattern.
- Divided-by-dt convention throughout; dx=1 grid units (Python converts physical D).
- **Sequencing (segregated, properties frozen per step)**:
  `updateProperties()` → momentum Picard + projection (existing) → `advanceScalars()`
  with the just-projected divergence-free velocity. Scalars-inside-Picard deferred.

### 3.4 Property closures: enum-dispatched device kernels

No per-cell Python, no device virtual dispatch. `flow/src/property_closures.hpp`:

```cpp
enum class ClosureKind { LinearMix, ArrheniusMu, PowerLawMu, BoussinesqForce, Table1D };
struct Closure { ClosureKind kind; CCField out; CCConst in0, in1;
                 std::array<double,8> p; View<double*> tabX, tabY; };
void updateProperties() { for (auto& c : closures_) applyClosure(c); markPropsDirty(); }
```

`applyClosure` = host `switch(kind)` → one dedicated `parallel_for` per kind. Inputs
resolve to any registered field (incl. `"p"`). Applied in registration order (documented —
lets `rho(c,T)` chain after transport). `markPropsDirty()` triggers momentum-band rebuild
and (Phase 5) Poisson-coefficient rebuild + Chebyshev-bounds invalidation.
**Escape hatch**: `set_field("mu", arr)` from Python each step (host F-order or CuPy
DLPack device, zero-copy) + `set_property_mode("variable")`. JIT/user lambdas deferred;
the `Closure` struct is the seam.

### 3.5 Variable-density projection

Face coefficient `openness → openness/ρ_face` (harmonic ρ mean) in a new
`buildCutcellOpVar` + `projectCorrectVar` (per-face 1/ρ on the gradient);
`divergOpen` unchanged. `CutcellMG` levels hold face-*coefficient* fields — the existing
`coarsenOpenAvg` rails reused verbatim on the coefficient. The constant-ρ path keeps
passing raw openness and is untouched. Scaling worked out so constant-ρ reduces exactly
to today's operator. Boussinesq (Phase 3) needs none of this — ρ variation only in the
gravity source.

### 3.6 CFD-DEM: unresolved point-particle, two-way, Python-composed

- Scope v1 was drag-only (ε in the correlation, incompressible fluid); the volume-averaged
  porous fluid (full continuity + drag-weighted projection, Model B) is now implemented and
  validated — see `flow/doc/porous_drag_scheme.md`. The drag-only mode remains as the dilute
  simplification.
- Drag laws: Stokes, Schiller–Naumann, Di Felice, Wen-Yu/Ergun — selectable, double math.
- Generic **trilinear P2G/G2P** kernels in core (`interp/particle_grid.hpp`):
  `trilinearGather` (grid→particle) and `trilinearScatterAtomic` (particle→grid,
  `Kokkos::atomic_add` on double) — physics-free, reusable.
- New top-level **`coupling/`** component → nanobind module `peclet.coupling`, operating
  purely on DLPack device arrays handed zero-copy from `peclet.dem`
  (`get_positions_view`) and `peclet.flow` (`field_view`). **No C++ link between flow and
  dem** — Python composes, matching suite architecture. `CfdDem` driver class:
  deposit ε → interpolate MAC-face fluid velocity at particles → drag →
  `set_external_forces` (dem) + feedback into flow `cellForce_` → N dem substeps
  (drag held constant) → `solver.step()`.
- Precision boundary: particles float, grid double — gather/scatter/drag arithmetic in
  double, cast to float at the particle write-back.

### 3.7 Shared decomposition + dynamic load balancing (all methods, one ORB)

**Constraint (user directive): every method uses the same `BlockDecomposer`, and after a
weighted re-decomposition all data — grid fields and particles — migrates to the new
blocks.** Static-only co-decomposition is NOT acceptable as the end state.

- **Shared handle**: both `flow`'s `Solver::initMpi` and dem's `ParticleHalo::initMpi`
  gain overloads accepting an externally constructed `const BlockDecomposer<3>&`
  (today each builds its own; the deterministic ORB on `(nranks, gsize)` makes them
  coincide, but coupled runs must pass the SAME instance so re-decomposition is atomic
  across methods). Python: a `peclet.core` / module-level `Decomposition` object created
  once and passed to both `init_mpi` calls.
- **New core primitive — grid field redistribution**
  (`core/include/peclet/core/decomp/grid_redistribute.hpp`):
  `redistributeGridFields(oldDec, newDec, fields, ghostWidth, comm)` — intersect the
  rank's old-owned box with all new-owned boxes, exchange sub-block bricks via the
  existing `NbxEngine`, unpack into freshly sized Views (block extents change per rank).
  Device path mirrors `GridHalo`: pack/unpack kernels on device, compact host-staged MPI
  buffers (GPU-aware opt-in via `PECLET_CORE_GPU_AWARE_MPI`). Pure data movement —
  **bit-exact by construction**, ghost cells refilled by a post-redistribution halo
  exchange.
- **flow side**: `Solver::redistribute(const BlockDecomposer<3>&)` — enumerate ALL fields
  via the FieldSet (registered + adopted members: velocity components, P, φ, sdf,
  openness, scalars, properties, forces), migrate inner data, reallocate the G=2 and g=1
  blocks, rebuild `GridHaloTopology`/`GridHalo`, `CutcellMG`/`VelocityMG` MPI folds and
  hierarchies, stencils, IBM overlay (recomputed from the migrated sdf), invalidate
  Chebyshev bounds and warm-start state.
- **dem side**: `rebalance()` split so the weighted-ORB *computation* and the *migration*
  are separable — coupled mode calls `migrateTo(newDec)` with the shared decomposition
  instead of computing its own.
- **Coupled rebalancing loop** (in `CfdDem`): every `rebalance_every` steps, build
  combined per-cell weights `w = w_fluid + γ·(deposited particle count)` (γ tunable;
  `w_fluid` = 1 per fluid cell or openness-based), call
  `BlockDecomposer::init(nranks, gsize, w)`, then `solver.redistribute(dec)` +
  `dem.migrate_to(dec)`. Also usable by flow alone (e.g. cut-cell-heavy subdomains).

## 4. Python API (target)

```python
s = peclet.flow.Solver(nx, ny, nz)            # nothing below used ⇒ current solver, untouched
T = s.add_scalar("T", diffusivity=1e-3)        # + set_scalar_bc(name, face, type, value)
s.set_property_model("mu", "arrhenius", field="T", A=..., Tref=...)
s.set_property_model("force_z", "boussinesq", T="T", T0=300.0, beta=2e-4, g=-9.81, rho0=1.0)
s.set_field("rho", arr)                        # escape hatch (host F-order or CuPy device)
s.step()
v = s.field_view("T")                          # zero-copy device array

cpl = peclet.coupling.CfdDem(flow_solver, dem_sim, drag="wen_yu",
                             rebalance_every=200, weight_gamma=5.0)
cpl.step(dt, dem_substeps=20)
```

## 5. Phases

Each phase is independently committable and leaves the suite green: all existing ctests
(flow `tests/kokkos` 14 + `tests/kokkos_mpi` 18 np1/2/4, dem MPI 6, core 51), the flow
regression suite bit-exact with unchanged iteration counts, on BOTH
`extern/install/host-openmp` and `nvidia-cuda` prefixes. Commit in the submodule at each
validated phase, then bump the umbrella pointer (push straight to main — repo practice).
MPI test registration follows core's `foreach(np IN ITEMS 1 2 4 8)` /
flow's np=1,2,4 pattern; force `-DMPIEXEC_EXECUTABLE=/usr/bin/mpirun`.

### Phase 1 — Field registry (M; core + flow; no physics change)
- Create `core/include/peclet/core/field/field_set.hpp` (§3.2).
- Modify `flow/src/flow_ibm.hpp`: Solver owns `FieldSet fields_` on the e_ block; adopt
  existing members; `addField/fieldView/exchangeField`.
- Modify `flow/src/flow_bindings.cpp`: `add_field/get_field/set_field/field_view/exchange_field`.
- Tests: `core/tests/test_field_set.cpp` (+ CMake registration),
  `flow/tests/kokkos/test_field_registry.cpp`,
  `flow/tests/kokkos_mpi/test_field_halo_mpi.cpp` (registered-field exchange bit-exact
  np1/2/4). Acceptance: F-order roundtrip; regression trivially bit-exact (`step()` untouched).

### Phase 2 — Scalar transport, constant properties (L; flow)
- Create `flow/src/scalar_transport.hpp` (§3.3): `scalarBuildDiffusionOpen`,
  `scalarAdvect`, `scalarBuildRhs`, BC ghost fills.
- Modify `flow/src/flow_ibm.hpp` (`addScalar`, `advanceScalars()` at end of `step()`;
  no-scalar path untouched) and bindings (`add_scalar`, `set_scalar_bc`).
- Tests: `flow/tests/kokkos/test_scalar_transport.cpp`,
  `flow/tests/kokkos_mpi/test_scalar_mpi.cpp`.
- Acceptance: diffusion MMS observed order ≥1.9; periodic Gaussian advection order ≥1.9
  with no TVD over/undershoot (>1e-12); scalar conservation with an immersed solid
  (adiabatic IBM); MPI bit-exact np1/2/4; regression bit-exact.

### Phase 3 — Property closures + per-cell body force + Boussinesq (M; flow)
- Create `flow/src/property_closures.hpp` (§3.4).
- Modify `flow/src/flow_ibm.hpp`: `closures_`, `updateProperties()` at top of `step()`;
  per-component `CCField cellForce_[3]` + `hasCellForce_` — `buildRhs` gets a **sibling
  kernel variant** adding `fb(i)` (never edit the validated kernel body).
- Bindings: `set_property_model(target, kind, **params)`, `set_property_table`.
- Tests: `flow/tests/kokkos/test_closures.cpp` (vs NumPy oracle);
  **differentially heated cavity vs de Vahl Davis** (Ra 1e3–1e5; Nu_avg, u_max/v_max
  within 2%) as `flow/examples/` or `tests/study/dvd_cavity.py`.
- Acceptance: benchmark within tolerance; MPI bit-exact; regression bit-exact (empty
  closure list ⇒ untouched path).

### Phase 4 — Variable viscosity + variable-coefficient momentum (M; flow)
- Modify `flow/src/cut_cell_ibm.hpp`: add `ibmBuildDiffusionVar<FaceProps>` (per-face β,
  per-cell idiag; **compute face averages in double, single cast to float** exactly
  mirroring `(float)(idiag + 6.0*beta)`).
- Create `flow/src/face_props.hpp`: `UniformFaceProps` (test-only bit-identity
  cross-check) + `FieldFaceProps` (arithmetic default, harmonic option).
- Modify `flow/src/flow_ibm.hpp`: `varProps_` branches in `rebuildStencils`,
  `buildAdvStencil` (fouw→face ρ), `buildRhs`, rotational pressure update.
  VelocityMG forced off under `varProps_` in v1 (assert + document; lift later).
- Audit `flow/src/mac_bc.hpp`: domain-BC folds bake ρ/μ into `bcBrhs_`/fold coefficients
  — the Phase-4 test matrix must include an outflow / domain-BC case.
- Tests: `flow/tests/kokkos/test_variable_mu.cpp`,
  `flow/tests/kokkos_mpi/test_varprops_mpi.cpp`.
- Acceptance: `UniformFaceProps`-driven Var kernel **bit-identical** bands vs the scalar
  kernel; two-layer Couette (10× μ jump, harmonic faces) <0.5% vs analytic piecewise
  profile; T-dependent-μ channel MMS; MPI bit-exact; regression + perf baseline unchanged.

### Phase 5 — Variable-density projection (L; flow)
- Modify `flow/src/mac_pressure.hpp`: `buildCutcellOpVar` (precomputed face-coefficient
  fields `open_f/ρ_f`), `projectCorrectVar`; `divergOpen` unchanged.
- Modify `flow/src/mac_cutcell_mg.hpp`: levels hold face-coefficient fields;
  `coarsenOpenAvg` reused verbatim; constant-ρ path keeps passing raw openness (untouched).
- Modify `flow/src/flow_ibm.hpp` `project()` var branch: bridge ρ to the g=1 MG block
  (`copyInner` + MG level-0 halo — see trap §7.3), rebuild coeffs when props dirty,
  **invalidate `chebBoundsSet_`**, default to PCG under `varProps_`.
- Tests: `flow/tests/kokkos/test_vardensity_projection.cpp`,
  `flow/tests/kokkos_mpi/test_vardensity_mpi.cpp`, `tests/study/rayleigh_taylor.py`.
- Acceptance: **hydrostatic balance acid test** (two-layer stratified ρ + gravity:
  u stays 0 to 1e-10 over 100 steps — catches ghost/coefficient bugs); MG-PCG converges
  at density ratio 10³ within an iteration budget (document the arithmetic-coarsening
  ratio limit); Rayleigh–Taylor growth rate vs linear theory ±10%; MPI bit-exact;
  regression untouched.

### Phase 6 — CFD-DEM two-way coupling, single rank (L; dem + core + new coupling/)
- dem: add `V3 extForce` SoA (`dem/src/particles.hpp`); drag term in
  `predictVelocityKokkos` (`dem/src/integration.hpp:44`, `v += extF(i)·invMass(i)·dt`);
  pass-through in `demStep`/`demStepMpi` (`dem/src/sim.hpp`); bindings
  `set_external_forces`, zero-copy `get_external_forces_view`, `clear_external_forces`.
- core: create `core/include/peclet/core/interp/particle_grid.hpp` (§3.6 P2G/G2P).
- Create `coupling/`: `src/drag.hpp`, `src/coupling_kernels.hpp` (ε deposition, MAC-face
  velocity interpolation, drag, momentum feedback), `src/coupling_bindings.cpp`
  (DLPack-only module `peclet.coupling`), `CMakeLists.txt` cloned from flow,
  `python/peclet_coupling/driver.py` (`CfdDem`).
- Tests: `coupling/tests/` — kernel unit tests vs NumPy oracle (host mirror);
  `test_terminal_velocity.py`; `test_fixed_bed_ergun.py`.
- Acceptance: single-particle terminal velocity vs Stokes <1%, Schiller–Naumann <3%
  (Re_p 1–100); fixed bed (ε 0.4–0.6) ΔP vs Ergun within 10% over 3 superficial
  velocities; Σ particle drag = −Σ grid feedback to float roundoff; OpenMP + CUDA.
  Note: atomic deposition ⇒ these tests are tolerance-based, not bit-exact (state in the
  test README so the bit-exact policy elsewhere is protected).

### Phase 7 — MPI coupling on a shared decomposition (M; dem + coupling + core)
- Shared-decomposition handles: `flow` `initMpi` and dem `ParticleHalo::initMpi`
  overloads accepting an external `BlockDecomposer<3>` (§3.7); Python `Decomposition`
  object passed to both.
- core: `GridHalo<T>::exchangeAdd` — add-reduce halo so ghost-layer particles' deposition
  (ε, feedback) folds back into owned cells.
- Coupled driver MPI path: each rank couples its owned block; ghost particles deposit
  into ghost cells → `exchangeAdd`.
- Tests: `coupling/tests/test_coupled_mpi.py` np1/2/4 — terminal velocity + fixed bed
  match np1 within tolerance (atomics); interpolation (grid-only) paths bit-exact;
  all existing flow/dem MPI ctests green.

### Phase 8 — Dynamic co-rebalancing: grid redistribution + combined weights (L; core + flow + dem + coupling)
Two committable milestones:
- **8a (core primitive)**: `core/include/peclet/core/decomp/grid_redistribute.hpp` —
  `redistributeGridFields(oldDec, newDec, fields, ghostWidth, comm)` (§3.7): box
  intersection, NBX brick exchange (reuse `NbxEngine`), device pack/unpack with
  host-staged buffers. Test: `core/tests/test_grid_redistribute_mpi.cpp` np1/2/4/8 —
  round-trip re-decomposition returns bit-identical field contents; randomized weighted
  re-decompositions conserve every value exactly.
- **8b (wiring)**: `Solver::redistribute(dec)` in `flow/src/flow_ibm.hpp` (migrate all
  FieldSet fields incl. adopted members, reallocate G=2/g=1 blocks, rebuild halos, MG
  folds/hierarchies, stencils, IBM overlay from migrated sdf, invalidate Chebyshev/warm
  start); dem `migrateTo(dec)` (split existing `rebalance()` into weight-ORB computation
  vs migration); `CfdDem` combined-weight rebalancing loop (`rebalance_every`,
  `weight_gamma`). Python: `solver.redistribute(dec)`, `dem.migrate_to(dec)`.
- Acceptance: mid-run `redistribute` is exact — a flow solution stepped N times with a
  re-decomposition at step N/2 matches the never-redistributed run bit-exactly (pure data
  movement + deterministic rebuilds); coupled run with `rebalance_every` matches the
  no-rebalance run within atomics tolerance; a deliberately particle-clustered case shows
  improved per-rank step-time balance (timers reported by the test).

## 6. Sizing / order notes

Phases 1→5 are strictly ordered (each validates on the previous). Phase 6 depends only on
Phase 3 (`cellForce_`), so it can run in parallel with 4–5 if two agents work
concurrently. Phase 8a (core redistribution) is independent of 6–7 and can start any
time after Phase 1.

## 7. Risks and traps (carry into every phase)

1. **Never edit a validated kernel body** — sibling `*Var` kernels only; in-kernel
   branches or "harmless" refactors cause FMA/reassociation codegen drift that silently
   breaks bit-exactness on CUDA.
2. **Float stencil bands**: `AC..AT` are `View<float*>` — compute face averages in
   double, cast once, mirroring today's `(float)(idiag + 6.0*beta)`.
3. **Two ghost blocks (G=2 vs g=1)**: ρ must be bridged (`copyInner`) AND ghosted with
   the MG level-0 halo before Poisson-coefficient assembly. Scalars/properties live only
   on the G=2 block. The hydrostatic test is the canary.
4. **Chebyshev bounds** are estimated once and cached (`chebBoundsSet_`) — stale bounds
   under changing coefficients diverge silently. Invalidate on every coefficient rebuild;
   PCG is the varProps default; document Chebyshev as constant-property until bound
   re-estimation is amortized.
5. **MG under large density ratios**: arithmetic coefficient coarsening degrades beyond
   ~10²–10³. PCG wrapping keeps results correct (iterations suffer); harmonic ρ face
   means on the fine level; iteration-count guard in tests.
6. **C-vs-F order at the dem↔flow boundary**: dem arrays C-order float32, flow F-order
   float64 — `CfdDem` must assert strides/dtypes; add a transposed-input unit test.
7. **Atomic deposition nondeterminism**: P2G `atomic_add` breaks run-to-run/np
   bit-exactness — coupling deposition tests are tolerance-based by design; keep every
   grid-only path bit-exact np1/2/4.
8. **VelocityMG × varProps**: `vmg_` setup takes scalar μ/ρ — assert off in v1.
9. **Domain-BC folds** (`mac_bc.hpp`) bake ρ/μ into fold coefficients — audit in Phase 4.
10. **Redistribution rebuild completeness** (Phase 8b): everything derived from block
    extents must be rebuilt — halo topologies, MG hierarchies + their internal halos,
    IBM overlay/idMap, warm-start φ, Chebyshev bounds. Enumerate via the FieldSet +
    a single `rebuildAfterRedistribute()` to avoid drift.

## 8. Explicitly deferred (do not scope-creep into phases)

VOF / level-set interface capturing + surface tension; Dirichlet/Robin scalar BCs at IBM
surfaces / conjugate heat transfer; ρε-weighted inertia + full deviatoric εμ viscous stress in the
porous momentum (accuracy; the Model-B volume-averaged fluid itself is DONE); JIT/user device
closures; batched or start/wait-async multi-field device
halo (only `exchangeAdd` is in scope); VelocityMG variable-coefficient support; AMR
(`core/amr`) unification with structured flow; compressible / low-Mach; energy-conserving
formulations.

## 9. Build / verification quick reference

```bash
# flow (in flow/, venv active):
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/nvidia-cuda" && cmake --build build -j
PYTHONPATH=$PWD/build python tests/regression/sdflow_regression.py        # bit-exact gate
cmake -S tests/kokkos -B build_kokkos -DCMAKE_PREFIX_PATH=$PWD/../extern/install/nvidia-cuda
cmake -S tests/kokkos_mpi -B build_kmpi -DCMAKE_PREFIX_PATH=$PWD/../extern/install/nvidia-cuda \
      -DMPIEXEC_EXECUTABLE=/usr/bin/mpirun     # NEVER let FindMPI pick ParaView's mpiexec
# core: ctest --test-dir build (CPU) / build_kokkos (device); MPI np 1,2,4,8
# dem: cmake -S . -B build -DCMAKE_PREFIX_PATH=... -DDEM_MPI=ON
# Repeat every device test on the host-openmp prefix.
```
