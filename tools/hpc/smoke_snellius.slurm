#!/bin/bash
# Release smoke test on Snellius (docs/RELEASE.md §7) against the venv that install_snellius.sh
# produced. Uses only drivers the suite already validates elsewhere:
#   * flow/scripts/verify_mpi_spheres_sdflow.py — distributed periodic sphere-packing permeability,
#     run at np=1 and np=N; the printed k must agree to all digits (bit-exact distributed solve).
#   * benchmarks/profile_mpi_flow.py — the weak-scaling comm-overhead tile (has_mpi + mpi_block).
#   * import checks for dem / voro / pnm / core.mpi / coupling (backend + MPI surface present).
#
#   sbatch --nodes=1 --gpus-per-node=4 --ntasks-per-node=4 tools/hpc/smoke_snellius.slurm v0.7.0 h100
#   sbatch -p genoa --gpus=0 --ntasks-per-node=4 -c 4      tools/hpc/smoke_snellius.slurm v0.7.0 cpu
# Record the job id + the two k lines in docs/SNELLIUS.md "Validated releases".
#SBATCH --job-name=peclet-smoke
#SBATCH --partition=gpu_h100
#SBATCH --time=00:20:00
#SBATCH --output=peclet-smoke-%j.out
#SBATCH --account=tes24005
set -euo pipefail
TAG="${1:?usage: smoke_snellius.slurm <tag> <h100|a100|cpu>}"; TARGET="${2:-h100}"
PROJ="${PROJ:-/projects/0/prjs1022/peclet}"; SUITE="$PROJ/suite-$TAG"
source "$SUITE/tools/hpc/snellius_env.sh"
source "$SUITE/.venv/bin/activate"
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-4} OMP_PROC_BIND=false
N=${SLURM_NTASKS:-4}
if [ "$TARGET" = cpu ]; then GPUOPT=""; else GPUOPT="--gpus-per-task=1 --gpu-bind=per_task:1"; fi
PY="$SUITE/.venv/bin/python"

echo "== 1. imports / backends"
srun --mpi=pmix --ntasks=1 $GPUOPT "$PY" - <<'PY'
import peclet.flow as f, peclet.dem as d, peclet.voro as v, peclet.pnm as p, peclet.morton, peclet.core.mpi
import importlib; c = importlib.util.find_spec("peclet.coupling") is not None
print(f"flow {f.execution_space} has_mpi={f.has_mpi} | dem {d.execution_space} step_mpi={hasattr(d.Simulation,'step_mpi')} "
      f"| voro {v.execution_space} VoronoiHalo={hasattr(v,'VoronoiHalo')} | pnm {p.execution_space} mpi={hasattr(p,'extract_pore_network_mpi')} | coupling={c}")
assert f.has_mpi and hasattr(d.Simulation, "step_mpi") and hasattr(v, "VoronoiHalo")
PY

echo "== 2. flow distributed solve: np=1 vs np=$N must print the same k"
cd "$SUITE/flow"
srun --mpi=pmix --ntasks=1  $GPUOPT "$PY" scripts/verify_mpi_spheres_sdflow.py | tee "$SLURM_SUBMIT_DIR/smoke-$SLURM_JOB_ID-np1.txt"
srun --mpi=pmix --ntasks=$N $GPUOPT "$PY" scripts/verify_mpi_spheres_sdflow.py | tee "$SLURM_SUBMIT_DIR/smoke-$SLURM_JOB_ID-np$N.txt"

echo "== 3. weak-scaling tile, $N ranks (timing only; per-step ms and pressure iters)"
cd "$SUITE"
srun --mpi=pmix --ntasks=$N $GPUOPT "$PY" benchmarks/profile_mpi_flow.py --L 48 --steps 20 --warmup 5 --csv "$SLURM_SUBMIT_DIR/smoke-$SLURM_JOB_ID.csv"
echo "smoke done — compare the k lines of np1 vs np$N (must be identical); file the numbers in docs/SNELLIUS.md"
