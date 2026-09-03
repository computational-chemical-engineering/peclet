# Covolume vs collocated Navier–Stokes on Voronoi meshes (track C2, 2026-09-03)

The Voronoi methods plan (V4) builds both static solvers on one operator layer (`voro`
`fv/mesh.hpp`, `fv/operators.hpp`) and gates them against each other. Both are on the periodic
Voronoi face mesh, both use the same two-point pressure Laplacian `L = Σ A_f/d_f` (exact on
Voronoi orthogonality), the same GraphAMG-preconditioned CG, SSP-RK3 with a projection after every
stage, and the same cell-centred convection/diffusion kernel; they differ in WHERE the velocity
lives and how the projection reaches it.

| | covolume (`fv/covolume.hpp`) | collocated (`fv/collocated.hpp`) |
|---|---|---|
| unknown | face-normal flux `u_f` | seed velocity vector `U_i` + the projected face flux `u_f` |
| momentum on faces | exact transpose of the Perot reconstruction `Rᵀ` | — |
| projection | exact (face field) | `flow`'s approximate projection: constraint `T` (centre→face), exact face projection, cell correction with `G = Tᵀ∘grad_f` (the constraint transpose — flow's gauge-exact gradient) |
| pressure in the predictor | none needed (the flux IS the projected field) | incremental: `−G P^n` at the cells, `P += φ` (flow's `incremental_`) |
| energy (inviscid, semi-discrete) | conserved exactly (`⟨Ru,a⟩_V = ⟨u,Rᵀa⟩_F`, convection skew-symmetric) | not exactly: the cell correction is approximate — measured drift O(dt·h²) |
| unstructured accuracy | Perot reconstruction first-order consistent on non-symmetric cells | plain `T` first order ∝ skewness; **skew-corrected `T` (default) second order** |

## Taylor–Green (viscous, ν = 0.01, T = 0.25, CFL 0.2), relative errors at t = T

`test_collocated_ns` (C), host-openmp; cell error = seed velocity in the V-norm, face error = face
flux in the F-norm; "Stokes" = the convective term switched off.

| mesh | n | skew | collocated plain: cell / face | collocated skew-corrected: cell / face | covolume: face / Perot cell | Stokes plain / skew |
|---|---|---|---|---|---|---|
| cubic lattice | 8 | 0 | 9.16e-3 / 6.77e-2 | 9.16e-3 / 6.77e-2 | 3.81e-2 / 4.09e-2 | 9.99e-3 / 9.99e-3 |
| | 16 | 0 | 2.48e-3 / 1.68e-2 | 2.48e-3 / 1.68e-2 | 9.99e-3 / 9.42e-3 | 2.53e-3 / 2.53e-3 |
| | 32 | 0 | 6.30e-4 / 4.19e-3 | 6.30e-4 / 4.19e-3 | 2.53e-3 / 2.30e-3 | 6.34e-4 / 6.34e-4 |
| **order** | | | **1.97** / 2.00 | **1.97** / 2.00 | 1.98 / 2.03 | 2.00 / 2.00 |
| 0.2h-jittered lattice | | 0.08 | | | | |
| **order** | | | 1.72 / 1.26 | **2.11** / 2.03 | 0.82 / 1.70 | 1.32 / 2.02 |
| random seeds + 30 Lloyd sweeps (CVT) | 8 | 0.039 | 1.22e-1 / 1.02e-1 | 8.42e-2 / 7.65e-2 | 7.85e-2 / 3.19e-2 | 1.00e-1 / 5.29e-2 |
| | 16 | 0.040 | 3.85e-2 / 3.34e-2 | 2.12e-2 / 1.98e-2 | 2.94e-2 / 1.08e-2 | 3.25e-2 / 9.16e-3 |
| | 32 | 0.040 | 1.71e-2 / 1.45e-2 | 4.99e-3 / 4.84e-3 | 1.21e-2 / 2.95e-3 | 1.64e-2 / 2.27e-3 |
| **order** | | | 1.17 / 1.21 | **2.08** / 2.03 | 1.29 / 1.87 | 0.99 / 2.01 |

Reading: on the cubic lattice the collocated and the covolume schemes are the MAC pair `flow`
has (both second order; the collocated cell error is 4× smaller at equal n because the seed value
is a point sample of a smooth field while the covolume flux carries the face-average error). On
unstructured Voronoi meshes the covolume scheme is limited to first order by the Perot
reconstruction (the face midpoint rule misses the facet second moments; `Rᵀ Δ₂ R` inherits it — the
Stokes-only column of `test_covolume_ns` isolates the viscous term), while the collocated scheme
with the plain constraint is limited by the skewness of the connector-foot interpolation (B4:
skewness limits flux consistency). The skew-corrected constraint pair removes that and is second
order on both the jittered lattice and the centroidal mesh; its Stokes-only order (2.02 / 2.01)
shows the two-point Laplacian of the cell field converges at second order in the solution — the
supra-convergence B4 measured for the pressure Poisson problem.

## Structure gates (a priori)

| gate | covolume | collocated |
|---|---|---|
| adjointness (`⟨Ru,a⟩_V = ⟨u,Rᵀa⟩_F` / `⟨TU,g⟩_F = ⟨U,Tᵀg⟩_V`) | 1e-15 | 1e-15 (plain and skew-corrected) |
| convection skew-symmetry with the projected flux | 1e-16 | 1e-17 |
| linear field reproduced at the face centroid (random mesh, skewness 0.24) | — | plain 2.2e-2, skew-corrected 5e-16 |
| inviscid TGV energy drift, 16³ jittered, T = 1.25 | 9.7e-7 (RK3 time error only: dt-order 2.96) | −7.0e-4 at CFL 0.2, −2.3e-4 at CFL 0.1; h-order 1.7–2.0 (O(dt·h²), flow's approximate-projection analysis) |
| face divergence | 6e-14 | 3e-14 |
| pressure PCG (GraphAMG on −V L) | 12 iterations vs 76 CG | same |

## Plane Poiseuille between SDF slabs (C3, `test_body_fitted`)

Body force, ν = 1, cubic lattice of seeds with the walls halfway between seed rows, both solvers
with the two-point no-slip wall flux `ν A (U_wall − U_i)/h_A`, marched to the steady state
(SSP-RK3, diffusion number 0.2).

| cells across the gap | collocated cell / face error | covolume face / Perot cell error |
|---|---|---|
| 4 | 8.54e-2 / 8.54e-2 | 8.54e-2 / 8.54e-2 |
| 8 | 2.14e-2 / 2.14e-2 | 2.14e-2 / 2.14e-2 |
| 16 | 5.34e-3 / 5.34e-3 | 5.34e-3 / 5.34e-3 |
| **order** | **2.00** | **2.00** |

Both solvers coincide to the digit on the lattice for this one-dimensional flow. The exact
parabola satisfies the interior discrete equations to round-off (4e-16); with the two-point wall
flux the wall row carries a residual of exactly f/4 (the derivative at h_A/2 rather than at the
wall — the classic half-cell truncation, second order globally); with the quadratic wall gradient
(the default) the residual is 5e-11 and the marched error 7e-6 at every n — the parabola is the
exact discrete steady state. Wall flux 0, face divergence 3e-16.

## Stokes drag of a simple-cubic sphere array (C4, `test_permeability`)

φ = 0.216, Zick & Homsy K = 7.442; collocated solver, Stokes, marched to a tight steady state;
0.15h-jittered lattice seeds clipped by the sphere (fluid volume exact to 2e-5).

| cells per box edge | cells per diameter | cells | K (quadratic wall gradient) | error | error with the two-point wall flux |
|---|---|---|---|---|---|
| 16 | 12 | 3031 | 7.261 | −2.43 % | −13.4 % |
| 24 | 18 | 10417 | 7.371 | −0.96 % | −7.5 % |
| 32 | 24 | 24945 | 7.414 | −0.37 % | — |

Second order with the wall-anchored quadratic wall gradient, on par with flow's cut-cell IBM
(−0.49 % at 32 cells per box edge). The geometry was never the limit (the SDF clip tiles the
fluid volume to 2e-5): with the two-point wall flux the fat wall cells (seeds within 0.4 h of the
wall dropped, h_A up to 1.4 h) made the wall shear first order (order 1.4). The quadratic fit
through the wall value, the cell and its neighbours (tangential variation removed with the cell
gradient) is flow's wall-anchored reconstruction on the unstructured mesh, and it also makes the
Poiseuille parabola the exact discrete steady state (wall-row residual 5e-11).

## DEC viscous term for the covolume scheme (C2a′, shelved)

The Nicolaides curl-curl Laplacian on the Voronoi edges is exactly symmetric and dissipative but
does not raise the covolume order: its linear-field residual converges at order 1.0 / 0.93 on the
jittered / centroidal meshes (Perot 0.58 / 0.56, similar magnitude), it is inconsistent on the
degenerate cubic lattice, and its explicit stability constant is about eight times the two-point
Laplacian's. Both covolume viscous terms carry the same skewness error (face-average flux versus
connector-midpoint value); the collocated scheme's skew-corrected pair is the second-order route.

## Semi-implicit step (C2c)

The collocated solver's implicit-diffusion step (flow's structure) reaches the same steady states
as the explicit RK3 march with a step 50–100× larger: Poiseuille exact to 4e-13 in 154 steps at
Δt = 20 h²/ν; the sphere-array drag identical to four digits with 340 / 270 / 260 steps at
n = 16 / 24 / 32 against 1100 / 2200 / 3700. On the transient Taylor–Green the first-order time
error is below the spatial error at CFL ≤ 0.2.

## Distributed (C5, `tests/kokkos_mpi/test_flow_mpi`)

Collocated solver on a 12³ jittered lattice split by the ORB decomposition, TGV, 20 steps:
np = 1 is bit-exact to the single-rank run; np = 2 and 4 agree with it to 3e-15 in velocity and
2e-16 in energy, face divergence 2e-14. The per-rank block-Jacobi GraphAMG costs 28 / 36 PCG
iterations against 11 on one rank.

## Consequences for the plan

* The collocated skew-corrected adjoint pair is the default static solver for body-fitted work
  (C3 walls, C4 permeability); its structure is `peclet.flow`'s, so the two codes solve the same
  problem the same way (the unstructured pieces — `T`, `Tᵀ`, `(I − S)⁻¹` — reduce to flow's
  ½/½ average and central difference on a lattice).
* The covolume scheme keeps its exact energy conservation and exact projection, which track D's
  moving-mesh Lagrangian needs; its viscous term wants the DEC (Nicolaides) curl-curl form on the
  Voronoi edges (C2a′) to reach second order on unstructured cells.
* Immersed solids do not exist on the body-fitted mesh, so flow's invisible-subspace / ghost
  projection machinery has no counterpart here; the wall treatment is the (T, Tᵀ) pair at the
  wall faces (C3).
