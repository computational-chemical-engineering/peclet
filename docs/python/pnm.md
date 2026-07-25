# peclet.pnm — pore-network extraction

Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology) and pore-network FLOW data (per-throat flow rates + pore pressures) from a peclet.flow DNS. Split out of peclet-flow (was `peclet.flow.pnm`).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.pnm`

peclet.pnm — pore-network extraction from SDF pore geometry.

``SDFReader``, ``extract_pores``, ``segment_volume``, ``extract_topology_gpu`` — the "pnm_from_sdf"
feature, split out of peclet-flow into its own package (the CFD solve lives in :mod:`peclet.flow`).

### `SDFReader`

| Method / property | Description |
|---|---|
| `read_vti` | read_vti(arg: str, /) -> tuple  Reads VTI; returns (sdf_3d[nz,ny,nx], origin_zyx, spacing_zyx) |

### `Pore`

| Method / property | Description |
|---|---|
| `radius` | (self) -> float |
| `x` | (self) -> float |
| `y` | (self) -> float |
| `z` | (self) -> float |

## `peclet.pnm`

peclet.pnm — pore-network extraction from SDF pore geometry.

``SDFReader``, ``extract_pores``, ``segment_volume``, ``extract_topology_gpu`` — the "pnm_from_sdf"
feature, split out of peclet-flow into its own package (the CFD solve lives in :mod:`peclet.flow`).

