# peclet.halo and peclet.geom — the particle halo and analytic-SDF geometry

The Lagrangian particle halo (`peclet.halo`, package `peclet-halo`, `pip install peclet[mpi]`) and the analytic-SDF scene authoring + rigid-body mass properties (`peclet.geom`, package `peclet-geom`, in plain `pip install peclet`). Until peclet 1.2.0 these were `peclet.core.mpi` and `peclet.core.geom`; those spellings still import (the same objects) with a `DeprecationWarning`, and are removed in 2.0.0. The AMR octree and its solver are the separate `peclet.amr` package since 2026-09-10 (QUALITY_PLAN G.2).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.halo`

peclet.halo — the distributed Lagrangian particle halo: ORB block decomposition, particle
migration, ghost exchange and weighted rebalancing over MPI.

Named for what it is, not for what it links against (suite/docs/CORE_BOUNDARY.md): `halo` is
already the thing's name on the C++ side — `peclet::halo`, `GridHalo`, `ParticleHalo`.

Needs an MPI toolchain to build and an MPI runtime to use, which is why it ships as an sdist behind
`pip install peclet[mpi]` while its former housemate `peclet.geom` ships wheels.

Until peclet 1.2.0 this was ``peclet.core.mpi`` in the ``peclet-core`` distribution. That spelling
still works and is the same object; it warns from 1.3.1 and is removed in 2.0.0.

### `ParticleMigrator`
Lagrangian particle migration over an ORB block decomposition of the box [origin, origin+extent) binned on `cells` cells per axis (MPI_COMM_WORLD). Positions are (N,3) float64, the per-particle payload a 2-D (N,K) float64 array with the same N (pack velocity, id, ... into the K columns).

MPI must already be initialized (import mpi4py.MPI first); the module never calls MPI_Init/Finalize. Construction does not communicate. migrate, rebalance and gather_ghosts are collective over MPI_COMM_WORLD: every rank calls them, in the same order, even with no particles.

| Method / property | Description |
|---|---|
| `cell_of` | cell_of(self, x: collections.abc.Sequence[float]) -> list[int]  Global decomposition cell index (i,j,k) containing x (after wrap). |
| `gather_ghosts` | gather_ghosts(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C'], rcut: float) -> tuple  Copies of the particles OTHER ranks own that lie within distance rcut of this rank's block, each at its periodic image nearest the block. A rank's own periodic images are not included (np=1 gets none; ParticleHalo.build(include_periodic_self=True) covers that). Collective. Returns (ghost positions (G,3), ghost payload (G,K)); the inputs are not modified. |
| `last_received` | last_received(self) -> int  Particles absorbed by this rank in the last migrate(). |
| `last_sent` | last_sent(self) -> int  Particles shipped by this rank in the last migrate(). |
| `migrate` | migrate(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C']) -> tuple  Reassign every particle to the rank owning its (wrapped) position. Collective. Returns this rank's (positions (M,3), payload (M,K)) after the exchange. |
| `owner_of` | owner_of(self, x: collections.abc.Sequence[float]) -> int  Rank that owns the block containing position x (after periodic wrap / boundary clamp). |
| `rank` | This process's MPI rank. |
| `rebalance` | rebalance(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C']) -> tuple  Re-decompose by particle count (weighted ORB) so each rank holds a near-equal share, then migrate. Pure redistribution (count/payload preserved); the partition is updated in place, so later owner_of/migrate/gather_ghosts calls use it. Collective. Returns this rank's (positions (M,3), payload (M,K)). |
| `wrap_position` | wrap_position(self, x: collections.abc.Sequence[float]) -> list[float]  Periodic-wrapped / boundary-clamped position for x (the canonical image). |

### `ParticleHalo`
Persistent owner<->ghost particle halo over the same decomposition as ParticleMigrator: build() the correspondence once, then forward/reverse (N,3) float64 fields each step while the owned particles and their order stay fixed. MPI must already be initialized; build, forward_positions, forward and reverse communicate, so every rank calls them.

| Method / property | Description |
|---|---|
| `build` | build(self, positions: ndarray[dtype=float64, order='C'], rcut: float, include_periodic_self: bool = False) -> int  Establish the owner<->ghost correspondence from this rank's owned positions (N,3): a ghost here is a copy of a particle another rank owns within distance rcut of this rank's block. include_periodic_self also emits a rank's own periodic images (needed on an undecomposed periodic axis, e.g. at np=1). Collective. Returns the ghost count G. |
| `forward` | forward(self, owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  owned (N,3) -> ghost (G,3) copied verbatim: use for velocities and other fields without an image shift. |
| `forward_positions` | forward_positions(self, owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  owned (N,3) -> ghost (G,3), adding each ghost's periodic image shift: use for positions. N must be the count passed to the last build(). |
| `num_ghost` | Ghost particles this rank receives (G), as established by the last build(). |
| `num_owned` | Owned particles (N) this rank passed to the last build(). |
| `owner_of` | owner_of(self, x: collections.abc.Sequence[float]) -> int  Rank that owns the block containing position x (after periodic wrap / boundary clamp). |
| `rank` | This process's MPI rank. |
| `reverse` | reverse(self, ghost: ndarray[dtype=float64, order='C'], owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  ghost (G,3) contributions summed back onto their owners: returns a new (N,3) array, owned + the reversed contributions (e.g. forces on ghosts); `owned` is not modified. |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `build_toolchain` | `'GNU 14.2.0 Release x86_64'` |

## `peclet.geom`

peclet.geom — analytic-SDF scene authoring: CSG trees, batch evaluation, lattice baking,
and rigid-body mass properties (mass, centre of mass, inertia tensor, principal frame).

Host-only and dependency-light by design: no MPI, no Kokkos, no Kokkos-backed solver. That is
why it ships as wheels and is part of a plain ``pip install peclet``.

Until peclet 1.2.0 this was ``peclet.core.geom`` in the ``peclet-core`` distribution, which could
not be installed without an MPI toolchain. ``peclet.core.geom`` still works and is the same object
(``peclet.core.geom.SceneBuilder is peclet.geom.SceneBuilder``); it warns from 1.3.0 and is removed
in 2.0.0. See suite/docs/CORE_BOUNDARY.md.

### `SceneBuilder`
Authors an analytic constructive-solid-geometry (CSG) scene as two arrays: a forest of NODES -- leaves (add_leaf), the union/intersection/difference combinators and add_reframed copies, each addressed by the index its add_* call returns -- and a list of INSTANCES (add_instance) that place one node's subtree in the world with a rigid-body transform, optional linear/angular velocity and a material id. A node is a shape DEFINITION; an instance is a PLACEMENT of one (see num_nodes vs num_instances). encode() flattens both to the (node_ints, node_reals, inst_ints, inst_reals) arrays that flow.set_scene, dem.add_analytic_wall and dem.add_scene_shape consume; eval()/eval_root() evaluate the scene directly, for authoring and debugging (solvers evaluate on device from the encoded arrays, not through this class).

| Method / property | Description |
|---|---|
| `add_difference` | add_difference(self, a: int, b: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  a minus b. |
| `add_instance` | add_instance(self, root: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0, lin_vel: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], ang_vel: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], center: collections.abc.Sequence[float] = [nan, nan, nan], material: int = -1) -> int  Place a tree in the world; returns the instance index. What flow's set_scene and the resolved coupling consume. `center` is the centre of rotation for ang_vel: leave it NaN (the default) and it FOLLOWS the body (the translation, re-anchored on every set_instance_transform); give any finite point and it is PINNED there in world coordinates -- (0, 0, 0) included. (Raw instance arrays keep the legacy reading of an all-zero centre as 'follows the body'; pin a world-origin centre from a raw array through flow's set_instance_motion(center=...).) |
| `add_intersection` | add_intersection(self, a: int, b: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  SDF max of subtrees `a` and `b` (their node indices) -- the shape occupied by both; returns the new combinator's node index. `translation`/`rotation` (quaternion x, y, z, w)/`scale` transform the frame both children are evaluated in, exactly as in add_union. |
| `add_leaf` | add_leaf(self, kind: str, params: collections.abc.Sequence[float], translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  Add a leaf primitive; returns its node index. kind: sphere [r], box [hx,hy,hz], hollow_cylinder [rOuter,height,thickness] (y axis, distance-exact), hollow_cylinder_shell [rOuter,rInner,height] (z axis, sign-exact), capsule [r,halfLength] (y), torus [R,r] (y), cone [rBottom,rTop,halfHeight] (y), ellipsoid [rx,ry,rz] (BOUND), superquadric [rx,ry,rz,e] (BOUND). rotation is a quaternion (x, y, z, w). |
| `add_reframed` | add_reframed(self, root: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  Deep-copy the subtree and pre-compose this transform onto the copied root, so eval_new(p) = eval_old(toLocal(W, p)) -- i.e. this PLACES the copy at W. With the inverse principal transform from body_properties (rotation = conjugate of its quat, translation = -com rotated by the conjugate... see principal_frame()), the copy's canonical frame IS the principal body frame, exactly, with no resampling. |
| `add_union` | add_union(self, a: int, b: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  SDF min of subtrees `a` and `b` (their node indices) -- the shape occupied by either one; returns the new combinator's node index. `translation`/`rotation` (quaternion x, y, z, w)/`scale` transform the frame BOTH children are evaluated in, so the union can be placed, rotated or scaled as one rigid piece without touching a or b. |
| `bake` | bake(self, root: int, origin: collections.abc.Sequence[float], spacing: collections.abc.Sequence[float], dims: collections.abc.Sequence[int]) -> numpy.ndarray[dtype=float32]  Sample a subtree on a lattice: flat float32, x-fastest (idx = i + j*nx + k*nx*ny), at nodes origin + (i,j,k)*spacing -- the layout dem's grid-SDF particles and shell generation consume. |
| `body_properties` | body_properties(self, root: int, lo: collections.abc.Sequence[float], hi: collections.abc.Sequence[float], n: int = 32, order: int = 5, nseg: int = 8, density: float = 1.0) -> dict  Mass properties of {subtree < 0} over [lo, hi] (which MUST contain the solid), constant density, by implicit quadrature: dict with volume, mass, com, inertia_tensor (3,3 about the COM), principal (3, ascending), rotation (3,3; columns = principal axes, p_input = com + R p_body) and quat (x,y,z,w). Sign-exact bracketing means bound-only leaves (ellipsoid, superquadric, CSG) carry NO systematic bias; measured ~4e-6 relative at n=32 (ctest geom_body). |
| `encode` | encode(self) -> tuple  The flat (node_ints, node_reals, inst_ints, inst_reals) arrays -- exactly what flow.set_scene, dem.add_analytic_wall and dem.add_scene_shape take. |
| `eval` | eval(self, points: ndarray[dtype=float64, shape=(*, 3), order='C']) -> numpy.ndarray[dtype=float64]  Signed distance of the whole scene (min over instances) at (N,3) world points. Authoring/debug; solvers evaluate on device. |
| `eval_root` | eval_root(self, root: int, points: ndarray[dtype=float64, shape=(*, 3), order='C']) -> numpy.ndarray[dtype=float64]  Signed distance of ONE subtree, in its own canonical frame, at (N,3) points. |
| `eval_root_grad` | eval_root_grad(self, root: int, points: ndarray[dtype=float64, shape=(*, 3), order='C']) -> tuple  Value AND analytic gradient of one subtree at (N,3) canonical points, one traversal: (values (N,), gradients (N,3), unnormalised). At CSG ridges the gradient is the ACTIVE branch's exact normal (deterministic left tie-break), not a finite-difference smear. |
| `num_instances` | num_instances(self) -> int  Number of INSTANCES -- entries created by add_instance, i.e. shape trees actually PLACED in the world with a transform and optional rigid-body velocity/material id. This is what solvers iterate over. Distinct from num_nodes: one node (say a stirrer built as a union of two leaves) can be instanced zero, one, or many times at different places, so num_instances can be smaller, equal to, or larger than num_nodes. |
| `num_nodes` | num_nodes(self) -> int  Number of NODES in the shape forest -- every leaf (add_leaf), CSG combinator (add_union/add_intersection/add_difference) and add_reframed copy adds exactly one, whether or not it has ever been placed with add_instance. A node is a shape DEFINITION addressed by the index its add_* call returned, not something a solver sees directly. |
| `principal_frame` | principal_frame(self, root: int, lo: collections.abc.Sequence[float], hi: collections.abc.Sequence[float], n: int = 32, order: int = 5, nseg: int = 8) -> int  Measure the subtree's mass properties and return a NEW root whose canonical frame is the principal body frame (COM at the origin, axes principal) -- the one-call answer to 'my shape's reference frame is not its principal frame'. The original subtree is untouched. |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `build_toolchain` | `'GNU 14.2.1 Release x86_64'` |

