# peclet.coupling — CFD-DEM coupling

Two-way coupling of `peclet.flow` and `peclet.dem`: the unresolved point-particle driver `CfdDem` (void fraction, drag laws, semi-implicit feedback) and the resolved cut-cell driver `ResolvedCfdDem` (hydrodynamic force/torque reaction on scene particles).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.coupling`

peclet.coupling — CFD-DEM coupling, unresolved and resolved.

Composes peclet.flow (Eulerian fluid) + peclet.dem (Lagrangian particles).

CfdDem is the UNRESOLVED point-particle driver: a grain is a point with a drag closure, and the
compute kernels (particle<->grid deposition, drag laws, momentum feedback) live in the _coupling
extension, running in place on the arrays the two solvers expose (zero-copy grid fields; particle
forces round-tripped through the dem host API).

ResolvedCfdDem is the RESOLVED driver (Layer 4 of suite/docs/archive/ANALYTIC_SDF_GEOMETRY.md): each grain
IS an analytic SDF instance in the flow solver's scene, the fluid resolves its surface, and the
coupling is a surface-traction exchange with no drag correlation in it. Pure Python -- it needs no
compiled kernels of its own.

### `CfdDem`
Unresolved point-particle CFD-DEM coupling of a `peclet.flow.Solver` and a
`peclet.dem.Simulation` (see the module docstring for the physics and the per-step algorithm).

This docstring documents the constructor.

Parameters
----------
flow : peclet.flow.Solver
    The Eulerian fluid solver. Its cell size and lower corner (`flow.spacing` / `flow.origin`)
    fix the physical units of the whole coupling: a solver built with `Solver(cells,
    extent=...)` couples in physical units, one built without `extent` couples in the
    historical cell units (spacing 1, origin 0). `flow.spacing` must be isotropic (equal on all
    three axes) -- an anisotropic solver raises `ValueError` at construction, because an
    unresolved particle's drag law needs one length scale.
dem : peclet.dem.Simulation
    The Lagrangian particle simulation; `dem.num_particles` is this rank's OWNED particle count
    under MPI.
fluid_dt : float
    The fluid time step, in the flow solver's own units (physical time if `flow` was built with
    `extent=`, otherwise cell time). DEM advances `dem_substeps` sub-steps of
    `fluid_dt / dem_substeps` each, holding the drag constant over them.
mu : float
    Fluid dynamic viscosity, in the caller's consistent unit system (the same system `flow`
    itself uses).
rho : float
    Fluid density, in the same unit system as `mu`.
radius : float or array_like
    Particle radius: a scalar (every particle shares it) or a per-particle array of shape
    `(N,)`, `N = dem.num_particles`, in the same physical length units as `flow.spacing`.
drag : str, default "schiller_naumann"
    The drag law: one of `"stokes"`, `"schiller_naumann"`, `"ergun"`, `"di_felice"`,
    `"wen_yu"`, `"gidaspow"`, `"beetstra"`, `"tang"`.
dem_substeps : int, default 20
    Number of DEM sub-steps per fluid step.
eps_min : float, default 0.25
    Void-fraction floor: a physical regularisation (voidage does not physically fall below
    random-close-packing values), not only a guard against numerical particle interpenetration.
smooth_length : float, default 0.0
    Physical width of the void-fraction (porosity) diffusion filter; `0.0` disables smoothing.
    A warning is raised if it is left too small relative to the particle diameter and the
    fluid cell (see the source for the threshold).
periodic : tuple of bool, default (True, True, True)
    Per-axis periodicity, used when folding/filling the deposit and reaction-force ghost
    layers.
move_particles : bool, default True
    If `False`, the bed is fixed: DEM dynamics are skipped and only the fluid is
    stepped/coupled.
implicit_drag : bool, default True
    If `True`, drag enters the fluid momentum equation's diagonal (`flow.enable_drag()`) --
    stable for stiff (dense) beds. If `False`, drag is applied as an explicit fluid reaction
    force (`flow.enable_cell_force()`).
porous : bool, default True
    If `True` (the suite default), the void fraction enters the volume-averaged fluid
    continuity and momentum equations, `d(eps)/dt + div(eps u) = 0`, not only the drag closure.
    `porous=False` solves plain incompressible Navier-Stokes with `eps` only in the drag term --
    a cheaper approximation for dilute/steady beds, not a faithful CFD-DEM and never for a
    published comparison.
advection : bool, default True
    If `True`, gas convection is on (implicit first-order-upwind plus explicit
    deferred-correction TVD). If `False`, the gas is Stokes-like: drag, viscous and pressure
    terms only, with no inertia.
gravity : tuple of float, default (0.0, 0.0, 0.0)
    Constant physical acceleration applied to the particles every DEM sub-step, and used by the
    stiff-safe drag cap's gravity-exact correction.

Raises
------
ValueError
    If `flow.spacing` is anisotropic.

| Method / property | Description |
|---|---|
| `compute_forces` | Evaluate the drag law at each particle and scatter its momentum reaction onto the fluid.  Must be called after `update_void_fraction(pos)` for the same `pos` -- it reads the void fraction that call deposits (`self._eps`). Exchanges the velocity fields' ghosts, gathers the fluid velocity and void fraction at each particle (wall-masked by the SDF), evaluates the selected drag law (`drag`, with the stiff-safe exponential-integrator cap when `move_particles` is `True`), and:    - writes the per-particle drag force (readable via `last_drag`);   - if `implicit_drag`, adds the linearised drag coefficient into the fluid's `drag_beta`     field (the momentum-diagonal term); otherwise adds the explicit reaction force directly     into the fluid's `force_x`/`force_y`/`force_z` fields;   - always folds the `force_x`/`force_y`/`force_z` momentum-feedback fields (`-F / Vcell`)     onto the owning fluid cells, across periodic images or MPI ranks;   - interpolates the fluid velocity at each particle and sets `last_slip` to it minus `vel`.  Parameters ---------- pos : array_like, shape (N, 3)     Particle positions in the flow solver's INTERNAL (index/cell) coordinates, as returned     by `self._particles()`. `N` is the number of particles this rank currently owns (`0` is     valid under MPI). vel : array_like, shape (N, 3)     Particle velocities, in the same internal (index) units as `pos`.  Returns nothing; results are read back from `last_drag` and `last_slip`, and the fluid's momentum fields now carry the feedback for the next `flow.step()`. |
| `last_drag` | The drag force on each particle from the most recent `compute_forces` call.  A host NumPy array of shape `(N, 3)`, `N` the number of particles this rank owns, in the caller's physical force units (identical to the internal value on a cell-unit solver). Reflects only the most recent step; copy it if you need to keep values across steps. |
| `last_slip` | Interpolated fluid velocity minus particle velocity from the most recent `compute_forces` call -- the relative (slip) velocity the drag law evaluated.  A host NumPy array of shape `(N, 3)`, `N` the number of particles this rank owns, in the caller's physical velocity units (identical to the internal value on a cell-unit solver). `None` if `compute_forces` has never been called (e.g. before the first `step()`). Reflects only the most recent step; copy it if you need to keep values across steps. |
| `rebalance` | Dynamic co-rebalancing (multi-rank only). Build ONE weight field over the global grid -- fluid work (1 per cell) + gamma * particle count -- and redistribute BOTH codes onto the same weighted ORB from it: the flow state via diagnostics.rebalance_by_weights (bit-exact migration + rebuild), the particles via migrate_to_weights. Because both build the SAME deterministic partition from the same array, they stay co-located. Call at a step boundary. No-op single-rank. |
| `slip` | Interpolated fluid velocity minus particle velocity (N,3) — what the drag law sees. `vel` may be host or device; returns a host NumPy array for convenient inspection. |
| `step` | Advance the coupled fluid + particles by one fluid time step `fluid_dt`.  In order: under MPI with `move_particles`, migrate DEM ownership onto the fluid's current block decomposition; gather particle positions/velocities; deposit particle volumes and update the void fraction (`update_void_fraction`); on the very first call with `porous=True`, seed the previous-step porosity so the first step sees no spurious `d(eps)/dt` (`flow.sync_porous_prev()`); evaluate drag and scatter the momentum feedback onto the fluid (`compute_forces`); if `move_particles`, write the drag into DEM's external force buffer and advance DEM `dem_substeps` sub-steps (drag held constant over them); finally advance the fluid one step.  Takes no arguments and returns nothing; results are read back afterwards from `last_drag`, `last_slip` and `last_eps`. |
| `update_void_fraction` | Deposit particle volumes onto the fluid grid and derive the void fraction `eps`.  Each particle's volume (from `self._rad`, radii already scaled to cells) is spread onto the grid's fluid corners with a wall-aware (SDF-masked), trilinear deposit into the padded `solidvol` buffer -- a registered flow field when `porous=True` or under MPI, otherwise standalone scratch. Ghost-layer deposits are then folded back onto owned cells (periodic wrap, or the MPI reverse halo plus a same-side fold at non-periodic domain faces); if `smooth_length > 0` the folded deposit is diffused to that physical filter width. The void fraction is `eps = 1 - solidvol / Vcell`, floored at `eps_min`; its ghost layer is filled (periodic wrap / MPI halo, with zero-gradient at non-periodic domain faces) and the whole padded buffer is clipped to `[eps_min, 1]` (ghost extrapolation can otherwise overshoot it).  Calling this with `pos.shape[0] == 0` is valid under MPI -- a rank may own no particles -- and still runs the halo collectives so every rank stays in lockstep.  Parameters ---------- pos : array_like, shape (N, 3)     Particle positions in the flow solver's INTERNAL (index/cell) coordinates, as returned     by `self._particles()` -- not the caller's physical coordinates.  Returns nothing. Sets `self._eps` (read by `compute_forces`, and copied to `self.last_eps` by `step()`) to the updated void-fraction field. |

### `ResolvedCfdDem`
Resolved (geometry-resolving) CFD-DEM coupling of a `peclet.flow.Solver` scene and a
`peclet.dem.Simulation` (see the module docstring for the physics: cut-cell IBM, the
hydrodynamic-load exchange, the reaction-vs-traction force choice, and the torque
validation/caveat).

This docstring documents the constructor.

Parameters
----------
flow : peclet.flow.Solver
    The Eulerian fluid solver; each grain becomes an analytic sphere instance in its scene
    (`set_scene` / `set_solid_from_scene`). Units are a pure identity with `dem`: a solver built
    with `Solver(cells, extent=...)` couples in the caller's own physical coordinates, one built
    without `extent` couples in cells.
dem : peclet.dem.Simulation
    The Lagrangian particle simulation. `dem.num_particles` fixes the grain count `self.n` for
    the life of this driver.
radius : float
    The single sphere radius shared by every grain (one `kSphere` node is installed for all
    instances), in the same length units as `flow`'s scene.
mu : float
    Fluid dynamic viscosity, in the caller's unit system (passed straight through to `flow`,
    with no conversion).
rho : float
    Fluid density, in the same unit system as `mu`.
fluid_dt : float
    The fluid time step, passed straight to `flow.set_dt`. DEM advances `dem_substeps`
    sub-steps of `fluid_dt / dem_substeps` per fluid step, holding the fluid force (and torque)
    constant over them.
dem_substeps : int, default 20
    Number of DEM sub-steps per fluid step.
periodic : tuple of bool, default (True, True, True)
    Per-axis periodicity `(bx, by, bz)`. The flow scene supports only an all-periodic or an
    all-non-periodic box; a mixed triple raises `ValueError`.
gravity : tuple of float, default (0.0, 0.0, 0.0)
    Physical acceleration used, together with `rho_p` and `buoyancy`, to add each grain's net
    gravitational/buoyant force to the hydrodynamic force before handing it to DEM.
rho_p : float, optional
    Particle density. If `None` (the default), no gravity/buoyancy force is added by this
    driver -- only the hydrodynamic force/torque is passed to DEM.
move_particles : bool, default True
    If `False`, the scene is installed once at construction and never rebuilt or moved, and DEM
    is never stepped or given forces/torques; only the (static) hydrodynamic load is computed
    each `step()`.
buoyancy : bool, default True
    If `True` and `rho_p` is given, only the net buoyant force `(rho_p - rho) * V * gravity` is
    added, on the assumption that the fluid's pressure field already carries the hydrostatic
    part. If `False` and `rho_p` is given, the full body force `rho_p * V * gravity` is added
    instead (for a setup with no hydrostatic pressure gradient in the fluid, e.g. the usual
    periodic box with no gravity in the fluid equations).
apply_torque : bool, default False
    If `True`, the reaction torque is also handed to DEM (`set_external_torques`). Off by
    default because DEM assigns a default inverse inertia unrelated to a grain's physical size,
    and handing it a torque before its physical principal inertia is set can spin it up without
    bound. `last_torque` is computed and stored either way.
force_method : {"reaction", "traction"}, default "reaction"
    `"reaction"` uses the discrete momentum-reaction force (`flow.hydro_force_torque_reaction()`),
    exactly conservative. `"traction"` uses the reconstructed surface-traction integral
    (`flow.hydro_force_torque()`), kept as a diagnostic; it under-reads the drag by a measured,
    resolution-independent ~29%.

Raises
------
ValueError
    If `periodic` is a mixed triple, or `force_method` is not `"reaction"` or `"traction"`.
TypeError
    If `periodic` is not a 3-sequence of bool.

| Method / property | Description |
|---|---|
| `step` | Advance the coupled system by one fluid time step `fluid_dt`.  If `move_particles`, first pushes DEM's current positions/quaternions/velocities/angular velocities into the flow scene and rebuilds the cut-cell geometry (`flow.rebuild_geometry()` -- the velocity and pressure fields survive it). Then advances the fluid one step and reads back the per-grain hydrodynamic load according to `force_method`, lagged by this one fluid step (weak, explicit coupling): `last_force` and `last_torque` are always set; `last_force_pressure` / `last_force_viscous` are set only when `force_method="traction"` (`None` otherwise).  If `move_particles` is `False`, returns after computing the load -- DEM is never stepped and receives no forces. Otherwise, the particles' net gravity/buoyancy is added to a copy of the hydrodynamic force (see `buoyancy` / `rho_p`), the result is written to DEM's external force buffer, the reaction torque is written to DEM's external torque buffer if `apply_torque`, and DEM advances `dem_substeps` sub-steps at the sub-step `dt` set in `__init__`, holding the applied force/torque constant over them.  Takes no arguments and returns nothing; results are read back from `last_force`, `last_torque`, and, in traction mode, `last_force_pressure` / `last_force_viscous`. |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `DRAG_BEETSTRA` | `6` |
| `DRAG_DI_FELICE` | `3` |
| `DRAG_ERGUN` | `2` |
| `DRAG_GIDASPOW` | `5` |
| `DRAG_SCHILLER_NAUMANN` | `1` |
| `DRAG_STOKES` | `0` |
| `DRAG_TANG` | `7` |
| `DRAG_WEN_YU` | `4` |

