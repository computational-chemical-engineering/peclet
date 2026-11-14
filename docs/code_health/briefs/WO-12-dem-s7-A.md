# WO-12 — dem S7 A-series: execute work orders A1–A4 of the S7 design (solveOne)

You execute a SETTLED design. You decide nothing the design leaves open: stop and report instead.

## Read first, in this order
1. Standing rules: `docs/code_health/RULES.md`, in the umbrella docs worktree
   `/home/frankp/Codes/suite/.claude/worktrees/suite-code-health`.
2. The design: `docs/code_health/designs/dem-s7-design.md` in the same worktree. The parts that
   bind you are §5 (A design; §5.4 codegen rules are binding), §7 (rows A1–A4 and the acceptance
   paragraph), §8 (gates) and the Appendix (`sass_gate.py`). Read §2–§4 once, for the reasons.

## Where
- Code: dem worktree `/home/frankp/Codes/suite/dem-health`, branch `code-health`, HEAD = the
  tidy-cleanup commit 17d83ec (or later, if the session says so). Commit there; never push.
- Probe/base builds: create a detached worktree for the base side
  (`git -C /home/frankp/Codes/suite/dem-health worktree add /home/frankp/Codes/suite/dem-s7base <prev> --detach`)
  with its own build dirs, reused across WOs (checkout `<prev>` per WO). Remove it at the end.
- Scratch scripts (`sass_gate.py`, `s7_branch_hash.py`, `bench_step_s7.py`) go to
  `/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/s7/`.
- Existing session scripts in the scratchpad (read their headers before use):
  - `cuda_ref.sh <tag> [ctest]` — CUDA build plus state_hash ×3, run in the worktree named by `W=`;
  - `cuda_env.py A1 A2 A3 -- B1 B2 B3` — the envelope rule;
  - `cuda_bench.sh <base_build> <head_build> [pairs]` — the ABBA bench.

## Machine rules
- Every GPU job (CUDA build tests, ctest, state_hash, bench) runs under
  `flock ~/Codes/bubble_column_perf/gpu_diag/mgd/heavy.lock`.
- CUDA lives at /usr/local/cuda/bin (13.5). The suite venv is /home/frankp/Codes/suite/.venv.
- Export `PECLET_SUITE=/home/frankp/Codes/suite`.
- Run every long job blind: `run_in_background`, one summary line, the log to a file, read only on
  failure (grep/tail).

## Per WO (A1, A2, A3, A4, in that order)
1. Implement exactly the WO's row of §7 per §5.2/§5.3, under the §5.4 rules. Use clang-format
   (suite venv) on the touched files.
2. Gates (§8), all against `<prev>` = the previous WO's commit:
   - G-host: `codehealth gate --mode refactor --base <prev> --ref-base 3fd9b93 --require-gain --json <f>`
     (`~/.venvs/codehealth/bin/codehealth`, tool pin 569c85b).
   - G-sass, G-fma, G-branch (A3 with the Poisson scenarios, A4 with β ≠ 0).
   - G-cuda and G-time. Before the first use of `bench_step_s7.py`, run one A/A pass as §8 says.
3. On PASS: commit (one commit per WO; the message states the moved ranges and the gate numbers),
   then log it: `codehealth log --gate-json <f> --campaign dem-s7 --target "src/solver_velocity.hpp::PGSManifoldSweep::solveOne" --recipe device-split-solveone --hypothesis "<one line: S0/S1 counts, cuda/time numbers>"`.
4. On any FAIL: stop. Do not try a variant the design does not name. The single exception is the
   design's own C6 fallback in A2, allowed once. Report the failing gate line and your diagnosis.

## Stop conditions (report and stop; never improvise)
- Any gate FAIL beyond the C6 fallback, or any SASS FAIL.
- A G-time MISS (< 0.90 after a rerun).
- A fact in the design proves false.
- Your context passes ~250k tokens: commit what has passed, write a ≤ 40-line handoff to
  `scratchpad/s7/HANDOFF-A.md`, and stop.

## Report (≤ 30 lines)
Per WO: commit sha, debt before → after (dem and solveOne), S0/S1 counts, G-cuda max ratio,
G-time median (both benches). Then anything that needs a decision.
