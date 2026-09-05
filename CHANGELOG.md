# Changelog

All notable changes to the peclet suite are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — 0.7.0 (in preparation, see docs/RELEASE_PREP.md)

Family: peclet-core 0.6.0, peclet-flow 0.5.0 (+ peclet-flow-cu13), **new** peclet-pnm-cu13 /
peclet-dem-cu13 / peclet-voro-cu13 and the `peclet-cu13` CUDA metapackage, peclet-pnm 0.1.1 (core
header repin), peclet-dem 0.5.0, peclet-voro 0.5.0, peclet-coupling 0.4.0, peclet-morton 0.2.1 (unchanged).

### Added
- **flow**: geometric VoF two-phase flow (Weymouth–Yue advection, CSF surface tension with curvature
  branches, contact angle, phase change), analytic-SDF **scenes with moving instances** (`set_scene`,
  `set_solid_from_scene`, `set_instance_motion/transform`, `hydro_force_torque_reaction`), momentum
  residual stop + velocity multigrid, telescoping pressure hierarchy, `rebalance_by_weights`, ghost MASK exchange.
- **core**: `peclet.core.geom.SceneBuilder` (analytic CSG scene authoring, mass properties), weighted
  rebalancing hooks, GPU-aware halo option; NBX inter-round tag-race fix.
- **dem**: analytic SDF walls with `set_wall_transform` / `wall_sdf_at`, `set_external_torques`, scene
  particles (`peclet.dem.scene_particle`), `set_shape_ids`; two out-of-bounds writes fixed.
- **voro**: `FlowSolver` (covolume + collocated Navier–Stokes on a Voronoi mesh), `redistribute_pore_mesh`,
  covolume MPI hooks, device-packed ghost exchange.
- **coupling**: `ResolvedCfdDem` (resolved cut-cell CFD-DEM), reaction torque opt-in.
- **flow**: free-slip / symmetry domain boundary (`set_domain_bc(face, 4)`, both grids, MPI; a half domain
  closed by a symmetry plane reproduces the full one pointwise) and the outflow-reversal census
  (`outflow_backflow()`, a one-time warning when an outlet reverses with the backflow stabilization off).
- **Packaging**: CUDA wheels for the whole family (`pip install peclet-cu13`); containers now include pnm
  and coupling; `__version__` derived from the installed metadata; release workflow documented in
  `docs/RELEASE.md` with pre-flight and audit tools under `tools/release/`; Snellius family install +
  smoke scripts under `tools/hpc/`; LUMI recipe (`docs/LUMI.md`, untested).

### Changed / Fixed
- **Clean interpreter teardown in every module** (was a `Kokkos::abort`, exit 134, whenever a solver or a
  zero-copy view outlived the atexit finalize — scripts, `python -c`, notebooks): shared
  `kokkos_teardown.hpp` registry, release-then-finalize; explicit `finalize()` per module.
- `__version__` reports the installed distribution's version (was a stale literal in every package).
- HIP (LUMI) link: default symbol visibility on the HIP path + AMR wrappers in a named namespace.
- **core.amr**: `Flow.step()`/`project()` before `set_solid` raise a named `RuntimeError` (was a segfault);
  `set_solid`/`finish_adapt`/`rebalance_mpi` with a Python callable no longer hang under the OpenMP host
  backend (the bindings release the GIL around the multithreaded operator build).
- **core**: NBX round tags live in a reserved range (fixes the np=8 particle-halo hang and the
  intermittent distributed-AMR ghost errors).
- **dem**: `add_scene_shape` sizes the contact buffers and every capacity-sized array follows the
  particle capacity (was a silent contact drop, then heap corruption); root-level scratch scripts are
  excluded from the sdist.
- (more at release time from the per-package logs — see RELEASE_PREP §1.4 for the gallery-found defects)

### Known limitations
- LUMI / HIP: the `peclet-hip` image builds and is published for the first time, but has not run on AMD
  hardware (no LUMI allocation yet) — see docs/LUMI.md.

## [0.6.0] — 2026-07-25

Family release: peclet-flow 0.4.0 (**BREAKING**: pore-network extraction split out of `peclet.flow.pnm`),
**new** peclet-pnm 0.1.0 (`peclet.pnm`: extraction + distributed MPI extraction + DNS network flow with
per-patch throats), peclet-dem 0.4.0, peclet-voro 0.4.0, peclet-morton 0.2.1 (cp38 wheels dropped),
peclet-core 0.5.0, peclet-coupling 0.3.0; peclet-flow-cu13 0.4.0. Zenodo DOIs minted per repo.

## [0.5.0] — 2026-07-06

peclet-coupling 0.2.0 joins the family as the `[cfd-dem]` extra (unresolved point-particle CFD-DEM
`CfdDem`: void fraction, drag laws, semi-implicit feedback); dem event-level restitution + multilevel
contact stabiliser; flow porous (ε-weighted) momentum for coupled runs.

## [0.4.4] / [0.4.3] / [0.4.2] / [0.4.1] — 2026-07-04

voro 0.3.1 → 0.3.3: SDF pore-mesh optimiser in the Python API (`optimize_pore_mesh`), O(N)
`sdf_voronoi_cells`, `ConvexCell::sectionPolygon` / `sdf_voronoi_section`; dem 0.3.1 `to_stl` mesh export.

## [0.4.0] — 2026-07-04

peclet-flow 0.3.0 (verify_bfs shear-layer stability, inflow/outflow + immersed solid fixed, deferred
correction), peclet-flow-cu13 first published (single-GPU CUDA wheel on `nvidia-cuda-runtime`),
dem 0.3.0, voro 0.3.0, core 0.3.0.

## [0.3.0] — 2026-07-03

voro graph-AMG mesh-optimiser preconditioner (host + device).

## [0.2.2] — 2026-07-03

peclet-flow 0.2.1: inflow/outflow domain BCs with immersed solids, `set_backflow_stabilization`,
`set_deferred_correction`.

## [0.2.1] — 2026-07-03

peclet-dem 0.2.1: periodic collision detection fix (unfilled ghost halo layers in the Kokkos port;
found through the gallery's random-packed-bed g(r)).

## [0.2.0] — 2026-07-02

Feature release: multi-rank Python API + HPC MPI containers.

### Added
- **Multi-rank (MPI) `flow` and `voro` exposed to Python**: `peclet.flow.Solver.init_mpi(gnx,gny,gnz)` +
  `peclet.flow.mpi_block(...)` for the distributed Navier–Stokes solve; `peclet.voro.VoronoiHalo` for the
  distributed tessellation (both validated bit-exact / Σvol-exact at np=1/2/4). Gated on
  `PECLET_FLOW_MPI` / `PECLET_VORO_MPI` (on in the containers).
- **MPI-enabled Apptainer containers** on GHCR (public): `peclet-cpu` and `peclet-cuda` (`-sm80`/`-sm90`),
  with `mpi4py` + distributed flow/dem/voro; the CUDA image bundles a from-source **CUDA-aware OpenMPI**.
- **Per-site launch**: MPI bind wrappers `snellius-run.sh` / `tue-run.sh` / `lumi-run.sh` + SLURM submit
  scripts for Snellius, TU/e SMM (`chem.smm03.q`), and LUMI.
- **Weak-scaling communication-overhead benchmark** `benchmarks/profile_mpi_flow.py`.
- Open-source hygiene: status badges, `CITATION.cff`, `CONTRIBUTING`/`CODE_OF_CONDUCT`/`SECURITY`,
  issue/PR templates, Dependabot, repo descriptions + topics.

### Fixed
- nvcc: an extended `__host__ __device__` lambda in a private dem method (`maxOwnedDisplacement`).
- Container builds on the Ubuntu-22.04 GPU bases: conditional `pip` upgrade for `--config-settings` /
  `--break-system-packages`.

### Changed
- Project display name capitalized to **Peclet** in the documentation (package/import/CLI names remain
  lowercase `peclet`).

### Known limitations
- The **LUMI / HIP** container still does not build (hipcc/lld undefined-vtable link error); needs on-GPU debugging.

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

[0.6.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.6.0
[0.5.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.5.0
[0.2.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.2.0
[0.1.0]: https://github.com/computational-chemical-engineering/peclet/releases/tag/v0.1.0
