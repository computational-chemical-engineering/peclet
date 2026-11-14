# Code-health campaign — standing rules

Every worker reads this before acting. Position: [STATE.md](STATE.md). Decisions: [DECISIONS_LOG.md](DECISIONS_LOG.md).
Briefs: [briefs/](briefs/). Tool: cce-code-health (`~/.venvs/codehealth`, pin in STATE.md), peer session `code_health` (SMM-TR09).

## The user's constraints (binding)
- Quality is the prime objective. Never change numerics while restructuring: a refactor is **proved
  bit-identical** (each repo's `state_hash` byte gate, host/OpenMP build, `OMP_NUM_THREADS=1`).
- `docs/DECISIONS.md` is binding; a refactor never swaps in a rejected alternative. Each submodule's
  `CLAUDE.md` lists its own settled decisions — read them.
- Public Python names follow `docs/NAMING.md`; refactors keep the Python API unchanged.
- Identifiers name what a thing is, never where it runs (DECISIONS: no `Device*`/`*Kokkos`).
- No environment variable may change a result.

## Git
- Work in a sibling worktree `suite/<repo>-health[-<topic>]`, branch `code-health[-<topic>]`; never in a shared checkout.
- Stage named paths only (never `git add -A`/`.`/`commit -a`).
- Push to main only after the user has OK'd that repo's adoption (see STATE.md); umbrella last.
- Never rewrite or force-push; keep paper-pinned commits reachable (flow f9eb1e0, pnm 0ccf947, pnm ea49b3a).

## Keep-out (re-check with the owner before touching; owners announce changes via hub)
- flow `src/vof/`, staggered viscous/VoF files, `VofCurvature`, AUTO setter: frozen until vof lands `sharpvisc-land`.
- voro `include/peclet/voro/lagrangian/*`: frozen (M7); voro goes last.
- voro: WAIT (session voronoi, 11-14) until the M7 m7-* branches land (date depends on the user). They modify
  ~30 files (convex_cell, tess_grid, repair, reeval_tessellation, subset_gather, ot_optimizer, params, energy/*,
  voro_bindings*, voro_optimizers.cpp, voro_tessellation.cpp, CMake, CLAUDE.md) and add ~25 lagrangian/ headers.
  voronoi_fable's ale-* branches may add more.
- pnm: open (A7 withdrew its freeze); send A7 the list of commits landed on pnm main; never touch `junction-law` / `suite/pnm-junction-law`.
  A7 (session `pnm`, 11-14): no pnm main work planned; junction-law (merge-base 0ccf947) rebases onto our batches,
  so send the commit list per batch. Heavy-overlap files (rebase cost): src/pnm_bindings.cpp, src/pore_kernels.hpp,
  src/pore_extraction.hpp, src/pore_extraction_mpi.hpp, tests/kokkos_mpi/test_pnm_flow_mpi.cpp. In pore_kernels.hpp
  never rename/move the flow-mapping stage kernels, and never touch the extract_network_flow(_mpi) binding block,
  unless that is the commit's point; formatting-only passes over those files are fine as SEPARATE commits.
  A7 11-14: FREE now: kernels::steepest; extract_pore_network_mpi (refactor OK, keep its parameter list and the
  segmentation-dispatch point recognizable). WAIT for junction-law on main (A7 pings): extract_network_flow_mpi,
  extract_network_flow_k, kernels::throatFlux.
- Umbrella `CHANGELOG`, `docs/NAMING.md`, `docs/DECISIONS.md`, `docs/decisions/`: vof is mid-commit — tell vof first.
- Other sessions' worktrees (`flow-svl-*`, `flow-sharpvisc-*`, `core-sharpvisc`, `voro-*`, `ale-*`).

## Running jobs on TRS2
- Bound OpenMP: `OMP_NUM_THREADS=1 OMP_PROC_BIND=false` for test batteries (8/rank made dem's take ~10 h).
- dem MPI: `-DMPIEXEC_PREFLAGS="--bind-to none"` (space; dem uses `separate_arguments`). core uses the `;` list form.
- nvcc: `/usr/local/cuda/bin` (13.5). GPU jobs take vof's flock `~/Codes/bubble_column_perf/gpu_diag/mgd/heavy.lock`.
- Run long things blind (one summary line, log to file); read logs by grep/tail only.

## Evidence standard
- A step counts only when its gate passes: `PECLET_SUITE=/home/frankp/Codes/suite codehealth gate` in the repo worktree.
- Quote real numbers from real runs. A changed hash is a bug in the change until shown otherwise.
- Skips are failures (exit 77, `***Skipped`, `Not Run`, `mpi cases skipped`).
