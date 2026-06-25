# Adaptive mesh refinement (AMR octree) — design & status

A block-local octree AMR for the suite, intended as a grid for geometric multigrid,
able to coexist with the existing uniform structured grid, and reusable as a general
adaptive tree (e.g. Barnes–Hut for particle methods). Lives in `transport-core`
(`include/tpx/amr/`), built on the `morton` primitive and the ORB `BlockDecomposer`.

## The non-standard choice: per-block local Morton, not one global SFC

The textbook linear octree (p4est/Dendro) keeps **one** global space-filling curve and
partitions it by index ranges. The suite instead keeps the ORB **block** decomposition
(`tpx::decomp::BlockDecomposer`) and gives **each block its own local Morton coordinate
system**. The trade-off — a per-block global-origin offset, and a global ordering that is
"ORB tree, then local Z-order" rather than one flat curve — buys block independence, narrow
codes, and direct reuse of the existing **owner-based** `GridHalo` (a ghost cell maps to
whoever owns its wrapped global cell — no Cartesian assumption) and ORB decomposer.

## Conventions

- **Fine units.** 1 fine unit = a leaf at level 0. A leaf at `level` L covers a `2^L` block
  per axis; its origin Morton code has the low `L*Dim` bits zero (morton's convention).
- **Levels.** Root cells sit at `level = lmax`; refinement decreases level toward 0 (finest).
- **Root brick.** A block is a brick of `brick[i]` root cells per axis (the block's ORB box of
  coarse cells), so it spans `brick[i]·2^lmax` fine units; require `2^Bits ≥ brick[i]·2^lmax`.
  A `1×1×1` brick degenerates to a single-root octree (the Barnes–Hut case); the rectangular
  brick is the grid case. Same data structure either way — it is one local octree per block.
- **Leaf storage.** Leaves tile the block without overlap, stored **sorted by code** (Z-order)
  — the order morton's curve and the device leaf arrays use. Refinement preserves it: a
  parent's `2^Dim` children occupy the parent's code range in ascending octant == ascending
  code order, so a split is a single forward pass with no re-sort.
- **A uniform (unrefined) octree is bit-identical to the existing structured block grid** —
  this is what makes structured ↔ AMR interop clean (structured = degenerate AMR).
- **2:1 (graded) balance.** No two face-adjacent leaves differ by more than one level.
  Detection is from the *fine* side: a leaf at level Lf probes one cell across each face; that
  point always lands inside a coarser neighbour, so any neighbour at level ≥ Lf+2 is found and
  split. Iterated to a fixpoint. (Within-block today; across-block is the distributed phase.)

## Layering

```
morton  (local codes + arithmetic + hierarchy + Z-order)            [reuse]
  └─ transport-core/decomp  (ORB assigns root cells to ranks)        [reuse]
       └─ transport-core/amr
            ├─ BlockOctree<Dim,Bits>        host topology: refine/coarsen/balance, queries
            ├─ DeviceBlockOctree<Dim,Bits>  Kokkos View mirror + device-callable queries
            ├─ DistributedOctree<Dim>       (TODO) ORB collection + cross-block 2:1 balance
            ├─ LeafField<T>                 (TODO) leaf-indexed fields + VTU export
            └─ AmrHalo<Dim>                 (TODO) owner-based ghost exchange for graded octrees
       └─ sdflow (TODO)  cut-cell IBM on leaves + AMR multigrid + AMR GridLayout
```

Topology mutation is host-side (it rebuilds the sorted leaf arrays); the per-leaf hot path
(point location, face-neighbour walk) is device-callable, mirroring the halo's host
(`grid_halo.hpp`) vs device (`grid_halo_kokkos.hpp`) split. Headers are guarded by
`TPX_HAVE_MORTON`; the device layer additionally needs a Kokkos build (`MORTON_ENABLE_KOKKOS`
⇒ `MORTON_HD == KOKKOS_FUNCTION`).

## Status

- **Phase 1 — DONE.** `BlockOctree<Dim,Bits>` (uniform construction, `refineIf`/`coarsenIf`,
  within-block `balance2to1`, point location, `faceNeighbor`, `bounds`) + `DeviceBlockOctree`
  (Kokkos mirror, device `locate`/`faceNeighbor`). Tests: `tests/test_block_octree.cpp`
  (cross-checked against the `morton_octree::Octree` oracle; tiling/volume, sorted invariant,
  balance idempotence) and `tests/test_block_octree_kokkos.cpp` (device == host bit-for-bit on
  the OpenMP backend). Build per `transport-core/CLAUDE.md`; `ctest -R block_octree`.
- **Phase 2 — DONE.** `AmrGeometry<Dim>` (fine-unit ↔ world mapping), `LeafField<T>` (value per
  leaf in Z-order slot order), and `writeVtu` (VTK UnstructuredGrid, one hexahedron/quad per
  leaf + per-leaf CellData) in `include/tpx/amr/{leaf_field,vtu_io}.hpp`. Test
  `tests/test_amr_vtu.cpp` (structure round-trip: cell/point counts, cell-data values).
- **Phase 3 — DONE.** `refineToSdf` (`include/tpx/amr/refine.hpp`): refine the band the SDF
  surface crosses down to a target level over the shared `tpx::geom` SDF. Test
  `tests/test_amr_sdf.cpp` (every surface-crossing leaf at target level, genuine adaptivity,
  2:1 balanced, volume conserved).
- **Phase 4 — DONE.** `DistributedOctree<Dim,Bits>` (`include/tpx/amr/distributed_octree.hpp`):
  ORB over root cells, per-rank block octree with matching world geometry, cross-block 2:1
  `balance()` to a global fixpoint (local balance + owner-based NBX round, fine-side detection),
  and `faceNeighborGather()` (owner-based ghost exchange, two-round NBX request/reply, self
  handled locally). Test `tests/test_amr_distributed_mpi.cpp` at np=1,2,4,8: the global leaf set
  and every face-neighbour value match an independent serial reference (whole domain as one
  block) — i.e. distributed balance == serial balance, and the ghost exchange is exact.
- **Phase 5 — DONE.** `AmrPoisson<Dim,Bits>` + `AmrMultigrid<Dim,Bits>`
  (`include/tpx/amr/poisson.hpp`): conservative cell-centered FV Laplacian (the coarse side of a
  2:1 interface sums flux over all fine neighbours; symmetric two-point coeff), Gauss-Seidel
  smoother, and a geometric V-cycle over the octree coarsened uniformly one level at a time
  (`coarsenIf`), restriction = volume-weighted child average, prolongation = piecewise-constant.
  Periodic; singular null space fixed by mean removal. Test `tests/test_amr_poisson.cpp`:
  conservation (∮ L u = 0) on uniform AND graded meshes; manufactured periodic solve with
  residual drop > 1e8/V-cycle and 2nd-order accuracy (16³ vs 32³ error ratio ≈ 4.0); graded
  Gauss-Seidel solvability.
- **Phase 5b — DONE (quadratic coarse-fine flux).** `AmrPoisson::applyLaplacianQuad`/`coarseStar`
  + `AmrMultigrid::solveQuad`: at a 2:1 face the raw coarse value is replaced by a tangential
  **quadratic** interpolation of the coarse field at the fine cell's tangential position
  (Martin–Cartwright). Both sides use the identical value, so the flux is symmetric and
  **refluxing is automatic** (the coarse face flux equals the summed fine sub-face fluxes); the
  quadratic operator is solved by deferred correction over the standard-operator V-cycle. Test
  `tests/test_amr_cf_quadratic.cpp` (2D half-coarse/half-fine, manufactured solution with nonzero
  tangential gradient at the interface): the standard two-point flux degrades toward 1st order in
  L∞ near the interface (≈1.9×/refine) while the quadratic flux stays **2nd order** (L²≈4.0×,
  L∞≈3.8×) and is conservative (∮ L_quad u = 0).
- **Phase 5c — DONE (cut-cell openness + coarsening).** `AmrPoisson::buildOpenness` stores a
  per-leaf per-face fluid fraction α∈[0,1] (from a geometry callable `openFn(faceCentreWorld,
  axis)`); the operator (standard + quadratic) weights every face flux by α (taken from the finer
  side, so shared faces are consistent and the operator stays conservative across 2:1 interfaces).
  `AmrMultigrid::setOpenness` **area-averages** α onto every coarser level (sdflow's
  `coarsenOpenAvg`), so the per-level operators are rediscretized with consistent openness and the
  openness-weighted quadratic C/F flux applies on each level; `coarseStar` drops the tangential
  correction near a nearly-closed face. Test `tests/test_amr_openness.cpp`: α≡1 reproduces the
  no-openness quadratic solve bit-for-bit; the openness-weighted quadratic operator conserves
  (∮≈6e-18); a variable-openness solve converges (residual drop ~1e14) with the coarsened α.
  *Remaining follow-ups:* fold into the device/distributed V-cycle; 3D cross-derivative term
  (dropped — affects only the C/F error constant, not the order).
- **Phase 5d — DONE (cut-cell Dirichlet sub-cell BC + κ).** `AmrCutCell<Bits>`
  (`include/tpx/amr/cut_cell.hpp`): a **faithful port of sdflow's ξ-polynomial scheme**
  (`cut_cell_ibm.hpp`: `poly_*`, `ibmFillEntry`, `ibmModifyStencil`) onto the cell-centered octree.
  Where the openness scheme imposes a *Neumann* wall, this imposes a *Dirichlet* value u=u_bc on
  the immersed boundary at the true sub-cell distance ξ·h (Shortley–Weller), with `D_rescale`
  row-scaling for the small-cell problem and the sandwich (double-sided) case. The cell fluid
  volume-fraction κ (subsampled) classifies solid/fluid/cut cells. Cut cells are assumed to have
  same-level neighbours (resolve the boundary in a uniformly-finest band). Test
  `tests/test_amr_cut_cell.cpp`: embedded-Dirichlet sphere (u=R²−r², lap u=−6, u=0 on r=R) is
  **2nd order** (16³→32³ L2 ratio ≈4.0); κ integrates to (4/3)πR³ (<3%); solid cells held at u_bc.
  This is the velocity-diffusion/scalar-Dirichlet half of the cut-cell IBM (the openness scheme is
  the pressure/Neumann half).
- **Phase 6 — DONE (collocated Stokes momentum+pressure step).** `AmrFlow<Bits>`
  (`include/tpx/amr/flow.hpp`) wires both cut-cell halves into one sdflow-style projection step:
  **momentum** = implicit backward-Euler viscous solve per component with the Dirichlet
  ξ-polynomial operator (no-slip IBM, `(ρ/dt)I − μ∇²`); **pressure** = the **Almgren–Bell–Colella
  (ABC) approximate projection**, sdflow's collocated coupling (`src/mac_approx_projection.hpp`):
  average cell velocities to a face (MAC) divergence, solve the openness Poisson `∇²φ = ∇·u*`, then
  correct the cell velocities by `½(g⁻+g⁺)` of the two adjacent FACE φ-gradients (a closed/solid
  face contributes a zero gradient). Stokes only (advection is the follow-up). Test
  `tests/test_amr_flow.cpp`: (1) body-force Poiseuille between immersed no-slip walls matches the
  analytic parabola to ~round-off (the discrete cut-cell Laplacian is exact for a parabola with
  walls on cell faces), solids held at 0; (2) the ABC projection reduces a pure-gradient (fully
  divergent) field's divergence and |u| sharply (>10×).
  **The collocated projection is the ABC method by design — do NOT replace it with Rhie–Chow.** The
  small residual cell divergence is intrinsic to cell-centered velocity placement (the *face* field
  is exactly divergence-free; the *cell* field only approximately), not a defect to engineer away;
  see `sdflow/doc/sdflow_colocated_plan.md` and the `amr-octree-status` memory note.
- **Phase 6b — DONE (momentum advection: SOU + implicit-FOU deferred correction).**
  `AmrFlow::setAdvection(true)` adds conservative `∇·(u u)` momentum advection. The high-order flux
  is **second-order upwind (SOU)** by default (`setAdvectionScheme(1)` ⇒ Koren TVD); the advecting
  face velocity is the cell→face average of the normal component (collocated `cadv` form), ±2-cell
  stencil. By default it runs as an **implicit-FOU deferred correction** (`setImplicitAdvection`,
  default ON): the first-order-upwind part is solved *implicitly* in the momentum operator
  (`AmrCutCell::buildAdvectionFou`, rebuilt each step from the lagged uⁿ; wall faces carry zero
  advecting velocity), and the explicit term is only the high-order−FOU difference — so it cancels at
  steady (leaving SOU) and is **unconditionally stable** for the FOU part. `setImplicitAdvection(false)`
  ⇒ fully explicit. Tests (`tests/test_amr_flow.cpp`): the SOU operator matches the analytic
  `∇·(u u_x)=(k/2)sin(2kx)` and converges ~2nd order (ratio >3.3; TVD ~2.8); constant → 0 (Galilean);
  Poiseuille with advection ON still recovers the exact parabola; and at advective CFL≈6.4 the
  implicit-FOU run stays bounded while fully-explicit advection blows up (NaN).
- **Phase 6d — DONE (graded-interface advection).** The advection is now C/F-consistent across 2:1
  interfaces: the **implicit FOU operator** (`AmrCutCell::buildAdvectionFou`/`fouApply`) is rebuilt
  each step as a **CSR** via `forEachFaceFull` — a coarse cell couples to *all* its fine sub-face
  neighbours (conservative), outflow→diagonal / inflow→off-diagonal, wall faces carry zero advecting
  velocity; the **high-order explicit flux** (`AmrFlow::advectHO`) also uses `forEachFaceFull`, with
  the second-upwind cell point-probed (`periodicNeighbor`) so SOU/TVD works across levels. The
  deferred correction is exactly ρ·(advectHO − fouApply) (same faces/velocities ⇒ cancels at steady).
  Test `tests/test_amr_flow.cpp::test_graded_advection`: a graded sphere mesh (60% of uniform cells)
  with advection ON stays bounded/stable. (A CSR count/fill mismatch at `velOut==0` segfaulted once —
  both passes must branch on the same condition.)
- **Phase 6e — DONE (device + distributed compute path).** Foundational operators on both backends:
  * **Distributed** `DistributedPoisson<Dim,Bits>` (`include/tpx/amr/distributed_poisson.hpp`):
    Laplacian matvec + weighted-Jacobi on the `DistributedOctree`, cross-block neighbours from the
    owner-based halo (`faceNeighborGather`); Jacobi reads only the previous iterate (one gather/sweep)
    so a distributed sweep is **bit-identical** to the whole-domain (`MPI_COMM_SELF`) solve. Test
    `tests/test_amr_distributed_poisson_mpi.cpp` np=1,2,4,8.
    **NBX bug fixed:** `faceNeighborGather`'s two rounds (request/reply) shared tag 0 — a rank still
    draining the request round could Iprobe-receive another rank's reply (same tag) and mis-parse it
    (8-byte-misaligned → garbage indices → segfault at np=4 *periodic*). Fixed with distinct tags
    (req=11, reply=12); `balance()` is unaffected (its per-iteration Allreduce already separates rounds).
  * **Device (Kokkos)** `deviceLaplacian`/`deviceJacobiSweep` (`include/tpx/amr/device_poisson.hpp`):
    the same operators as `Kokkos::parallel_for` over the leaf Views using `DeviceBlockOctree`'s
    device face-neighbour walk; **bit-identical** to the host operator. Test
    `tests/test_amr_device_poisson_kokkos.cpp` (OpenMP; the same code runs CUDA/HIP).
- **Phase 6f — DONE (device + distributed multigrid V-cycle).** Full geometric-MG V-cycles on both
  backends, building on the 6e operators. Both are Jacobi-smoothed (order-independent), with averaging
  restriction + piecewise-constant prolongation (correction scheme).
  * **Distributed** `DistributedMultigrid<Dim,Bits>` (`distributed_poisson.hpp`): the hierarchy is a
    stack of `DistributedOctree`s on the successively halved global root grid, each ORB-decomposed over
    the *same* comm. For a power-of-two grid + rank count the ORB decompositions **nest** (rank r's
    coarse block = its fine block halved), so every fine cell's parent is owned by the same rank ⇒
    restriction/prolongation are purely local (no comm); only the Jacobi smoother uses the per-level
    halo. `build()` asserts the nesting (each `c2p` resolves locally). Test
    `tests/test_amr_distributed_mg_mpi.cpp` np=1,2,4,8: **bit-identical** COMM_WORLD vs COMM_SELF, and
    the residual drops ≥3 orders in 8 V-cycles (4-level hierarchy on 16³). New `DistributedOctree`
    helpers `globalRootOf`/`findGlobalRoot` build the nested transfer maps; `DistributedPoisson::residual`
    returns the residual vector.
  * **Device (Kokkos)** `DeviceMultigrid<Dim,Bits>` (`device_multigrid.hpp`): the uniform-coarsened
    octree hierarchy, each level's operator a **precomputed face CSR** (`DeviceFvOp`: `invVol`,
    `faceStart`/`faceNbr`/`faceW`), with fine↔coarse maps as device Views (`c2p` for prolong; CSR
    `childStart`/`childIdx` for restriction). Restriction iterates over *coarse* cells summing children
    in fixed CSR order (no atomics) ⇒ deterministic and **bit-identical** to the host Jacobi V-cycle.
    Test `tests/test_amr_device_multigrid_kokkos.cpp` validates device==host bit-for-bit on a graded mesh.
- **Phase 6g — DONE (consistent graded operator folded into the device V-cycle).** The device operator
  is now the **consistent conservative two-point FV Laplacian** (`(Lu)_i = invVol_i·Σ_f w_f(u_j−u_i)`,
  `w_f = openness·A_f/d_f`, coarse side carrying one face per 2:1 sub-neighbour), built on the host from
  `AmrPoisson::forEachFaceNeighbor` and uploaded as the face CSR above — so `deviceApplyFv` ==
  `AmrPoisson::applyLaplacian` **bit-for-bit**. This replaces the earlier *plain* `(u_j−u_i)/h0²` op
  that ignored 2:1 geometry and **stalled** the graded V-cycle (~0.03). The graded V-cycle now drops the
  residual **≥3 orders** (test check), and the whole standard V-cycle is bit-identical to a host
  Jacobi-MG mirror. **2nd order at 2:1 interfaces:** `solveQuad()` wraps the V-cycle in deferred
  correction with the quadratic coarse-fine flux (`AmrPoisson::coarseStar`) evaluated on device as a
  second precomputed CSR (`deviceQuadDelta`, = `applyLaplacianQuad − applyLaplacian` to round-off);
  it drives the 2nd-order graded residual down.
- **Phase 6h — DONE (graded *distributed* octree + consistent operator).** The consistent conservative
  FV Laplacian now runs on a genuinely graded `DistributedOctree` (refine local leaves + `balance()`
  cross-block 2:1), with the coarse side of every 2:1 interface carrying one face per fine sub-neighbour
  — *including sub-neighbours owned by another rank*. `DistributedFvOperator<Dim,Bits>`
  (`include/tpx/amr/distributed_fv.hpp`): each leaf's face stencil is enumerated exactly like
  `AmrPoisson::forEachFaceNeighbor` (same axis/dir/sub-k order); in-block neighbours resolve locally,
  cross-block neighbours become **ghost** entries. Ghost cells are discovered by *one* owner gather of
  the across-face covering level (new `DistributedOctree::coverLevels`) — enough to know whether a remote
  face is same/coarser (one neighbour) or finer (2^(Dim-1) sub-neighbours, each possibly a *different*
  owner); each matvec/sweep then fills ghost values with one owner gather (`coverValues`). Because the
  per-entry term `w(val−u_i)` is summed in the same face order whether a neighbour is local or ghost, the
  operator is **bit-identical** COMM_WORLD vs COMM_SELF, and on a single block **bit-identical to host
  `AmrPoisson::applyLaplacian`**. New `DistributedOctree` public API: `coverLevels`/`coverValues`
  (owner-based by-coordinate gathers, distinct NBX tag pairs 21/22 + 23/24), `faceAcross`, and
  `blockFineOrigin`/`globalFineSize`/`periodic`/`rootSpan`/`h0` accessors. Test
  `tests/test_amr_distributed_fv_mpi.cpp` np=1,2,4,8: apply + Jacobi solve bit-exact WORLD==SELF, apply
  bit-exact vs host on SELF, smoother reduces the residual.
- **Phase 6i — DONE (graded *distributed* multigrid V-cycle).** `GradedDistributedMultigrid<Dim,Bits>`
  (`distributed_fv.hpp`): a full geometric-MG V-cycle on the graded distributed octree, built on the 6h
  operator. The hierarchy keeps the **same ORB blocks** and coarsens each rank's local octree
  (`coarsenIf`, which is guarded by `level < lmax` so it *never* merges the root brick — every rank
  stops at the uniform root brick, no cross-block re-decomposition). Uniform coarsening preserves 2:1
  grading; the consistent per-level `DistributedFvOperator` handles whatever remains. **Transfers are
  local**: a fine leaf's covering coarse leaf is in the same block (parents never cross root cells), so
  restriction (average children) and prolongation (piecewise-constant) need no comm — only the per-level
  Jacobi smoother uses the operator's ghost halo. Jacobi + local transfers are order-independent /
  per-cell ⇒ the V-cycle is **bit-identical** COMM_WORLD vs COMM_SELF (the 2^Dim children of a coarse
  cell sum in octant order, identical regardless of block origin). The coarsest level (uniform root
  brick) is bottom-solved with extra Jacobi. Test `tests/test_amr_distributed_graded_mg_mpi.cpp`
  np=1,2,4,8: bit-exact WORLD==SELF, and on a **manufactured RHS** `b = L·u_exact` (exactly
  volume-weighted-mean-zero — conservation cancels the face contributions bit-wise, so the singular
  operator has no nullspace floor) the residual converges to **round-off (≥8 orders)**.
- **Phase 6j — DONE (chained bottom solve → uniform `DistributedMultigrid`).** The coarsest graded
  level (uniform root brick: root cells at level `lmax`) is now bottom-solved by the uniform
  `DistributedMultigrid` on the root grid, instead of plain Jacobi. The mapping is clean: that level and
  the uniform MG's finest are the *same* root grid over the *same* ORB decomposition, so cells correspond
  (mapped by global root cell, identity in practice). **Sign convention (suite-wide): every operator is
  the Laplacian `L = ∇²`** (negative-definite — `AmrPoisson::applyLaplacian`, `DistributedFvOperator`,
  `DistributedPoisson`, the device operators), solved as `L u = rhs`. So the bottom step solves
  `L e = res` as `inner.vcycle(e, res)` (correction scheme): `res = b − Lx`; a few inner V-cycles;
  `x += e` — no sign flip. The inner MG is itself bit-exact WORLD==SELF and the map is identity, so the
  chained V-cycle stays **bit-identical** across ranks. `GradedDistributedMultigrid::vcycle` now takes `innerCycles`
  (default 6) instead of `bottom`. Test still converges to round-off (≥8 orders), np=1,2,4,8 — now with a
  *true multigrid* coarse solve all the way down (root grid must be power-of-two for the inner MG's ORB
  nesting).
- **Phase 6k — DONE (cut-cell openness on the distributed/graded path).** `DistributedFvOperator::init`
  and `GradedDistributedMultigrid::build` take an optional `openFn(faceCentroidWorld, axis) → [0,1]`;
  the face weight becomes `w_f = α_f · A_f/d_f`. The clean trick: α is evaluated at the **finer side's
  (sub-)face centroid in world coords**, which both sides of a face — even across a block boundary —
  compute identically, so α is symmetric with **no openness exchange** and the operator stays conservative
  (manufactured RHS still exactly mean-zero). Matches `AmrPoisson::buildOpenness` bit-for-bit. *Subtlety
  fixed:* the sub-face α must use the **finer neighbour's actual lower corner** (`lo−sj`), not the probe
  point (`lo−1`) used to *find* it — coeff is position-independent (so the openness-free test missed it)
  but α is not (`fineLoGlobal`). Each MG level re-samples `openFn` at its own face centroids (a
  rediscretized coarse operator); with openness the coarsest is bottom-solved by Jacobi on its own
  (openness-carrying) operator rather than the openness-free uniform inner MG. Test
  `tests/test_amr_distributed_openness_mpi.cpp` np=1,2,4,8: apply bit-exact WORLD==SELF and vs host
  `AmrPoisson` on a single block; the graded MG with openness converges (≥6 orders, manufactured RHS) and
  is bit-exact WORLD==SELF.
- **Phase 6l — DONE (openness coarsened across the *device* MG levels).** `DeviceMultigrid::build(finest,
  h0, openFn)` now builds its per-level operators from an internal host `AmrMultigrid` (`hmg_`) with
  `setOpenness(openFn)` — so the finest aperture is **area-averaged to every coarser level**
  (`coarsenOpenAvg`), giving consistent cut-cell operators all the way down instead of finest-only. Each
  device level's face CSR is built from `hmg_->op(L)`, so the device operator on every level is
  **bit-for-bit** the host `op(L).applyLaplacian` (openness included); the quadratic correction and
  bottom solve inherit the coarsened openness through the same operators. (This also retired the unused
  finest-only `proto` parameter and de-duplicated the host hierarchy build.) Test
  `tests/test_amr_device_openness_kokkos.cpp`: device==host `applyLaplacian` bit-exact on **every** level,
  and the openness V-cycle converges (≥3 orders, manufactured RHS) on the graded mesh.
- **Phase 6m — DONE (κ-weighted restriction evaluated; kept opt-in, NOT default).** Added an optional
  Galerkin-style κ-weighted restriction to `DeviceMultigrid` (`setKappaRestrict(true)`): the coarse
  residual is `Σ_child κ_c·res_c / Σ_child κ_c` with κ the fine cell's fluid fraction (mean face aperture),
  downweighting nearly-solid children at thin cut features. Default stays the plain volume-average.
  **Experiment** `tests/test_amr_kappa_restrict_kokkos.cpp` A/Bs the two on a strongly-cut graded mesh:
  plain converges to ~5e-7 (≈0.49/cycle), κ-weighted only to ~2e-3 (≈0.64/cycle) — **κ-weighting is
  worse**. It breaks the exact conservation of the volume-average, so on this singular (periodic) problem
  the restricted residual is no longer ⊥ the operator's constant null space ⇒ slower convergence + a
  residual floor. **Conclusion: keep plain volume-average as the default**; κ-restrict is a documented
  opt-in for non-singular / Dirichlet configurations where the conservation constraint doesn't bite.
- **Phase 6n — DONE (homogeneous-Dirichlet BC + κ-restrict re-tested there).** Added a non-periodic mode
  to `AmrPoisson` (`setPeriodic(false)` ⇒ a domain-boundary face is a `u=0` wall at half a cell, folded
  into the diagonal via `boundaryDiag`; `forEachFaceNeighbor` skips it), propagated by
  `AmrMultigrid::setPeriodic` and carried on device by `DeviceFvOp::bcDiag` (the three device kernels add
  `−bcDiag·u_i`; bcDiag=0 in the periodic default ⇒ no behaviour change). `DeviceMultigrid::build(finest,
  h0, openFn, periodic=false)` gives a homogeneous-Dirichlet cut-cell MG. Re-running the κ-restrict A/B on
  this **non-singular** operator (`tests/test_amr_kappa_dirichlet_kokkos.cpp`): plain → ~2.6e-10
  (≈0.36/cyc), κ-weighted → ~6.7e-7 (≈0.47/cyc) — **the κ stall/floor is gone** (both reach round-off),
  confirming the constant null space was the cause of the periodic floor. κ still does not *beat* plain
  here (slightly slower — the prolongation stays plain piecewise-constant, an unmatched transfer pair). Net:
  plain volume-average stays the default everywhere; κ-restrict is safe on non-singular configs but not a
  convergence win in these tests.
- **Phase 6c — Stokes-drag vs Zick & Homsy (DONE — tight match).** Replicated sdflow's exact drag
  metric (`validate_zick_homsy_sdflow.py`): `K = f N³/(6πμR U_sup)` for a simple-cubic sphere array,
  vs Z&H (1982) — the same ground truth sdflow validates against. Test `tests/test_amr_drag.cpp`.
  **Result (uniform grid):** **within ~1% of Z&H**, dt-independent — φ=0.125: N=8 −0.8%, N=16 +0.4%,
  N=32 +0.3%; φ=0.064 N=16 −0.7%; φ=0.216 N=16 −0.03%. This is within sdflow's own <0.5% accuracy
  (collocated carries the known ~1% per-grid gap vs staggered).
  **Two fixes got there, and they are the lesson, not the cut-cell operator:**
  (1) `buildCutcellOp` is just `A = -div(open·grad)` — the *same* openness-weighted Laplacian we
  already had; the accuracy came from the **gradient-normalised openness** (`ccFractionCore`, a 2nd
  order aperture) replacing crude indicator subsampling; (2) the dominant error was the **projection
  scheme** — a plain non-incremental Chorin projection has an O(dt) splitting-error boundary layer
  (≈ −11% drag at N=32, dt=60); the **incremental rotational** update `p += (ρ/dt)φ − μ∇·u*` removes
  it and makes the steady drag dt-independent. **Graded drag — DONE (now works).** The flow
  operators were made C/F-consistent: (1) `AmrCutCell` momentum diffusion — regular fluid cells use
  `idiag·u − μ∇²` via an internal C/F-aware `AmrPoisson` (with `coeff(si,sj)` at 2:1 faces), cut
  cells keep the ξ-overlay (finest, same-level), solid = identity; (2) the ABC projection's
  divergence and gradient now use `AmrPoisson::forEachFaceFull` (same 2:1 sub-face enumeration +
  openness as the pressure operator), and the projection uses the *standard* (consistent) openness
  V-cycle so D, G, L share the same faces. Before this, the graded flow **diverged** (Umean → 1e27);
  after, it is **stable** and matches Z&H: φ=0.125, finest 32 — wide band (95% fine) +0.8%, tight
  band (30% of cells) +6.6%; finest 16 band 2.5 (82% cells) +1.8%. The graded error shrinks toward
  the uniform/Z&H result as the fine band widens — the accuracy/cost trade-off (coarse far field +
  the 1st-order C/F flux used for projection stability). Test `tests/test_amr_drag.cpp` runs a graded
  sphere solve and asserts stability + <10% vs Z&H + genuinely-coarsened mesh. (Advection's ±2
  stencil is still same-level-only — fine, since cut/feature cells live in the finest band; graded
  *advection* interfaces remain a follow-up. The periodic SC array is a poor AMR showcase anyway —
  an isolated sphere in a big box is the natural next case.)
- **Phase 7 — DONE.** `BarnesHut<Dim,Bits>` (`include/tpx/amr/barnes_hut.hpp`): the same octree
  built top-down by particle insertion (refine any leaf with >1 particle) over a 1×1×1 root
  cube, per-node centre-of-mass/mass aggregates up the Morton hierarchy, θ-criterion traversal
  for a softened 1/r² interaction. Test `tests/test_amr_barnes_hut.cpp`: θ=0 reproduces the
  direct O(N²) sum to round-off; θ=0.3 within a few percent.
- **Phase 8 — DONE (dynamic / solution-adaptive AMR + field remap).** Until now refinement was static
  (geometry-driven `refineToSdf`). Added solution-adaptive (re)meshing:
  * **Indicators** (`include/tpx/amr/indicators.hpp`): `lohnerIndicator` — the Löhner (1987) normalized
    second-difference feature detector, E∈[0,1], the standard robust AMR criterion (tracks curvature /
    steep fronts, self-normalizing so one threshold works across scales; ε filter suppresses noise-level
    ripples); plus `secondDiffIndicator` (raw |∂²u|·h²). Neighbours from `faceNeighbor`; a missing
    (block/domain-edge) neighbour contributes 0 on that axis.
  * **Conservative field remap** (`include/tpx/amr/adapt.hpp`, `transferField(oldT, oldF, newT)`): the
    reusable bridge between *any* two octrees on the same domain — copy where the level matches, prolong
    where the new mesh is finer (piecewise-constant, or minmod-limited linear), volume-weighted average
    where it is coarser. **Conservation:** PC prolong and volume-average restrict are exactly
    conservative; linear prolong is too under uniform refinement, and a per-source-cell scalar correction
    (rescale a cell's children so they volume-average back to the parent) restores exact conservation when
    2:1 balance refines a cell non-uniformly. This one op powers refinement, coarsening and balance
    transfers uniformly.
  * **Driver** (`adapt.hpp`): `flagByIndicator` (refine where E>refineThresh & can go finer; coarsen
    where E<coarsenThresh & all siblings agree); `adaptField(t, f, flags)` → coarsen + refine + 2:1
    balance + remap, with flags looked up by *code* so they survive the intermediate index changes;
    `adapt(t, f, refineThresh, coarsenThresh)` is the all-in-one Löhner step.
  Tests: `tests/test_amr_transfer.cpp` — conservation under refine/coarsen, refine→coarsen round-trip
  identity, exact restriction of a linear field, and linear-beats-PC accuracy (still conservative);
  `tests/test_amr_adapt.cpp` — Löhner localizes a tanh front (strong at the front, ~0 in the far field),
  one adapt step refines there + coarsens away conservatively, and iterating tracks the front with the
  finest cells hugging it at ~⅓ the leaves of a uniform-fine grid. **End-to-end**
  `tests/test_amr_adapt_transport.cpp`: a Gaussian blob advected in a divergence-free periodic velocity
  by `ScalarTransport` while the mesh is re-adapted every few steps — total mass Σ V·c is conserved
  through *every* transport step and *every* adapt/remap, the blob advects to the right place with the
  finest cells following it, and the adaptive mesh stays well under a uniform-fine grid. This proves the
  dynamic-AMR infra composes with a real time-dependent solver.
  * **Distributed** `distributedAdapt` (`include/tpx/amr/distributed_adapt.hpp`): the same step on a
    `DistributedOctree`, keeping the ORB ownership. The Löhner indicator is evaluated through the
    owner-based face-neighbour halo (`faceNeighborGather`) so flags match the whole-domain ones; each rank
    refines/coarsens its *local* octree (sibling groups never cross root cells), then `balance()` restores
    global 2:1, and the field is remapped *locally* with `transferField` (conservative per block, no field
    comm). Bit-identical COMM_WORLD vs COMM_SELF (mesh + field) and globally conservative. Test
    `tests/test_amr_distributed_adapt_mpi.cpp` np=1,2,4,8.
  * **Load re-balancing — DONE.** `DistributedOctree::rebalance(fields)`
    (`include/tpx/amr/distributed_octree.hpp`): weight = octree leaf-count per global root cell
    (SUM-Allreduce of the zero-padded local counts) → weighted re-decompose with the **weighted ORB**
    (`BlockDecomposer::init(…, weights)`) → for each leaf whose root cell's owner changed, migrate its
    global Morton code + level + field columns to the new owner over NBX → each rank rebuilds its local
    octree from the kept+received leaves (`BlockOctree::assign`, rebased to the new block origin + re-sorted
    Z-order) and swaps in the new decomposition/block geometry. This is a *migration* of the same global
    mesh (NOT a `transferField` remap): exactly conservative, every cell's field bit-identical, the global
    octree unchanged — only ownership moves. Test `tests/test_amr_distributed_rebalance_mpi.cpp` np=1,2,4,8:
    each cell still carries its own value + WORLD==SELF mesh/field, Σ V·f and leaf count conserved, and the
    max/mean leaf imbalance drops. This is the AMR half of the **cross-cutting** weighted-ORB load balancing
    (shared with dem's particle imbalance via `rebalanceByParticleCount`); see `docs/ROADMAP.md` Phase 7.
    *Remaining:* the on-device counterpart.
- **Phase 6 — PARTIAL (transport-core piece DONE).** `ScalarTransport<Dim,Bits>`
  (`include/tpx/amr/scalar_transport.hpp`): explicit FV advection–diffusion on the octree —
  monotone upwind advection + the conservative two-point diffusion flux, 2:1 interfaces summed on
  the coarse side, face-normal velocity sampled from a user callable. Test
  `tests/test_amr_transport.cpp`: divergence-free update conserves total scalar to round-off
  (uniform AND graded); a sine mode decays at the analytic rate exp(−D k² t); upwind is monotone
  and preserves a constant. This is the reusable "AMR for scalar transport" core a consumer
  imports. **Remaining (user-facing):** sdflow-proper wiring — an AMR `GridLayout`-style policy,
  cut-cell IBM on leaves, and structured-hydro ↔ AMR coupling by leaf point-location — is a large
  change inside sdflow (whose solver currently assumes a flat structured grid) and is left for a
  steered session.
