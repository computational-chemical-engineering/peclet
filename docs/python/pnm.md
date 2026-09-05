# peclet.pnm — pore-network extraction

Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology), pore-network FLOW data (per-throat flow rates + pore pressures) from a peclet.flow DNS, and the distributed (MPI) extraction on the core ORB decomposition.

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

### Module attributes

| Attribute | Value in this build |
|---|---|
| `execution_space` | `'OpenMP'` |

### `extract_network_flow`
```
extract_network_flow(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float], u: ndarray[dtype=float64, order='C'], v: ndarray[dtype=float64, order='C'], w: ndarray[dtype=float64, order='C'], p: ndarray[dtype=float64, order='C'], ox: ndarray[dtype=float64, order='C'] | None = None, oy: ndarray[dtype=float64, order='C'] | None = None, oz: ndarray[dtype=float64, order='C'] | None = None, grad_p_zyx: collections.abc.Sequence[float] = [0.0, 0.0, 0.0]) -> dict

Pore-network FLOW data from a MAC field on the same grid as the SDF: segments the SDF, then returns per-pore-label centers/pressures (trilinear p at the basin peak, periodic) and per-throat flow rates (sum of openness-weighted MAC face fluxes o*u*A over the label-interface faces; positive from the lower to the higher label). All arrays are (Nz,Ny,Nx) C-order on the SDF grid: pass flow's fields as get_uf().T, get_p().T, get_ox().T, ... u(i,j,k) is the -x face velocity of cell (i,j,k) (flow's MAC layout); omit ox/oy/oz for a fully open grid. grad_p_zyx adds the macroscopic gradient along the min-image pore-to-pore vector to throat_dp (= P_i - P_j, drives flow i->j when positive). pore_residual is the signed flux sum over each pore's whole boundary — ~solver tolerance when u is flow's projected divergence-free field. Throats are PER-PATCH (a connected patch of interface faces): two disjoint interfaces between the same two pores are separate parallel throats, so the throat list can repeat a label pair.
```

### `extract_network_flow_mpi`
```
extract_network_flow_mpi(sdf_local: ndarray[dtype=float32, order='C'], global_shape_zyx: collections.abc.Sequence[int], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float], u: ndarray[dtype=float64, order='C'], v: ndarray[dtype=float64, order='C'], w: ndarray[dtype=float64, order='C'], p: ndarray[dtype=float64, order='C'], ox: ndarray[dtype=float64, order='C'] | None = None, oy: ndarray[dtype=float64, order='C'] | None = None, oz: ndarray[dtype=float64, order='C'] | None = None, grad_p_zyx: collections.abc.Sequence[float] = [0.0, 0.0, 0.0]) -> dict

Distributed network-flow extraction (collective over MPI_COMM_WORLD): all arrays are this rank's ORB block (Nz,Ny,Nx C-order, from mpi_block; MAC fields from a distributed peclet.flow run on the SAME BlockDecomposer). Returns the same dict as extract_network_flow, GLOBAL and identical on every rank.
```

### `extract_pore_network`
```
extract_pore_network(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> tuple

Fused extraction (SDF uploaded once, segmentation device-resident across stages): returns (pores, segmentation_flat, connections).
```

### `extract_pore_network_mpi`
```
extract_pore_network_mpi(sdf_local: ndarray[dtype=float32, order='C'], global_shape_zyx: collections.abc.Sequence[int], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> tuple

Distributed fused extraction (collective over MPI_COMM_WORLD). sdf_local is this rank's ORB block (Nz,Ny,Nx C-order, from mpi_block). Returns (pores_owned_by_this_rank, segmentation_flat_local_block, connections_global). Bit-exact to the single-rank extract_pore_network on the gathered grid.
```

### `extract_pores`
```
extract_pores(sdf: ndarray[dtype=float32, order='C'], origin_zyx: collections.abc.Sequence[float], spacing_zyx: collections.abc.Sequence[float]) -> list[peclet.pnm._pnm.Pore]
```

### `extract_topology_gpu`
```
extract_topology_gpu(segmentation: collections.abc.Sequence[int], shape: collections.abc.Sequence[int]) -> list[tuple[int, int]]
```

### `finalize`
```
finalize() -> None

Release every live object and zero-copy array of this module, then Kokkos::finalize() (deterministic teardown; also run automatically at interpreter exit). Idempotent. After it, the module's solver objects and *_view arrays must not be used.
```

### `mpi_block`
```
mpi_block(global_shape_zyx: collections.abc.Sequence[int]) -> tuple

This rank's ORB block of the global grid: (origin_zyx, shape_zyx). Slice the global SDF with these and pass the local block to extract_pore_network_mpi.
```

### `mpi_rank`
```
mpi_rank() -> int

This rank's index in MPI_COMM_WORLD (MPI_Init is called if needed).
```

### `mpi_size`
```
mpi_size() -> int

Number of ranks in MPI_COMM_WORLD (MPI_Init is called if needed).
```

### `segment_volume`
```
segment_volume(sdf: ndarray[dtype=float32, order='C'], spacing_zyx: collections.abc.Sequence[float]) -> list[int]
```

