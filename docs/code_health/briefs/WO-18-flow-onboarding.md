# WO-18 — flow onboarding: gate config, self-test, baseline (no refactor steps)

Read first: `docs/code_health/RULES.md` (flow keep-out from vof, 11-15), `/home/frankp/Codes/suite/flow/CLAUDE.md`
(read it from the new worktree, not the shared checkout, whose main is stale), then the two working setups as
templates: dem `/home/frankp/Codes/suite/dem-health/.codehealth/{config.toml,playbook.md}` and pnm
`/home/frankp/Codes/suite/pnm-health/.codehealth/{config.toml,playbook.md}`, and `docs/code_health/briefs/WO-9-pnm-onboarding.md`
(the same job for pnm; its trap list holds here too: venv prefix, core pinned via FETCHCONTENT_SOURCE_DIR for the
base worktree, MPIEXEC_PREFLAGS form (flow takes the LIST form `--bind-to;none`, unlike dem/pnm), peclet.halo on
PYTHONPATH from `core/build_health_py`, OMP_NUM_THREADS=1, `same_lines` for the `[peclet] ... headers ->` configure
line, clang-tidy needing `-isystem` for omp.h, CUDA at /usr/local/cuda/bin).
Tool: `~/.venvs/codehealth/bin/codehealth` (pin 93a36d8; `--help` on each subcommand).

## Goal
flow gets the same behaviour gate as dem/pnm, proved by a self-test, plus a baseline scan, ready for refactor rounds.

## Do
1. `cd /home/frankp/Codes/suite/flow && git fetch origin && git worktree add ../flow-health -b code-health origin/main`
   (origin/main = eed2fa4; the shared checkout's local main is stale and diverged, do NOT use it or touch it). Work only
   in suite/flow-health. Never touch any other flow worktree or branch (list: `git worktree list`; vof's are named in RULES).
2. Recon (concise): test options and ctest families (host, MPI, python, python-MPI, collocated/ghost guards such as
   `collocated_stability_guard`), what `tests/regression/state_hash.py` covers (does any case run VoF with the
   sharp viscous interface? list the scenarios) and whether it is byte-identical across two runs at
   OMP_NUM_THREADS=1 (if not, STOP and report), the clang-format/clang-tidy configs and CI jobs, how
   `cmake/PecletDeps.cmake` reports the resolved core path, and cold build/ctest times.
3. Write `.codehealth/config.toml` adapted from dem/pnm: tiers clang_format, build_host, ctest_host, state_hash
   (reference tier; fail_regex for skipped MPI cases if they can skip silently), build_cuda, clang_tidy (campaign).
   frozen: cmake/*, CMakeLists.txt, tests/regression/*, CLAUDE.md, AGENTS.md; forbid: tests/*, packaging/*,
   pyproject.toml, and EVERY keep-out path from RULES.md (src/vof/sharp_viscous.hpp, src/vof/curvature_field.hpp,
   src/flow_ibm*.hpp, doc/vof_sharp_viscous_stress.md, doc/full_viscous_stress.md). The sharp-viscous block of
   src/flow_bindings.cpp cannot be expressed as a path; put it in the playbook keep-out. Scope `src/*`.
   If the per-step gate would take > 60 min, report the tier times and propose a cheaper step tier set (do not drop
   state_hash or ctest_host on your own).
4. Write `.codehealth/playbook.md` adapted from dem's (now with S7/S8 lessons): flow's settled decisions from
   flow/CLAUDE.md and the suite register (ABC approximate projection, never Rhie–Chow; pressure/forces inside the
   implicit predictor; device-first; no env var changes results); drop dem-only recipes; ADD a keep-out section
   quoting RULES.md's flow lines, including "refactors adjacent to the keep-out (MAC stress elements, VoF band
   worklists) must be bitwise on state_hash AND a sharp VoF run".
5. If PecletDeps needs the symmetric `[peclet] <repo> headers -> <path>` line (as dem 246837a / pnm 49df044), make
   it its OWN commit, verified by state_hash identical before/after.
6. Measure each tier once (cold). Run the self-test with a mutation that MUST be caught by state_hash (a numerics
   constant in a projection or advection kernel outside the keep-out; report file:line and before→after). Then a
   smoke gate on a comment-only change (throwaway branch, deleted after). Both must PASS.
7. Commit config + playbook (named paths). That commit is flow's campaign base CB. Then
   `codehealth scan --json <scratchpad>/flow-scan.json` and `codehealth hotspots` (top 10 by debt, brain list).

## Rules
Never push. No `src/` edits other than step 5 (in cmake/). Long runs in the background with one completion wait;
logs to files; read only by grep/tail. GPU jobs only under `flock ~/Codes/bubble_column_perf/gpu_diag/mgd/heavy.lock`.
Bound OpenMP (`OMP_NUM_THREADS=1` for state_hash, ≤ 8 for batteries, `OMP_PROC_BIND=false`). Stop and report (do
not decide) when state_hash is not deterministic at one thread, when a tier cannot run without editing tests/, or
when the self-test mutation is not caught. At ~250k context: commit what passed, write a ≤ 40-line handoff to
`<scratchpad>/flow/HANDOFF.md`, stop. Scratchpad:
`/tmp/claude-1003/-home-frankp-Codes-suite/e3266d37-f20d-42f9-a9e5-a2c74cad3279/scratchpad/flow/`.

## Report (≤ 30 lines)
CB sha; tier table (name, kind, cold time, pass criterion); state_hash scenarios (and whether any exercises sharp
VoF); self-test (mutation file:line, caught by which tier); smoke gate line; baseline (files, NLOC, debt, brain,
health) + top-10 functions (debt, CCN, NLOC, file:line) with a marker on any in or adjacent to the keep-out.
Commit attribution lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Acof2w3UKREYgkhpAVtQ7
