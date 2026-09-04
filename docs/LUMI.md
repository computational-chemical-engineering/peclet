# Running peclet on LUMI (CSC / EuroHPC) — UNTESTED

> **Status: the HIP container image builds (since 2026-09-04, CI run 33874788583, whole family with
> MPI on) but no peclet build has ever RUN on LUMI.** This page is the recipe we intend to validate
> once a LUMI allocation is granted. Every command below is derived from the LUMI documentation and
> from the Snellius recipe ([SNELLIUS.md](SNELLIUS.md)), not from a run. The former blocker, a link
> error in the HIP build of the Python modules, is fixed (§4). Treat the version pins as hypotheses.

## Coordinates (fill in when the project exists)

| | |
|---|---|
| host | `lumi.csc.fi` (`lumi-uan01..04` login nodes) |
| account | `project_46XXXXXXX` (every `#SBATCH --account`) |
| project space | `/project/project_46XXXXXXX/peclet` (small, backed up) / `/scratch/project_46XXXXXXX` (runs) |
| GPU partition | `standard-g` / `small-g` / `dev-g` — MI250X, **8 GCDs per node** (each MI250X = 2 GCDs = 2 "GPUs"), 4 nodes minimum on `standard-g` |
| CPU partition | `standard` / `small` — 2× AMD EPYC 7763, 128 cores/node |
| container runtime | Apptainer/Singularity; site images under `/appl/local/containers/sif-images/` |

Billing is per GPU-hour with **one GCD = one GPU**; `--gpus-per-node=8` books a full node.

## 1. Toolchain (Cray PE)

```bash
module load LUMI/24.03 partition/G          # the software stack; check `module avail LUMI`
module load PrgEnv-cray                      # or PrgEnv-gnu; hipcc is the device compiler either way
module load craype-accel-amd-gfx90a rocm     # MI250X target + ROCm (6.0.x on LUMI/24.03)
module load cray-python                      # Python 3.11 with mpi4py already built against Cray-MPICH
export MPICH_GPU_SUPPORT_ENABLED=1           # GPU-aware Cray-MPICH
export CXX=hipcc
```

Facts to verify on day one: the exact `LUMI/` stack and `rocm` version (`module spider rocm`), that
`cray-python`'s `mpi4py` imports and reports `MPI.Get_library_version()` = Cray MPICH, and that
`hipcc --offload-arch=gfx90a` compiles a trivial Kokkos kernel from the bootstrapped prefix.

## 2. Building from source (`tools/hpc/install_lumi.sh`, untested)

Mirrors `install_snellius.sh`: clone the umbrella at the release tag into its own tree, `python -m venv
--system-site-packages` (to inherit `cray-python`'s mpi4py rather than rebuilding it), bootstrap
Kokkos for `lumi-hip` (`KOKKOS_ARCH=AMD_GFX90A`, `CXX=hipcc`), then `pip wheel` the family in
dependency order with `PECLET_*_MPI=ON` into `wheelhouse/<tag>-lumi-hip/` and install from there.

```bash
cd /project/project_46XXXXXXX/peclet
git clone --branch v<family> --recurse-submodules https://github.com/computational-chemical-engineering/peclet.git suite-v<family>
sbatch -p dev-g --gpus-per-node=1 --ntasks-per-node=1 -t 2:00:00 suite-v<family>/tools/hpc/install_lumi.sh v<family>
```

Differences from Snellius that the script encodes:

- **hipcc, not nvcc**: Kokkos is configured with `-DCMAKE_CXX_COMPILER=hipcc` and
  `-DKokkos_ARCH_AMD_GFX90A=ON`; there is no `Kokkos_ENABLE_*_CONSTEXPR` analogue to remember.
- **MPI is Cray-MPICH**: `mpicc`/`CC` wrappers come from the PE; `-DMPIEXEC_EXECUTABLE=$(which srun)`
  (there is no `mpirun`).
- **No `--gpus-per-task` binding by default**: LUMI's recommended GPU↔CPU affinity is a
  `select_gpu` wrapper that sets `ROCR_VISIBLE_DEVICES=$SLURM_LOCALID` and a CPU mask per GCD; the
  smoke job below carries a minimal version.
- Under `Kokkos_ENABLE_HIP` every module sets `CXX_VISIBILITY_PRESET default` (the fix of §4);
  `-Wl,--no-gc-sections` alone did not help. Virtual wrapper classes in binding TUs must live in named
  namespaces.

## 3. Running

```bash
#SBATCH --partition=standard-g --nodes=1 --gpus-per-node=8 --ntasks-per-node=8 --cpus-per-task=7
module load LUMI/24.03 partition/G rocm cray-python
export MPICH_GPU_SUPPORT_ENABLED=1 OMP_NUM_THREADS=7
cat > select_gpu <<'S'
#!/bin/bash
export ROCR_VISIBLE_DEVICES=$SLURM_LOCALID
exec "$@"
S
chmod +x select_gpu
srun --cpu-bind=mask_cpu:0xfe000000000000,0xfe00000000000000,0xfe0000,0xfe000000,0xfe,0xfe00,0xfe00000000,0xfe0000000000 \
     ./select_gpu python driver.py
```

(The CPU masks are LUMI's documented GCD-to-NUMA mapping; verify against the current LUMI docs.)
`peclet.flow.execution_space` must print `HIP`.

The container route: `containers/hip.def` (ROCm 6.2.4 base, vanilla MPICH) launched through
`containers/lumi-run.sh`, which binds the host Cray-MPICH + libfabric/cxi + GTL over the
container's MPICH ABI (`libmpi.so.12`), and `containers/submit/lumi.slurm`. The image has never
been built successfully (§4); pin the base ROCm ≤ the host driver's ROCm when it is.

## 4. The former blocker: HIP link error in the nanobind modules (FIXED 2026-09-04)

Every HIP container build from 0.3.0 to 0.6.0 died linking `_flow`/`_voro` with

```
ld.lld: error: undefined hidden symbol: vtable for Kokkos::Impl::SharedAllocationRecord<Kokkos::HIPSpace, Kokkos::Impl::ViewValueFunctor<Kokkos::Device<Kokkos::HIP, Kokkos::HIPSpace>, double>>
ld.lld: error: undefined hidden symbol: vtable for std::_Sp_counted_ptr_inplace<peclet::core::halo::GridHaloTopology<3>, ...>
>>> the vtable symbol may be undefined because the class is missing its key function
```

**Update 2026-09-04:** overriding nanobind's visibility preset to `default` on the HIP path (now in
every module's CMakeLists under `if(Kokkos_ENABLE_HIP)`) makes flow, dem and voro link and install in
the container build (CI run 33868865327). The same error class then surfaced for core's `amr`
module and then voro, whose virtual wrapper classes sat in anonymous namespaces (moved to named
ones). Run 33874788583 then built `peclet-hip.sif` with the whole family. The image is published at
the next tag; the on-hardware validation of §5 is what remains.

Original diagnosis: nanobind marks the module target `CXX_VISIBILITY_PRESET hidden`; under hipcc the host-side objects
reference these template vtables as hidden while no object defines them. The same link happens in a
source build, so this blocks the pip route too. Experiments are ordered in
[RELEASE.md §8](RELEASE.md#8-phase-g-lumi-package-untested); the first (override the visibility
preset to `default` on the HIP path) is a two-line CMake change per module and can be tried on a
LUMI login node in seconds — or without LUMI through the `Containers` workflow (`only=hip`,
`push=false`).

## 5. What "validated on LUMI" will mean

1. `install_lumi.sh` completes; `import peclet.flow` reports `HIP`, `has_mpi True`.
2. The smoke job (a port of `tools/hpc/smoke_snellius.slurm`): the periodic-sphere permeability is
   bit-identical at 1 and 8 ranks; dem `step_mpi` conserves the particle count; the 1-rank number
   agrees with the Snellius/CUDA number to the float tolerance.
3. One gallery page (`zick-homsy`) re-rendered against the LUMI venv.
4. `peclet-hip:<family>-gfx90a` pulled from GHCR and the same smoke job run through `lumi-run.sh`.

Until then, release notes say: *LUMI/HIP — recipe provided, untested; no container image published.*
