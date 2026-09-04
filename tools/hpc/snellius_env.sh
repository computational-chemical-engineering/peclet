#!/bin/bash
# GPU-aware Snellius toolchain, sourced by the install / smoke / run scripts so they all agree.
# Identical to peclet-examples/examples/wall-bounded-turbulence/snellius_env.sh (validated
# 2026-07..09); keep the two in sync. See ../../docs/SNELLIUS.md.
#
# 2024a stack (GCCcore-13.3.0): satisfies BOTH Kokkos 5.1.1 (CUDA >= 12.2) AND GPU-aware MPI
# (UCX-CUDA exists for this CUDA). Fails fast with a module listing if a name has drifted.
_die() { echo "FATAL(snellius_env): $*" >&2; module -r avail "${2:-}" 2>&1 | tail -20 >&2; return 1 2>/dev/null || exit 1; }

module purge
module load 2024                           || _die "'2024' module tree not loadable" '^2024'
module load gompi/2024a                    || _die "gompi/2024a not loadable" '^gompi'
module load CUDA/12.6.0                     || _die "CUDA/12.6.0 not loadable" '^CUDA/12'
module load UCX-CUDA/1.16.0-GCCcore-13.3.0-CUDA-12.6.0 || _die "UCX-CUDA/1.16.0 not loadable" '^UCX-CUDA'
module load Python/3.12.3-GCCcore-13.3.0 2>/dev/null || \
  module load "$(module -r -t avail '^Python/3.*GCCcore-13.3.0$' 2>&1 | grep -E '^Python/3' | sort -V | tail -1)" || \
  _die "no Python 3.x for GCCcore-13.3.0" '^Python/3'

export OMPI_MCA_pml=ucx UCX_MEMTYPE_CACHE=n     # GPU-aware MPI
echo "[snellius_env] $(module -t list 2>&1 | grep -iE 'gompi|^GCC|OpenMPI|^CUDA/|UCX-CUDA|^Python/' | tr '\n' ' ')"
