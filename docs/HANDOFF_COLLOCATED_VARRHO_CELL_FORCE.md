# Handoff: collocated + variable density diverges under an axially varying cell force

Opened 2026-09-25. Owner: next session → `architect` design pass. Status: OPEN, not started.

## The question

Why does `SolverColocated` with variable density (rung V8, the face-acceleration path) blow up when a
per-cell body force varies **along its own axis**, and what should the design be instead? An answer
must say either "the V8 architecture is wrong for cell forces, here is the replacement" or "it is a
defect in the discretization, here is the fix", with the analysis that decides between them.

## The facts (measured 2026-09-25, flow `1fdee46`)

- **Repro:** `flow/tests/python/test_cell_force_placement.py`. It drives a Taylor–Green cell force at
  N = 16/32/64, and one of its cases is drag with β(x,y) and force = β·U0. It skips exactly
  `("collocated", True)` (`SKIP` at l.146). Removing that skip reproduces the failure.
- **Divergence:** u reaches 1e74 by step 100 at dt = 1, and it also grows at dt = 0.1. Every dt from
  0.1 to 100 was tried. It is not a CFL-type limit.
- **Selective:** a force varying only *across* its axis, e.g. f_x(y), is stable. A force varying
  *along* it, e.g. f_x(x), is not.
- **Other paths are fine** (all in the same test):
  - staggered, constant ρ: order 2.00;
  - staggered, variable ρ: order 2.00;
  - collocated, constant ρ: order 1.99, cell value reproduced to 5e-14.
- **Pre-existing:** the force-placement fix (`1fdee46`) did not change this path's arithmetic. The
  path was already a face mean.

## Current design of the path

`flow/src/collocated_varrho.hpp:70-89` builds the face acceleration, called from
`flow_ibm_project.hpp:644`:

```cpp
const double rf = haveRho ? 0.5 * (rho(i) + rho(i - s)) : rhoC;
const double f = fc + (haveFb ? 0.5 * (fb(i) + fb(i - s)) : 0.0) -
                 (incr ? wa * (P(i) - P((long)i - s)) : 0.0);
af(i) = dt * f / rf;
```

- Every force goes in as a MAC **face** acceleration, added after `centerToFace`.
- The cell velocity then takes the mean of the two face corrections: the same averaging operator
  that `projectCorrectCenter` applies to φ differences (`collocated_varrho.hpp:163`).
- CSF is added the same way (`addFaceAccelCsf`, balanced-force V4 pairing).
- Closed faces (o ≤ 1e-12) get af = 0.

### Leading suspicion, unverified

The cell velocity sees the average of the face accelerations, (a_{i-½} + a_{i+½})/2. That is a wide
stencil in the force's own direction. Together with the collocated projection's invisible
(checkerboard) subspace, it could feed a mode the projection cannot damp. See
`flow/doc/collocated_invisible_subspace.md` and the memory note on the collocated attractor
campaign.

A force varying across its axis never produces such a difference along that axis, which would
explain the selectivity. **Check this against the numbers before building on it.**

## Settled — do not relitigate (see `docs/DECISIONS.md`)

- The collocated coupling is the Almgren–Bell–Colella approximate projection. **Never Rhie–Chow.**
- **USER rule (2026-09-25):**
  - Volumetric forces go where the velocity is defined: the face mean on staggered, the cell value
    on collocated (`Grid::atVelocity`, `src/grid_layout.hpp:43-51,88-92`).
  - Surface forces use a finite-volume view: they are integrated over the control-volume faces.
  - Register entry: `docs/decisions/flow.md`, "volumetric forces at the velocity location".
- Balanced-force CSF on V8 (V4 pairing) must keep annihilating a constant-κ surface tension.
- **Never change numerics while restructuring.** The staggered paths, collocated constant-ρ, the
  state_hash cases and CFD-DEM (porous = True, which is staggered) must stay byte-identical.
- flow is the method reference. Read `flow/doc/` before designing.

## Open

- Is a volumetric cell force on collocated variable-ρ a cell-value source, as the user rule
  implies, or a face acceleration, as V8 does now? What does that do to V8's balanced-force
  property for pressure, gravity and CSF?
- Which terms stay face accelerations (pressure, CSF, hydrostatic), and which become cell sources?

## Verification

- `test_cell_force_placement.py` with the skip removed: order about 2 on collocated variable ρ, and
  the drag case at round-off.
- The full flow battery: 167/167, np8 last. Run with `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` and
  `--bind-to none`.
- The VoF/V8 gates in `docs/wo_vof_mpi_parity_gates.md`, and state_hash byte-identity outside V8.

## Deliverable

The architect writes a design note in `flow/doc/` covering:
- the root-cause analysis;
- the chosen design and the alternatives it rejects;
- work orders for `opus-implementer`, and the gates;
- a register entry.

It writes no production code.

## Out of scope

- The staggered paths.
- CFD-DEM coupling.
- gamma calibration.
- dem.
