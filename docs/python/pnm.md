# peclet.pnm — pore-network extraction

Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology), pore-network FLOW data (per-throat flow rates + pore pressures) from a peclet.flow DNS, and the distributed (MPI) extraction on the core ORB decomposition.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.pnm`

peclet.pnm — pore-network extraction from SDF pore geometry.

The "pnm_from_sdf" feature, split out of peclet-flow into its own package (the CFD solve lives in
:mod:`peclet.flow`). Everything is Kokkos (CUDA / HIP / OpenMP, ``execution_space`` says which):

- ``SDFReader.read_vti(path)`` -> ``(sdf, origin_zyx, spacing_zyx)``
- ``Pore`` (``x``, ``y``, ``z``, ``radius``)
- ``extract_pores(sdf, origin_zyx, spacing_zyx)`` -> ``list[Pore]``
- ``segment_volume(sdf, spacing_zyx)`` -> flat per-voxel labels (pores ``1, 2, …``, grains
  ``-1, -2, …``, ``0`` debris)
- ``extract_topology(segmentation, shape_zyx)`` -> sorted unique ``(a, b)`` label pairs
- ``extract_pore_network(sdf, origin_zyx, spacing_zyx)`` -> ``(pores, segmentation, connections)``,
  the fused pipeline (one SDF upload, segmentation device-resident across the stages)
- ``extract_network_flow(sdf, origin_zyx, spacing_zyx, u, v, w, p, ox=, oy=, oz=, grad_p_zyx=)``
  -> dict of per-pore pressures / residuals and per-throat flow rates from a peclet.flow MAC field
- built with ``PECLET_PNM_MPI``: ``mpi_rank()``, ``mpi_size()``, ``mpi_block(global_shape_zyx)``,
  ``extract_pore_network_mpi(...)`` and ``extract_network_flow_mpi(...)`` — the same pipelines
  distributed on the peclet-core ORB blocks, bit-exact to single-rank
- ``finalize()`` releases the Kokkos state (also registered at exit)

Conventions: arrays are ``(Nz, Ny, Nx)`` C-order and every triple describing them is z-y-x with
the ``_zyx`` suffix; SDF sign is negative inside the solid. Precision: the SDF is float32 and the
geometry kernels compute in float32 (``origin_zyx`` / ``spacing_zyx`` are narrowed from double,
so pore centres and radii are float32 in the input unit system); the network-flow MAC fields
(``u``, ``v``, ``w``, ``p``, openness) are float64.

### `SDFReader`

| Method / property | Description |
|---|---|
| `read_vti` | read_vti(arg: str, /) -> tuple  Reads VTI; returns (sdf_3d[nz,ny,nx], origin_zyx, spacing_zyx) |

### `Pore`
One detected pore: a strict local maximum of the SDF over its 26-neighbourhood (periodic in all three directions). The centre is the peak voxel's position plus a squared-SDF-weighted sub-voxel offset over the 3x3x3 stencil, in the unit system of origin_zyx / spacing_zyx; the radius is the SDF value at the peak, i.e. the physical inscribed-sphere radius. All fields are float32.

| Method / property | Description |
|---|---|
| `radius` | Inscribed-sphere radius = the SDF value at the peak voxel (physical units). |
| `x` | Centre x coordinate (physical units of origin_zyx / spacing_zyx). |
| `y` | Centre y coordinate. |
| `z` | Centre z coordinate. |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `execution_space` | `'OpenMP'` |

### `extract_network_flow`
```
extract_network_flow(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float], u: ndarray[dtype=float64, order='C'], v: ndarray[dtype=float64, order='C'], w: ndarray[dtype=float64, order='C'], p: ndarray[dtype=float64, order='C'], ox: ndarray[dtype=float64, order='C'] | None = None, oy: ndarray[dtype=float64, order='C'] | None = None, oz: ndarray[dtype=float64, order='C'] | None = None, grad_p_zyx: collections.abc.Sequence[float] = [0.0, 0.0, 0.0]) -> dict

Pore-network FLOW data from a MAC field on the same grid as the SDF: segments the SDF, then returns per-pore-label centers/pressures (trilinear p at the basin peak, periodic) and per-throat flow rates (sum of openness-weighted MAC face fluxes o*u*A over the label-interface faces; positive from the lower to the higher label). All arrays are (Nz,Ny,Nx) C-order on the SDF grid: pass flow's fields as get_uf().T, get_p().T, get_ox().T, ... u(i,j,k) is the -x face velocity of cell (i,j,k) (flow's MAC layout); omit ox/oy/oz for a fully open grid. grad_p_zyx adds the macroscopic gradient along the min-image pore-to-pore vector to throat_dp (= P_i - P_j, drives flow i->j when positive). pore_residual is the signed flux sum over each pore's whole boundary — ~solver tolerance when u is flow's projected divergence-free field. Throats are PER-PATCH (a connected patch of interface faces): two disjoint interfaces between the same two pores are separate parallel throats, so the throat list can repeat a label pair.
```

### `extract_pore_network`
```
extract_pore_network(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> tuple

Fused extraction (SDF uploaded once, segmentation device-resident across stages): returns (pores, segmentation_flat, connections).

UNITS: everything is in the system `origin_zyx` / `spacing_zyx` and the SDF are stated in (the VTI's own, straight from SDFReader.read_vti) — pore centres are physical coordinates and a pore radius is the physical inscribed radius, not a voxel count. Pass spacing_zyx = [1,1,1] and origin_zyx = [0,0,0] to work in voxels. Measured on flow/data/packing_ring.vti: doubling the spacing, the origin and the SDF together leaves the pore count (7199) and the throat-connection count (53020) unchanged and doubles every radius BITWISE. One sub-voxel caveat: the centre's intra-cell offset is guarded by an absolute `sw > 1e-6` on a squared-distance weight sum, so a near-degenerate peak's centre can shift by a fraction of a cell (measured up to 0.37 cells) under a change of unit system. Radii, counts and topology are unaffected.
```

### `extract_pores`
```
extract_pores(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> list[peclet.pnm._pnm.Pore]

Pore detection: every voxel with sdf > 0 that is a strict local maximum of the SDF over its 26 neighbours (periodic wrap in x, y, z; ties broken towards the higher flat index) becomes a Pore. sdf is a float32 (Nz,Ny,Nx) C-order array; origin_zyx / spacing_zyx are the grid's z-y-x origin and cell size (narrowed to float32). Returns the list of Pore(x, y, z, radius) in the input unit system, in device-completion order (NOT sorted; sort by (z, y, x) for a reproducible order). Capped at 1e6 pores.
```

### `extract_topology`
```
extract_topology(segmentation: collections.abc.Sequence[int], shape_zyx: collections.abc.Sequence[int]) -> list[tuple[int, int]]

Label adjacency of a segment_volume result: the sorted, unique (a, b) pairs with a < b of labels that share a voxel face (+x, +y, +z, periodic wrap). segmentation is the flat label vector, shape_zyx = (Nz, Ny, Nx) of the grid it was made on (= sdf.shape). Pairs with a label <= 0 are pore-solid (or grain-grain / debris) contacts; the pore-to-pore throats are the pairs with both labels > 0. One entry per label pair (a per-PATCH throat list, which can repeat a pair, is what extract_network_flow returns).
```

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

### `segment_volume`
```
segment_volume(sdf: ndarray[dtype=float32, order='C'], spacing_zyx: collections.abc.Sequence[float]) -> list[int]

Marker-controlled watershed segmentation of the SDF grid. Returns a flat int32 label per voxel in the SDF's x-fastest order (reshape to sdf.shape): pore voxels (sdf > 0) carry the id of the pore basin they belong to, 1, 2, ... in first-encounter (flat-index) order of the basin peaks — the same peaks extract_pores finds — assigned by a gradient-ascent path to the local SDF maximum; solid voxels (sdf <= 0) carry the NEGATIVE id -1, -2, ... of their connected solid grain (26-connected components of the deep solid, sdf < -1.5 * min spacing, flooded outwards by a Jacobi min-label sweep), and 0 marks solid debris no grain reached. Periodic in all three directions. spacing_zyx only sets the deep-solid marker threshold.
```

