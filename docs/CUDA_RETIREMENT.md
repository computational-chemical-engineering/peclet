# CUDA retirement plan

Goal: make the **Kokkos** implementations the canonical, default ones across the suite — drop the
`kokkos` suffix from module/file/namespace names, delete the CUDA implementations, and land the result
on each repo's `main`. After this, every method code builds and runs on Kokkos (CUDA *and* HIP/OpenMP
backends) with no CUDA-only path.

> **STATUS: COMPLETE (2026-06-20).** All three repos retired CUDA and merged `kokkos-migration → main`:
> cfd-gpu (`sdflow`/`pnm_backend`), packing-gpu (`demgpu`), core (Kokkos grid + particle
> halos). Validated on CUDA + host-openmp; `tests/kokkos_mpi` ctests pass np=1,2,4. Not pushed (per the
> milestone-commit policy). Restore points: the `pre-cuda-retirement` tag on each repo. Phase checklist
> below is all checked off.

## Status going in (verified 2026-06-20)

The migration is **numerically complete** — every solver, method, and option is ported and validated on
CUDA + OpenMP backends:

- **core** — Kokkos grid + particle halos (incl. periodic self-ghosts). Legacy CUDA halo
  (`grid_halo_cuda.cuh`) still present.
- **cfd-gpu `sdflow`** — full cut-cell IBM Navier–Stokes + geometric MG-PCG, all three pressure drivers
  (V-cycle / PCG / Chebyshev), implicit-FOU + Picard, velocity-MG (IBM-staircase / domain-BC const-coeff
  / upwind-convective), all domain BCs (cavity / channel / BFS), multi-rank MPI; `pnm_backend` pore
  extraction bit-identical. Kokkos sources in `src/kokkos/`, module `sdflow_kokkos` + `pnm_kokkos` in
  `kokkos_module/`.
- **packing-gpu `demgpu`** — all XPBD kernels, ArborX broad-phase (cuBQL already retired in the CUDA
  build too), analytic shapes (sphere / hollow-cylinder / box), growth / rotation / thermostat /
  periodicity / friction, `get_sdf_grid`, `write_vtp`, distributed demStep (periodic self-ghosts).
  Kokkos sources in `src/cuda/*_kokkos.hpp` + `*_portable.hpp`, module `demgpu_kokkos` in
  `kokkos_module/`.

**Out of scope** (not CUDA, or not in the migrated path):
- **voronoi_dynamics** — OpenMP/CPU (Boost + Voro++), *no CUDA*. Its Kokkos-OpenMP rebuild is a separate,
  later effort; nothing to retire here.
- **morton_arithmetic** — ~~Leave as-is~~ **RETIRED (2026-06-22):** the raw-CUDA backend (`cuda/`,
  `morton::cuda`) was deleted and replaced by a portable **Kokkos** backend (`include/morton/kokkos.hpp`,
  `morton::kokkos`; CUDA/HIP/OpenMP, opt-in `-DMORTON_ENABLE_KOKKOS=ON`). The core's `MORTON_HD` now
  resolves to `KOKKOS_FUNCTION`. Device output validated bit-for-bit vs the scalar library on OpenMP +
  CUDA; device-resident throughput preserved (~51 GMops/s 2D-32 encode). Restore point:
  `pre-cuda-retirement` tag in the morton repo.

### Gaps to close before deleting CUDA (the real remaining work)

The numerics are done, but the Kokkos *modules* are not yet drop-in replacements:

1. **Naming / build** — modules are `sdflow_kokkos` / `demgpu_kokkos` / `pnm_kokkos`, built as *separate*
   `kokkos_module/` find_package projects. The canonical names and the main `cmake -S . -B build` still
   produce the CUDA modules. `main` has no Kokkos on any repo.
2. **cfd `sdflow` API** — Kokkos `Solver` is missing, vs CUDA: `set_incremental_pressure`,
   `set_pressure_warmstart`, `set_state` (real features); `get_resolution`, `get_spacing`, `size`
   (trivial getters); `set_velocity_streams` (CUDA-only → drop / no-op shim).
3. **packing `demgpu` API** — the **MPI step is not exposed in Python** (only in the C++ test): add
   `init_mpi` / `enable_mpi_step` / `step_mpi` to the binding (gated, like the cfd MPI build). Plus
   missing `export_sdf`, `export_lammps`, `get_masses`, `get_growth_rate`, `get_profiling_info`,
   `get_domain_min/max`, `compute_overlaps`.

Not gaps: arbitrary grid-SDF shapes are a `+inf` placeholder in **both** CUDA and Kokkos; `pnm_kokkos` is
already a superset of `pnm_backend`.

## Locked decisions (user, 2026-06-20)

1. **Full de-naming** — strip `kokkos` from filenames *and* namespaces, not just the module name.
2. **Update scripts to the Kokkos API** — do *not* add CUDA-compat method aliases; instead update the
   verify scripts to the (canonical, formerly-Kokkos) method names.
3. **Close all gaps** — implement every missing real feature (cfd 3 methods + getters, packing MPI
   binding + exports/getters); `set_velocity_streams` becomes a no-op shim (kept only if a script calls it).
4. **Sequence** — implementer's choice. Plan does cfd first (most complete → the template), then packing,
   then core; merge each as it lands.

## Restore points

Tag `pre-cuda-retirement` created on each repo's current `kokkos-migration` HEAD (the full validated
CUDA + Kokkos state): core `a6ef3fa`, cfd-gpu `47e52c3`, packing-gpu `af3250a`. cfd-gpu also
keeps the older `pnm_backend-reference` tag. CUDA is recoverable from these after deletion.

## Phased plan

Work continues on the `kokkos-migration` branch of each repo, merging to `main` at the end of each
repo's Phase 4. Nothing is pushed until the user says.

### Phase 0 — tag for restore  ✅ DONE
`pre-cuda-retirement` tags created (see above). This plan committed to the umbrella `docs/`.

### Phase 1 — close the API gaps (per repo)  ✅ DONE
- **cfd**: add to the Kokkos `Solver` — `set_incremental_pressure`, `set_pressure_warmstart`,
  `set_state`, `get_resolution`, `get_spacing`, `size`; `set_velocity_streams` → no-op shim. Validate
  with the existing `kokkos_module/verify_*.py`.
- **packing**: add the gated MPI binding (`init_mpi` / `enable_mpi_step` / `step_mpi`) to
  `kokkos_module/binding.cpp` + a gated `demgpu_kokkos` MPI build target (mirror cfd's pattern); add
  `export_sdf` / `export_lammps` / the missing getters. Validate.

### Phase 2 — parity sweep (the go/no-go gate)  ✅ DONE
Run every top-level `verify_*` script + `cfd-gpu/tests/regression/sdflow_regression.py` against the
Kokkos modules, and record CUDA-vs-Kokkos deltas. Acceptance bar: **machine-precision, or a difference
explainable purely by roundoff / reduction order** (cfd co-imports the Kokkos-free CUDA `sdflow` for a
direct compare; packing is per-process + physical/roundoff-fuzzy because XPBD accumulates via atomics).

### Phase 3 — rename + make Kokkos canonical (per repo)  ✅ DONE
- Rename modules: `sdflow_kokkos → sdflow`, `demgpu_kokkos → demgpu`, `pnm_kokkos → pnm_backend`.
- Strip `kokkos` from filenames (`*_kokkos.hpp → *.hpp`, `src/kokkos/ → src/`) and from
  namespaces/symbols (full de-naming, decision 1).
- Make the repo's main `cmake -S . -B build` produce the canonical modules via `find_package(Kokkos)` +
  `find_package(ArborX)` against `extern/install/<backend>`. **Note:** this makes the bootstrapped
  toolchain (`tools/bootstrap_deps.sh`) a *hard* build dependency (was optional) — document it.
- Update the verify scripts to the canonical API (decision 2) and the canonical module names.

### Phase 4 — delete CUDA (per repo)  ✅ DONE
Remove the `.cu` / `.cuh` solver sources, the CUDA pybind bindings, and `grid_halo_cuda.cuh`; drop the
CUDA / cuBQL / nvcc paths from CMake. Update each `CLAUDE.md` + the suite `docs/` to describe the
Kokkos-only world.

### Phase 5 — merge + tidy  ✅ DONE (merged; umbrella docs + submodule pointers updated; push pending user OK)
Merge `kokkos-migration → main` in each repo; repoint the umbrella `peclet` submodule pointers + update
the umbrella docs (`ARCHITECTURE.md`, `ROADMAP.md`, `PORTABILITY.md`). Push when the user asks.

## Per-repo checklist

| Repo | Phase 1 (gaps) | Phase 3 (rename) | Phase 4 (delete) |
|------|----------------|------------------|------------------|
| **cfd-gpu** | +3 methods, +3 getters, streams shim | `src/kokkos/*` → `src/`, `cfdk::` → `dns::`/canonical, `sdflow_kokkos`→`sdflow`, `pnm_kokkos`→`pnm_backend` | delete `distributed_ns.cuh`, `mac_*.cuh`, `cut_cell_ibm.cuh`, `staggered_advection.cuh`, `pore_extraction.{cu,cuh}`, `sdflow_bindings.cu`, `bindings.cpp` |
| **packing-gpu** | MPI binding + build, exports, getters | `*_kokkos.hpp`→`*.hpp`, `dem::` kept, `demgpu_kokkos`→`demgpu` | delete `*.cu`/`*.cuh`, `main_binding.cpp`, `ParticleSystem.cuh`, `src/mpi/*.cu` |
| **core** | — | — | delete `grid_halo_cuda.cuh` + its test/CMake entry |
| **voronoi_dynamics** | — (no CUDA; separate later Kokkos-OpenMP effort) | — | — |
| **morton_arithmetic** | add `morton::kokkos` (`include/morton/kokkos.hpp`) + `MORTON_ENABLE_KOKKOS` build/tests/bench | `MORTON_HD`→`KOKKOS_FUNCTION`; no module rename (header-only) | delete `cuda/` (`morton::cuda`); tag `pre-cuda-retirement` |

## Validation gate (every phase)

- cfd: all `scripts/verify_*_sdflow.py` (→ renamed) + `tests/regression/sdflow_regression.py` pass;
  Kokkos-vs-CUDA machine-precision on the co-import scripts; `tests/kokkos_mpi` ctests pass np=1,2,4.
- packing: `verify_*.py` pass; physical-equivalence vs CUDA (per-process); `tests/kokkos_mpi` ctests pass.
- Both backends (CUDA + host-openmp) green before each merge.

## Validation outcome (2026-06-20)

- **cfd-gpu — machine-precision.** Co-import (Kokkos-free CUDA `sdflow` + Kokkos `sdflow`): periodic
  sphere Stokes `k` agrees to ~1e-13 (max|Δu| ~1e-12). All `scripts/verify_*_sdflow.py` pass against the
  renamed `sdflow` (cavity/channel/BFS/poiseuille/implicit-FOU; Zick–Homsy <0.4% vs ground truth;
  chebyshev == MG-PCG 0.0000%). `pnm_backend` (incl. the added `SDFReader`) bit-identical. The regression
  metrics (K/k*/order/divergence) are **+0.00%** vs the CUDA baseline — only the MG-PCG *iteration counts*
  differ (float-operator reduction order, same converged solution), so the baseline was re-recorded for
  Kokkos. `tests/kokkos` 14/14, `tests/kokkos_mpi` 18/18 (np=1,2,4), CUDA + OpenMP.
- **packing-gpu — faithful drop-in (physical/per-process).** Every top-level `verify_*.py` runs unmodified
  against the renamed `demgpu` and its **pass/fail matches the CUDA `demgpu`**: collision_spheres /
  thermostat / precession PASS on both; the `verify_stacking*` scripts FAIL on **both** backends — a
  pre-existing CUDA friction/settling defect (documented; a separate deferred numerics task, not a port
  regression). `tests/kokkos` 8/8, `tests/arborx` 2/2, `tests/kokkos_mpi` 6/6, CUDA + OpenMP.
- **core** — CPU 27/27; Kokkos halo path (`TPX_ENABLE_KOKKOS`) 33/33, np=1,2,4.
