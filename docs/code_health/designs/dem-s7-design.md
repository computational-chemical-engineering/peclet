# dem S7 design: `PGSManifoldSweep::solveOne` and the `demSolveContacts` remainder

Architect design note for WO-11 (brief: `briefs/WO-11-dem-s7-design.md`; rules: `RULES.md`).
Written against dem `code-health` @ **757edf1** (line numbers below refer to it). No production code.
Implementer: an `engineer` (device steps A*) and an `engineer` or `spec-implementer` (host steps B*);
nothing below is left to choose except where §9 names a default.

---

## 1. Problem and scope

Two dem brain functions are decomposed into readable parts, with behaviour proved unchanged:

- **A. `PGSManifoldSweep::solveOne`** (`src/solver_velocity.hpp:1042`; CCN 79, NLOC 294, nesting 5,
  debt 97.4). The per-manifold PGS body shared by six CUDA kernels (§3.1).
- **B. `demSolveContacts`** (`src/solve_driver.hpp:1524`; CCN 78, NLOC 257, params 6, debt 87.7).
  Host orchestration whose complexity sits in six `[&]` lambdas and in duplicated plan blocks.

Out of scope: the `*Incremental` colouring merge (rejected, not bitwise); any numerics or algorithm
change; performance work beyond "no slowdown"; changing `PGSManifoldSweep`'s data members or
`makePGSManifoldSweep`'s signature; the other device brains (recommendation only, §9 item 11); pnm, flow, voro.

## 2. Constraints and invariants

- **Host bitwise.** Every step passes `codehealth gate --mode refactor --base <prev> --ref-base 3fd9b93
  --require-gain` (ctest 303/303, `state_hash` byte-identical at `OMP_NUM_THREADS=1`). That build uses
  `-DCMAKE_CXX_FLAGS=-ffp-contract=off`: it proves the source-level operation order and nothing about
  contraction. Contraction is checked separately (§5.2 G-fma, G-sass).
- **GPU.** RTX 5080 (sm_120), CUDA 13.5, nvcc `--fmad=true` (default). GPU `state_hash` is not run-to-run
  deterministic, so the pre-registered device check is the envelope rule plus CUDA ctest 303/303.
  This note adds a stronger, deterministic check: the generated SASS (§5.2 G-sass). The brief forbids
  "fused multiply-add changes by reassociation"; on the GPU that is exactly a change in the FP opcode
  mix of a kernel, which G-sass detects and the envelope cannot.
- **Unchanged by construction:** kernel launch order, fences, `deep_copy`s, MPI calls, atomics (type,
  target, order), colourings and sweep order; every View keeps its memory space; no `this` capture in a
  device lambda; no env var; no public API (`dem_bindings.cpp`) change; no new files; nothing under
  `tests/`, `cmake/`, `CMakeLists.txt`, `.codehealth/`.
- **Metric (cpp@0).** Function debt = (CCN−10)⁺ + 0.1·(NLOC−70)⁺ + 3·(nesting−3)⁺ + (params−5)⁺.
  Brain = CCN > 25 and NLOC > 70. Round exit: brain ≤ 12 (now 9), dem debt < 1649.4 (now 1635.4), CUDA
  check. Lambda bodies count in the enclosing function.
- **Structs.** ≤ 10 parameters per helper. No struct is named inside a `KOKKOS_LAMBDA` unless it is a
  device functor (the new device structs are nested in `PGSManifoldSweep` and used only by its member
  functions — the `MlCoarseSweep::Row` precedent, `solver_multilevel.hpp:729`). Host structs are
  unpacked to the old local names before any `KOKKOS_LAMBDA` (S3–S6 pattern).
- **Aggregates are initialised with designated initialisers** (`Row{.realA = realA, ...}`), never
  positionally: `Row` has many same-typed neighbours (`invMassA`/`invMassB`, `applyA`/`applyB`) whose
  silent swap only some branches would expose.

## 3. Evidence gathered for this design (measured 2026-11-14, probe worktrees, not dem-health)

### 3.1 Base codegen (dem 757edf1, target `dem` = `_dem.*.so`, build_cuda flags)

`solveOne` is fully inlined into six kernels; no spills; the 15 `CALL`s are the IEEE div/sqrt slow
paths (FCHK + MUFU.RCP/RSQ pattern), not user functions:

| kernel | instr | REG | STACK/LOCAL | FFMA |
|---|---|---|---|---|
| `demFusedColorSweepK<PGSManifoldSweep>` (distributed step, fused) | 1792 | 96 | 0/0 | 325 |
| `demFusedSweepLoopK<PGSManifoldSweep>` (single-GPU fused loop) | 1896 | 96 | 0/0 | 331 |
| `solveVelocityPGS` colour launch, bucket and full-scan variants | 1760 ×2 | 96 | 0/0 | — |
| `solveVelocityPGSBuckets` (level-ordered stabilization) | 1760 | 96 | 0/0 | — |
| `demFusedMlLoopK` (multilevel fused, also inlines `MlCoarseSweep`) | 3224 | 108 | 0/0 | 442 |

The other 621 kernels of the module do not contain `solveOne`.

### 3.2 Experiment: the naive extraction is NOT codegen-neutral

A probe applied the obvious design — `Row` + `bool row(int, Row&)` out-param seam, `applyImpulse`
(6 sites) and `recordCorrection` (3 sites), all `KOKKOS_FORCEINLINE_FUNCTION`, bodies moved verbatim —
and compared SASS against base: all six kernels changed; REG 96→128 (fused/colour kernels) and 108→168
(ML loop); FFMA +2, FMUL +1, FSETP +4 per kernel (ML loop FFMA −4, FMUL −10); STACK/LOCAL stayed 0;
the other 621 kernels were byte-identical. 96→128 registers cuts the resident warps per SM from 20 to
16 (65 536 regs / (32 × REG)). So "force-inline and the compiler will undo it" is false here, and a
helper split must be engineered and checked, not assumed. Bisection: §3.3.

### 3.3 Bisection

Each probe = one change on top of 757edf1, built and compared kernel by kernel (627 kernels). "Perm-eq"
= same instruction count and the same multiset of instruction shapes (registers, immediates, `.reuse`
hints stripped): the same arithmetic, scheduled and allocated differently.

| probe | change (all helpers `KOKKOS_FORCEINLINE_FUNCTION`) | identical | rest | REG | FP opcodes |
|---|---|---|---|---|---|
| e_record | `recordCorrection` (3 sites) | **627** | — | = | = |
| e_apply | one `applyImpulse(real, dLin, dAng, invMass, invI, q)` (6 sites) | 621 | 6 perm-eq | = | = |
| e_split | `applyLinear` + `applyAngular` (source order preserved) | 622 | 5 perm-eq | = | = |
| e_row | `bool row(int, Row&)` out-param, `Row` holds `ManifoldC` | 621 | 6 changed, +96…+120 instr, +49 `MOV` | 96→128, 108→168 | FFMA +2, FMUL +1, FSETP +4 |
| e_rowinl | e_row with `KOKKOS_INLINE_FUNCTION` | 621 | as e_row | as e_row | as e_row |
| e_lean | e_row without `ManifoldC` in `Row` | 621 | as e_row | 96→128 | as e_row |
| **e_two** | `Row` filled by two **void** helpers; both early exits stay in `solveOne` | **625** | 2 perm-eq | = | = |

Mechanism: `bool row(idx, r)` adds a control value the original never had. After inlining, its two
`return false` paths and the success path merge before the caller's `if (!ok) return;`; every `Row`
field is then a phi of (value, undef) whose value does not dominate the merge, so ~30 values get edge
copies and stretched live ranges (+49 MOV, +32 registers) and the exit predicates are re-evaluated
(FSETP/FSEL). Neither struct size (e_lean) nor the inline attribute (e_rowinl) matters. Keeping the
exits in `solveOne`, on the original conditions, removes the effect (e_two). Pure dedups that move
an expression into an argument perturb only the instruction schedule (e_apply, e_split).

## 4. Decision

### 4.1 A — chosen

`solveOne` becomes a six-line sequence over a nested `Row` aggregate: two **void** builders fill it
(`gatherRow`, `weighRow`), `solveOne` keeps the two early exits on their original conditions, and three
channel helpers (`normalImpulse`, `releaseImpulse`, `frictionImpulse`) consume it by `const&`, with
small sub-helpers where a channel alone would exceed CCN ~13. Four device kernels remove the
duplicated code: `applyLinear`, `applyAngular`, `recordCorrection`, `pairVelocity`, plus the pure
`normalVelocity`. Every new function is `KOKKOS_FORCEINLINE_FUNCTION` and single-exit. Moved code is
moved verbatim, with an unpack header that rebinds the old local names from `Row`. Acceptance of
every device step is a deterministic SASS comparison (§8 G-sass): each kernel identical (S0) or
perm-eq with no more registers (S1).

Rejected:
- **`bool row(int, Row&)` (the `MlCoarseSweep::row` pattern)**: measured +32 registers (−20 % resident
  warps) and changed FP opcodes in all six kernels (§3.3).
- **Helpers with explicit long parameter lists instead of a struct**: the channels need 15–20 values
  each, more than the 10-parameter limit.
- **Generic `[&]` lambdas inside `solveOne`**: the metric counts them in `solveOne` (no gain), and the
  playbook rejects debt-by-lambda-shuffling.
- **One `applyImpulse` with six parameters**: also only schedule-perturbing, but it evaluates the
  angular impulse before the linear stores; the order-preserving pair keeps one more kernel
  byte-identical and no function above five parameters.
- **Relying on `KOKKOS_INLINE_FUNCTION`**: it gave the same code here (e_rowinl), but a helper that
  takes `Row&` and is outlined would put `Row` in local memory; force-inlining makes inlining a
  contract instead of a heuristic. `solveOne` itself keeps `KOKKOS_FUNCTION` (its inlining into the six
  kernels is an existing property, checked by G-sass: same `CALL` count, no new kernel-level function).
- **The envelope check alone for the GPU**: it cannot see a contraction change; G-sass can.

### 4.2 B — chosen

The design of §6: one owning object for the only mutable shared state (`ColoringInvariant`), free
functions for the pure operations (`growCopySlots`, `withConsensus`, `foldVelocityCopies`,
`syncVelocityPhase`), the Poisson views grouped (`PoissonBankViews`, which also carries the one handle
only a lambda held), one shared builder for the two sweep plans (`SweepPlan`), one for the velocity
solve views (`openVelocityCopies`), and three host predicates.

Rejected:
- **A `SolveState` object owning all the locals with the lambdas as methods**: a context bag with
  behaviour; it hides which phase needs what. The playbook names the anti-pattern.
- **Keeping the lambdas and passing them on**: the metric still counts them in `demSolveContacts`, and
  the dependencies stay implicit (`[&]`).
- **Re-deriving the writable orphan-peak view from `P` inside the free functions without grouping the
  views**: bitwise-safe today (§6.2), but it puts a second derivation of the same handle in the code;
  grouping keeps one.
- **Adding `orphPkW` as a 28th member of `VelocitySolveContext`**: grows the bag the campaign logged as
  an anti-pattern; grouping shrinks it by four instead.

## 5. Design A — `PGSManifoldSweep::solveOne`

### 5.1 Data (nested in `PGSManifoldSweep`, after the data members)

```
/// The endpoints' velocities (B on a wall: the wall's average velocity, zero spin).
struct PairVelocity { F3 vA, wA, vB, wB; };

/// One manifold's constraint row as the three impulse channels share it: the manifold, its endpoints'
/// solve slots, mass data and velocities at the start of this manifold's solve, the averaged normal
/// and arm sums, and the substep's sign, effective mass, side gate and restitution. Filled by
/// gatherRow then weighRow; read-only afterwards.
struct Row {
  ManifoldC m;
  int idB, realA, realB;            // idB < 0: wall manifold (realB = idB)
  float invMassA, invMassB;
  F3 invIA, invIB;
  F4 qA, qB;
  PairVelocity vel;                 // loaded by gatherRow (fallback: flat vA, wA, vB, wB, see C6)
  float invN, restitution, eMat;    // restitution after the material override; weighRow may zero it
  F3 Nsum, TauA, TauB, rAavg, rBavg;
  float lenN;
  F3 vGrowth;                       // from here on: written by weighRow
  float vn, sgn, wTotal;
  unsigned char sf;
  bool applyA, applyB;
};

/// The Poisson release's budget: the pair's owed impulse, the release speed scale and the endpoints'
/// orphan balances.
struct ReleaseBudget { float owed, vPeak, orphA, orphB; };
```

### 5.2 Functions — signature, line range moved (757edf1), what each owns

All `KOKKOS_FORCEINLINE_FUNCTION`, `const` members of `PGSManifoldSweep`, defined in-class, in this
order, above `solveOne`. "Unpack" = the first lines of the helper rebind the `Row` fields it reads to
the old local names (`const int realA = r.realA, realB = r.realB;` …; a field the moved code mutates is
copied into a non-const local: `float restitution = r.restitution;`), so the moved block is byte-identical.

| function | moves | owns / returns | CCN est. |
|---|---|---|---|
| `void applyLinear(int real, F3 dLin, float invMass)` | the three `velPred(real, k) += d.k * invMass;` lines | linear body update | 1 |
| `void applyAngular(int real, F3 dAngWorld, F3 invI, F4 q)` | `Jl = invRotateVector`, `dwl`, `dww = rotateVector`, three `angVelPred +=` | angular body update | 1 |
| `void recordCorrection(int idx, float lenN, float corr)` | `atomic_max(maxApproach)` + the QS-gated `atomic_max(maxApproachQS)` | residual record (same atomics, same order) | 2 |
| `PairVelocity pairVelocity(const Row& r)` | the `ld3(velPred…)`/wall-velocity reload block (:1206–1213, :1315–1322) | current endpoint velocities, re-read from memory | 2 |
| `static float normalVelocity(const PairVelocity& v, F3 Nsum, F3 TauA, F3 TauB, F3 vGrowth)` | `float vn = dot3(...) + ... + dot3(wB, TauB); vn += dot3(vGrowth, Nsum); return vn;` (the :1083–1085 form, verbatim operand order) | approach velocity | 1 |
| `void gatherRow(int idx, Row& r)` | :1046–1078 (`const ManifoldC m` … `const float lenN`), then `r = Row{.m = m, …, .lenN = lenN};` | manifold, endpoints, sums, `lenN` | ~7 |
| `void weighRow(int idx, Row& r)` | :1081–1106 (`diffCenters` … `wTotal`), then member writes `r.vGrowth = vGrowth; r.vn = vn; r.sgn = sgn; r.wTotal = wTotal; r.sf = sf; r.applyA = applyA; r.applyB = applyB; r.restitution = restitution;` | sign, effective mass, side gates | ~5 |
| `void normalImpulse(int idx, const Row& r, float v0til)` | :1111–1173 (resting gate, Moreau/Newton target, projected increment, apply) | `lambdaAcc(idx)` | ~11 |
| `ReleaseBudget releaseBudget(int idx, const Row& r)` | :1190–1204 (`owed`, `vPeak`, orphan availability) | read-only | ~6 |
| `void releaseImpulse(int idx, const Row& r)` | comment :1175–1188; eligibility :1205; approach :1206–1217 via `pairVelocity`/`normalVelocity`; then `releaseIncrement(idx, r, b, vtil3)` | — | ~5 |
| `void releaseIncrement(int idx, const Row& r, const ReleaseBudget& b, float vtil3)` | :1218–1296 (`relA/relB`, `wRel`, target, clamped increment, draw, apply) with `float owed = b.owed;` | `restRel(idx)`, `restBank(idx)` | ~11 |
| `float drawOrphans(int realA, int realB, float need, float orphA, float orphB)` | the body of `if (rNew > cap && (...))` minus its `if (draw > 0.0f) {...}` tail: `float draw = 0.0f; if (orphA > 0) {...} if (need > 0 && orphB > 0) {...} return draw;` | `restOrphan(realA/B)` | 4 |
| `void frictionImpulse(int idx, const Row& r)` | :1299–1314 (`mu`, `ltOld`, gate, `nhat`) and :1366–1398 (`dApp`, accumulator write, record, apply) | `lambdaT(idx)` | ~13 |
| `F3 slipError(int idx, const Row& r, F3 nhat)` | :1315–1338 (reload via `pairVelocity`, `vrel`, `vt`, Walton β, `vtErr`) | — | ~6 |
| `F3 tangentialPredictor(const Row& r, F3 vtErr, F3 ltOld, float& wT)` | :1339–1351 (`vtLen`, `ltNew = ltOld`, `wT = invMassA + invMassB`, GS increment) | sets `wT` | ~6 |
| `F3 coneProject(int idx, const Row& r, float mu, F3 nhat, F3 ltNew)` | :1352–1365 (tangent-plane projection, Coulomb bound incl. the QS position carry, clamp) | — | ~5 |

Call-site forms (exact):
- normal A: `if (applyA) { applyLinear(realA, Jlin, invMassA); applyAngular(realA, JangA, invIA, qA); }`;
  normal B: `if (idB >= 0 && applyB) { applyLinear(realB, F3{-Jlin.x, -Jlin.y, -Jlin.z}, invMassB);
  applyAngular(realB, JangB, invIB, qB); }`. `(-Jlin.x) * invMassB` is today's `-Jlin.x * invMassB`
  (unary minus binds first); negation is exact.
- release: `applyAngular(realA, scale3(TauA, lambdaR), invIA, qA)`, B with `F3{-JlinR.x, …}` and
  `scale3(TauB, lambdaR)`; friction: `applyAngular(realA, cross3v(rAavg, dApp), invIA, qA)`, B with
  `F3{-dApp.x, …}` and `cross3v(rBavg, scale3(dApp, -1.0f))` — the angular argument stays after the
  linear call, as today.
- `recordCorrection(idx, lenN, Kokkos::fabs(dApplied) * wTotal / lenN)`,
  `recordCorrection(idx, lenN, Kokkos::fabs(dR) * wRel / lenN)`, and in friction
  `if (wT > 1e-9f) recordCorrection(idx, lenN, dLen * wT);`.
- release approach: `const float vtil3 = sgn * normalVelocity(pairVelocity(r), Nsum, TauA, TauB, vGrowth);`
  weighRow: `float vn = normalVelocity(vel, Nsum, TauA, TauB, vGrowth);` (from A3 on; A2 keeps :1083–1085 verbatim).
- friction core: `float wT; const F3 ltNew = coneProject(idx, r, mu, nhat, tangentialPredictor(r, vtErr, ltOld, wT));`
- release draw: `if (rNew > cap && (orphA > 0.0f || orphB > 0.0f)) { const float draw = drawOrphans(realA,
  realB, (rNew - cap) * lenN, orphA, orphB); if (draw > 0.0f) { owed += draw; restBank(idx) = owed;
  cap = owed / lenN; } }` — the comment :1238–1241 stays above it.

### 5.3 The resulting `solveOne`

```
KOKKOS_FUNCTION void solveOne(int idx) const {
  Row r;
  gatherRow(idx, r);
  if (r.lenN < 1e-9f)
    return;
  weighRow(idx, r);
  if (r.wTotal <= 0.0f)
    return;
  // Restitution bias on the PRE-SOLVE approach (resting threshold as in the one-shot path).
  const float v0til = r.sgn * vn0(idx);
  normalImpulse(idx, r, v0til);
  if (restRel.extent(0) > 0 && r.sf == 0 && v0til < -restVelThreshold * r.lenN)
    releaseImpulse(idx, r);
  frictionImpulse(idx, r);
}
```

### 5.4 Codegen rules (binding on every A step)

- **C1 Single exit, original conditions.** No helper contains a `return` that ends the manifold's solve,
  and no helper returns a flag the original code did not branch on. Early exits live in `solveOne` and
  test `Row` fields with the original expressions. (Measured reason: §3.3.) A helper may return a value
  the original already branched on (`drawOrphans` → `draw > 0.0f`).
- **C2 Verbatim moves.** Moved statements keep their text, order and parenthesisation; only the unpack
  header and the call lines are new. No expression is re-associated, hoisted, merged or recomputed;
  in particular `v0til` is computed once (in `solveOne`) and passed, and `restitution` is re-zeroed in
  `normalImpulse` exactly where it is today.
- **C3 Re-read, never forward.** Release and friction re-read body velocities from memory
  (`pairVelocity`), as today; a channel never receives another channel's updated velocities in
  registers. The velocities in `Row::vel` are the pre-normal ones and are used only by `weighRow`.
- **C4 Passing.** `Row` by `Row&` into the two builders and by `const Row&` into everything else;
  `F3`/`F4`/scalars by value; a second result by `float&` (`wT`). No helper takes or returns a `View`.
- **C5 Force-inline every new function** (`KOKKOS_FORCEINLINE_FUNCTION`); `solveOne` keeps
  `KOKKOS_FUNCTION`; existing `detail::` helpers are untouched.
- **C6 Fallback for `Row::vel`.** If A2 fails G-sass only because of the nested `PairVelocity` member,
  flatten it to `F3 vA, wA, vB, wB` (the measured e_two layout) and retry once; anything else that fails
  G-sass is reverted and escalated, never accepted.
- **C7 Formatting.** clang-format 18.1.8 (suite venv). If it reflows a moved block, that is the only
  permitted textual change of the block.

### 5.5 Expected metric (A total ≈ −90 debt, ±15)

`solveOne` ends at CCN ~6, NLOC ~12 (not a brain from A3 on: NLOC < 70). The largest new functions:
`frictionImpulse` ~13 (debt ~3), `normalImpulse` ~11, `releaseIncrement` ~11 (debt ~1 each); nesting ≤ 3
everywhere. `solver_velocity.hpp` keeps its existing `large_file`/`duplication` smells (NLOC 1425 →
~1430); the duplicated-line fraction should fall (six 9-line apply blocks go).

## 6. Design B — `demSolveContacts`: who owns the solve's host state

### 6.1 Diagnosis

The six lambdas are not one concern but four, each with its own owner:

| lambda | captures (by `[&]`) | real owner |
|---|---|---|
| `growSlots` :1584 | `slotBase`, `P` | a pure operation on `P` |
| `noteInvariant` :1589 | `edgeA`, `edgeB`, `P.vertexDegree`, `invariantMsg` | the colouring-invariant ledger |
| `voteInvariant` :1670 | `invariantPending`, `invariantMsg`, `hooks` | the colouring-invariant ledger |
| `foldVel` :1773, `syncVel` :1797 | `space`, `P`, `VC`, `velCopiesOn`, `velM`, `orphV`, `orphPkW`, `hooks` | the velocity phase (all of it is in `VelocitySolveContext` or `P`, except `orphPkW`) |
| `withConsensus` :1783 | `P.maxConsensus` | a pure operation on `P` |

Only the invariant ledger is genuinely mutable shared state (`invariantMsg` grows, `invariantPending`
flips once). Everything else is either a pure operation on `P` or already settled velocity-phase state.
So the state design is: **one small owning object for the ledger, free functions for the rest, and
the five Poisson views grouped so that the velocity phase's settled state carries the one handle
(`orphPkW`) that today only a lambda holds.** No context bag grows; `VelocitySolveContext` shrinks by
four members.

Two further blocks are plain duplication or plain derivation and move by the existing recipes: the
velocity and position sweep plans (buckets + fused context + schedule, :1614–1630 and :1683–1694, the
same twelve lines twice) and the velocity solve-view setup (:1747–1771).

### 6.2 Types and functions (all in `src/solve_driver.hpp`, host-only, `inline`)

```
/// The colouring invariant (§4.2 item 4, §12 S3): the failing phase's edges, the accumulated message,
/// and whether the distributed vote is still owed. A single rank throws at seal(); the distributed
/// step throws inside the first stop vote, on every rank.
struct ColoringInvariant {
  Kokkos::View<int*, CpMem> edgeA, edgeB;  // a failed phase's colouring edges (scratch)
  std::string msg;
  bool pending = false;
  void note(const char* phase, Kokkos::View<const int*, CpMem> color, int n,
            Kokkos::View<const int*, CpMem> vertexDegree);          // body of noteInvariant, verbatim
  template <class Hooks> void seal();                               // :1665-1669 verbatim
  template <class Hooks> float vote(const Hooks& hooks, float res); // body of voteInvariant, verbatim
};
inline void growCopySlots(Particles& P, int slotBase, int nCopies);  // body of growSlots

/// Event-level (Poisson) restitution views, all empty when the model is off.
struct PoissonBankViews {
  Kokkos::View<float*, CpMem> bank, rel;
  Kokkos::View<const float*, CpMem> vPeak;
  Kokkos::View<float*, CpMem> orphan, orphanPeak;   // orphanPeak WRITABLE (today's orphPkW)
};
inline PoissonBankViews poissonBankViews(Particles& P, bool on);    // the five ternaries :1722-1732

inline float withConsensus(Particles& P, float res, bool cons);     // body of the lambda
inline void foldVelocityCopies(CpExec& space, Particles& P, const VelocitySolveContext& ctx);
template <class Hooks>
inline void syncVelocityPhase(Particles& P, const Hooks& hooks, const VelocitySolveContext& ctx);

/// One coloured phase's sweep plan: owns the dense-bucket offsets and the fused context that its
/// ColorSchedule points at, so it is built in place and never copied or moved.
struct SweepPlan {
  std::vector<int> offs;
  FusedSweepCtx fused{};
  ColorSchedule sched{};
  SweepPlan() = default;
  SweepPlan(const SweepPlan&) = delete;
  SweepPlan& operator=(const SweepPlan&) = delete;
};
inline void planColorSweeps(SweepPlan& plan, CpExec& space, Particles& P,
                            Kokkos::View<int*, CpMem> color, int n, int numColors,
                            Kokkos::View<int*, CpMem> perm, Kokkos::View<int*, CpMem> offsDev,
                            bool wantFused);                        // 9 params (debt 4, accepted)

/// The velocity phase's solve views and slot override: true masses; the hub copies' split masses;
/// or each slot's global k_vel (rank-level M). Seeds the copy slots where copies exist.
struct VelocitySolveViews {
  Kokkos::View<const float*, CpMem> invMass;
  Kokkos::View<const float* [3], CpMem> invInertia;
  SlotOverride ov;
};
inline VelocitySolveViews openVelocityCopies(Particles& P, int slotBase, bool velM,
                                             bool velCopiesOn, const PoissonBankViews& pv);
```

Exact rules:

- **ColoringInvariant.** `note` = the `noteInvariant` body with `invariantMsg`→`msg`,
  `P.vertexDegree`→`vertexDegree`. `seal<Hooks>()` = `pending = !msg.empty(); if constexpr
  (!Hooks::distributed) { if (pending) throw std::runtime_error(msg); }`, called exactly where
  :1665–1669 stand. `vote` = the `voteInvariant` body with `invariantPending`→`pending`. The object is
  a local of `demSolveContacts` (`ColoringInvariant inv;` replacing `edgeA, edgeB` :1583 and
  `invariantMsg` :1588) and is passed **by non-const reference** to `colorVelocityPhase`,
  `colorPositionPhase` (replacing `edgeA, edgeB, growSlots, noteInvariant`), and to
  `solveVelocityPhase`, `runOverlapProjection`, `solvePositionPhase` (replacing `voteInvariant`).
  Inside the colour phases, alias at the top — `Kokkos::View<int*, CpMem>& edgeA = inv.edgeA;` (same
  for B) — so the bodies, including the `edgeA = Kokkos::View<int*, CpMem>(...)` reallocations, stay
  verbatim; `growSlots(n)` → `growCopySlots(P, slotBase, n)`; `noteInvariant(...)` →
  `inv.note(..., P.vertexDegree)`. Calls `voteInvariant(x)` → `inv.vote(hooks, x)`.
- **PoissonBankViews.** Built once at :1722 (`const PoissonBankViews pv = poissonBankViews(P,
  poisson);`). `VelocitySolveContext` replaces `bankV, relV, vpkC, orphV, orphPk` by one member
  `PoissonBankViews poissonViews;`. The eight unpack sites keep their local names and types:
  `const auto& bankV = ctx.poissonViews.bank;` (same for `relV`←`rel`, `vpkC`←`vPeak`,
  `orphV`←`orphan`), and **`const Kokkos::View<const float*, CpMem> orphPk =
  ctx.poissonViews.orphanPeak;`** — an explicit const-View copy, so every downstream use, including
  device-lambda captures, has exactly today's type. `orphPkW` (:1752) becomes `pv.orphanPeak`.
  *Handle identity:* today `orphPk` is taken at :1729 and `orphPkW` at :1752; they are the same
  allocation because `P.bodyOrphanVPeak` is only reallocated by `Particles::ensureCapacity`
  (`particles.hpp:677`), whose only callers are `step_solve.hpp:200/305` (before the solve) and
  `growSlots` (colouring, before :1722). Re-check this with
  `grep -n "ensureCapacity(" src/*.hpp` in the WO; a new in-solve caller voids B2/B3.
- **Free functions.** `withConsensus(P, res, cons)` = the lambda body. `foldVelocityCopies` =
  `if (ctx.velCopiesOn) foldCopies(space, P.velCopies, P.velPred, P.angVelPred,
  ctx.poissonViews.orphan, ctx.poissonViews.orphanPeak, P.maxConsensus);`. `syncVelocityPhase` = the
  `syncVel` body with `VC`→`P.velCopies`, `velM`/`velCopiesOn`→`ctx.`, `orphV`/`orphPkW`→
  `ctx.poissonViews.orphan`/`.orphanPeak`. The callables `FoldVel&&`, `SyncVel&&`,
  `WithConsensus&&` disappear from the signatures of `solveVelocityPhase`, `stabilizeOneSided`,
  `stabilizeMultilevel`, `stabilizeOrdered`, `stabilizeEscalation`, `stabilizeVelocityPhase`,
  `runOverlapProjection`, `solvePositionPhase`; their bodies call `foldVelocityCopies(space, P, ctx)`,
  `syncVelocityPhase(P, hooks, ctx)`, `withConsensus(P, x, cons)` where they called `foldVel()`,
  `syncVel()`, `withConsensus(x, cons)`. Same calls, same order, same arguments.
- **SweepPlan.** `planColorSweeps` body = the velocity block :1614–1630 generalised:
  `const bool dense = P.velocityUseGS && n > 0 && numColors > 0; if (dense) buildColorBuckets(View<const
  int*>(color), n, numColors, perm, P.bucketCursor, plan.offs); const View<const int*> permC(perm);
  plan.fused = (dense && wantFused) ? demMakeFusedCtx(space, plan.offs, offsDev, P.fusedBar) :
  FusedSweepCtx{}; plan.sched = ColorSchedule{color, numColors, permC, dense ? &plan.offs : nullptr,
  plan.fused.maxBucket > 0 ? &plan.fused : nullptr};` (parameter View types follow the `Particles`
  members). `wantFused` (:1629, a pure host function of `P` and `Hooks`) moves up to just before the
  velocity plan. Velocity: `SweepPlan velPlan; planColorSweeps(velPlan, space, P, P.manifoldColor, nm,
  numColors, P.velPerm, P.velOffsDev, wantFused);` at the place of :1614; position: `SweepPlan posPlan;
  planColorSweeps(posPlan, space, P, P.unitColor, numPosUnits, numPosColors, P.posPerm, P.posOffsDev,
  wantFused);` at the place of :1683. `velSched`/`posSched` become `velPlan.sched`/`posPlan.sched`;
  `velCtx.velPermC = velPlan.sched.perm`, `velCtx.velFusedP = velPlan.sched.fused` (the same handles as
  today). Device work order is unchanged: `buildColorBuckets` then `demMakeFusedCtx`, per phase, at
  the same two points of the solve.
- **openVelocityCopies** = :1747–1771 verbatim with `VC`→`P.velCopies` (alias `PhaseCopies& VC =
  P.velCopies;` at the top), `orphV`/`orphPkW`→`pv.orphan`/`pv.orphanPeak`, and the three outputs
  returned as `VelocitySolveViews{.invMass = ..., .invInertia = ..., .ov = ...}` initialised to today's
  defaults (`P.invMass`, `P.invInertia`, `SlotOverride{}`). The caller: `const VelocitySolveViews sv =
  openVelocityCopies(P, slotBase, velM, velCopiesOn, pv);` and `.invMassVel = sv.invMass`, etc.
- **Mode predicates** (B6, replace-temp-with-query, host scalars only):
  `inline bool gravityOn(const Particles& P)` (the `P.gravity.x != 0.0f || ...` expression),
  `template <class Hooks> inline bool islandSleepingOn(const Particles& P, bool gravity)` (the
  `sleepOn` expression with `usePersistPre`→`gravity`), `inline bool frictionOn(const Particles& P)`.
  `usePersist` (:1700) is the same expression as `usePersistPre` (:1534) over an unchanged `P.gravity`:
  delete it and use `usePersistPre` (its comment moves to `usePGS`).

## 7. Work orders

One commit per WO, in this order; each WO's gate runs against the previous WO's commit. Debt figures
are estimates (±30 %); the gate measures. "Device gates" = G-host, G-sass, G-fma, G-branch, G-cuda,
G-time (§8); "host gates" = G-host, G-sass (expect all kernels S0 or renamed-with-identical-body).

| WO | content | expected Δdebt (dem) | gates |
|---|---|---|---|
| **A1** | `applyLinear`, `applyAngular`, `recordCorrection`; replace the 6 apply blocks and 3 atomic pairs (§5.2 call forms). `solveOne` CCN 79→76, NLOC 294→~245 | −8 | device; expect S0 for 621 + {S0,S1} for the 6 (e_split + e_record measured 622 S0 + 5 S1) |
| **A2** | `PairVelocity`, `Row`, `gatherRow`, `weighRow`, `normalImpulse`; `solveOne` = builders + exits + `v0til` + normal call, release and friction still inline behind one unpack header | −28 | device; expect S0/S1 (e_two measured 625 S0 + 2 S1); C6 fallback once |
| **A3** | `pairVelocity`, `normalVelocity` (also used by `weighRow`), `ReleaseBudget`, `releaseBudget`, `releaseImpulse`, `releaseIncrement`, `drawOrphans`; release gate in `solveOne`. `solveOne` leaves the brain list (NLOC < 70) | −36 | device; G-branch MUST include the Poisson scenarios (the host gate has no release coverage) |
| **A4** | `frictionImpulse`, `slipError`, `tangentialPredictor`, `coneProject`; `solveOne` = §5.3 | −20 | device; G-branch with β ≠ 0 |
| **B1** | `ColoringInvariant` (+`note`, `seal`, `vote`), `growCopySlots`; colour phases take `inv` (12→9, 14→11 params); `solveVelocityPhase`, `runOverlapProjection`, `solvePositionPhase` take `ColoringInvariant&` | −22 | host |
| **B2** | `PoissonBankViews`, `poissonBankViews`; `VelocitySolveContext` 5 members → `poissonViews`; 8 unpack sites (§6.2); `orphPkW` → `pv.orphanPeak`; re-run the `ensureCapacity(` grep | −7 | host |
| **B3** | `withConsensus`, `foldVelocityCopies`, `syncVelocityPhase` as free functions; remove `FoldVel&&/SyncVel&&/WithConsensus&&` from 8 signatures (−3 params on six velocity helpers, −1 on two position helpers) | −29 | host |
| **B4** | `SweepPlan`, `planColorSweeps`; both plan blocks; `wantFused` moves above the velocity plan | −12 | host + **G-cuda** (the fused-context path is CUDA-only host code the host gate never runs) |
| **B5** | `VelocitySolveViews`, `openVelocityCopies` | −7 | host |
| **B6** | `gravityOn`, `islandSleepingOn<Hooks>`, `frictionOn`; delete `usePersist` (use `usePersistPre`). `demSolveContacts` → CCN ~24, NLOC ~140: leaves the brain list | −9 | host |
| B7 (only if `demSolveContacts` is still a brain after B6) | move the legacy-friction block (`if (legacyFriction) {` at :1845, through its closing brace) verbatim into `legacyFrictionPhase<Hooks>(P, nc, hooks)` (extract-kernel-phase) | −3 | host |

Round expectation: dem debt 1635.4 → ~1460 (−175), brain 9 → 7 (`solveOne`, `demSolveContacts` out), no
new brain, no new file smell. Exit rule (brain ≤ 12, debt < 1649.4, CUDA check) is met at every step.

Acceptance per WO, in addition to the gates: `git diff --color-moved=zebra` shows the moved blocks as
moved (only unpack headers, call lines, `return`-less helper shells and clang-format reflow are new);
for B steps, a grep shows no new `[&]` lambda and no new member of `VelocitySolveContext`; for every
step, parameter counts ≤ 10 and no struct named inside a `KOKKOS_LAMBDA`. Log each WO in the run log
with the gate line, the G-sass line and (device steps) the G-cuda and G-time numbers.

Independence: A and B touch different files (`solver_velocity.hpp` vs `solve_driver.hpp`) and can be
reordered as blocks; within A and within B the order above is a dependency order (A3 needs A2's `Row`;
B3 and B5 need B2's `PoissonBankViews`).

## 8. Verification gates

| gate | what it proves | how | pass |
|---|---|---|---|
| **G-host** | host bitwise, tests, format, file smells, debt gain | `PECLET_SUITE=/home/frankp/Codes/suite codehealth gate --mode refactor --base <prev> --ref-base 3fd9b93 --require-gain` | GATE PASS (all tiers); `state_hash` byte-identical; ctest 303/303, no skip |
| **G-sass** | device codegen: same arithmetic, no register growth | build target `dem` (the gate's build_cuda configure, own build dir per side, e.g. a detached probe worktree at `<prev>`, reused across WOs) and run `sass_gate.py BASE.so HEAD.so` (Appendix) | `SASS PASS`: every kernel S0 or S1; 0 unmatched bodies. A device WO reports its S0/S1 counts; any FAIL = stop |
| **G-fma** (A steps) | host contraction unchanged (site builds with `-march` let GCC fuse) | the gate's host configure but `-DCMAKE_CXX_FLAGS="-march=native -ffp-contract=fast"`, own build dir per side; `state_hash.py --save` + G-branch, `OMP_NUM_THREADS=1` | base vs head byte-identical. Validity check, once: these hashes must differ from the `-ffp-contract=off` hashes in ≥ 1 scenario, else the tier tests nothing — report it |
| **G-branch** (A steps; both host builds) | bitwise coverage of the `solveOne` branches `state_hash` does not reach | scratchpad `s7_branch_hash.py` (≤ 80 lines, hash = `state_hash.state_hash` of pos/vel/quat): (1) `poisson_drop`: 216 spheres r 0.5 from `_jittered_grid`-style placement above a plane, g = −9.81, initial vz = −2, `set_material_params(0.8, 0.3, 0.4)`, `set_restitution_model('poisson')`, dt 0.002, 300 steps; (2) `materials`: same bed, two material ids alternating, `set_pair_material(0, 1, 0.6, 0.1)`, plus a wall carrying material id 1 via `set_wall_material_id(wid, 1)` if the API admits a wall in this scene (it is documented for SDF walls; if none is reachable, log "wall-material override: ctest only"), 300 steps; (3) `stab_<mode>` for `multilevel`, `ordered`, `escalate`: the `_xpbd_periodic_bed` setup with `set_stabilization(mode)`, 100 steps | base vs head byte-identical in every scenario |
| **G-cuda** (A steps, B4) | GPU behaviour within run-to-run noise | pre-registered `cuda_ref.sh` (CUDA ctest + `state_hash` ×3 base, ×3 head) | ctest 303/303; per scenario A-vs-B max\|Δ\| ≤ 1.5 × max(within-A, within-B) |
| **G-time** (A steps) | no GPU slowdown | pre-registered ABBA `cuda_bench.sh`, `examples/bench_step.py` np1 N=4000, 5 pairs; **plus** the variant below | median base/head ≥ 0.95 pass; 0.90–0.95 rerun with 10 pairs; < 0.90 MISS (both benches) |

**Does the registered bench exercise the changed path?** Partly. `bench_step.py` runs the distributed
step at np 1, so the fused colour sweep `demFusedColorSweepK<PGSManifoldSweep>` executes `solveOne`
(fused is on by the "auto" policy wherever CUDA-graph replay is unavailable, i.e. the distributed
step). With its defaults (friction 0, restitution 0, Newton model) only the builders and the normal
channel execute; the release and friction channels are compiled into the same kernel (they set its
register count) but never run. A bench that runs them: a scratchpad copy `bench_step_s7.py` of
`bench_step.py` with `s.set_material_params(0.5, 0.2, 0.4)` and `s.set_restitution_model('poisson')`
inserted before `s.set_dt(dt)`, run by the same ABBA harness. **Pre-registered here:** the same
thresholds; before its first use, one A/A run (base vs base, 5 pairs) records its noise band in the run
log, and if the A/A pair range leaves [0.90, 1.10] it is run with 10 pairs from then on. Neither bench
times the single-GPU fused loop (`demFusedSweepLoopK`) or the multilevel kernel; G-sass bounds those
(same arithmetic, REG ≤ base).

What G-sass does and does not prove: S0 proves the kernel unchanged. S1 proves the same multiset of
arithmetic instructions and no register growth; it does not by itself prove the same dataflow (two
FFMAs could in principle swap operand roles). Under C2 the expression trees, and with them NVVM's
contraction choices (made per `fadd` on its operand order), are preserved; G-fma tests the same
property deterministically on the host compiler, and G-cuda bounds the rest.

## 9. Risks and open questions

Each item: what is open, whether it needs a **fact** or the **user's preference**, and the default
that applies until someone decides.

1. **S1 accepted as GPU evidence** (preference: the orchestrator's standard of proof). S1 is strong
   evidence, not proof (§8). *Default:* accept S0 or S1 together with G-fma, G-branch and G-cuda; reject
   everything else. Revisit only if a reviewer asks for proof-level GPU identity, which would need a
   deterministic single-sweep GPU harness (not designed here).
2. **A step fails G-sass** (fact, per step). *Default:* C6 once for A2; otherwise bisect the step's seams
   (one helper at a time, ~6 min per build), keep the passing seams, revert the failing one and report
   it to the session with the S-class line. Never accept a REG increase or an FP-opcode change.
3. **Helper granularity in A** (preference: reviewer's taste). 13 functions and 3 small structs replace
   one 294-line body; the cut lines follow the existing comment blocks (resting gate, Poisson release,
   orphan draw, Walton target, Coulomb bound). *Default:* as designed. Merging `tangentialPredictor`
   into `coneProject` (one 7-parameter function, CCN ~10) is the acceptable alternative if the reviewer
   finds the friction split too fine; it is codegen-neutral by C1/C2.
4. **Per-step CUDA envelope when every kernel is S0** (preference). It is redundant then, but it is the
   pre-registered rule and compute is free. *Default:* keep it on every device step.
5. **G-branch coverage of hub copies** (fact). `ov.relax` / hub slots need a body with > 32 velocity
   edges (`kHubEdgeBudget`). *Default:* add a scenario only if a Python-reachable one (e.g. one large
   sphere among ≥ 40 small ones via per-particle scales) is found within 30 min; otherwise record "hub
   path: covered by ctest only" in the run log. The multilevel/ordered/escalate scenarios stay.
6. **Handle identity of the orphan-peak view (B2/B3)** (fact). Relies on `P.bodyOrphanVPeak` not being
   reallocated inside the solve (`ensureCapacity` callers: `step_solve.hpp:200/305`, `growSlots`).
   *Default:* as designed; the B2 WO re-runs the grep and stops if a new in-solve caller appears.
7. **`SweepPlan` is self-referential** (fact about future misuse). Copy and assignment are deleted, so a
   copy is a compile error. *Default:* as designed.
8. **`MlCoarseSweep::row` uses the measured-costly `bool row(idx, Row&)` pattern** (fact, unmeasured for
   that struct). It may cost registers in `demFusedMlLoopK` / `demFusedCoarseCycleK` today. Changing it
   is a performance optimisation, out of scope. *Default:* record it in the campaign log as a follow-on
   idea; do not touch it in S7.
9. **Order of the round** (preference). *Default:* A1–A4, then B1–B6 (B7 if needed). If A stalls on a
   codegen failure, B proceeds independently.
10. **Playbook** (preference, `.codehealth/` is outside steps). *Default:* after S7, the orchestrator's
    docs commit adds a recipe `device-row-seam` (rules C1–C7, G-sass, the §3.3 table as evidence) and
    the anti-pattern "success-flag out-param seam in device code" to `.codehealth/playbook.md`.
11. **Follow-on device brains** (preference: scope of S8). Measured shape: `solveVelocity` :76,
    `solveVelocityColoredGS` :1681 and `hertzWallForces` (`solver_hertz.hpp:180`) are each one large
    `KOKKOS_LAMBDA` body — the A recipe (functor-from-lambda into a device functor with a `Row`-style
    aggregate, C1–C7, G-sass) applies directly. `generateSdf` (output only, two lambdas) applies too but
    needs its own output-hash probe (no `state_hash` coverage). `ParticleHalo::packState` is host code
    (deep copies + host loops): the host recipe, no device gates. *Default ranking for S8:*
    `solveVelocityColoredGS` (shares the normal-channel physics), `hertzWallForces`, `packState`,
    `solveVelocity`, `generateSdf`; none scheduled in S7.

---

## Appendix — `sass_gate.py`

Tested on the §3.3 probes: e_two vs e_split → `SASS PASS: 627 common, S0 623, S1 4`; e_two vs
e_rowinl → `SASS FAIL … REG 96->128`. Needs `cuobjdump` on PATH (`/usr/local/cuda/bin`). Usage: `sass_gate.py BASE.so HEAD.so`; one line; exit 0/1.

```python
import collections, hashlib, re, subprocess, sys
INS = re.compile(r'^\s*/\*[0-9a-f]{4,}\*/\s+(.*?)\s*;?\s*/\*\s*0x[0-9a-f]+\s*\*/\s*$')
def index(so):
    fns, cur = {}, None
    for line in subprocess.run(["cuobjdump", "-sass", so], capture_output=True, text=True).stdout.splitlines():
        m = re.match(r'^\s*Function : (\S+)', line)
        if m: cur = fns.setdefault(m.group(1), []); continue
        mi = INS.match(line) if cur is not None else None
        if mi: cur.append(mi.group(1).rstrip(' ;'))
    res, lines = {}, subprocess.run(["cuobjdump", "-res-usage", so], capture_output=True, text=True).stdout.splitlines()
    for i, l in enumerate(lines):
        m = re.match(r'^\s*Function (\S+):\s*$', l)
        if m and i + 1 < len(lines):
            res[m.group(1)] = {k: int(v) for k, v in re.findall(r'(REG|STACK|LOCAL):(\d+)', lines[i + 1])}
    return fns, res
def renamed(ins):
    seen = {}
    def sub(m): return seen.setdefault(m.group(0), f"{re.match(r'[A-Z]+', m.group(0)).group(0)}{len(seen)}")
    return "\n".join(re.sub(r'\b(?:UR|UP|R|P|B)\d+\b', sub, s) for s in ins)
def shapes(ins):
    def sh(s):
        s = s.replace('.reuse', '')
        s = re.sub(r'\b(?:UR|UP|R|P|B)\d+\b|\bRZ\b|\bPT\b|\bURZ\b', 'r', s)
        return re.sub(r'0x[0-9a-f]+|-?\d+(\.\d+)?(e[+-]?\d+)?', 'k', s)
    return collections.Counter(map(sh, ins))
(fa, ra), (fb, rb) = index(sys.argv[1]), index(sys.argv[2])
key = lambda f: hashlib.sha1(renamed(f).encode()).hexdigest()
n0 = n1 = 0; bad = []
for k in fa.keys() & fb.keys():
    a, b = fa[k], fb[k]
    if renamed(a) == renamed(b): n0 += 1; continue
    A, B = ra.get(k, {}), rb.get(k, {})
    if (len(a) == len(b) and shapes(a) == shapes(b) and B.get("REG", 0) <= A.get("REG", 0)
            and B.get("STACK", 0) == 0 and B.get("LOCAL", 0) == 0
            and sum("CALL" in s for s in a) == sum("CALL" in s for s in b)):
        n1 += 1; continue
    bad.append(f"{k[:60]} n {len(a)}->{len(b)} REG {A.get('REG')}->{B.get('REG')} STACK {B.get('STACK')} LOCAL {B.get('LOCAL')}")
ua = collections.Counter(key(fa[k]) for k in fa.keys() - fb.keys())
ub = collections.Counter(key(fb[k]) for k in fb.keys() - fa.keys())
unmatched = sum((ua - ub).values()) + sum((ub - ua).values())
ok = not bad and not unmatched
print(f"SASS {'PASS' if ok else 'FAIL'}: {len(fa.keys() & fb.keys())} common, S0 {n0}, S1 {n1}, FAIL {len(bad)}, "
      f"unmatched bodies {unmatched}" + (f"; first: {bad[0]}" if bad else ""))
sys.exit(0 if ok else 1)
```

Build of one side (≈ 300 s, CPU only, no GPU lock needed): the gate's `build_cuda` configure line into
`<tree>/build_s7_sass`, then `cmake --build <tree>/build_s7_sass --target dem -j16`; the module is
`<tree>/build_s7_sass/peclet/dem/_dem.cpython-313-x86_64-linux-gnu.so`.