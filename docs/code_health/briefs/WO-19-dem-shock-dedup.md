# WO-19 — dem S9: keep the shock-propagation path, cover it, then dedup it out of both velocity solvers

Read first: `docs/code_health/RULES.md`, `dem-health/CLAUDE.md` (settled decisions), `dem-health/.codehealth/playbook.md`
(S7/S8 recipes and anti-patterns), `docs/code_health/briefs/WO-17-dem-s8.md` (the gate set and scripts you reuse),
DECISIONS_LOG entries of 2026-11-15 on the shock block. Suite register: `docs/DECISIONS.md:441` ("grounded rise-gated
inelastic shock"). Tool: `~/.venvs/codehealth/bin/codehealth` (pin 93a36d8).

## Why (user, Decision Desk card dem-shock-block, signed 2026-11-15, VERIFIED)
"I am hesitant to delete it. Maybe it is not used now, but it actually has a function for specific cases not used.
Therefore I do not want to remove it. I also do not want to change the physics. Changing numeric to roundoff error
would be fine. Can you keep the functionality, but refactor the code such that the code health does improve?"
So: the shock path STAYS and stays callable with the same semantics. No deletion, no physics change.

## Current state (dem main 2ed8411; scan 11-15)
- The same shock block (persistent/posPred/gHat/grounded; up/thr/riseThr gate; suppress the lower grounded,
  non-rising side: w_n = 0, apply = false, restitution = 0) is written TWICE:
  `src/solver_velocity.hpp:191-210` in `solveVelocity` (line 76, CCN 37, NLOC 141, 22 params, debt 51.1, brain) and
  `:1914-1928` in `solveVelocityColoredGS` (line 1822, CCN 31, NLOC 131, 8 params, debt 30.1, brain; inputs via
  `struct ShockPropagation` at :1800).
- Both callers pass it EMPTY (`src/solve_driver.hpp:950` passes `{}`s; the GS caller passes an empty ShockPropagation),
  so no scenario reaches it and state_hash says nothing about it. The resting-threshold branch is also uncovered.

## Do
0. In `suite/dem-health` (yours): `git fetch origin && git switch -c shock-dedup origin/main` (2ed8411). Own build dirs.
1. **Coverage first, its own commit** (tests/ is outside the refactor gate's forbid only for this step; it changes no
   `src/`): a kokkos unit test in `tests/kokkos/test_solver_velocity.cpp` (or a new file registered in that
   CMakeLists) that calls BOTH `solveVelocity` and `solveVelocityColoredGS` with non-empty shock inputs on small
   hand-built manifolds and checks the physics, not just a hash: (a) A above grounded, non-rising B → B's velocity
   unchanged, A corrected, no bounce (e = 0); (b) mirror case (B above A); (c) rising support (−v·ĝ > 4·vRest) →
   symmetric momentum-conserving impulse; (d) ungrounded support → symmetric; (e) near-horizontal pair (|up| ≤ 0.3|dx|)
   → symmetric; (f) persistent = 0 → symmetric; (g) both solvers agree on these cases. Also print a bitwise hash of the
   outputs so base and head can be compared. Run it on host and CUDA. If any expectation FAILS on main, STOP and report:
   that is a physics finding for Frank, not something to fix here.
2. **Refactor** (gate base = the step-1 commit), recipe `dedup-device-predicate` + `launch-params-struct`:
   - one `KOKKOS_INLINE_FUNCTION` member of `ShockPropagation` (or a free helper beside it) returning WHICH side is
     static (a small enum/int: none / A / B) from (idx, idA, idB, realA, realB, vA, vB, restVelThreshold). RETURN the
     value; no success-flag out-params (playbook: raised regs 96→128). The caller keeps the three assignments.
   - `solveVelocity` takes `ShockPropagation shock = {}` in place of its four loose parameters (22 → 19 params);
     update its one caller (`solve_driver.hpp:950`) and any test callers. Defaults must reproduce today's exactly.
   - Same launches, same order, same atomics, same capture-by-value; `usePersist` stays the outer guard.
3. Gates, numbers written before the run:
   - G-host step gate `codehealth gate --mode refactor --base <step-1 sha> --ref-base 3fd9b93 --require-gain`: 13/13,
     state_hash bitwise.
   - the step-1 test's hash: bitwise base vs head on host `-ffp-contract=off` AND on `-march=native -ffp-contract=fast`
     (G-fma). This is the proof for the moved code, since state_hash cannot see it.
   - G-sass (WO-17 scripts): S0/S1 on every kernel; regs ≤ base.
   - G-cuda: CUDA ctest all pass + envelope A-vs-B ≤ 1.5 × max(within) per scenario; plus the step-1 test on CUDA.
   - G-time: ABBA bench_step.py, 5 pairs, median ≥ 0.95.
   - **Round-off allowance (the user's)**: if ONLY the step-1 test's hash differs on the fma build or on CUDA, the
     step may still pass when every case's outputs agree to ≤ 4 ulp (float) and all (a)–(g) expectations hold. Log it
     as accepted-roundoff with the max |Δ| in ulp. Any state_hash difference, or any difference on the
     `-ffp-contract=off` host build, is a FAIL (the dead path cannot move live results).
   - Campaign gate `--cadence campaign --base 3fd9b93` 13/13 (clang-tidy ratchet) at the end.
4. Log steps to the run log as dem-s9 (`codehealth log`), recipe ids as above.

## Rules
Never push. Never touch dem/main checkout, dem-cudaref, dem-cudahead, or anything outside dem-health. Stage named paths.
GPU jobs only under `flock ~/Codes/bubble_column_perf/gpu_diag/mgd/heavy.lock`. OMP_NUM_THREADS=1 for state_hash, ≤ 8
for batteries, OMP_PROC_BIND=false; MPIEXEC_PREFLAGS="--bind-to none" (space form, dem); PYTHONPATH with core's
peclet.halo build. Long runs in background, one wait, logs to files, read by grep/tail. Stop and report when a step-1
physics expectation fails on main, when G-sass shows a register increase you cannot remove, or when a gate other than
the round-off case fails twice. At ~250k context: commit what passed, ≤ 40-line handoff to
`/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/s9/HANDOFF.md`, stop.

## Report (≤ 30 lines)
Commits (sha, one line each); step-1 test cases and that each passes on host + CUDA; gate table with numbers;
debt/CCN/params before → after for both functions; brain count; dem total debt (was 1475.6); any accepted-roundoff.
Commit attribution lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
