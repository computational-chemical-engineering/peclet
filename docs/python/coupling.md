# peclet.coupling — CFD-DEM coupling

Two-way coupling of `peclet.flow` and `peclet.dem`: the unresolved point-particle driver `CfdDem` (void fraction, drag laws, semi-implicit feedback) and the resolved cut-cell driver `ResolvedCfdDem` (hydrodynamic force/torque reaction on scene particles).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.coupling`

peclet.coupling — CFD-DEM coupling, unresolved and resolved.

Composes peclet.flow (Eulerian fluid) + peclet.dem (Lagrangian particles).

CfdDem is the UNRESOLVED point-particle driver: a grain is a point with a drag closure, and the
compute kernels (particle<->grid deposition, drag laws, momentum feedback) live in the _coupling
extension, running in place on the arrays the two solvers expose (zero-copy grid fields; particle
forces round-tripped through the dem host API).

ResolvedCfdDem is the RESOLVED driver (Layer 4 of suite/docs/ANALYTIC_SDF_GEOMETRY.md): each grain
IS an analytic SDF instance in the flow solver's scene, the fluid resolves its surface, and the
coupling is a surface-traction exchange with no drag correlation in it. Pure Python -- it needs no
compiled kernels of its own.

### `CfdDem`

| Method / property | Description |
|---|---|
| `compute_forces` | &nbsp; |
| `last_drag` | &nbsp; |
| `last_slip` | &nbsp; |
| `rebalance` | Dynamic co-rebalancing (multi-rank only). Build ONE weight field over the global grid -- fluid work (1 per cell) + gamma * particle count -- and redistribute BOTH codes onto the same weighted ORB from it: the flow state via rebalance_by_weights (bit-exact migration + rebuild), the particles via migrate_to_weights. Because both build the SAME deterministic partition from the same array, they stay co-located. Call at a step boundary. No-op single-rank. |
| `slip` | Interpolated fluid velocity minus particle velocity (N,3) — what the drag law sees. `vel` may be host or device; returns a host NumPy array for convenient inspection. |
| `step` | &nbsp; |
| `update_void_fraction` | &nbsp; |

### `ResolvedCfdDem`

| Method / property | Description |
|---|---|
| `forces` | &nbsp; |
| `step` | &nbsp; |
| `torques` | &nbsp; |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `DRAG_BEETSTRA` | `6` |
| `DRAG_DI_FELICE` | `3` |
| `DRAG_ERGUN` | `2` |
| `DRAG_GIDASPOW` | `5` |
| `DRAG_SCHILLER_NAUMANN` | `1` |
| `DRAG_STOKES` | `0` |
| `DRAG_TANG` | `7` |
| `DRAG_WEN_YU` | `4` |

