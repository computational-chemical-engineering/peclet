# Code-health campaign — STATE (rewritten in place; rules in RULES.md)

**Objective.** Lower code debt across the peclet suite with behaviour proved unchanged, using
cce-code-health (debt metrics + base-vs-head gate). Peclet side: this campaign; tool side: session `code_health`.

**Tool pin.** cce-code-health 9b8f138 in `~/.venvs/codehealth` (cpp@0 + C++ self-test).

## Where we are (2026-11-13)
- Repo 1 = **dem** (worktree `suite/dem-health`, branch `code-health`, off main e375b97).
  Gate config committed locally on that branch (`.codehealth/config.toml`), NOT pushed: adopting `.codehealth/` in the
  public dem repo is the user's call.
- Baseline scan (scope `src/*`): 26 files, 13063 NLOC, debt 1872.6, health 5.49, brain 12.
- Self-test (mutation `src/solver_hertz.hpp:59`): running.

## Next actions
1. Self-test must detect the mutation (state_hash and/or ctest) → then the gate is trusted.
2. WO-1: rename the dem `*Kokkos` identifiers (DECISIONS: no `*Kokkos` names), one plain commit, state_hash identical.
3. Campaign base after WO-1. Step order: `demSolveContacts` phase extraction (one phase per step) → launcher parameter
   objects (struct of Views) → velocity/position colouring dedup.
4. Then pnm, then flow (after sharpvisc-land), voro last.

## Gates (dem, measured 11-13 on TRS2 at load ~80)
| tier | pass criterion | time |
|---|---|---|
| clang_format | 0 diffs (CI blocking set) | <1 s |
| build_host / build_cuda | builds (CUDA with tests + MPI) | ~150 s / ~340 s |
| ctest_host | 303/303, no skip | ~345 s |
| state_hash | hashes.json byte-identical to base | 6 s |
| clang_tidy (campaign) | per-file/check counts do not rise (baseline 2514 warnings) | ~530 s |

## Open decisions (default in force)
- Push `.codehealth/` to dem main → waiting for the user.
- `performance-unnecessary-value-param` (947 hits, mostly `Kokkos::View` by value, which is idiomatic) → leave it, never "fix" it; propose excluding it in dem's `.clang-tidy`.

## Anchors
`dem-health/src/solve_driver.hpp:293` demSolveContacts (debt 345); `dem-health/.codehealth/config.toml`.
