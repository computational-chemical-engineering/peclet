# Suite Architecture

> Status: design document (living). Companion to [CONVENTIONS](CONVENTIONS.md),
> [STYLE](STYLE.md), [INTERFACES](INTERFACES.md), [ROADMAP](ROADMAP.md).

## Purpose

The suite simulates **transport phenomena** with several complementary methods. Each method is its
own code and stays that way — but they should **correspond**: share data conventions, geometry
(SDF-described solids), the immersed-boundary methodology, GPU support, MPI domain decomposition with
asynchronous ghost-layer exchange, and Python bindings. This document defines the layering that makes
that correspondence concrete, so a developer moving between codes finds the same primitives, the same
conventions, and the same interfaces.

## Method taxonomy

| Code | Kind | State representation | Status |
|------|------|----------------------|--------|
| `flow` | **Eulerian** | Structured grid: staggered MAC (default) or collocated/cell-centered, via a `GridLayout` policy | Extensively developed |
| `dem` | **Lagrangian** | Particles (DEM/XPBD), SoA on GPU | Extensively developed |
| `voro` | **Mixed** | Moving particles + their Voronoi cells (Lagrangian carriers, Eulerian-like fluxes across cell faces); also a mesh generator + Navier–Stokes on the Voronoi mesh | Developed; Kokkos + nanobind Python |
| `pnm` | Eulerian post-processing | Pore/throat network extracted from an SDF grid (watershed), network flow from a `flow` DNS | Developed; split out of `flow` 2026-07 |
| `coupling` | **Coupled** | `flow` + `dem` in one process: unresolved (volume-averaged drag, void fraction) and resolved (cut-cell reaction) two-way coupling | Developed; distributed when both are |
| `amr` | **Eulerian, adaptive** | Block-local-Morton octree (per-block octree, distributed octree with leaf/field rebalance, solution-adaptive refinement) carrying a collocated cut-cell Navier–Stokes solver (ghost projection, mixed-level cut band, AMR multigrid/BiCGStab) | Under development; split out of `core/amr/` with its history 2026-09-10 (QUALITY_PLAN G.2); depends on `core` + `morton` only |
| `morton` | Primitive | Z-order codes / spatial index | Mature |

(`block_decomposer`, the original source of the shared MPI layer, has been **retired/archived**; its
reusable parts now live in `core`.)

The Eulerian/Lagrangian/mixed split is the key axis: it determines *what travels in a halo exchange*
(grid cell slabs vs. migrating particles vs. ghost particles + cell neighbours) but **not** the
decomposition (all use the same block decomposition) nor the geometry (all use the same SDF + IBM).

## Layered design

```
            ┌──────────────────────────────────────────────────────────┐
 methods    │  flow  pnm  dem  voro  coupling  amr     │   separate repos
            └──────────────────────────────────────────────────────────┘
                   │             │                │
                   ▼             ▼                ▼
            ┌──────────────────────────────────────────────────────────┐
 core       │                   core                         │   new shared repo
            │  decomposition · halo (async MPI) · geometry/SDF · ibm   │
            │  solver (face-CSR, BiCGStab, colouring, GraphAMG) · vof  │
            │  common types/conventions · python (nanobind bridge)     │
            └──────────────────────────────────────────────────────────┘
                   │                                        │
                   ▼                                        ▼
            ┌─────────────────────┐                ┌──────────────────┐
 primitives │  morton  │                │ Kokkos, ArborX,  │   external / vendored
            │  (block/cell index) │                │ Voro++, MPI, ... │
            └─────────────────────┘                └──────────────────┘
```

**Rule:** dependencies point downward only. A method depends on `core`; `core`
depends on primitives. No method depends on another method; primitives depend on nothing in the suite.

## `core` modules

- **common** — shared types and conventions in code form (vector/index aliases, axis order, units,
  error/logging). Codifies [CONVENTIONS](CONVENTIONS.md).
- **decomposition** — orthogonal recursive bisection of the global domain into rank-owned blocks
  (`BlockDecomposer`), global↔local indexing with ghost layers (`BlockIndexer`), and morton/Z-order
  cell indexing (via `morton`). Ported from the retired `block_decomposer` (see above).
- **halo** — the asynchronous ghost-layer exchange. One `HaloExchange` interface, two engines: an
  **NBX nonblocking-consensus** loop for dynamic/sparse patterns (particle migration) and a
  **persistent neighborhood-collective** path for static grid halos. Field-agnostic pack/unpack so a
  grid scalar field, a grid vector field, and a particle attribute array all flow through one path.
  GPU-aware (device-buffer exchange, on-device pack/unpack).
- **geometry/SDF** — one signed-distance representation (analytic shapes + grid SDF), VTI/VTP I/O, the
  shared sign convention (negative inside solid). All three methods already use SDFs; this unifies
  them.
- **ibm** — the common Immersed Boundary Method interface: cut-cell / boundary data derived from an
  SDF, consumed by Eulerian solvers (and the point-shell collision analog in `dem`).
- **python** — the shared **nanobind** zero-copy array bridge (`peclet::core::python`,
  `include/peclet/core/python/ndarray_interop.hpp`) so every method exposes Python the same way (array shapes,
  ownership, naming). Host Views/vectors export as NumPy without a copy; device Views export as DLPack
  for CuPy/PyTorch. Provisioned via `cmake/SuiteNanobind.cmake`; see CONVENTIONS §6.

## How each method maps onto the core

- **flow (Eulerian):** the global MAC grid is partitioned by `decomposition`; each rank owns a block
  with ghost cells; per-step it exchanges grid-field halos through the **persistent neighborhood**
  path; SDF geometry + IBM come from `geometry`/`ibm`. First solver to be wired in (most grid-native).
- **dem (Lagrangian):** particles are owned by the block containing them; per-step it does
  **particle migration** (NBX path) + **ghost-particle** exchange near block boundaries; collision
  geometry uses the shared SDF. Reuses its existing ArborX broad-phase locally inside a block.
- **voro (mixed):** particles migrate like Lagrangian carriers (NBX path), but each rank
  also needs **ghost particles** one interaction radius deep to close the Voronoi cells touching the
  block boundary; fluxes across Voronoi faces are the Eulerian aspect. Gets nanobind bindings via
  `python`.
- **pnm (post-processing):** the SDF grid is partitioned like `flow`'s; the distributed extraction
  runs the watershed per block and reconciles labels across the halo, bit-exact to the single-rank
  extraction on the gathered grid.
- **coupling (flow + dem):** one shared `BlockDecomposer` for the grid and the particles; the
  particle→grid deposition uses the add-reduce halo (`exchange_field_add`) and the grid→particle
  interpolation the ordinary ghost exchange, so the coupled step is distributed whenever both codes
  are.

## What stays method-specific

Numerical schemes and solvers: the CFD projection solver and its multigrid, the VoF advection, the
XPBD / Hertz–Mindlin contact solvers, the device Voronoi tessellator, the pore-network watershed,
the CFD-DEM drag closures. The core provides *where data lives and how it moves*, not *how the
physics is integrated*.
