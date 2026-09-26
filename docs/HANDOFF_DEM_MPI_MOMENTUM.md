# Handoff: dem's distributed contact solve must conserve momentum across rank boundaries

Opened 2026-09-25. Owner: next session, which runs the `architect` design pass and then the
implementation. Status: first fix landed (dem 7074ee6..c771e07, pushed); **REOPENED** — see below. Design: `dem/docs/mpi_momentum_conservation.md`;
numbers: `dem/docs/momentum_evidence/AFTER.md`. Performance was measured at host load 55–60; a quiet-host
re-measure (`run_perf_ab.sh`) is still owed.

**STATE 2026-09-26 (resume here).** Framework design: `dem/docs/contact_solve_framework.md`
(§1–§11, §12 session decisions S1–S18, §13 amendment; the evidence is in
`dem/docs/contact_evidence/IMPL_A.md`). Worktree `suite/dem-contacts`, branch `contacts`, pushed to
dem main at **5ffce63**.

**Landed work orders:**

| work order | content | commit |
|---|---|---|
| WO-0 | instrumentation | 3e9a870 |
| WO-1 | midpoint friction | 07114fb |
| WO-2 | mass-split Jacobi | 5c91df9 |
| WO-3 | per-pair position units + wall ids | 785d984 |
| WO-4 | complete colouring + hub copies (fixes the production colour race) | ca32026 |
| WO-4b | ω_pos = 1, coarse mass | 8b4a5f3 |
| WO-5 | rank-level mass splitting + a stop that includes consensus | 0ea32ba |
| WO-5b | world-frame inverse inertia in legacy friction | 4665e0f |

The battery passes 201/201 (python_mpi run). np 2–8 converge to np 1 at the float floor, with the
stops off. Conservation: dP ≤ 8e-7, ring dLvel ≤ 4e-8.

**Next:**
1. WO-6: rank-level X for the g = 0 one-shot. This also fixes the energy creation at rank faces
   from c771e07; the 3-body scene at e = 0.8 must give np 2 = np 1 = 0.2459.
2. WO-7: drift vote / `migrateToBlocks` / band (D4a).
3. WO-9: dem uses core `allImages` (D4b). Core efa9b0d is on core main; the 1.3.0 version bump
   7405577 sits on branch `images` in `suite/core-images`, and the PyPI publish is **awaiting USER
   OK**.
4. WO-10: gates, mutations, docs.
5. WO-11: evidence + perf. Then register entries (§10, §13.7), DECISIONS.md, pointer.

**Open for the user:**
- R-U4 (WO-12): an accumulated, retractable position projection. It changes every np 1 run with
  coupled contacts. np ≥ 2 residual overlap is 1.7–2.5 × np 1 at the adaptive stop.
- The core 1.3.0 publish, and the peclet-core shell's DeprecationWarning wording.

**Deferred follow-ups:**
- S17: the multilevel coarse cycle is translation-only, so angular momentum is lost (np 1 too;
  opt-in mode). It needs a rigid-body aggregate design.
- The serial PGS restitution target of 0 on separating contacts creates energy (+6 % at e = 0.9).
- The position-phase effective mass uses body-frame rotational terms although the rotation is never
  applied (`solver_position.hpp` `computeW`). Found 2026-09-26; not investigated.

**Status 2026-09-25 evening: REOPENED as a framework redesign** (USER: "It feels that we are trying to
patch this issue while it needs a rigorous design. Think of a principled method ... implementation plan.
Take performance also into account. Test it well"). Documentation is on dem main e90caff:
- `dem/docs/contact_evidence/FOLLOWUPS.md` — four defects reproduced, with report-only ctests (3e72ad5).
- `dem/docs/contact_evidence/review/review_momentum.md` — the independent review of c771e07.
- `dem/docs/contact_evidence/ARCHITECT_BRIEF.md` — the brief for the framework design.

**Defects, most severe first:**
1. **Colour overflow: a race in PRODUCTION defaults.**
   - Five colourings cap at 63 colours, so contact 64 and up at a body reuse colour 62. The fallback
     is dead.
   - Ring beds: 79–613 contact points per particle, 1240–6439 same-colour pairs per step in the
     position phase.
   - Sphere beds reach it at size ratio ≥ 6.
   - CUDA dP is 1–4e-2.
2. **Energy creation at rank faces: a regression in c771e07** (review, CONFIRMED).
   - The one-shot g = 0 restitution sweep never retracts, so owner-exclusive solves add up on a face
     body.
   - 3-body KE at e = 0.8: np 2 gives 0.555, np 1 gives 0.246, and before c771e07 it was 0.340.
   - The PGS (gravity) path is fine.
3. **Pairs no rank sees.**
   - (a) Drift with `rebalance_every=0`, which is the step_mpi default: a pair is lost once both
     bodies are more than 1.857 R past their blocks, at np ≥ 4.
   - (b) core's halo sends one periodic image per (particle, rank), so an undecomposed periodic axis
     loses edge-wrap pairs: np 2 loses 2, np 4 loses 3.
4. **No gate detects a dropped contact** (review, confirmed by mutation). The ovl metric counts owned
   contacts only.
5. **Legacy friction couple.** ±J_t is applied at two points, so ΔL = dist·n × J_t (ratio 1.000).
   Reached by g = 0 runs with friction. The PGS cone is clean.
6. **Per-body Jacobi factors** are non-conserving serially (np 1 dP 9e-3). Not reached from defaults.

**Proposed principle, under test by the architect:** one owned impulse per contact, with bodies always
v0 + M⁻¹Jᵀλ, plus mass splitting (m/k, I/k) and mass-weighted consensus averaging at syncs. The same
mechanism covers rank faces, colour-overflow hubs and the Jacobi paths. It conserves momentum, cannot
create kinetic energy (Jensen), and its fixed point is the coupled solution. It also needs:
- a single application point per contact;
- visibility guaranteed by band = reach + skin, with drift-vote migration and ghosts keyed by
  (gid, image shift).

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
