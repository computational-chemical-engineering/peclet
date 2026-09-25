# Design decisions — suite-wide

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### All coupled methods must share one BlockDecomposer; static-only co-decomposition is rejected
- area: suite-wide
- source: multiphysics-framework-plan.md:410
- decided: undated (referenced as a lasting constraint within a 2026-07-05-dated plan)
- status: settled
- quote: |
    **User directive (lasting constraint): all methods must share ONE BlockDecomposer in coupled
    runs, and dynamic load rebalancing must remain possible — grid fields must be redistributable
    after weighted re-decomposition. Static-only co-decomposition rejected.** ⇒ Phase 8: new core
    primitive `redistributeGridFields` (box-intersection NBX brick exchange, bit-exact) +
    `Solver::redistribute(dec)` + dem `migrateTo(dec)` + combined-weight (`w_fluid + γ·particles`)
    rebalance loop in `CfdDem`.
- rejected: "Static-only co-decomposition"
- why: dynamic load rebalancing must remain possible; grid fields must be redistributable after weighted re-decomposition

### CMake suite_require_nanobind must be a macro, not a function
- area: suite-wide
- source: nanobind-zero-copy-migration.md:15
- decided: undated
- status: settled
- quote: |
    **Gotcha:** `suite_require_nanobind` MUST be a CMake **macro**, not a function — `find_package(Python)` sets `Python_INCLUDE_DIRS` which nanobind reads at module-creation (directory) scope; a function scopes it locally → `nanobind-static` compiles without `Python.h`.
- rejected: implementing suite_require_nanobind as a CMake function
- why: a function scopes Python_INCLUDE_DIRS locally, causing nanobind-static to compile without Python.h

### Collocated default is AUTO ghost projection (in both flow and AMR), with documented fallbacks
- area: suite-wide
- source: collocated-attractor-campaign.md:53
- decided: 2026-08-25
- status: settled
- quote: |
    **MERGES + DEFAULT SWITCH DONE 2026-08-25 ...**: collocated default = AUTO ghost in BOTH
    flow.SolverColocated and core AmrFlow (fallbacks: gauge-exact on porous/varRho/BC/Chebyshev in
    flow; aperture on thin band in AMR; any explicit scheme call disables AUTO).
- rejected: none stated as an alternative default (aperture/gauge-exact remain as explicit fallbacks, not the default)
- why: validated AUTO == ghost records digit-for-digit; explicit schemes == their records

### Convention going forward: never add cell-unit API surface; new setters take physical inputs
- area: suite-wide
- source: physical-units-plan.md:44
- decided: 2026-09-06
- status: settled
- quote: |
    **How to apply:** never add cell-unit API surface; new setters take physical inputs and convert with
    `u_.*ToInt()`; the bit-identity gate is a `.npz` battery compared with `np.array_equal` at
    `extent=None`, and the scale gate poses the SAME problem in two unit systems 1000x apart
- rejected: adding new cell-unit-only API surface
- why: none stated beyond the directive

---

### Cross-backend gate for "ported"
- area: suite-wide
- source: cuda-kokkos-migration.md:94
- decided: 2026-06-18
- status: settled
- quote: |
    - Cross-backend gate: a piece is "ported" only when it passes on both a CUDA and a HIP build.
- rejected: none stated
- why: none stated

### D1–D9: clean break at 1.0.0 — no aliases, two API tiers, no numerics-changing env vars, single version source, honest CI, AMR relocated
- area: suite-wide
- source: suite-quality-plan-1-0-0.md:15-21
- decided: 2026-09-08
- status: settled
- quote: |
    **The plan:** `suite/docs/QUALITY_PLAN.md` (umbrella). Decisions D1–D9: clean break at **1.0.0**
    (every non-canonical name REMOVED, kwargs renamed, no aliases; NAMING.md §0 alias ladder is
    suspended for this one release and binding after), two API tiers (public vs `diagnostics`), no
    env var may change numerics, pyproject.toml is the single version source (CMake reads it),
    CI must not be green-by-no-op, core = infrastructure with the AMR flow solver RELOCATED (to flow
    or a `dev/amr-flow` branch — never deleted), docs describe what exists, old identifiers
    (`tpx`, `sdflow`, `vorflow`, `mortonarith`) gone.
- rejected: keeping compatibility aliases; letting env vars change numerics; multiple version sources; deleting AMR
- why: none stated beyond the directive

### Design: keep index-native kernels, fold the metric into constants at the API boundary via reference scales
- area: suite-wide
- source: physical-units-plan.md:16
- decided: 2026-09-06
- status: settled
- quote: |
    **Plan:** `docs/PHYSICAL_UNITS_PLAN.md` (umbrella), D1–D5 accepted. Keep flow's index-native kernels,
    fold the metric into constants at the API boundary; reference scales (`hRef`, `rhoRef` = first set_rho,
    `tRef` = first set_dt) keep the float operators O(1). `extent=None` = cell units, bit-identical.
- rejected: reworking the kernels themselves to be metric-aware (rejected in favor of index-native kernels + boundary conversion)
- why: keeps float operators O(1) and preserves bit-identical cell-unit behaviour when extent=None

### Device-resident class duals take a data-structure suffix "View", not a location word
- area: suite-wide
- source: peclet-v0.1-release.md:78
- decided: 2026-07-01
- status: settled
- quote: |
    The device-resident class duals took a **data-structure suffix `View`** (NOT a location word):
    `ParticleMigratorDevice`→`ParticleMigratorView`, `DistributedPoisson/MultigridDevice`→`*View` (the
    host CPU-MPI classes `ParticleMigrator`/`DistributedPoisson`/`DistributedMultigrid` keep the bare
    names — they're genuine production, not oracles).
- rejected: a location-word suffix (e.g. "Device") for these class duals
- why: none stated beyond the convention itself; distinguishes "genuine production" host classes from device-resident duals

### Do not change numerics while porting (faithful port principle)
- area: suite-wide
- source: cuda-kokkos-migration.md:304-307
- decided: 2026-06-19
- status: settled
- quote: |
    IMPORTANT lesson learned & in [[migration-faithful-port]]: do
    NOT change schemes while porting (the ~1% task-1 error was a cell-average-vs-point-value scheme swap I made;
    the rotational 'instability' was a symptom of that, not real).
- rejected: changing scheme/numerics mid-port
- why: caused a ~1% error mistaken for an instability

### Every peclet numerical method must run fully on-device and be MPI-distributable; host paths are oracles/tests only
- area: suite-wide
- source: device-first-mpi-design-principle.md:10
- decided: 2026-07-03
- status: settled
- quote: |
    **Design principle for ALL methods in the Peclet suite** (user directive, 2026-07-03): every
    numerical computation must be able to run **fully on the Device (GPU)** and must be
    **MPI-distributable** on large systems (halo/ghost exchange). No method may depend on a
    host-orchestration bottleneck (per-iteration host↔device downloads, host assembly, host linear
    solves).
- rejected: host-orchestration bottlenecks — per-iteration host↔device downloads, host assembly, host linear solves
- why: "the suite targets GPU + at-scale multi-GPU (LUMI/Snellius). A host-in-the-loop numeric kills GPU throughput and cannot scale across ranks."

### Feature-completion option A: Kokkos takes canonical names only after full parity; no merge until then
- area: suite-wide
- source: cuda-kokkos-migration.md:290-292
- decided: 2026-06-19
- status: settled
- quote: |
    FEATURE-COMPLETION PLAN (2026-06-19, user chose option A = Kokkos takes the canonical sdflow/demgpu
    names + retire CUDA, but ONLY after feature-parity + a parity test vs CUDA; do NOT merge to main yet;
    voronoi Kokkos port deferred to AFTER CUDA retirement).
- rejected: other unnamed options (not detailed in note) — merging/renaming before parity was confirmed
- why: none stated beyond "user chose option A"

### Host serial paths are permitted only as oracles/unit tests, never as the production path
- area: suite-wide
- source: device-first-mpi-design-principle.md:18
- decided: 2026-07-03
- status: settled
- quote: |
    - Host serial paths are allowed ONLY as **oracles / unit tests** (bit/te-exact references), never
      the production path. (This is already the pattern: `flow_oracle.hpp`, voro's disabled legacy
      half-edge oracle.)
- rejected: any host serial path as a production code path
- why: none stated beyond the existing pattern being cited as precedent

### KEPT exceptions to the device-naming ban: transfer verbs and prose
- area: suite-wide
- source: peclet-v0.1-release.md:87
- decided: 2026-07-01
- status: settled
- quote: |
    KEPT: `toDevice`/`copyToDevice`/`toHost` transfer verbs; bare-word "device" in prose comments.
- rejected: none — these are the explicit exceptions to the banned-qualifier rule above
- why: none stated

---

### Kokkos device sources must be .cpp, not .cu
- area: suite-wide
- source: cuda-kokkos-migration.md:109-112
- decided: 2026-06-18
- status: settled
- quote: |
    3. **Device sources must be `.cpp` (compiled as CXX), NOT `.cu`** — Kokkos 5.x routes C++ TUs
       through nvcc via its launch compiler; forcing `LANGUAGE CUDA` bypasses flag injection
       (`--extended-lambda` error). Concrete convention for the .cu-heavy cfd-gpu/packing-gpu ports.
- rejected: forcing LANGUAGE CUDA / .cu extension
- why: "forcing LANGUAGE CUDA bypasses flag injection (--extended-lambda error)"

### Kokkos migration requires C++20
- area: suite-wide
- source: cuda-kokkos-migration.md:104-105
- decided: 2026-06-18
- status: settled
- quote: |
    Three reality-forced decisions (apply to all later phases):
    1. **Kokkos 5.1.1 requires C++20** — suite device side moves C++17→C++20 under Kokkos.
- rejected: staying on C++17
- why: Kokkos 5.1.1 requires C++20

### Migration considered complete: user decision option c
- area: suite-wide
- source: cuda-kokkos-migration.md:582-586
- decided: undated (post 2026-06-20 session)
- status: settled
- quote: |
    ==> MIGRATION CONSIDERED COMPLETE (user decision, option c): single-GPU FULLY ported (all solver variants +
    MG + packing shapes/get_sdf_grid + RingBed correct & faster) on CUDA+OpenMP; cfd MPI FULLY ported (whole
    sdflow solver multi-rank, bit-exact); packing MPI primitives ported+tested. The ONE remaining follow-up =
    the packing distributed demStep (KokkosSim stepMpi via DeviceParticleHaloKokkos).
- rejected: other unnamed completion options
- why: none stated beyond "user decision, option c"

### Naming convention: identifiers name what a thing is, never where it runs; "device"/"Kokkos" are banned qualifiers
- area: suite-wide
- source: peclet-v0.1-release.md:62
- decided: 2026-07-01 (naming refactor, done + committed)
- status: settled
- quote: |
    **NAMING REFACTOR (DONE + committed, NOT pushed) — pre-publish uniformity pass:** Convention =
    *identifiers name what a thing is, never where it runs*; `device`/`Kokkos` banned as qualifiers
    (device execution via Kokkos is the uniform implied model). Scheme (confirmed): C++ namespace
    mirrors Python — **`peclet::<leaf>`** + headers under **`include/peclet/<leaf>/`**; morton keeps
    its standalone `morton::` identity (only its Python dist is peclet-morton).
- rejected: identifiers naming a thing by its execution location (e.g. "Kokkos"/"Device" qualifiers)
- why: "device execution via Kokkos is the uniform implied model"

### Naming convention: one short lowercase identity, drop "-gpu"
- area: suite-wide
- source: cuda-kokkos-migration.md:48-63
- decided: 2026-06-20
- status: settled
- quote: |
    NAMING CONVENTION (user-agreed). Goal: one short lowercase identity per code for repo/module/namespace, drop
    the misleading `-gpu` (Kokkos is portable). **TIER 1 DONE** (in-repo module+namespace renames, low risk): packing module
    `demgpu`->`dem` (+ `src/demgpu_bindings.cpp`->`dem_bindings.cpp`, CMake target/project, build flag `DEMGPU_MPI`->`DEM_MPI`,
    all `import demgpu`->`import dem`); cfd module `pnm_backend`->`pnm` + C++ namespace `dns`->`sdflow` (so the solver
    namespace matches its module; `dns` was a retirement-era artifact).
    ...
    **TIER 2 DONE** (2026-06-20, pushed): repo dirs + GitHub remotes renamed in-place (old URLs redirect), `-gpu` dropped:
    `cfd-gpu`->`sdflow`, `packing-gpu`->`dem`, `morton_artithmetic`(typo)->`morton`. **GitHub-only now** -- dropped all
    GitLab remotes/second-push-URLs (user wants one env for CI). `block_decomposer` ARCHIVED on GitHub + removed as a
    suite submodule.
- rejected: keeping the "-gpu" suffix; GitLab remotes
- why: "Kokkos is portable" (the -gpu suffix is misleading); "user wants one env for CI" (GitHub-only)

### No `Device*`/`*Kokkos` class names for exposed kernels; host code is an unexposed oracle only
- area: suite-wide
- source: device-naming-retirement.md:10-14
- decided: 2026-06-27
- status: settled
- quote: |
    **Suite-wide "no Device/Kokkos in exposed-kernel names; one device path per kernel" refactor — DONE +
    PUSHED 2026-06-27** ... User's rule: exposed computational kernels run on **device** (CPU = Kokkos Serial
    backend, or GPU); **no class named `Device*` or `*Kokkos`**; host code kept ONLY as a dev-stage
    bit-exact **oracle**, NOT exposed by Python. The old names below are RETIRED — don't reference them.
- rejected: class names containing `Device*` or `*Kokkos`; exposing host-only kernel code to Python
- why: user's naming rule; host is retained only as a validation oracle

### Provisioning via shared install prefix + find_package, not FetchContent
- area: suite-wide
- source: cuda-kokkos-migration.md:105-109
- decided: 2026-06-18
- status: settled
- quote: |
    2. **Provisioning = shared install prefix + find_package, NOT FetchContent** — ArborX does
       `find_package(Kokkos CONFIG)` and can't consume an in-tree Kokkos, so one install-prefix
       mechanism is the only thing that composes (and avoids rebuilding Kokkos per repo). Local
       stand-in for cluster `module load`.
- rejected: FetchContent
- why: "ArborX does find_package(Kokkos CONFIG) and can't consume an in-tree Kokkos, so one install-prefix mechanism is the only thing that composes"

### Suite-wide migration from pybind11 to nanobind + scikit-build-core, on a shared zero-copy bridge
- area: suite-wide
- source: nanobind-zero-copy-migration.md:11-13
- decided: 2026-06-28
- status: settled
- quote: |
    DONE 2026-06-28 (NOT pushed; commit at milestones per [[commit-at-milestones]], push-direct per [[push-directly-to-main]]). Migrated every suite Python binding from pybind11 to **nanobind** + **scikit-build-core**, on a shared zero-copy array bridge.
    **The keystone:** `transport-core/include/tpx/python/ndarray_interop.hpp` (namespace `tpx::python`): `view_to_ndarray` (Kokkos View → NumPy host / DLPack device, capsule-owns-a-View-copy = zero-copy + correct lifetime), `vector_to_ndarray` (host vector, no extra copy), `ndarray_to_view`/`ndarray_to_vector` (import; host→deep_copy, device-on-backend→unmanaged wrap, mismatch→raise).
- rejected: pybind11 as the binding framework
- why: none stated beyond the migration goal (zero-copy View↔ndarray bridge, shared across the suite)

### USER DIRECTIVE: peclet must match/exceed SOTA massively-parallel-code performance in every component, including setup
- area: suite-wide
- source: performance-sota-yardstick.md:11-22
- decided: 2026-08-28
- status: settled
- quote: |
    **The idea of peclet is to match or exceed the (parallel) performance of the best SOTA
    massively parallel code** (user, 2026-08-28, verbatim intent). This applies to ALL
    functionality — "I want all functionality to run efficiently parallel both on CPU and also
    GPU" — not only the per-step solve. Setup paths (octree build, operator assembly, `setSolid`,
    overlay builds, MG hierarchy construction) count: a serial setup that costs minutes at 10M
    cells fails the yardstick even if the march is fast.
- rejected: judging performance only by the per-step solve/march, ignoring setup-path cost
- why: user directive; a slow serial setup undermines the suite's parallel-performance claims even if the march is fast

### USER DIRECTIVE: peclet.flow is the reference for shared-method design elsewhere in the suite, not Basilisk or the literature
- area: suite-wide
- source: flow-is-the-method-reference.md:8-19
- decided: 2026-09-03
- status: settled
- quote: |
    When a method in another peclet code (voro's collocated solver was the case) has a counterpart in
    `peclet.flow`, study flow's own documents and implementation FIRST and transfer that structure;
    do not take Basilisk (or a paper) as the reference. Concretely for the collocated projection: flow
    uses the incremental predictor with the cell pressure gradient = the EXACT TRANSPOSE of the
    centre→face constraint (gauge-exact `gpCenterGrad` = transpose of `centerToFace`), used in both the
    predictor and the correction; the Basilisk face-acceleration form was considered in flow's
    collocated discussions and REJECTED — do not reintroduce it.
- rejected: taking Basilisk (or a paper) as the reference for a shared method design; the Basilisk face-acceleration form for the collocated projection
- why: user wants peclet internally consistent ("similar problems are solved in similar ways in different parts of the code"); flow's collocated campaign already learned the hard lessons (adjoint pairing = stability, invisible subspaces, rotational-update instability)

---

### USER DIRECTIVE: quality is the prime objective; next release is a clean-break 1.0.0, API-breaking allowed; AMR preserved not deleted
- area: suite-wide
- source: suite-quality-plan-1-0-0.md:11-13
- decided: 2026-09-08
- status: settled
- quote: |
    **Directive (2026-09-08, user):** "Quality is the prime objective … no other users yet, so be
    API-breaking if needed … if the version should be major because API breaking, do so … AMR is
    being developed, do not throw it away; you might move things to a development branch."
- rejected: preserving backward compatibility / a minor version bump
- why: user directive, verbatim as quoted

### USER DIRECTIVE: solvers take a physical domain + physical properties; spatial discretization must not influence physical property values
- area: suite-wide
- source: physical-units-plan.md:11
- decided: 2026-09-06
- status: settled
- quote: |
    **Directive (2026-09-06):** "The spatial discretization should not influence the values of the physical
    properties"; different extents and cell counts per axis (anisotropic h); the same inputs for AMR/Voronoi
    meshes; big refactor acceptable, performance must not suffer.
- rejected: none stated (directive against the prior cell-unit-only API)
- why: none stated (direct user statement)

### atexit Kokkos::finalize is required on CUDA, not just optional as on OpenMP
- area: suite-wide
- source: nanobind-zero-copy-migration.md:23-25
- decided: 2026-06-28
- status: superseded
- quote: |
    **Decisions/findings:** (1) dropped the atexit `Kokkos::finalize` EVERYWHERE (a returned array's owning capsule outlives the hook → "deallocated after Kokkos::finalize" abort); kept `finalize()` methods. Matches tpx_amr's existing choice.
    ...
    **CUDA-VALIDATED 2026-06-28 on RTX 5080 (sm_120) — three critical fixes the host-only build hid:**
    ...
    2. **atexit `Kokkos::finalize` is REQUIRED on CUDA** (I had wrongly removed it thinking no-finalize was benign — true only on OpenMP). No-finalize → `cudaErrorCudartUnloading` at every exit (Kokkos device state torn down after CUDA runtime unloads). Pattern: dem/vorflow/tpx_amr keep a `releaseAll()`→finalize registry...
- rejected: dropping atexit Kokkos::finalize everywhere (the initial host-only-validated decision)
- why: on CUDA, no-finalize causes `cudaErrorCudartUnloading` at every exit; this was masked on OpenMP where no-finalize is benign
- conflict: the initial "dropped everywhere" decision is directly reversed for CUDA by the later CUDA-validation entry in the same note

### morton stays on ctypes by design; vorflow's legacy host bindings stay on pybind11
- area: suite-wide
- source: nanobind-zero-copy-migration.md:17
- decided: 2026-06-28
- status: settled
- quote: |
    **morton left on ctypes by design** (dependency-free PyPI wheels). vorflow LEGACY host `python/bindings.cpp` left on pybind11 (device is canonical).
- rejected: migrating morton's bindings to nanobind; migrating vorflow's legacy host bindings to nanobind
- why: morton's ctypes choice preserves "dependency-free PyPI wheels"; vorflow's legacy host path is superseded by the device path (canonical), so it wasn't worth migrating

### nanobind Kokkos+CUDA modules require NOMINSIZE (nanobind's default -Os breaks nvcc)
- area: suite-wide
- source: nanobind-zero-copy-migration.md:24
- decided: 2026-06-28
- status: settled
- quote: |
    1. **NOMINSIZE** on EVERY `nanobind_add_module` for Kokkos modules — nanobind's default `-Os` is rejected by nvcc (`nvcc fatal: 's': expected a number`). Without it NO nanobind Kokkos module builds on CUDA.
- rejected: nanobind's default -Os compile flag for Kokkos CUDA modules
- why: "nvcc fatal: 's': expected a number" — nvcc rejects -Os

### Wheels for a toolchain without OpenMP ship Kokkos::Threads, not Serial
- area: suite-wide
- source: RELEASE_PREP.md:11.3
- decided: 2026-09-13
- status: settled
- quote: |
    Windows and macOS wheels ship `Kokkos::Threads`. Threads is 1.65x faster than Serial on both
    platforms at identical numbers (3.87 vs 6.37 s on Windows, 3.00 vs 4.99 s on macOS; k =
    1.2407e-01 and 14 steps in every run), needs no bundled runtime, asserts no version the build
    cannot check, and keeps the macOS wheel floor at 11.
- rejected: the Kokkos Serial backend (single-threaded, and it was chosen only because the third
    option was not on the table); clang-cl (real OpenMP 5.0, but swaps the compiler for the whole
    Windows build and bundles libomp.dll); pre-setting OpenMP_CXX_SPEC_DATE to walk MSVC's
    _OPENMP = 200203 past Kokkos' OpenMP >= 3.0 gate (asserts a version nothing verifies); Homebrew's
    libomp on macOS (only a tahoe bottle is published, which drags the wheel floor from macOS 11 to
    26, and `coupling` importing flow + dem would load two copies of it)
- why: MSVC defines _OPENMP as 200203 whatever runtime is selected -- measured with /openmp:llvm
    actually reaching the compiler -- and AppleClang ships no OpenMP at all, so the gate is a macro
    version rather than a capability. Kokkos' C++ std::thread backend needs no OpenMP runtime, and
    the suite is indifferent to which host space it gets: exactly one line in eight repositories
    names Kokkos::OpenMP, and it is #ifdef-guarded.

### A host backend that does not size itself must be handed the thread budget
- area: suite-wide
- source: RELEASE_PREP.md:11.3
- decided: 2026-09-13
- status: settled
- quote: |
    `Kokkos::Threads` asks hwloc for the topology and falls back to ONE thread when hwloc is absent
    (Kokkos_Threads_Instance.cpp:487) -- and it is absent in every peclet wheel. Measured on 48
    cores: unset, the quick start takes 4.43 s, exactly its one-thread time, against 0.64 s at 24
    threads. defaultHostThreads() therefore asks whether the backend sizes ITSELF and hands it the
    budget when it does not.
- rejected: keeping the "say nothing on an unconstrained machine" policy for every backend (it is
    neutral only for OpenMP, whose own default is the whole machine; on Threads it is a silent 7x
    cut); capping the default below the CPU budget on the strength of 3-4 vCPU CI numbers
- why: OpenMP reads OMP_NUM_THREADS through its runtime and defaults to the machine, so peclet can
    stay quiet; Kokkos itself reads only KOKKOS_NUM_THREADS, so on Threads and Serial neither the
    user's variable nor a sensible default reaches anything unless peclet supplies it. Verified end
    to end on a Threads wheel: default 4.428 s -> 0.899 s, same k, both variables still honoured.

### A solver's internal grid-count threshold is a count, not cell-unit API
- area: suite-wide
- source: amr documentation pass 2026-09-24 (amr `4758ba7`, `8b913b1`); USER DECISION 2026-09-24
- decided: 2026-09-24
- status: settled
- quote: |
    The coarsest multigrid level's size (flow `set_pressure_bottom_extent(cells=)`, amr the same
    after its rename) is a count of cells per axis on the coarsest grid, not a length: the limit
    exists because the bottom smoother (60 Jacobi sweeps) solves a level only up to about 4 cells
    per axis, whatever the physical size of the domain. Such solver-internal grid-count thresholds
    are exempt from "never add cell-unit API surface". The exemption is narrow: the quantity must
    be a property of the discrete solver that does not scale with the physical problem, the keyword
    is `cells` (NAMING.md §1.8), and the docstring says "a count, not a length".
- rejected: a physical-length form (wrong: the same length means a different level count at a
    different resolution, while the smoother's limit is a cell count); hiding the knob on the
    diagnostics tier only (flow already ships it public, and one concept gets one tier)
- why: the directive exists so that a user states the PROBLEM physically and the discretization
    is derived; a solver threshold on the discrete grid is not part of the problem statement, and
    forcing it into a length would make it resolution-dependent

### Iteration order follows storage: x fastest on every backend
- area: suite-wide
- source: flow `f981453` (`src/policy.hpp`, ctest `iteration_order`), coupling `412b067`, umbrella `a64fb65` (CONVENTIONS §1); USER DIRECTIVE 2026-09-25
- decided: 2026-09-25
- status: settled
- quote: |
    Fields are x-fastest (I = x + y*nx + z*nx*ny, LayoutLeft, Fortran-order (nx,ny,nz) in Python,
    x-fastest in VTI), so every multi-dimensional kernel iterates x fastest on EVERY backend,
    through one project alias (flow `MDRange2/3<Exec>` = Rank<N, Iterate::Left, Iterate::Left>);
    a bare `Kokkos::Rank<N>` is forbidden (a ctest greps for it). Kokkos' backend default is Left
    on CUDA but Right (z fastest) on host backends, so every flow host kernel strode against
    memory: 7-point stencil 9.87 ms (Right) vs 1.32 ms (Left) on 128x96x64, 1 thread; bubble
    column 1x8 threads 471 -> 399 ms/step. GPU results bitwise unchanged; on host only MDRange
    reductions change summation order (~1e-14 relative).
- rejected: relying on the backend default iteration (silently wrong-strided on host); per-site
    explicit policies without an alias and a guard (the default crept back in 283 sites)
- why: USER DIRECTIVE "too silly — repair it": storage, kernel order, NumPy order and file-format
    order are ONE convention, stated once in CONVENTIONS §1

### Collocated pressure and forces stay in the implicit predictor — never a face acceleration after the viscous solve
- area: suite-wide (flow, amr, voro collocated paths)
- source: flow doc/collocated_varrho_forces.md §2, §7; flow 26c7717, 693f83c; amr 5ccf518, ece52bd; USER DIRECTIVE 2026-09-25
- decided: 2026-09-25
- status: settled
- quote: |
    On a collocated grid the lagged pressure gradient and every force enter the momentum equation
    INSIDE the implicit (viscous/drag) predictor. They are never added as a face acceleration
    after the implicit solve (Basilisk centered.h's uf += dt*a, and any equivalent "kick",
    whatever it is called). Mechanism: after A^{-1}, -dt G P^n/rho_f lies exactly in the range
    the projection removes, so P^n never reaches u. With kappa = 0 the scheme is non-incremental
    Chorin: the steady state is scaled by (1 + dt mu Lambda) (V8: TG error 9.2/9.8/10.6 at
    N = 16/32/64, order -0.1; drag 2.48). With the rotational update the pressure obeys
    P^{n+1} = -4 kappa dt S P^n/(rho h^2): -12 at (pi,pi,pi), measured -12.0000 at mu dt = 1 and
    -1.2000 at 0.1, unstable once mu dt/(rho h^2) > 1/12. The same instability rated flow's
    collocated VoF to density ratio ~100 (T2 "~4x per step"). The WO-T port reintroduced this
    in 2026-09 despite the earlier clause, which named the form but not the mechanism. The guard
    is therefore a GATE, not a grep: every collocated density path runs the seeded-checkerboard
    growth test (dt 0.1-100) and the dt-independence test (flow
    tests/python/test_collocated_stability_guard.py; amr test_amr_stability_guard). Variable
    density keeps balance through the mass-adjoint pair and the optional balanced-force
    projection.
- rejected: the Basilisk face-acceleration ("centered.h") form on any collocated path; a text
    prohibition alone (already existed and was bypassed)
- why: the defect is structural and silent at small mu*dt, so only a signature test at large
    mu*dt catches it
- conflict: sharpens suite-wide "flow is the reference ... Basilisk face-acceleration form
    REJECTED" (2026-09-03)
