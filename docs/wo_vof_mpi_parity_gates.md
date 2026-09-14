# Work order — the VoF MPI parity gates: `vof_bc_mpi_np2` and `vof_collocated_mpi`

Written 2026-09-14 during the peclet 1.0.1 release, which these failures did **not** cause and did
not block. Self-contained: a session picking this up needs nothing from the conversation that
produced it.

---

## 1. The question

`tests/kokkos_mpi/test_vof_bc_mpi.cpp` fails at np=2 on a 48-core workstation and passes in CI.
**Is the np=2 VoF packing path actually wrong, or is the gate asking for agreement tighter than the
solver beneath it can deliver?** Answer with evidence, then either fix the code or change the gate —
with the reasoning recorded either way.

Do not answer it by loosening a tolerance until the run goes green. If the gate moves, it moves for
a stated reason, in the style of the precedent in §6.

## 2. Why this needs care rather than a quick patch

The failing quantity is a **field** comparison, not an iteration count. A field disagreeing at 3e-9
between decompositions is either (a) a solver tolerance showing through, which is benign and means
the gate is misspecified, or (b) a genuine decomposition-dependent difference in the VoF packing
path, which is a correctness bug in a distributed method and matters a great deal. Those two have
opposite fixes. The whole job is telling them apart.

## 3. Current state — reproduce it first

```bash
cd /home/frankp/Codes/suite/flow
source ../.venv/bin/activate
cmake -S . -B build_dev -DCMAKE_PREFIX_PATH="$PWD/../extern/install/host-openmp" \
      -DPECLET_FLOW_BUILD_TESTS=ON -DPECLET_FLOW_MPI=ON -DMPIEXEC_EXECUTABLE=/usr/bin/mpirun
cmake --build build_dev -j 12
OMP_NUM_THREADS=8 OMP_PROC_BIND=false ctest --test-dir build_dev -R vof_bc_mpi_np2 --output-on-failure
```

Observed, deterministic to the digit over repeated runs (2026-09-14, 48-core Threadripper 5965WX,
OpenMPI, `host-openmp` Kokkos prefix):

```
VOF BC MPI np=2  grid 16x16x32  block 16x16x16  cut axes: z
  [slug-kin  np=2] colour vs single-rank 0.000e+00 (BITWISE required)
  [slug-kin  np=2] ledger vs single-rank 7.189e-13; global budget |sum(C) - ledger| 2.274e-13
  [jet-coupl np=2] colour vs single-rank 1.332e-15; pressure 14/400, max|div| 1.799e-08
  [packing   np=2] colour vs single-rank 3.174e-09; budget |d sum(eps_eff C) - ledger| 4.547e-11
                   (rel 1.228e-14); solid colour 0.000e+00; pressure 16/400
  [packing   np=2] FAIL — colour beyond the reduction floor (tol 1.0e-11)
```

Read that carefully, because three of the four lines are the control group:

- **slug-kin is BITWISE identical** at np=2. The kinematic path is decomposition-exact.
- **jet-coupl agrees to 1.3e-15.**
- **packing's conservation budget closes to 1.2e-14 relative** — mass is not being lost or gained.
- Only packing's *pointwise* colour disagrees, at 3.2e-9.

### The gate

`tests/kokkos_mpi/test_vof_bc_mpi.cpp:421` (and the identical one at :357 for the jet case):

```cpp
const double dc = maxAbsDiff(gc, ref.getVof());   // gathered np=2 field vs a single-rank rerun
...
const double tol = (size == 1) ? 0.0 : 1e-11;
if (!(dc <= tol)) { ... fail = 1; }
```

### The configuration that fails

`configurePacking`, `test_vof_bc_mpi.cpp:180`:

```cpp
static void configurePacking(IbmSolver& s, int ox, int oy, int oz, int lnx, int lny, int lnz) {
  s.setRho(1.0);
  s.setMu(0.5);
  s.setDt(0.1);
  for (int f = 0; f < 4; ++f) s.setDomainBc(f, 1, 0, 0, 0);
  s.setDomainBc(4, 2, 0.0, 0.0, 0.5);  // inflow at -z
  s.setDomainBc(5, 3, 0, 0, 0);        // outflow at +z
  s.setVelocityIterations(60);
  s.setPressureLevels(4);
  s.setPressureIterations(400);
  s.setSolid(packingSdf(ox, oy, oz, lnx, lny, lnz), true);
  s.enableVof();
  ...
```

**It sets no pressure tolerance**, so it runs on the solver default
`double pcgRtol_ = 1e-10;  // cut-cell pressure MG-PCG` (`src/flow_ibm.hpp:4284`).

The gate therefore demands `1e-11` from a colour field advected by a velocity whose pressure solve
stopped at a **1e-10** relative residual. The jet case, which passes at 1.3e-15, is the one that
*does* pin its tolerance explicitly — `s.setPressureFcg(true, 400, 1e-11)` at :152.

That asymmetry is the strongest clue on the table. It is a hypothesis, not a finding: 3.17e-9 is
~30x the pressure rtol, and why the amplification is 30x and not 1x is exactly the thing to
establish.

## 4. Constraints and invariants

- **Do not change numerics to make a test pass.** Suite standing directive; a change meant to be
  inert must be proved bit-identical at the old configuration, not assumed.
- np=1 must stay **exactly** decomposition-independent (`tol = (size == 1) ? 0.0 : ...`). Whatever
  happens above np=1, the np=1 branch keeps its zero.
- `slug-kin` must stay **bitwise** at every rank count. If a change to the VoF path perturbs that,
  the change is wrong.
- The conservation budget gate (`budget / g0 < 1e-10`) stays; it is currently passing at 1.2e-14 and
  is the check that would catch a real mass error.
- Geometric VoF on the collocated grid is rung V8 and the ghost projection v1 does not support it —
  the AUTO scheme falls back to gauge-exact and says so. That is expected, not part of this problem.

## 5. Settled, not open

- The suite's collocated pressure coupling is Almgren–Bell–Colella; **Rhie–Chow is rejected** and has
  been re-proposed by mistake three times. Not relevant to the fix, but do not wander there.
- This is **not** a 1.0.1 regression, and re-checking that is wasted effort. Proof: `git diff
  v1.0.0..v1.0.1` over flow's `src/`, `include/` and `tests/` is **empty** — 1.0.1 changed flow's
  CMake and packaging only. The binary that fails is, source for source, the 1.0.0 binary.
- flow's CI passes all 35/35 np≤2 MPI tests on this code, on a 4-CPU runner. The failure is
  environment-dependent, not intermittent: it is bit-reproducible on the 48-core box.

**Genuinely open:** whether the packing np=2 path has a real defect, and if not, what the gate
should say instead.

## 6. The precedent to follow (and to distinguish from)

flow `65b2b6a`, "vardensity_mpi: the V-cycle-count parity gate is exact at np=1, +/-1 above it",
widened a sibling gate. Read the commit in full — it is the model for how to change a gate here:

```cpp
// np=1 must be decomposition-independent EXACTLY. np>1 gets one V-cycle of slack, for the
// same reason utol and ptol get a floor there: the stopping test is `maxabs(r) < rtol*r0`,
// and at np>1 both sides of that come from a global reduction whose summation order is not
// the single-rank order. The count is a DISCONTINUOUS function of a quantity that already
// carries a reduction-order floor ...
const long itTol = (size == 1) ? 0 : 1;
```

**But note the difference.** That gate counts V-cycles — a discontinuous integer sitting on a
threshold. This one compares a continuous field. "Reduction order" explains a ±1 iteration count far
more readily than it explains 3.2e-9 in a field whose other two cases agree at 1.3e-15 and bitwise.
Do not reuse the argument by analogy; earn it or reject it.

## 7. The second, related failure

`vof_collocated_mpi_np2` and `_np4` fail on the same box at `OMP_NUM_THREADS=2` and **pass at 1, 4
and 8**:

```
[hydro-z np=2] du 1.264e-14 (|u| 3.479e-13)  duf 7.789e-15 (|uf| 1.871e-13)
               dP 2.728e-12 (|P| 1.150e+03)  dC 0.000e+00   d(iters) 2   *** FAIL ***
```

Every field agrees at round-off; only `d(iters)` differs. This one *is* 65b2b6a's shape, and
65b2b6a's own comment records that "the count sequence changes with the OpenMP THREAD COUNT alone at
fixed np=1". Likely the same fix, and cheap — but decide it on its own evidence, and note that a gate
which passes at 1, 4 and 8 threads and fails at 2 is a gate that will fail again on someone else's
machine.

## 8. How the answer will be verified

- `OMP_NUM_THREADS=8 OMP_PROC_BIND=false ctest --test-dir build_dev --output-on-failure -LE bench`
  — **155/155**. It is 154/155 today, and 151/155 at `OMP_NUM_THREADS=2`, so check both thread
  counts; a fix that is green only at one of them has not finished.
- `slug-kin` still bitwise; np=1 branches still exact; the budget gate untouched and still passing.
- If the conclusion is "the gate was wrong": the new tolerance is justified from the solver
  tolerance it sits on, in a comment of the kind 65b2b6a wrote, and the number is derived rather
  than fitted to today's 3.17e-9.
- If the conclusion is "the packing path is wrong": a test that fails before the fix and passes
  after, and an explanation of why CI's 4 CPUs hid it.

## 9. Deliverable

- The fix, or the gate change, in `flow`, with the reasoning in the commit message.
- An entry in `suite/docs/DECISIONS.md` + `docs/decisions/flow.md` if a gate's contract changes —
  that is a decision a later session could plausibly undo.
- Update `suite/docs/RELEASE_PREP.md` §11.4, which currently records this as open.

## 10. Out of scope

- The 1.0.1 release: it is done. Do not retag anything.
- VoF W4 (parked WIP on branch `vof-w4`, 32/33, G2 unmet) — unrelated campaign.
- The Windows/macOS wheel work of 1.0.1 (RELEASE_PREP §11.2, §11.3).
- Anything about the quick start, the container thread pool, or `cpu_budget`.
