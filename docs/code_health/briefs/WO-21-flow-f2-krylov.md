# WO-21 — flow F2: CutcellMG Krylov drivers and decomposition in src/mac_cutcell_mg.hpp (refactor class, bitwise)

Read first: `docs/code_health/RULES.md` (flow keep-out), `flow-health/CLAUDE.md` (settled decisions),
`flow-health/.codehealth/{config.toml,playbook.md}` (recipes, anti-patterns, and the section "Extra gates per file"),
`docs/code_health/briefs/WO-18-flow-onboarding.md` (how the gate was built). For the dem precedent on device code
(G-sass, G-fma, coverage), read the "Anti-patterns" in `dem-health/.codehealth/playbook.md`.
Tool: `~/.venvs/codehealth/bin/codehealth`, pin 719092b; `--help` on each subcommand.

## Goal
F1 (WO-20, branch `f1`, 42bdc15..73a6f63; read its log entry in DECISIONS_LOG and the F1 evidence paragraph in the
flow playbook) took buildAmg, initMpi and solvePCGResident down and left a shared FP32-attempt prologue/failure path.
F2 targets in the same file (scan at 73a6f63): `solveFCGAttempt` :3434 debt 47.6, CCN 39; `solveBiCGStab` :3591 45.5,
CCN 32; `solvePCGAttempt` :2528 40.5, CCN 33; `decomposition` :1589 40.0, CCN 42. The Krylov drivers share structure
with what F1 extracted from solvePCGResident: reuse those members before writing new ones. Also the duplicate of
`can`/`evenOn` near line 7820 (F1 left it). flow now: debt 5657.1, brain 46. F1 is not landed yet (Desk card
flow-f1-land); F2 stacks on it.

## Do
0. Worktree `suite/flow-health` (yours). Branch `f2` off `f1` (73a6f63). Step gates use `--base <prev>`; the round
   compares against 73a6f63. Core comes from the detached `suite/core-health-flowpin` (7cec32a) through `$FLOW_CORE`
   as in the config; never use or touch the shared `suite/core`.
1. Read the three functions and pick seams by the recipes. Host-side setup (initMpi, buildAmg) first, where seams are
   cheap. `solvePCGResident` is the solve hot path: change it only with seams that keep the launch, fence and
   reduction order, and only if a step there passes G-sass.
2. Per step: `codehealth gate --mode refactor --base <prev> --require-gain`, all checks PASS, state_hash and sharp_vof
   bitwise. Log every try with `codehealth log` (run id flow-f2, recipe id).
3. Per round, before you report, compare the round's head with CB:
   - **G-cuda (vof's rule)**: build CUDA for both sides under the GPU flock. state_hash and the sharp-VoF run on the
     GPU must be BITWISE base == head. First run base twice on the GPU; if base differs from itself, STOP and report.
     If head != base, bisect to the step and drop it.
   - **MPI MG**: `mg_stencil_halo_np*`, `mg_fp32_vcycle_mpi_np2`, `test_telescope_mpi`, `cg_guard_mpi` and
     `mg_vcycle_symmetry_mpi` must pass at np 1/2/4 (they are registered in tests/kokkos_mpi; report each np you ran,
     run at OMP_NUM_THREADS=2).
   - **G-sass** if any device code changed (adapt the dem script from the dem playbook; S0/S1, regs ≤ base).
   - **G-time** if `solvePCGResident` or any kernel changed: ABBA 5 pairs on one GPU MG case (e.g.
     `scripts/bench_velocity_mg_256.py` or a pressure-MG case you justify). Median ≥ 0.95.
   - campaign gate `--cadence campaign --base b148fe1`: all PASS (ctest_long, build_cuda, clang_tidy ratchet).

## Rules
Never push. Never touch src/ outside `src/mac_cutcell_mg.hpp` unless a moved helper must go next to its caller in the
same file. Keep-out: if a seam would touch a keep-out file, or the sharp-viscous block in flow_bindings.cpp, drop it.
No numerics change. Same launches, fences, MPI calls and reductions in the same order. No public-surface change.
GPU jobs only under `flock ~/Codes/bubble_column_perf/gpu_diag/mgd/heavy.lock`. OMP_NUM_THREADS=1 for reference tiers
(the config does this), ≤ 8 for batteries, OMP_PROC_BIND=false; MPIEXEC_PREFLAGS list form `--bind-to;none`. Long
runs in the background with one wait, logs to files, read by grep/tail. Reuse the F1 scripts in
`/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/f1/` (branch_probe.py
after every step, cuda_ref.sh, mpimg.sh, sass_gate.py, bench_abba.sh); copy them to scratchpad/f2/. Do not edit
the F1 commits. Stop and report when GPU base is not
deterministic, when a gate fails twice on one step, or when a seam needs a decision the recipes do not cover.
At ~250k context: commit what passed, write a ≤ 40-line handoff to
`/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/f2/HANDOFF.md`, stop.

## Report (≤ 30 lines)
Commits (sha, recipe, debt before → after per function); a gate table with numbers (step gates, G-cuda bitwise, MPI
MG per np, G-sass, G-time, campaign); flow debt and brain count before → after; any step dropped and why.
Commit attribution lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
