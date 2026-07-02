# Changelog

All notable changes to the peclet suite are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-07-02

First public release.

### Added
- **`peclet.*` PEP-420 namespace family** on PyPI: `peclet-core`, `peclet-flow`, `peclet-dem`,
  `peclet-voro`, `peclet-morton`, and the `peclet` metapackage (`pip install peclet` for the CPU family).
- **Self-contained multicore-CPU (OpenMP) wheels** for the compute codes (vendored Kokkos/ArborX); GPU
  and MPI builds via source + containers.
- **`peclet.flow`** — incompressible cut-cell IBM Navier–Stokes on a staggered MAC grid with geometric
  multigrid pressure solve; `pnm` pore-network extraction. Multi-rank (MPI) solver exposed to Python
  (`Solver.init_mpi`, `mpi_block`).
- **`peclet.dem`** — XPBD discrete-element packing with SDF collision + distributed step.
- **`peclet.voro`** — dynamic Voronoi tessellation + distributed `VoronoiHalo`.
- **`peclet.core`** — shared ORB block decomposition, asynchronous grid/particle halo, SDF geometry,
  dynamic load balancing, AMR octree (MPI + Kokkos).
- **`peclet.morton`** — Morton/Z-order codes with arithmetic in Morton space.
- **Documentation site** (MkDocs Material, GitHub Pages) with a Python-forward API reference and per-code
  Doxygen; **HPC container** guide.
- **Apptainer containers** on GHCR: `peclet-cpu` and `peclet-cuda` (`-sm80`/`-sm90`), MPI-enabled
  (mpi4py + distributed flow/dem/voro), with per-site MPI bind wrappers (`snellius-run.sh`, `tue-run.sh`,
  `lumi-run.sh`) + SLURM submit scripts and a weak-scaling communication-overhead benchmark
  (`benchmarks/profile_mpi_flow.py`).
- MIT license across the suite; `CITATION.cff`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.

### Known limitations
- The **LUMI / HIP** container does not yet build (an `hipcc`/`lld` undefined-vtable link error involving
  nanobind hidden-visibility and the static Kokkos libraries); it needs on-GPU debugging. The CUDA image
  demonstrates the multi-GPU flow/voro code is correct.
- Multi-node / multi-GPU container runs on Snellius/LUMI/TU-e have not been validated on-cluster (match
  your site's exact OpenMPI module for the bind model).

[0.1.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.1.0
