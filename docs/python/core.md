# peclet.core — shared infrastructure (MPI halo, geometry)

The Lagrangian particle halo (`peclet.core.mpi`) and the analytic-SDF scene authoring + rigid-body mass properties (`peclet.core.geom`). The AMR octree and its solver are the separate `peclet.amr` package since 2026-09-10 (QUALITY_PLAN G.2).

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.core.mpi`

core Lagrangian halo (block decomposition + particle migration/ghosts)

### `ParticleMigrator`
Lagrangian particle migration over an ORB block decomposition of the box [origin, origin+extent) binned on `cells` cells per axis (MPI_COMM_WORLD). Positions are (N,3) float64, the per-particle payload (N,K) float64.

| Method / property | Description |
|---|---|
| `cell_of` | cell_of(self, x: collections.abc.Sequence[float]) -> list[int]  Global decomposition cell index (i,j,k) containing x (after wrap). |
| `gather_ghosts` | gather_ghosts(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C'], rcut: float) -> tuple  Copies of particles within rcut of this rank's block (periodic images handled); returns the (ghost positions (G,3), ghost payload (G,K)). |
| `last_received` | last_received(self) -> int  Particles absorbed by this rank in the last migrate(). |
| `last_sent` | last_sent(self) -> int  Particles shipped by this rank in the last migrate(). |
| `migrate` | migrate(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C']) -> tuple  Reassign every particle to the rank owning its (wrapped) position; returns this rank's (positions (M,3), payload (M,K)) after the exchange. |
| `owner_of` | owner_of(self, x: collections.abc.Sequence[float]) -> int  Rank that owns the block containing position x (after periodic wrap / boundary clamp). |
| `rank` | This process's MPI rank. |
| `rebalance` | rebalance(self, positions: ndarray[dtype=float64, order='C'], payload: ndarray[dtype=float64, order='C']) -> tuple  Re-decompose by particle count (weighted ORB) so each rank holds a near-equal share, then migrate. Pure redistribution (count/payload preserved); the partition is updated in place. Returns this rank's (positions (M,3), payload (M,K)). |
| `wrap_position` | wrap_position(self, x: collections.abc.Sequence[float]) -> list[float]  Periodic-wrapped / boundary-clamped position for x (the canonical image). |

### `ParticleHalo`
Persistent owner<->ghost particle halo over the same decomposition as ParticleMigrator: build() the correspondence once, then forward/reverse Vec3 fields each step.

| Method / property | Description |
|---|---|
| `build` | build(self, positions: ndarray[dtype=float64, order='C'], rcut: float, include_periodic_self: bool = False) -> int  Establish the owner<->ghost correspondence over this rank's owned positions |
| `forward` | forward(self, owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  owned (N,3) -> ghost (G,3) verbatim (velocities, ...) |
| `forward_positions` | forward_positions(self, owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  owned (N,3) -> ghost (G,3) with the periodic image shift (positions) |
| `num_ghost` | Ghost particles this rank receives (G), as established by the last build(). |
| `num_owned` | Owned particles (N) this rank passed to the last build(). |
| `owner_of` | owner_of(self, x: collections.abc.Sequence[float]) -> int  Rank that owns the block containing position x (after periodic wrap / boundary clamp). |
| `rank` | This process's MPI rank. |
| `reverse` | reverse(self, ghost: ndarray[dtype=float64, order='C'], owned: ndarray[dtype=float64, order='C']) -> numpy.ndarray[dtype=float64]  ghost (G,3) summed onto owned (N,3); returns owned + reversed contributions |

### Module attributes

| Attribute | Value in this build |
|---|---|
| `build_toolchain` | `'GNU 14.2.0  x86_64'` |

## `peclet.core.geom`

Analytic-SDF scene authoring: SceneBuilder (leaves + CSG + transforms + instancing), batch evaluation, lattice baking, and rigid-body mass properties (mass, COM, inertia tensor, principal moments + quaternion) by implicit quadrature.

### `SceneBuilder`

| Method / property | Description |
|---|---|
| `add_difference` | add_difference(self, a: int, b: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  a minus b. |
| `add_instance` | add_instance(self, root: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0, lin_vel: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], ang_vel: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], center: collections.abc.Sequence[float] = [nan, nan, nan], material: int = -1) -> int  Place a tree in the world; returns the instance index. What flow's set_scene and the resolved coupling consume. `center` is the centre of rotation for ang_vel: leave it NaN (the default) and it FOLLOWS the body (the translation, re-anchored on every set_instance_transform); give any finite point and it is PINNED there in world coordinates -- (0, 0, 0) included. (Raw instance arrays keep the legacy reading of an all-zero centre as 'follows the body'; pin a world-origin centre from a raw array through flow's set_instance_motion(center=...).) |
| `add_intersection` | add_intersection(self, a: int, b: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int |
| `add_leaf` | add_leaf(self, kind: str, params: collections.abc.Sequence[float], translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  Add a leaf primitive; returns its node index. kind: sphere [r], box [hx,hy,hz], hollow_cylinder [rOuter,height,thickness] (y axis, distance-exact), hollow_cylinder_shell [rOuter,rInner,height] (z axis, sign-exact), capsule [r,halfLength] (y), torus [R,r] (y), cone [rBottom,rTop,halfHeight] (y), ellipsoid [rx,ry,rz] (BOUND), superquadric [rx,ry,rz,e] (BOUND). rotation is a quaternion (x, y, z, w). |
| `add_reframed` | add_reframed(self, root: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int  Deep-copy the subtree and pre-compose this transform onto the copied root, so eval_new(p) = eval_old(toLocal(W, p)) -- i.e. this PLACES the copy at W. With the inverse principal transform from body_properties (rotation = conjugate of its quat, translation = -com rotated by the conjugate... see principal_frame()), the copy's canonical frame IS the principal body frame, exactly, with no resampling. |
| `add_union` | add_union(self, a: int, b: int, translation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0], rotation: collections.abc.Sequence[float] = [0.0, 0.0, 0.0, 1.0], scale: float = 1.0) -> int |
| `bake` | bake(self, root: int, origin: collections.abc.Sequence[float], spacing: collections.abc.Sequence[float], dims: collections.abc.Sequence[int]) -> numpy.ndarray[dtype=float32]  Sample a subtree on a lattice: flat float32, x-fastest (idx = i + j*nx + k*nx*ny), at nodes origin + (i,j,k)*spacing -- the layout dem's grid-SDF particles and shell generation consume. |
| `body_properties` | body_properties(self, root: int, lo: collections.abc.Sequence[float], hi: collections.abc.Sequence[float], n: int = 32, order: int = 5, nseg: int = 8, density: float = 1.0) -> dict  Mass properties of {subtree < 0} over [lo, hi] (which MUST contain the solid), constant density, by implicit quadrature: dict with volume, mass, com, inertia_tensor (3,3 about the COM), principal (3, ascending), rotation (3,3; columns = principal axes, p_input = com + R p_body) and quat (x,y,z,w). Sign-exact bracketing means bound-only leaves (ellipsoid, superquadric, CSG) carry NO systematic bias; measured ~4e-6 relative at n=32 (ctest geom_body). |
| `encode` | encode(self) -> tuple  The flat (node_ints, node_reals, inst_ints, inst_reals) arrays -- exactly what flow.set_scene, dem.add_analytic_wall and dem.add_scene_shape take. |
| `eval` | eval(self, points: ndarray[dtype=float64, shape=(*, 3), order='C']) -> numpy.ndarray[dtype=float64]  Signed distance of the whole scene (min over instances) at (N,3) world points. Authoring/debug; solvers evaluate on device. |
| `eval_root` | eval_root(self, root: int, points: ndarray[dtype=float64, shape=(*, 3), order='C']) -> numpy.ndarray[dtype=float64]  Signed distance of ONE subtree, in its own canonical frame, at (N,3) points. |
| `eval_root_grad` | eval_root_grad(self, root: int, points: ndarray[dtype=float64, shape=(*, 3), order='C']) -> tuple  Value AND analytic gradient of one subtree at (N,3) canonical points, one traversal: (values (N,), gradients (N,3), unnormalised). At CSG ridges the gradient is the ACTIVE branch's exact normal (deterministic left tie-break), not a finite-difference smear. |
| `num_instances` | num_instances(self) -> int |
| `num_nodes` | num_nodes(self) -> int |
| `principal_frame` | principal_frame(self, root: int, lo: collections.abc.Sequence[float], hi: collections.abc.Sequence[float], n: int = 32, order: int = 5, nseg: int = 8) -> int  Measure the subtree's mass properties and return a NEW root whose canonical frame is the principal body frame (COM at the origin, axes principal) -- the one-call answer to 'my shape's reference frame is not its principal frame'. The original subtree is untouched. |

