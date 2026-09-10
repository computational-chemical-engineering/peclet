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
- ``segment_volume(sdf, spacing_zyx)`` -> int32 ``(Nz, Ny, Nx)`` per-voxel labels (pores
  ``1, 2, …``, grains ``-1, -2, …``, ``0`` debris)
- ``extract_topology(segmentation, shape_zyx=None)`` -> sorted unique ``(a, b)`` label pairs as an
  ``(M, 2)`` int32 array (``shape_zyx`` only for a flat label vector)
- ``extract_pore_network(sdf, origin_zyx, spacing_zyx)`` -> ``(pores, segmentation, connections)``,
  the fused pipeline (one SDF upload, segmentation device-resident across the stages)
- ``extract_network_flow(sdf, origin_zyx, spacing_zyx, u, v, w, p, ox=, oy=, oz=, grad_p_zyx=)``
  -> dict of per-pore pressures / residuals and per-throat flow rates (float64 arrays, throats
  ``(M, 2)`` int32) from a peclet.flow MAC field — the openness must be the one the field was
  projected with (flow: ``set_solid(..., cutcell_pressure=True)``)
- built with ``PECLET_PNM_MPI``: ``mpi_block(global_shape_zyx)`` -> ``(offset_zyx, shape_zyx)``
  (this rank's ORB block, in voxels), ``extract_pore_network_mpi(...)`` and
  ``extract_network_flow_mpi(...)`` — the same pipelines distributed on the peclet-core ORB
  blocks, bit-exact to single-rank (rank / size come from mpi4py)
- ``finalize()`` releases the Kokkos state (also registered at exit)

Conventions: arrays are ``(Nz, Ny, Nx)`` C-order and every triple describing them is z-y-x with
the ``_zyx`` suffix (``Pore.x/y/z`` are three self-named scalars, the one exception); SDF sign is
negative inside the solid. Arrays in, arrays out: the segmentation, connection and throat lists
and the network-flow scalars are NumPy arrays over the kernels' own host buffers (no per-element
conversion); only the pores are a Python ``list[Pore]``. Precision: the SDF is float32 and the
geometry kernels compute in float32 (``origin_zyx`` / ``spacing_zyx`` are narrowed from double,
so pore centres and radii are float32 in the input unit system); the network-flow MAC fields
(``u``, ``v``, ``w``, ``p``, openness) are float64.

### `SDFReader`

| Method / property | Description |
|---|---|
| `read_vti` | read_vti(arg: str, /) -> tuple  Reads a VTI (VTK ImageData) SDF volume. Returns the tuple (sdf, origin_zyx, spacing_zyx), in that order: sdf a float32 (Nz,Ny,Nx) C-order array over the reader's buffer (no copy), origin_zyx and spacing_zyx the z-y-x lists of the grid origin and cell size (float64). |

### `Pore`
One detected pore: a strict local maximum of the SDF over its 26-neighbourhood (periodic in all three directions). The centre is the peak voxel's position plus a squared-SDF-weighted sub-voxel offset over the 3x3x3 stencil, in the unit system of origin_zyx / spacing_zyx; the radius is the SDF value at the peak, i.e. the physical inscribed-sphere radius. All fields are float32. The centre is exposed as three self-named scalars x, y, z (not a triple), so no axis order is implied and no _zyx suffix applies — the documented exception to NAMING.md 1.7.

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

Returns a dict: 'pores' (list[Pore], ordered by label: pores[k] is label k+1), 'pore_pressure' and 'pore_residual' (float64 (N,)), 'throats' ((M,2) int32 label pairs a < b, per PATCH), 'throat_flow', 'throat_area' and 'throat_dp' (float64 (M,)).

PRECONDITION (cross-repo, not checkable here): the openness arrays must be the face openness the velocity field was projected with. For peclet.flow's cut-cell IBM that means the solid was set with set_solid(..., cutcell_pressure=True) — without it every openness flow reports is 0, so every throat_flow and throat_area comes back 0; for the ghost-cell IBM (set_ghost_projection) pass get_ox_proj()/get_oy_proj()/get_oz_proj() instead.
```

### `extract_network_flow_mpi`
```
extract_network_flow_mpi(sdf_local: ndarray[dtype=float32, order='C'], global_shape_zyx: collections.abc.Sequence[int], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float], u: ndarray[dtype=float64, order='C'], v: ndarray[dtype=float64, order='C'], w: ndarray[dtype=float64, order='C'], p: ndarray[dtype=float64, order='C'], ox: ndarray[dtype=float64, order='C'] | None = None, oy: ndarray[dtype=float64, order='C'] | None = None, oz: ndarray[dtype=float64, order='C'] | None = None, grad_p_zyx: collections.abc.Sequence[float] = [0.0, 0.0, 0.0]) -> dict

Distributed network-flow extraction (collective over MPI_COMM_WORLD): all arrays are this rank's ORB block (Nz,Ny,Nx C-order, from mpi_block; MAC fields from a distributed peclet.flow run on the SAME BlockDecomposer). Returns the same dict as extract_network_flow, GLOBAL and identical on every rank.

Returns a dict: 'pores' (list[Pore], ordered by label: pores[k] is label k+1), 'pore_pressure' and 'pore_residual' (float64 (N,)), 'throats' ((M,2) int32 label pairs a < b, per PATCH), 'throat_flow', 'throat_area' and 'throat_dp' (float64 (M,)).

PRECONDITION (cross-repo, not checkable here): the openness arrays must be the face openness the velocity field was projected with. For peclet.flow's cut-cell IBM that means the solid was set with set_solid(..., cutcell_pressure=True) — without it every openness flow reports is 0, so every throat_flow and throat_area comes back 0; for the ghost-cell IBM (set_ghost_projection) pass get_ox_proj()/get_oy_proj()/get_oz_proj() instead.
```

### `extract_pore_network`
```
extract_pore_network(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> tuple

Fused extraction (SDF uploaded once, segmentation device-resident across stages): returns the tuple (pores, segmentation, connections), in that order, each element exactly what extract_pores, segment_volume and extract_topology return (list[Pore]; int32 (Nz,Ny,Nx) array; (M,2) int32 array).

UNITS: everything is in the system `origin_zyx` / `spacing_zyx` and the SDF are stated in (the VTI's own, straight from SDFReader.read_vti) — pore centres are physical coordinates and a pore radius is the physical inscribed radius, not a voxel count. Pass spacing_zyx = [1,1,1] and origin_zyx = [0,0,0] to work in voxels. Measured on flow/data/packing_ring.vti: doubling the spacing, the origin and the SDF together leaves the pore count (7199) and the throat-connection count (53020) unchanged and doubles every radius BITWISE. One sub-voxel caveat: the centre's intra-cell offset is guarded by an absolute `sw > 1e-6` on a squared-distance weight sum, so a near-degenerate peak's centre can shift by a fraction of a cell (measured up to 0.37 cells) under a change of unit system. Radii, counts and topology are unaffected.
```

### `extract_pore_network_mpi`
```
extract_pore_network_mpi(sdf_local: ndarray[dtype=float32, order='C'], global_shape_zyx: collections.abc.Sequence[int], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> tuple

Distributed fused extraction (collective over MPI_COMM_WORLD). sdf_local is this rank's ORB block (Nz,Ny,Nx C-order, from mpi_block); origin_zyx / spacing_zyx are the GLOBAL grid's. Returns the tuple (pores, segmentation, connections), in that order: the pores whose peak this rank owns (list[Pore]), this rank's block of the segmentation (int32 array of sdf_local.shape, global label ids), and the GLOBAL connection list ((M,2) int32, identical on every rank). Bit-exact to the single-rank extract_pore_network on the gathered grid.
```

### `extract_pores`
```
extract_pores(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> list[peclet.pnm._pnm.Pore]

Pore detection: every voxel with sdf > 0 that is a strict local maximum of the SDF over its 26 neighbours (periodic wrap in x, y, z; ties broken towards the higher flat index) becomes a Pore. sdf is a float32 (Nz,Ny,Nx) C-order array; origin_zyx / spacing_zyx are the grid's z-y-x origin and cell size (narrowed to float32). Returns the list of Pore(x, y, z, radius) in the input unit system, in device-completion order (NOT sorted; sort by (z, y, x) for a reproducible order). Capped at 1e6 pores.
```

### `extract_topology`
```
extract_topology(segmentation: ndarray[dtype=int32, order='C', writable=False], shape_zyx: collections.abc.Sequence[int] | None = None) -> numpy.ndarray[dtype=int32]

Label adjacency of a segment_volume result: the sorted, unique (a, b) pairs with a < b of labels that share a voxel face (+x, +y, +z, periodic wrap), as an (M,2) int32 array. segmentation is the int32 (Nz,Ny,Nx) array segment_volume returned (read in place, no copy); a flat x-fastest label vector is accepted too, then shape_zyx = (Nz, Ny, Nx) of the grid it was made on (= sdf.shape) is required. Rows with a label <= 0 are pore-solid (or grain-grain / debris) contacts; the pore-to-pore throats are the rows with both labels > 0. One row per label pair (a per-PATCH throat list, which can repeat a pair, is what extract_network_flow returns).
```

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

### `mpi_block`
```
mpi_block(global_shape_zyx: collections.abc.Sequence[int]) -> tuple

This rank's ORB block of the global (Nz,Ny,Nx) grid (collective; MPI_Init is called if needed): returns the tuple (offset_zyx, shape_zyx), in that order — two int 3-tuples, the block's first VOXEL index per axis and its voxel count per axis. offset_zyx is an integer grid offset, NOT the physical origin_zyx the extraction functions take (that stays the global grid's). Slice the global SDF as sdf[oz:oz+sz, oy:oy+sy, ox:ox+sx] and pass the block to extract_pore_network_mpi / extract_network_flow_mpi.
```

### `segment_volume`
```
segment_volume(sdf: ndarray[dtype=float32, order='C'], spacing_zyx: collections.abc.Sequence[float]) -> numpy.ndarray[dtype=int32]

Marker-controlled watershed segmentation of the SDF grid. Returns an int32 (Nz,Ny,Nx) C-order label array (sdf.shape; the same memory as the kernels' flat x-fastest label vector — no copy, no reshape needed): pore voxels (sdf > 0) carry the id of the pore basin they belong to, 1, 2, ... in first-encounter (flat-index) order of the basin peaks — the same peaks extract_pores finds — assigned by a gradient-ascent path to the local SDF maximum; solid voxels (sdf <= 0) carry the NEGATIVE id -1, -2, ... of their connected solid grain (26-connected components of the deep solid, sdf < -1.5 * min spacing, flooded outwards by a Jacobi min-label sweep), and 0 marks solid debris no grain reached. Periodic in all three directions. spacing_zyx only sets the deep-solid marker threshold.
```

