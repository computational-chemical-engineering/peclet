# Paper ideas using the peclet suite

A living register of scientific papers the suite could carry. It holds one entry per idea, **rewritten
in place, not appended**. Each entry gives the claim, why peclet can make it, the evidence that
already exists, the missing experiments, and a status.

- A plan that grows past a few paragraphs moves to its own file, like
  `flow/doc/collocated_paper_plan.md`, and the entry here points to it.
- The software paper itself is `docs/paper/` (JOSS), and is not repeated here.

**Status vocabulary:**
- **idea**: not started.
- **evidence**: results exist, no paper plan yet.
- **plan**: a paper plan exists.
- **drafting**, **submitted**, **published**.

Seeded 2026-09-26 at the user's request. The entries marked *seeded* were reconstructed from session
notes; check each one's evidence before building on it.

---

## 1. Restitution of non-spherical particles: impulse (XPBD) against soft-contact DEM

- **Status:** idea (USER 2026-09-26).
- **Claim.**
  - The impulse method, with contact-point restitution and a Moreau-simultaneous impact law,
    returns the specified coefficient of restitution for non-spherical particles by construction,
    at any orientation and impact speed.
  - Soft-contact models only approximate it:
    - Hertz–Mindlin with point springs, as in multi-sphere, superquadric and level-set DEM;
    - the Walton–Braun hysteretic linear model.
  - Hertz–Mindlin over-dissipates eccentric impacts, because its dashpot uses the translational
    reduced mass, not the rotational effective mass. It also depends on the assumed contact
    curvature and on the shell density.
  - Walton–Braun fixes e for a single contact but not for multi-point contacts.
  - So for non-spherical particles, XPBD is the more accurate method as well as the cheaper one.
- **Why peclet.** One code runs all three laws on the same geometry, shells, SDFs and time
  integration:
  - XPBD with Moreau (dem, the default from 2026-09-26);
  - `step_hertz` (the `demStepForce` driver);
  - Walton–Braun (to be added as a second law of that driver).
- **Experiments.**
  - Single-body drops and binary collisions: cube, hollow cylinder, box, a grid-SDF shape.
  - Sweep orientation (centric to eccentric), impact speed and input e.
  - Plot output e (normal velocity at the contact point, and body-level energy) against input e.
  - Then a bulk consequence: packing density or a rotating drum of tubes, to see whether the
    single-contact differences matter in bulk.
  - Wall time per simulated second for each law, at the time step each allows.
- **Parameter mapping** (so the comparison is like for like):
  - XPBD takes Walton's (1993) three-parameter impact law: e, μ, and the tangential restitution β₀.
  - Walton–Braun takes k_load/k_unload = e², μ, and the tangential k_t/k_n. In soft models β₀
    *emerges* from k_t/k_n and the tangential damping; for Hertz–Mindlin k_t/k_n = 2(1−ν)/(2−ν).
  - Comparing the emergent β₀ with XPBD's imposed β₀ on oblique impacts (spin reversal) is part of
    the result.
  - Walton–Braun is implemented in its common-practice form: hysteretic normal, plus the Mindlin
    history spring with a Coulomb clamp and a single μ. The original softening-tangential form and a
    separate μ_s/μ_k are optional variants.
- **Prerequisites:**
  - the Walton–Braun law;
  - optionally the effective-mass dashpot for Hertz, as a variant, not a default;
  - two-way shell detection (dem, in progress) for thin-walled shapes.
- **Pointers:** `dem/src/solver_hertz.hpp` (the point-spring Hertz and dashpot weighting);
  `dem/docs/contact_physics_followups.md` §4 (the restitution laws); `suite/docs/HANDOFF_DEM_MPI_MOMENTUM.md`
  (the queued candidates).

## 2. Momentum-conserving distributed impulse DEM

- **Status:** evidence (*seeded*).
- **Claim.**
  - Domain-decomposed impulse (XPBD/PGS) DEM loses momentum and can create energy at rank faces
    unless every body that is updated in several places is solved through copies.
  - The copies need mass splitting for projection phases and exclusive holding for the one-shot
    restitution sweep, with complete colouring and guaranteed contact visibility.
  - With these the method conserves momentum at the float floor and is rank-count independent.
  - It costs 2–6 % over the non-conserving scheme.
- **Evidence:**
  - `dem/docs/contact_solve_framework.md` (design);
  - `dem/docs/contact_evidence/AFTER.md` §1–§10 (conservation 1e-8, np 1–8 energy equal to np 1,
    visibility oracles, mutation controls, cost).
- **Missing:**
  - a literature position against other parallel NSCD/PGS codes (Siconos, Chrono, LMGC90);
  - a scaling run on many GPUs.

## 3. Event-level (Poisson) restitution for rigid-contact DEM

- **Status:** evidence (*seeded*).
- **Claim.** Rigid-contact DEM under-returns energy in chain-loaded impacts and drives rotating
  drums too weakly. A per-pair event bank of compression impulse, with per-body orphan accounts for
  contacts that die, recovers soft-sphere reference behaviour: drum circulation amplitude and silo
  discharge at the level of MUSEN/LIGGGHTS. It is opt-in, because it costs per step (USER directive
  2026-09-26).
- **Evidence:**
  - memory `dem-event-level-restitution`;
  - the Dosta 2024 benchmark runs (`~/Codes/dem-bench/peclet/`).
- **Missing:**
  - the open 100k-impact softening;
  - an energy bound;
  - the interaction with Moreau targets.

## 4. Impulse DEM against Hertz codes on the Dosta 2024 benchmark set

- **Status:** evidence (*seeded*); gallery entry `peclet-examples/benchmarks/dem-bulk-dosta2024`.
- **Claim.** An impulse DEM matches Hertz–Mindlin codes (MUSEN, LIGGGHTS) on silo discharge, drum
  mixing and impact penetration, at 2.5–77× lower wall time. The paper would name where it cannot
  match (floor-limited rebound) and why.
- **Missing:** a re-run on the final solver (framework, Moreau), with scatter.

## 5. Steady-state attractor families in collocated cut-cell approximate projections

- **Status:** plan: `flow/doc/collocated_paper_plan.md` (the tracker lives there).

## 6. GPU dynamic Voronoi tessellation of moving particles

- **Status:** evidence (*seeded*); memory `voronoi-methods-plan`, `docs/studies/voro_update_throughput.md`.
- **Claim.** A dual-triangle ConvexCell engine with incremental repair builds and updates 3D
  Voronoi and power tessellations at 14–17 M cells/s. Repair reaches 80 % weak efficiency at 4
  GPUs, periodic and Lees–Edwards boxes included.
- **Missing:** a comparison with state-of-the-art GPU Voronoi codes, and the method derivation
  document (deferred by the user).

## 7. Massively parallel cut-cell Stokes/Navier–Stokes through packed beds

- **Status:** evidence (*seeded*); Zenodo 10.5281/zenodo.22828093 (peclet 1.1.0 scaling deposit);
  `docs/SCALING_ISSUES.md`; memory `comm-scaling-plan`, `porous-scaling-benchmark`.
- **Claim.** A cut-cell IBM with MG-PCG on an ORB decomposition reaches 64 % weak efficiency at 32
  H100s and 1.81 G cells, with permeability accurate to 0.1 % against the Zick–Homsy class of
  references.
- **Missing:** the multigrid-depth cap and float operator-storage issues (SCALING_ISSUES top two),
  and a positioning against other porous-media DNS codes.
