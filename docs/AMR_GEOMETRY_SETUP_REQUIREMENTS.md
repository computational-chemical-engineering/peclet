# AMR input to the shared-SDF (scene) layer: what `AmrFlow::setSolid` needs

*2026-08-28, from the mixed-level cut-band campaign (Fable session). Companion to
[ANALYTIC_SDF_GEOMETRY.md](ANALYTIC_SDF_GEOMETRY.md) — this note is the AMR consumer's
requirements + measurements for that plan's Layer-2-for-core rung. It exists so the scene API is
shaped by what the AMR builders actually do, before it freezes.*

## 1. The measurement that motivates this (all numbers RTX 5080 host, single-threaded)

`AmrFlow::setSolid` on the 180-sphere RCP bed, depth-7 graded mesh (1.79M leaves): **127 µs/leaf
≈ 8×10³ cells/s, single-threaded** — ≈4 min at 1.8M leaves, would be ~66 min/arm at depth 9.
The SOTA yardstick ([[performance-sota-yardstick]]): p4est runs full adapt + 2:1 balance at
~10⁵–10⁶ octants/s/core (5×10¹¹ octants on 220k cores); Parthenon and cornerstone/SPH-EXA build
and hold the mesh device-resident. We are two orders off per core, before parallelism.

Phase breakdown (`PECLET_CORE_PROFILE_SETUP=1`, permanent env-gated profiler in `flow.hpp`):

| phase | µs/leaf | share | what it samples |
|---|---:|---:|---|
| `mom_.build` (cut-cell momentum stencils) | 85.4 | 67% | SDF at centers + probe points |
| `presMG_.build` (openness MG hierarchy) | 13.8 | 11% | SDF at ALL coarse levels' faces |
| `buildOpenness` (level-aware canonical rule) | 13.2 | 10% | SDF at face-adjacent centers |
| `buildGhostOverlaySampled` (mixed-level overlay) | 12.1 | 10% | SDF at virtual uniform positions |
| C/F overlays + device assembly + uploads + MG | ~2.8 | 2% | — |

The cost model closes exactly, and a sphere-doubling experiment CONFIRMS it directly
(duplicating the sphere list keeps the geometry identical but doubles per-eval cost:
M=180 → 127.1 µs/leaf, M=360 → 246.5 µs/leaf; three M=180 repeats within 0.2%):

- **101 SDF evaluations per leaf** (measured by a counting callback, depth-6 graded bed);
- **1.18 µs per evaluation** for the 180-sphere brute-force union (from the doubling slope:
  119.4 µs/leaf per 180 spheres ÷ 101 evals; one sqrt + three `nearbyint` per sphere per query);
- SDF share at M=180: 119.4 of 127.1 µs/leaf = **94%**; builder logic is only ~8 µs/leaf.

So: **~94% of AMR setup is SDF evaluation cost**, split multiplicatively into (a) evals/leaf
(101 — with cross-phase redundancy), (b) cost/eval (brute force over all primitives), and
(c) serialism (one core, host). The scene layer owns (b) and the batched/device form of (c);
the AMR builders own (a) and the loop structure of (c).

## 2. The inversion (user brainstorm, endorsed): geometry drives, not cells

Cell-driven queries make every cell pay a full acceleration-structure traversal — including the
far field, which only needs a sign. Inverting it: **for each primitive (BVH/AABB leaf), enumerate
the octree cells its bounding band overlaps and append the primitive to those cells' candidate
lists** (the band-splat already named as contract 9 / the `generateSdfKokkos` pattern in
ANALYTIC_SDF_GEOMETRY.md). Cells never touched by any band get a cheap far-field default.

On the *graded* octree the enumeration Frank sketched (triple loop in Morton arithmetic,
stepping levels) has a clean linearized form the AMR side already owns: the leaf array is
Morton-sorted, so an AABB decomposes into a small set of Morton index ranges and the overlapped
leaves — at whatever level each happens to be — fall out of **binary searches on the sorted leaf
array** (the p4est primitive; no per-level loops, 2:1 grading handled by construction).
`BlockOctree` + the morton library provide everything needed; the AMR side can supply this as
`leavesInBox(aabb) -> leaf ranges` if the scene layer wants it as a callback rather than a
dependency.

After the splat, per-cell sampling iterates a candidate list of ~1–5 primitives instead of 180:
that alone is the EBGeometry "order of magnitude"; on this bed it is ~30× at the surface and
more in the far field.

## 3. What the AMR builders need from the scene API (the requirements)

1. **Batched evaluation, not a scalar callback.** The builders' natural shape is: collect a
   point array (device View), evaluate all points in one `parallel_for`, read back nothing (the
   samples stay on device for device assembly; host builders take a host mirror). A
   `std::function<double(Vec<3>)>` scalar interface locks in serial host evaluation forever —
   it is the single API decision that matters most.
   The AMR side commits to restructuring its builders into collect-points → batch-evaluate →
   build-rows passes to consume this (that refactor is AMR work, not scene work).
2. **Per-cell candidate lists as a first-class output** (contract 9), built geometry-driven
   (§2). The overlay/openness/momentum builders will then sample against the list.
3. **Level-aware probe positions.** The mixed-level cut band samples at positions that depend
   on the LEAF's OWN level: cell centers, face centers, ±h_L and ±2h_L axis probes, and the
   sampled overlay's *virtual uniform positions* across 2:1 boundaries. The openness MG
   hierarchy additionally samples at EVERY COARSE LEVEL's face centers. So the batch API must
   take arbitrary point arrays — never assume one lattice spacing.
4. **Periodicity is min-image over the box extent** and must be exact (the classification is a
   float-sign contract: overlay-closed ⇔ binary-closed). The current AMR stopgap
   (`Flow.set_solid_spheres`, core 29ba5b0) does min-image with `nearbyint`; whatever the scene
   does must agree in sign at the ±h/2 probe scale, or classifications flicker.
5. **Determinism and parity.** Oracle (host) and device evaluate the SAME scene: bit-identical
   per point is the target the suite's parity ctests assume (float leaves are already bit-exact
   across host/device in Layer 0's gates — keep that property through the acceleration layer:
   candidate-list ORDER must not change the result, so combine with min/max, not summation).
6. **Equal-radius fast path is worth keeping** (monodisperse beds are the workhorse): nearest
   surface = nearest center, so the union needs ONE sqrt per query (min over squared center
   distances first). The current stopgap pays a sqrt per sphere.
7. **The dem RCP bed is the benchmark geometry**: 180 spheres, φ=0.63
   (`core/tests/data/rcp_pack_seed3_unit.txt`), depth-7/8 graded meshes via
   `core/tests/study/amr_bed_graded.py`. Acceptance: `set_solid` at depth 8 (7.01M leaves)
   should land at seconds, not the current ~13 min — i.e. ≥100× = candidates (~30×) ×
   equal-R (~3×) — before any parallelism, and the phase profile is one env var away.

## 4. Division of labour (proposed)

| item | owner | status |
|---|---|---|
| Candidate lists / band-splat / BVH, device scene, batched eval API | SDF agent (Layer 2-for-core) | their plan already names it (contract 9, Layer 2) |
| `AmrFlow::setSolid(SceneView)` overload consuming it | joint (API theirs, call sites AMR) | after the API lands |
| Builder restructure: collect-points → batch-eval → build rows | AMR | blocked on API shape (item 1 above) |
| Cross-phase sample redundancy (101 evals/leaf → share coincident points) | AMR | independent, can start |
| Parallel builder loops (deterministic two-pass CSR; host now, device later) | AMR | independent of scene API |
| `Flow.set_solid_spheres` stopgap | AMR | freeze as-is; retire when the scene overload lands |

The AMR-side items marked independent do not touch `geom/` and cannot collide with the SDF
agent; everything that touches evaluation waits for their API.


---

## 5. DELIVERED (2026-08-29, SDF agent) — handoff record, API frozen

Everything in §3 items 1-2 and 4-6 is implemented in `core/include/peclet/core/geom/`
(`scene_query.hpp`, `device_scene.hpp`, shims in `common/portable.hpp`); the stopgap
`Flow.set_solid_spheres` is retired — same Python signature, now backed by
`geom::SphereBedQuery`, which also slots directly into `AmrFlow::setSolid`'s templated `SdfFn`
(and inlines there; no `std::function` anywhere).

**Measured, single-threaded, RTX 5080 host, `amr_bed_graded.py` meshes:**

| depth | leaves | set_solid BEFORE | AFTER | end-to-end |
|---|---:|---:|---:|---:|
| 6 | 262k | 33.3 s (127.1 µs/leaf) | 3.3 s (12.5 µs/leaf) | 10.2× |
| 7 | 1.79M | ~227 s (127 µs/leaf) | 23.5 s (13.1 µs/leaf) | 9.7× |
| 8 | 7.01M | ~13 min | 95.6 s (13.6 µs/leaf) | ~8× |

Eval-cost reduction (the scene layer's share of the product): 1.18 µs/eval → ~0.03-0.05 µs/eval
≈ **~30-40×**, from candidate lists of mean length **3.75** (vs 180) on the RCP bed. The modeled
"equal-R ~3×" does NOT stack on top of short lists: that estimate assumed the sqrt dominates a
180-long loop, but at 3.75 candidates the min-image divides dominate and equal-R saves only the
2.75 extra sqrts. The residual ~8 µs/leaf is builder logic — the AMR-side rows of §4's table
(sample redundancy, parallel loops), which is where "seconds, not minutes" now lives:
8 µs/leaf ÷ 16 threads × 7M ≈ 4 s once the collect-points → batch-evaluate → build-rows
restructure lands.

**Classification parity:** depth-6 fluid mask **bit-identical** to the retired stopgap
(0 diffs / 262 130); fluid counts identical at depth 7/8. Gate `geom_scene_query` (host ctest):
candidate-grid path vs brute force **bitwise** over 182k probes incl. surface-hugging ±h/2-scale
points, superset audit, per-bin shuffle invariance, out-of-coverage fallback.

**One deviation from §3.4, deliberate and measured.** The canonical per-sphere expression is
FMA-canonical (`d = fma(-nearbyint(d/L), L, d)`; `d2 = fma(z,z,fma(y,y,x*x))`), NOT the stopgap's
two-rounding form. Reason: §3.5 requires host ≡ device **bit-identical**, and nvcc FMA-contracts
the plain `x*x + y*y + z*z` chain — measured 22 001/200 000 CUDA probes off by 1 ulp at the sqrt
magnitude; after canonicalisation **0/200 000** (ctest `geom_batch_device`, OpenMP + CUDA).
Explicit `fma` is correctly rounded by IEEE everywhere and cannot be re-contracted. The
difference vs the legacy expression is bounded (measured worst **1.32 ulp** at sqrt magnitude,
zero sign flips beyond the knife edge over 160k probes) and produced **zero** classification
changes on the acceptance meshes. Sign-flip exposure: a probe must land within ~2 ulp
(~1e-17) of a surface; at 7×10⁸ evals per depth-8 build the collision probability is ~1e-4.

**Two notes for the AMR side:**
- ~15% of the serial win is left on the table because `std::fma` compiles to a libm call in the
  module build (no `-mfma`); depth-6 measured 10.8 → 12.5 µs/leaf plain→fma. Adding `-mfma` (or
  `-march=native`) to the python module's host flags recovers it — build config is yours.
- Candidate lists are keyed by a **uniform auxiliary lattice**, queried per POINT in O(1) — not
  per octree leaf — so probes at any level/h hit the right list with no `leavesInBox` and no
  per-level machinery. The batched API (`evalSphereUnionPoints` / `evalScenePoints`, device View
  in → distances out; `*Host` forms for the oracle) takes arbitrary point arrays per §3.1/§3.3.
  Restructure the builders against these; `leavesInBox` remains unneeded by the scene layer.
