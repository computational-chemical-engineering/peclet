# peclet.coupling — unresolved point-particle CFD-DEM

Two-way coupling of `peclet.flow` (Eulerian fluid) and `peclet.dem` (Lagrangian particles) for
dilute-to-dense point-particle suspensions and packed beds. Multiphysics Phase 6 — see
`../docs/MULTIPHYSICS_PLAN.md`.

## Design

Physics-free glue. The compute kernels (particle↔grid deposition, drag laws, momentum feedback) live
in the `_coupling` nanobind extension and run **in place** on the arrays the two solvers already
expose — the fluid grid fields zero-copy through `flow.field_view(...)`, the particle drag
round-tripped through the dem host API. **There is no C++ link between flow and dem**: the Python
`CfdDem` driver (`python/peclet_coupling/driver.py`) composes them. This mirrors the suite's
architecture (Python is the composition layer).

Per fluid step (`CfdDem.step()`):
1. **Void fraction** — scatter each particle's volume onto the grid (trilinear), periodic-fold the
   ghost deposits, and `ε = clamp(1 − Vsolid/Vcell)`.
2. **Drag + feedback** — gather the fluid velocity and ε at each particle, evaluate the drag law
   (Stokes / Schiller–Naumann / Ergun / Di Felice), write the drag force to the particles and deposit
   the reaction onto the fluid momentum source.
3. **Advance** — apply the drag to the particles and sub-step dem `dem_substeps` times (drag held
   constant), then advance the fluid one step (its RHS/operator now carry the feedback).

### Implicit drag (the key stability piece)

An explicit reaction force `−β(u−u_p)` in the fluid RHS **diverges** for the stiff drag coefficient
β of a dense bed (β·dt/ρ ≫ 1; local β reaches ~10³). So the default feedback is **semi-implicit**:
the coupling deposits the linear-drag *coefficient* density onto flow's `drag_beta` field (added to
the momentum diagonal by `flow.enable_drag()`) and the target `β·u_p` onto `force_*` (the RHS), so
the fluid solve becomes `(ρ/dt + β)u = … + β u_p` — unconditionally stable for any β. The particle
side stays explicit (fine for moving particles at moderate β). `implicit_drag=False` selects the
explicit `−F/Vcell` feedback (dilute only).

### Scope (v1)

- **Model B** (drag-only): ε enters the drag correlation, not the fluid continuity/momentum
  (no porous-media source terms). Valid dilute→moderate; the fixed-bed Ergun ΔP still closes via the
  feedback.
- Single rank. Periodic ghost fold/fill is done in NumPy on the padded buffers; the shared
  decomposition + add-reduce halo for MPI is Phase 7.
- Deposition uses `atomic_add` ⇒ results are tolerance-, not bit-exact.

## Validation (`tests/`, host-openmp)

- **`test_terminal_velocity.py`** — single settling sphere: the slip velocity matches Stokes to
  **0.10 %** and Schiller–Naumann to **1.4 %** (the lab-frame speed is ~2× the slip because the
  particle drags its own Stokeslet flow, so the physical comparison is the slip).
- **`test_fixed_bed_ergun.py`** — uniform fixed bed (one particle per cell, ε = 0.6): the measured
  (f_drive, U) pair lands on the Ergun curve to **0.0 %** across the viscous, transition and inertial
  (Re_p ≈ 6) regimes — validating ε deposition, both Ergun terms, and the stable two-way feedback.
- P2G/G2P conservation + the gather/scatter adjoint identity: `core` `test_particle_grid`.

## Build

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/host-openmp"
cmake --build build -j        # -> build/peclet/coupling/_coupling.*.so
# run the tests (all three build trees on PYTHONPATH):
PYTHONPATH="$PWD/build:$PWD/../flow/build:$PWD/../dem/build" \
  python tests/test_fixed_bed_ergun.py
```

## Follow-ups

Model-A porous terms (dense fluidization); kernel-width (vs trilinear) deposition smoothing; the
Phase-7 MPI path (shared `BlockDecomposer` + `GridHalo::exchangeAdd` for ghost-layer deposits); CUDA
validation of the zero-copy device path.
