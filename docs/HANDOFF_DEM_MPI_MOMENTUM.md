# Handoff: dem's distributed contact solve must conserve momentum across rank boundaries

Opened 2026-09-25. Owner: next session, which runs the `architect` design pass and then the
implementation. Status: first fix landed (dem 7074ee6..c771e07, pushed); **REOPENED** — see below. Design: `dem/docs/mpi_momentum_conservation.md`;
numbers: `dem/docs/momentum_evidence/AFTER.md`. Performance was measured at host load 55–60; a quiet-host
re-measure (`run_perf_ab.sh`) is still owed.

**STATE 2026-09-26 night (resume here).** dem main **77ba917** (pushed): the framework + WO-12
(0520b21), then the performance package, CI repairs and the follow-ups design note. Core 1.3.0 is
published. Evidence: `dem/docs/contact_evidence/AFTER.md` §1–§10.

**Done this round.**
- **Cost closed, bit for bit:** +9–17 % → **+2–6 %** against c771e07 (AFTER.md §10, `after12/`).
  The cost was host work: a serial host sort of every contact key in the unit build, a host sort of
  every gid in `mapVelocitySlots`, O(N_owned) owner kernels at every sync, and launch count.
  Byte-equal dumps in 29 scenes × np 1–8; battery 264/264 host and CUDA.
- **CI was red since f44fba7** (not only this work): clang-format (fixed, whitespace only) and core's
  rename `peclet.core.mpi` → `peclet.halo` (CI + Python MPI drivers moved). dem now pins the ctest
  launcher beside mpicxx: ParaView's mpiexec on PATH had made every np ≥ 2 ctest run singletons.
- **Coupling re-run** (dem 0520b21): host 22/22, nothing moved. The coupling tests never exercise
  the new contact solve (coverage gap). CUDA found a pre-existing race (coupling kernels on their
  own stream, flow's halo exchange unfenced): **fixed, coupling 63919cc** (a device-wide fence at
  entry and exit of every coupling wrapper; 0/30 bad runs, cost +0.9 %). Open: only 3 of coupling's
  ~10 test files are registered in ctest; flow raises `pressure_solve_failed()` when the PCG start
  residual is round-off (1e-48–7e-12) in the porous Ergun test (`mac_cutcell_mg.hpp:1221`); CUDA
  np 4 costs 480 ms/step against 13 at np 1 (probably 4 ranks sharing one GPU without MPS).
- **Architect design** `dem/docs/contact_physics_followups.md`:
  - Q-A: rigid 6-DOF multilevel aggregates, ΔL = 0 exactly.
  - Q-B: keep the position phase translation-only, with the consistent diagonal invM_A + invM_B.
    `ring_mini` never converged because the scene starts tunnelled (85/106 pairs infeasible even
    with rotation); new gate `ring_collide`.
  - F1: tube/box broad phase used the radius, not the bounding radius; end contacts were missed.
  - F2: one-way shell detection (open, R-B2).
  - Q-C: restitution-law options.

**Landed after (dem a96a14c, umbrella 1454d85, battery 291/291 host + CUDA):**
- WO-A1/A2: rigid multilevel aggregates, `hub_ml` dLvel 3e-3 -> 6e-7 (gated 1e-6); +19-25 %
  in opt-in multilevel mode.
- WO-B0: tube/box circumscribed `baseRadius` (coax tubes 0 -> 203 contacts; `pack_rings` reaches
  phi 0.342, where main reached 0.188), plus the Hertz sphere-radius fix it exposed.
- WO-B1: translational position diagonal. WO-B2: `ring_collide` gate.
- WO-C1: `sim.diagnostics.set_restitution_target('newton'|'moreau')`; the default stays Newton.
  The evidence is in `dem/docs/contact_evidence/restitution_law_ab.md`: the Dosta impact rebound
  moves -20 % under Moreau.
- Register +7.
- Worktrees removed. `dem-perfbase` (c771e07 plus a PERF_G patch, `build_pb`) is kept as the A/B
  baseline, and `dem-contacts` is stale (branch `contacts`).

**Queued candidates (USER 2026-09-26, not started):**
1. **Study: XPBD against Hertz for non-spherical collisions.** Drop cubes and tubes at several
   orientations and impact speeds, then compare effective restitution with input e under both
   engines.
   - The expectation to test: XPBD imposes e per contact point with the full rotational effective
     mass, so it returns e by construction. Hertz with shapes uses the translational m* in its
     dashpot, a fixed contact curvature and shell-density-dependent stiffness. It therefore
     over-dissipates eccentric impacts, like every mainstream code (multi-sphere, superquadric,
     LS-DEM).
   - This could be a small paper or gallery entry.
   - Hertz itself stays "as everyone does" (USER); no change to it.
2. **Walton–Braun hysteretic linear law** as a second law of the generalized `demStepForce` driver,
   beside Hertz–Mindlin. Its restitution is e = sqrt(k_load / k_unload), independent of geometry
   and mass for a single contact, which is why polyhedral codes use it. It needs a per-pair plastic
   overlap history (a carried float, like the Mindlin history).

**Waiting on the user:** the restitution law (Q-C; recommendation Moreau); R-B2 two-way shell
detection (recommended next package).

**Performance left:**
- the S14 extra velocity iterations (principled);
- the halo topology rebuilt every step at `verlet_skin = 0` (~2.5 ms/step at 157k np 4, host);
- the drift vote.
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
