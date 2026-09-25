# Handoff: dem's distributed contact solve must conserve momentum across rank boundaries

Opened 2026-09-25. Owner: next session, which runs the `architect` design pass and then the
implementation. Status: **DONE 2026-09-25** (dem 7074ee6..c771e07, pushed). Design: `dem/docs/mpi_momentum_conservation.md`;
numbers: `dem/docs/momentum_evidence/AFTER.md`. Performance was measured at host load 55–60; a quiet-host
re-measure (`run_perf_ab.sh`) is still owed.

**Follow-ups found on the way (not fixed, each needs its own work order):**
1. **Colour overflow (correctness, likely a race):** both colourings put every contact beyond a body's
   62nd into colour 62. A body with more than 63 contacts then has several same-colour contacts, i.e.
   concurrent read-modify-write on multi-thread/GPU. The stall-break fallback never fires. This comes
   from reading the code; there is no reproduction yet.
2. **Legacy friction lever-arm couple:** `solveContactFrictionKokkos` applies ±J_t at two surface
   points δ apart, so ΔL = δ n × J_t per contact. Serial dLvel is 1.9e-5. The fix changes np = 1.
3. **The count-averaged Jacobi paths** (`velocityUseGS=false`, and the GS fallbacks) use per-body
   factors, so they are momentum non-conserving even serially (np 1 dP 9e-3). They are gated at the
   serial level only.
4. **Pairs no rank sees:** both ends drifted out of their owners' blocks with `rebalance_every=0`.
   Also, in a strongly jittered periodic box, np 2/4 lose 2–3 corner-wrap pairs. A missed contact is
   an interpenetration.

## The user's decisions (2026-09-25, verbatim)

- "That momentum is not conserved is not acceptable. This should be solved."
- "That DEM is not reproducible, on the level of roundoff errors, on multi threaded architectures
  this is not an issue for me."
  - So conservation is required to round-off.
  - Bitwise reproducibility across thread counts, thread schedules or the GPU is NOT required.
  - Do not sort contacts just to get bitwise reproducibility.

## The defect

The distributed XPBD step (`dem/src/step_solve_mpi.hpp:24-32`, `MpiSolveHooks`) is a
processor-block Gauss–Seidel.

- Colouring and sweeps are rank-local over owned + ghost bodies.
- A contact between bodies on two ranks is **solved redundantly on both owners**. Each rank keeps
  only its own body's update, and the ghost copy is overwritten at the next refresh.
- Owner A sweeps contact (p,q) in A's state, and owner B sweeps it in B's state. The states differ,
  because each rank has already swept other contacts in its own order. So the impulse applied to p
  is not the negative of the one applied to q.
- Result: **linear momentum (and angular momentum) is not conserved at rank boundaries.**
- This holds for both the velocity solve (restitution/PGS/friction) and the position (overlap)
  projection. It is the same mechanism in each.

**Measured** (2026-09-25, dem `c64e117` investigation):
- Scene: the 3-body chain p–q–s in `tests/kokkos_mpi/test_ghost_band_mpi.cpp`, mode `margin`
  (l.186).
- When q's owner sweeps q–s before q–p, **the whole chain's centre of mass shifts rigidly by
  2.1e-2 in one step**. Every pair still touches exactly. The serial reference conserves the
  centre of mass to round-off.
- The sweep order came from OpenMP thread order in the narrow phase. With several threads,
  2 of 8 runs at np 2 and 2 of 8 at np 4 showed it; at 1 thread, 0 of 8.
- The ctest now pins one thread (`c64e117`). **That pin hides the symptom, not the defect.**
  Remove it once conservation holds.

`dem/docs/mpi.md:69-72,89-96` calls agreement with single-rank "statistical"
(N=200: mean 5e-3, max 0.11). That is acceptable as a *trajectory* difference. Non-conservation is
not acceptable. The doc never mentions it; fix the doc too.

## Settled — do not relitigate (see `docs/DECISIONS.md`, `docs/decisions/dem.md`)

- **Local particle order is canonical** (ascending source rank), never MPI arrival order
  (dem `f7b7b22`). np 4 and np 8 are bitwise run-to-run reproducible at 1 thread. Keep that.
- **Keep the modern solver stack.** The distributed step drives the SAME modern stack as
  single-GPU (`demSolveContacts`, `src/solve_driver.hpp:239`):
  - colored GS restitution;
  - warm-started PGS with **gid-keyed** persistent contacts;
  - statics/stabilization;
  - friction cone;
  - adaptive stops, Allreduce-MAXed.
- Do not revert to count-averaged Jacobi as the whole solver. A conservative Jacobi-type treatment
  of **cross-rank contacts only** is a legitimate candidate.
- Every method on-device and MPI-distributable. No host serial production path.
- Deadlock fixes stay: one-sided halo, global skin vote, ghost band max(rcut, 2.1 R_max global),
  and the empty-rank vote. `enable_mpi_step(sync_every=M)` semantics stay.
- The rebalance/migration contact ledger (`MigratePack`) stays gid-keyed.

## Open — for the architect

How is each cross-rank contact given ONE impulse, applied equal and opposite to both bodies,
without losing Gauss–Seidel convergence or adding a sync per contact? Candidates to weigh, not
prescribed:
1. **Single owner per cross-rank pair.** For example, the rank owning the lower gid computes the
   impulse and sends −J to the partner's owner, accumulated like a force.
2. **Globally consistent colouring of the interface contacts.** Both sides then sweep them in the
   same colour from the same refreshed state.
3. **Interface contacts solved Jacobi-style**, symmetric by construction, with interior contacts
   kept GS.

The design must also cover:
- angular momentum: friction impulses at an offset;
- positions: the overlap projection;
- the force-based Hertz–Mindlin engine (`step_hertz_mpi`, `src/solve_driver_force.hpp`). Check
  whether it is already pairwise-symmetric. It should be, if both owners evaluate the same pair
  from the same synced state; prove it or fix it.
- cost per substep (messages, syncs) against today's.

## Verification the result must pass

- **New gates** at np 2, 4 and 8, and at 1 and 8 OpenMP threads:
  - total linear momentum and centre-of-mass drift of a closed, force-free system to round-off
    (relative ≲ 1e-6 in float);
  - angular momentum with friction;
  - the p–q–s chain;
  - a random dense cluster straddling rank corners.
- **Existing gates:**
  - the dem battery (78 ctests, `align_np8` last). Build with
    `-DMPIEXEC_PREFLAGS="--bind-to none"`, with a SPACE: dem runs `separate_arguments`, so
    `--bind-to;none` breaks every MPI ctest.
  - the 12 `python_mpi_*` tests, which need `PYTHONPATH` to include core's Python build (they SKIP
    otherwise);
  - np 4/8 bitwise run-to-run at 1 thread.
- **Remove the single-thread pin** on the `ghost_band_*` ctests (`c64e117`) and show them stable at
  8 threads.
- **np 1 unchanged, bitwise.** Say explicitly if np 2 changes; it is allowed to, because this
  changes numerics.
- **Coupling (CFD-DEM):** run coupling's MPI tests (Ergun, moving suspension) and report deltas.
- **Performance:** ms/step at N=20000 periodic, np 4 and np 8, before and after. Pin each rank
  with `taskset`, and state the host load.

## Deliverables

1. A design note by the `architect` in `dem/docs/`, committed, with:
   - the root cause;
   - the chosen scheme and the rejected ones;
   - work orders;
   - the gates above.
2. The implementation, in the sibling worktree `suite/dem-momentum`.
3. The updated `dem/docs/mpi.md` and `dem/CLAUDE.md` trap text.
4. A register entry in `docs/decisions/dem.md`. The earlier entry "ghost_band_* ctests run on one
   host thread" gets `status: superseded`.
5. The umbrella pointer bump, with `DECISIONS.md` regenerated
   (`python3 docs/decisions/build_index.py`) and the count in `CLAUDE.md` updated.

## Out of scope

- Bitwise reproducibility with threads or on the GPU.
- gamma calibration.
- flow.
- The collocated variable-density issue (`docs/HANDOFF_COLLOCATED_VARRHO_CELL_FORCE.md`).
