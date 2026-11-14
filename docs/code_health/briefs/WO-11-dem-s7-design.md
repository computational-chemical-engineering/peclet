# WO-11 — dem S7 design brief (architect): device inner loop + demSolveContacts remainder

Standing rules: `docs/code_health/RULES.md` (read first). State: `docs/code_health/STATE.md`.
Code: dem worktree `/home/frankp/Codes/suite/dem-health`, branch `code-health` (never another tree).

## 1. The question
How to decompose two dem functions into readable parts with **bitwise-identical host results and no
GPU slowdown**? Write the answer as work orders that an engineer runs one gated step at a time:
- **A. `PGSManifoldSweep::solveOne`** (`src/solver_velocity.hpp:1042`, a `KOKKOS_FUNCTION` member;
  CCN 79, NLOC 294, debt 97.4, the largest in dem). This is THE hot device routine of the velocity
  solve, shared verbatim by the coloured launch, the fused colour-sweep kernel (`solver_fused.hpp`)
  and the multilevel fused path (`solver_multilevel.hpp`, `fine.solveOne(vPerm(i))`).
- **B. `demSolveContacts`** remainder (`src/solve_driver.hpp:1524`; CCN 78, NLOC 257, debt 87.7).
  This is host orchestration. Its complexity sits in `[&]` host lambdas that close over the whole
  function scope: `growSlots` :1584, `noteInvariant` :1589, `voteInvariant` :1670, `foldVel` :1773,
  `withConsensus` :1783 and `syncVel` :1797. The tool counts lambda bodies in the enclosing function.

## 2. Why the architect
- A is performance-critical device code. Splitting it into `KOKKOS_INLINE_FUNCTION` helpers
  changes what nvcc sees: inlining, register allocation and local-memory spills. The design must
  say how to keep codegen equivalent. Should it use `KOKKOS_FORCEINLINE_FUNCTION`? Which state
  should travel by value, and which by reference? Where are the seams that do not split a
  register-resident accumulator?
- B is a closure-state design problem. The lambdas share mutable locals (flags, counters, views)
  across the solve phases. Earlier rounds moved whole phases out with context structs; the
  playbook's "context bag" anti-pattern and the ≤ 10 params rule constrain the options.

## 3. Current state and prior art (all in the dem worktree)
- S1–S6 history: `.codehealth/playbook.md` (recipes extract-kernel-phase, launch-params-struct,
  dedup-colouring; anti-pattern: long-parameter helpers, context bags) and
  `docs/code_health/DECISIONS_LOG.md` in the umbrella docs worktree.
- Patterns already accepted in this codebase:
  - device functors with `KOKKOS_FUNCTION` members (`PGSManifoldSweep`, `MlCoarseSweep::row`/`solveOne`,
    and since S7 step 2 `MlMatchFilter`);
  - structs passed by const& and unpacked to the old names before any `KOKKOS_LAMBDA`
    (S3–S6 phase extractions).
- Rejected so far: the `*Incremental` colouring pair. It differs in launch order, atomics and
  tie-break, so the merge is not bitwise. Do not propose it again.

## 4. Constraints (non-negotiable)
- Never change numerics while changing structure. Host results stay **bitwise identical**: the
  gate runs ctest (303) plus `state_hash` at `OMP_NUM_THREADS=1`. No reordering of floating-point
  operations, no fused multiply-add changes by reassociation, and the same atomics in the same
  order.
- GPU (RTX 5080, CUDA 13.5, Kokkos OPENMP;SERIAL;CUDA): state_hash is NOT run-to-run deterministic.
  The check is the envelope rule: A-vs-B max|Δ| ≤ 1.5 × max(within-A, within-B) per scenario, plus
  CUDA ctest 303/303.
- GPU timing gate (pre-registered): ABBA `examples/bench_step.py` np1 N=4000, 5 pairs.
  - median base/head ≥ 0.95 is a PASS;
  - 0.90–0.95 means rerun with 10 pairs;
  - < 0.90 is a MISS.
  The design must say whether this bench exercises the solveOne path that changes. If it does
  not, name a bench that does.
- At most 10 parameters per helper, and no struct is named inside a `KOKKOS_LAMBDA` unless it is a
  device functor following the existing pattern.
- No public API change, no new files (unless a restructure plan is approved by Frank), and no
  edits under tests/, cmake/ or CMakeLists.txt.

## 5. Decided (do not reopen) / open
- Decided: the round happens (Frank, 2026-11-14). The landing is a PR with full CI after S7 closes.
  The milestone exit rule: brain ≤ 12, debt below the S6 milestone (1649.4), and the CUDA check.
- Open: the decomposition seams for A and B, the order of steps, and which of the other device
  brains are worth a follow-on step under the same recipe. Those brains are `solveVelocity` :76
  (51.1), `solveVelocityColoredGS` :1681 (42.1), `hertzWallForces` (`solver_hertz.hpp:180`, 49.4),
  `generateSdf` (`output_sdf.hpp:29`, 66.5; output only) and `ParticleHalo::packState`
  (`mpi_halo.hpp:1575`, 36.4).

## 6. Verification per step
`codehealth gate --mode refactor --base <prev> --ref-base 3fd9b93 --require-gain` (bitwise host tiers).
For every step that touches device code, also the CUDA check and the timing gate above
(scripts in the session scratchpad: `cuda_ref.sh`, `cuda_env.py`, `cuda_bench.sh`).

## 7. Deliverable
A design note at `docs/code_health/designs/dem-s7-design.md` in the umbrella docs worktree
(`/home/frankp/Codes/suite/.claude/worktrees/suite-code-health`) with these sections:
- the seams for A, with function signatures and what each helper owns;
- the codegen safeguards for A (inline policy, and how to check it: e.g. compare `-Xptxas -v`
  register and spill counts, base vs head);
- the state design for B;
- the work orders in order, each with its expected debt change and its gates;
- the risks.
No production code.

## 8. Out of scope
The `*Incremental` merge, any change to numerics or algorithms, performance optimization beyond
"no slowdown", and the pnm, flow and voro repos.
