# WO-22 — flow F3: gpDebugReport + CutcellMG rank-query leftovers (refactor class, bitwise; small round)

Read first: `docs/code_health/RULES.md` (flow keep-out), `flow-health/CLAUDE.md` (settled decisions),
`flow-health/.codehealth/{config.toml,playbook.md}` (recipes, anti-patterns, and the section "Extra gates per file"),
`docs/code_health/briefs/WO-18-flow-onboarding.md` (how the gate was built). For the dem precedent on device code
(G-sass, G-fma, coverage), read the "Anti-patterns" in `dem-health/.codehealth/playbook.md`.
Tool: `~/.venvs/codehealth/bin/codehealth`, pin 719092b; `--help` on each subcommand.

## Goal
F1 and F2 are LANDED (flow main ed61f38; flow debt 5606.2, brain 43). F3 is a small round, kept small on purpose
(token budget):
(1) `src/ghost_projection_debug.hpp` `gpDebugReport` :60, debt 49.0, CCN 46, NLOC 170 (it only prints, under
    PECLET_FLOW_GP_DEBUG). vof's EXTRA GATE: the debug report text byte-identical base vs head on one collocated
    'ghost' case with PECLET_FLOW_GP_DEBUG set (pick a short case; state the command), plus state_hash, which already
    includes the collocated ghost entry.
(2) `src/mac_cutcell_mg.hpp`: the three-line rank-query block in solveWithRestart, solveChebyshev and guessTraceExit
    → the existing `commRank` member (F2 left it).
Do NOT touch src/cut_cell_ibm.hpp (vof keep-out, 11-16) or src/scalar_krylov.hpp (no owner yet).

## Do
0. Worktree `suite/flow-health` (yours). `git fetch origin && git switch -c f3 origin/main` (ed61f38, which now carries
   .codehealth/). Step gates use `--base <prev>`; the round compares against ed61f38. Core comes from the detached `suite/core-health-flowpin` (7cec32a) through `$FLOW_CORE`
   as in the config; never use or touch the shared `suite/core`.
1. Read the three functions and pick seams by the recipes. Host-side setup (initMpi, buildAmg) first, where seams are
   cheap. `solvePCGResident` is the solve hot path: change it only with seams that keep the launch, fence and
   reduction order, and only if a step there passes G-sass.
2. Per step: `codehealth gate --mode refactor --base <prev> --require-gain`, all checks PASS, state_hash and sharp_vof
   bitwise. Log every try with `codehealth log` (run id flow-f3, recipe id).
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
   - campaign gate `--cadence campaign --base ed61f38`: all PASS (ctest_long, build_cuda, clang_tidy ratchet).

## Rules
Never push. Never touch src/ outside `src/mac_cutcell_mg.hpp` and `src/ghost_projection_debug.hpp`. Keep-out: if a seam would touch a keep-out file, or the sharp-viscous block in flow_bindings.cpp, drop it.
No numerics change. Same launches, fences, MPI calls and reductions in the same order. No public-surface change.
GPU jobs only under `flock ~/Codes/bubble_column_perf/gpu_diag/mgd/heavy.lock`. OMP_NUM_THREADS=1 for reference tiers
(the config does this), ≤ 8 for batteries, OMP_PROC_BIND=false; MPIEXEC_PREFLAGS list form `--bind-to;none`. Long
runs in the background with one wait, logs to files, read by grep/tail. Reuse the F1/F2 scripts in
`/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/f1/` and `.../f2/` (krylov_probe.py) (branch_probe.py
after every step, cuda_ref.sh, mpimg.sh, sass_gate.py, bench_abba.sh); copy them to scratchpad/f3/. Stop and report when GPU base is not
deterministic, when a gate fails twice on one step, or when a seam needs a decision the recipes do not cover.
At ~250k context: commit what passed, write a ≤ 40-line handoff to
`/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/f3/HANDOFF.md`, stop.

## Report (≤ 30 lines)
Commits (sha, recipe, debt before → after per function); a gate table with numbers (step gates, G-cuda bitwise, MPI
MG per np, G-sass, G-time, campaign); flow debt and brain count before → after; any step dropped and why.
Commit attribution lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7

Budget: aim to finish under ~150k context; read functions by line range (grep -n / sed -n), never whole files.
At the end commit the run log `.codehealth/runs/flow-f3.jsonl` (paths cut to basenames) + one playbook evidence line.
