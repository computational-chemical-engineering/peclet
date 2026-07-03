# `peclet-cuda`: a pip-installable single-GPU CUDA wheel (prototype)

**Status:** validated proof-of-concept (2026-07-03, RTX 5080 / sm_120, CUDA 13.2). A GPU `peclet.flow`
wheel builds with the *stock* packaging, installs into a clean venv, reports `execution_space == "Cuda"`,
and runs a correct GPU solve. This documents the recipe and what remains to ship it on PyPI.

## Why this is possible (correcting "no portable GPU wheel")

`docs/DEPLOYMENT.md` says GPU peclet is not pip-installable. That is true **as currently packaged**, but
the blocker it cites is really about *multi-GPU MPI*, not single-GPU:

| Cited constraint | Reality for a **single-GPU** wheel |
|---|---|
| GPU arch (sm_80 vs sm_120) | Solvable — one CUDA fatbin holds SASS for many arches + PTX for JIT forward-compat (CuPy/PyTorch do this). |
| CUDA runtime version | Solvable — bundle `libcudart` (auditwheel) or depend on the `nvidia-*-cu1x` PyPI wheels. |
| MPI ABI | **N/A** — the Python module is single-rank; it links no MPI. |

The intractable part (MPI ABI) doesn't exist in the path ordinary users want. So a single-GPU CUDA wheel
is a packaging exercise, not a research problem.

## Proven recipe (what was actually run)

Built against the bootstrapped CUDA Kokkos prefix (static Kokkos → embedded in the module):

```bash
export PATH=/usr/local/cuda-13.2/bin:$PATH
export CMAKE_PREFIX_PATH=$PWD/extern/install/nvidia-cuda     # Kokkos 5.1.1, CUDA on, sm_120, static .a
python -m pip wheel ./flow --no-deps -w cuda_wheels
# -> cuda_wheels/peclet_flow-0.2.1-cp313-cp313-linux_x86_64.whl   (1.4 MB; _flow.so = 3.57 MB w/ sm_120 fatbin)
```

Notably the consumer build needed **no manual compiler override** — `find_package(Kokkos)` from the CUDA
prefix transparently routes the module TUs through `nvcc_wrapper`, even though `flow/CMakeLists.txt`
declares `project(... LANGUAGES CXX)` with the default host compiler.

Verification in a clean venv (no suite, no source tree):

```bash
python -m venv gpuvenv && gpuvenv/bin/pip install numpy peclet_flow-*.whl
gpuvenv/bin/python -c "import peclet.flow as f; print(f.execution_space)"   # -> Cuda
```

A 48³ all-fluid body-force solve (30 steps) produced uniform plug flow `<u>=1.5`, **max divergence
2.13e-16**, wall 0.64 s — correct physics, on the GPU.

## Runtime dependencies (the portability lever)

`ldd` on the installed `_flow.so`:

```
libcuda.so.1      # NVIDIA driver — host-provided, NEVER bundled (correct)
libcudart.so.13   # CUDA runtime — the one thing to bundle or depend on
libstdc++/libm/libgcc_s/libc     # standard, manylinux-provided
```

Kokkos is **static** — there is no `libkokkos*.so` dependency. So making the wheel portable is exactly:
handle `libcudart.so.13`, nothing else.

## Implemented (`peclet-flow-cu13`)

The runtime-dependency packaging is done and validated end-to-end (a wheel installs into a clean venv
with **no system CUDA** and runs on the GPU):

1. **CUDA runtime as a dependency (not bundled).** `flow/packaging/pyproject-cuda.toml` publishes the
   CUDA build as **`peclet-flow-cu13`** depending on **`nvidia-cuda-runtime`** (>=13,<14). Note the
   naming: NVIDIA **dropped the `-cuXX` suffix at CUDA 13** — the runtime package is `nvidia-cuda-runtime`
   (13.3.29), which lays `libcudart.so.13` at `site-packages/nvidia/cu13/lib/`; the old
   `nvidia-cuda-runtime-cu13` is a deprecated placeholder. `libcuda.so.1` (driver) stays host-provided.
2. **rpath to the runtime wheel.** `-DPECLET_CUDA_RUNTIME_WHEEL=ON` (CMakeLists) bakes
   `$ORIGIN/../../nvidia/cu13/lib` into `_flow.so` (and one level deeper for `pnm`), so `import
   peclet.flow` finds libcudart in the dependency wheel. Verified: `ldd` resolves libcudart from the
   nvidia wheel, GPU solve correct (div ~1e-16), Kokkos is static (no `libkokkos.so`).
3. **Distinct package name.** `peclet-flow-cu13` installs the same `peclet.flow` import and is mutually
   exclusive with the CPU `peclet-flow` (CuPy's `cupy` vs `cupy-cuda12x` model). CPU `peclet-flow` is
   untouched (the CMake option defaults OFF).
4. **CI publish.** `flow/.github/workflows/release.yml` gains a `cuda-wheel` job: a `manylinux_2_28`
   container installs the CUDA 13 toolkit, builds a Kokkos-CUDA prefix once, builds the wheel per CPython
   against it, `auditwheel repair --exclude libcudart.so.13 --exclude libcuda.so.1` retags to manylinux,
   then re-adds the nvidia rpath (auditwheel resets it). `publish` uploads it alongside `peclet-flow` via
   Trusted Publishing — **register the publisher for `peclet-flow-cu13` on PyPI too**.

## Still open

- **Teardown abort (ship-blocker).** After a solve the GPU module aborts at interpreter exit (`exit
  134`); import-only exits cleanly (0), so it is **live device allocations outliving `Kokkos::finalize`**
  — a `Solver`'s Kokkos Views are still alive when Kokkos finalizes at exit. Compute is correct and
  returns first, but the non-zero exit breaks orchestration. Fix with deterministic teardown: register
  `Kokkos::finalize` via `atexit` and release the solver's device registries before it (the `dem`
  binding already does this — port the pattern to `flow`).
- **Multi-arch SASS (perf).** The CI wheel builds one SASS baseline (`Kokkos_ARCH_TURING75` / `sm_75`) +
  PTX, so it *runs* on Turing..Blackwell by JIT but isn't arch-optimized. For per-arch SASS, validate the
  Kokkos wrinkle: Kokkos historically wants a single `Kokkos_ARCH_*` — confirm Kokkos 5.x tolerates a
  multi-value `CMAKE_CUDA_ARCHITECTURES` (raw nvcc `-gencode` does).
- **`peclet-dem-cu13`.** The same recipe applies to `dem` (RingBed's GPU packing path); `dem` also pulls
  ArborX, so its CUDA build wires ArborX against the same Kokkos-CUDA prefix. Not yet done.
- **First CI run** may need the CUDA-toolkit-in-manylinux install and the `sm_75` baseline adjusted to
  the pinned CUDA's actual arch floor.

## Scope

Single-GPU CUDA only. **AMD/HIP** and **multi-GPU MPI** stay source/container builds — those genuinely
hit the arch × runtime × MPI-ABI wall a portable wheel can't cross.
