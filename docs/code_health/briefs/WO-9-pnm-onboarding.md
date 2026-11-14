# WO-9 — pnm onboarding: gate config, self-test, baseline (no refactor steps)

Read first: `docs/code_health/RULES.md` (incl. the pnm keep-out from A7), `docs/code_health/STATE.md` (dem gate table
and what it took), `pnm/CLAUDE.md`, then dem's working setup as the template:
`/home/frankp/Codes/suite/dem-health/.codehealth/config.toml` and `.codehealth/playbook.md`, and
`docs/code_health/DECISIONS_LOG.md` entries of 2026-11-13 (the traps dem hit: venv prefix, core pinned for the base
worktree via FETCHCONTENT_SOURCE_DIR, MPIEXEC_PREFLAGS "--bind-to none" with a space vs list form, peclet.halo on
PYTHONPATH from `core/build_health_py`, OMP_NUM_THREADS=1, `same_lines` for the `[peclet] ... headers ->` configure
line, clang-tidy needing `-isystem` for omp.h, CUDA at /usr/local/cuda/bin).
Tool: `~/.venvs/codehealth/bin/codehealth` (pin 00b1849; `--help` on each subcommand).

## Goal
pnm gets the same behaviour gate dem has, proved by a self-test, plus a baseline scan — ready for refactor rounds.

## Do
1. `cd /home/frankp/Codes/suite/pnm && git worktree add ../pnm-health -b code-health main` (main = 0ccf947). Work only
   there. Never touch pnm main's checkout, `junction-law`, `suite/pnm-junction-law`, `suite/pnm-netflow-momentum`.
2. Recon (concise): how tests are enabled (options), which ctests exist (host, MPI, python, python-MPI), what
   `tests/regression/state_hash.py` covers and whether it is deterministic at OMP_NUM_THREADS=1 (run it twice; must
   be byte-identical — if not, STOP and report), what clang-format/clang-tidy configs and CI jobs pnm has, how
   `cmake/PecletDeps.cmake` resolves core (does it print the resolved path on both branches like dem 246837a?).
3. Write `.codehealth/config.toml` by adapting dem's: same tier set (clang_format, build_host, ctest_host,
   state_hash reference tier with fail_regex for skipped MPI cases if applicable, build_cuda, clang_tidy campaign),
   same env, frozen/forbid adapted to pnm's layout (frozen: cmake/*, CMakeLists.txt, tests/regression/*, CLAUDE.md;
   forbid: tests/*, packaging/*, pyproject.toml), scope `src/*`. Write `.codehealth/playbook.md` by adapting dem's
   (pnm's settled decisions from pnm/CLAUDE.md; drop dem-only recipes; ADD a keep-out section quoting RULES.md's
   A7 lines: no renames/moves of the flow-mapping stage kernels in pore_kernels.hpp nor of the
   extract_network_flow(_mpi) binding block).
4. If PecletDeps needs the symmetric `[peclet] <repo> headers -> <path>` line (as dem 246837a), make that its OWN
   commit, verified by state_hash identical before/after. Report it; it touches a file everyone touches.
5. Measure each tier once (cold) and run the self-test with a mutation that MUST be caught by state_hash (pick a
   numerics constant in a pore-extraction kernel; report file:line and the before→after value), e.g.
   `codehealth gate --self-test --mutate <file:line> ...` per `--help`. Then a smoke gate on a comment-only change
   (on a throwaway branch, deleted afterwards). Both must PASS (self-test = mutation caught, baseline clean).
6. Commit config and playbook (named paths). That commit is pnm's campaign base CB. Then `codehealth scan --json
   /tmp/claude-1003/pnm-scan.json` and `codehealth hotspots` (top 10 by debt, brain list).

## Rules
Never push. No `src/` edits other than step 4 (and that one is in cmake/). Long runs in the background with one
completion wait; logs to files; read only by grep/tail. Stop and report (do not decide) when state_hash is not
deterministic at one thread, when a tier cannot be made to run without editing tests/, or when the self-test
mutation is not caught.

## Report (≤ 30 lines)
CB sha; tier table (name, kind, cold time, pass criterion); self-test result (mutation file:line, caught by which
tier); smoke gate line; baseline (files, NLOC, debt, brain, health) + top-10 functions (debt, CCN, NLOC, file:line)
with a marker on any that sit in A7's heavy-overlap files; anything odd the tool did.
Attribution lines for commits:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
