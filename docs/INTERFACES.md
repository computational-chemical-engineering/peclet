# Suite Interfaces

> Status: design document (living). The common abstractions every method shares, expressed as **C++20
> concepts** (host-side). These are *contracts*, not base classes — a type satisfies a concept by
> having the right members, so existing solvers adopt them incrementally without inheritance. At the
> CUDA/device boundary, the same shape is expressed with traits/CRTP (C++17). See [STYLE](STYLE.md).

The interfaces are deliberately small. They describe **where data lives and how it moves**, leaving the
numerics to each method. Signatures below are illustrative sketches in namespace `tpx`.

## 1. `Domain` — the global problem extent

```cpp
template <class D> concept Domain = requires(const D d, int axis) {
  { d.dim() }        -> std::convertible_to<int>;       // spatial dimension
  { d.length() }     -> /* Vec<Dim> */;                 // box size L
  { d.origin() }     -> /* Vec<Dim> */;
  { d.periodic(axis) } -> std::convertible_to<bool>;    // per-axis periodicity
};
```

Eulerian domains add a cell resolution `resolution() -> IVec<Dim>`; Lagrangian domains expose only the
continuous box. Lees–Edwards is a `Domain` variant carrying `shear()`.

## 2. `Decomposition` — global → rank-owned blocks

```cpp
template <class P> concept Decomposition = requires(const P p, int rank, /*IVec*/ gi) {
  { p.numBlocks() }            -> std::convertible_to<int>;
  { p.localBlock(rank) }       -> /* Block: origin, size (in cells or coords) */;
  { p.ownerOf(gi) }            -> std::convertible_to<int>;  // which rank owns a global index/point
  { p.neighbors(rank) }        -> /* range of neighbour ranks */;
};
```

Implemented by the ORB `BlockDecomposer` (from `block_decomposer`). A `Block` knows its inner region
and its ghost-layer width; `BlockIndexer` converts global↔local linear indices including ghosts.

## 3. `Field` — a payload that can be packed into/out of buffers

The single abstraction that lets grid fields and particle arrays share one exchange path.

```cpp
template <class F> concept Field = requires(F f, std::size_t i, std::byte* buf) {
  typename F::value_type;
  { f.pack(i, buf) }   -> std::convertible_to<std::size_t>;  // serialize element i, return bytes
  { f.unpack(buf) }    -> /* void */;                        // append a received element
  { f.bytesPerElem() } -> std::convertible_to<std::size_t>;
};
```

- A **grid field** packs the cells of a ghost slab (contiguous; can memcpy whole faces).
- A **particle attribute array** packs the attributes of a migrating/ghost particle.
- On GPU, `pack`/`unpack` have device counterparts (kernels) operating on device buffers.

## 4. `HaloExchange` — asynchronous ghost-layer communication

The heart of the near-term work. **Topology** (who talks to whom, message sizes) is separated from
**Exchange** (per-step movement) so the expensive setup happens only on (re)build.

```cpp
template <class H> concept HaloExchange = requires(H h, /*Field*/ field) {
  { h.buildTopology(/*Decomposition, ghostWidth*/) };   // (re)compute neighbour map + counts
  { h.start(field) };                                   // post non-blocking sends/recvs (+pack)
  { h.wait(field) };                                    // complete + unpack
  { h.exchange(field) };                                // start();wait() convenience
};
```

Two implementations behind this one concept:

- **`NbxExchange`** — nonblocking-consensus (`Isend`/`Irecv`/`Iprobe`/`Ibarrier`/`Allreduce`), ported
  from `block_decomposer/src/MPISync.hpp`. Best for **dynamic, sparse** patterns: particle migration,
  ghost-particle gather where the neighbour set and counts change every step.
- **`PersistentNeighborExchange`** — a dist-graph communicator
  (`MPI_Dist_graph_create_adjacent`) with `MPI_Neighbor_alltoallv` / persistent `MPI_Start`. Best for
  **static** patterns: a fixed Eulerian grid where the neighbour set and slab sizes are constant.

**Compute/comm overlap** is part of the contract: `start(field)` returns immediately; the caller
computes the block interior, then `wait(field)` completes before the boundary is computed.

**GPU-awareness:** buffers may be device pointers; the engine detects CUDA-aware MPI and exchanges
device buffers directly, with `pack`/`unpack` running as device kernels.

## 5. `SdfGeometry` — SDF-described solids

```cpp
template <class G> concept SdfGeometry = requires(const G g, /*Vec*/ p) {
  { g.eval(p) }     -> std::convertible_to<typename G::Real>;  // <0 inside solid (see CONVENTIONS)
  { g.grad(p) }     -> /* Vec: outward (into-fluid) normal direction */;
  { g.aabb() }      -> /* {min, max} */;
};
```

Backed by analytic primitives and grid SDFs (with scale), VTI I/O. Shared by all three methods.

## 6. `ImmersedBoundary` — IBM cut-cell data from an SDF

```cpp
template <class I> concept ImmersedBoundary = requires(const I ib) {
  { ib.activeCells() }  -> /* range of cut/boundary cell indices */;   // SoA on GPU
  { ib.apply(/*field, dir*/) };                                        // modify stencil at boundary
};
```

Models cfd-gpu's Robust-Scaled IBM (per-cut-cell rescale factors baked into stencil coefficients); the
packing-gpu point-shell-vs-SDF collision is the Lagrangian analog and shares the `SdfGeometry` source.

## 7. `Stepper` — the time-integration entry point

```cpp
template <class S> concept Stepper = requires(S s, /*Real*/ dt) {
  { s.step(dt) };                  // advance one step
  { s.time() } -> /* Real */;
};
```

Every method exposes `step(dt)` with identical semantics so drivers and Python bindings look the same.

## 8. `PythonModule` — binding surface

Not a C++ concept but a contract (see [CONVENTIONS §6](CONVENTIONS.md)): pybind11 module exposing
`Solver(...)` → `initialize`/`set_*` → `step(dt)` → `get_*` numpy accessors, with the shared array
shape/order rules. The core's `python` helpers provide the numpy↔core conversions so every module
implements this identically.
