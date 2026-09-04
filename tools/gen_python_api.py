"""Generate static Markdown Python-API reference pages from the installed peclet modules' docstrings."""
import importlib, inspect, os, sys, textwrap

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

# (page-file, title, blurb, [ (import_path, [class names] or None for free-functions) ... ])
PAGES = [
    ("flow.md", "peclet.flow — Eulerian Navier–Stokes solver",
     "The incompressible cut-cell IBM Navier–Stokes solver on a staggered MAC grid (staggered `Solver`, "
     "collocated `SolverColocated`), with geometric VoF two-phase flow, analytic moving geometry (scenes) "
     "and the distributed (MPI) solve. `execution_space` reports the compiled-in Kokkos backend; "
     "`has_mpi` whether this build carries the multi-rank API. Regenerate from an MPI-enabled build.",
     [("peclet.flow", ["Solver", "SolverColocated"])]),
    ("pnm.md", "peclet.pnm — pore-network extraction",
     "Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology), "
     "pore-network FLOW data (per-throat flow rates + pore pressures) from a peclet.flow DNS, and the "
     "distributed (MPI) extraction on the core ORB decomposition.",
     [("peclet.pnm", ["SDFReader", "Pore"])]),
    ("dem.md", "peclet.dem — Lagrangian DEM (XPBD + Hertz–Mindlin)",
     "Discrete-element simulation with SDF point-shell collision, analytic SDF walls (static and "
     "moving), scene particles, and the distributed (MPI) step. The MPI methods are present only in "
     "an MPI-enabled build.",
     [("peclet.dem", ["Simulation"])]),
    ("voro.md", "peclet.voro — dynamic Voronoi tessellation + Voronoi-mesh flow",
     "Moving-cell Voronoi tessellation, moving-cell dynamics, the unstructured-mesh generator that "
     "feeds `peclet.flow`, the covolume / collocated Navier–Stokes solver on a Voronoi mesh "
     "(`FlowSolver`) and the distributed tessellation (`VoronoiHalo`).",
     [("peclet.voro", ["Tessellation", "Simulation", "FlowSolver", "VoronoiHalo"])]),
    ("coupling.md", "peclet.coupling — CFD-DEM coupling",
     "Two-way coupling of `peclet.flow` and `peclet.dem`: the unresolved point-particle driver "
     "`CfdDem` (void fraction, drag laws, semi-implicit feedback) and the resolved cut-cell driver "
     "`ResolvedCfdDem` (hydrodynamic force/torque reaction on scene particles).",
     [("peclet.coupling", ["CfdDem", "ResolvedCfdDem"])]),
    ("morton.md", "peclet.morton — Morton/Z-order arithmetic",
     "Vectorised Morton (Z-order) codes with O(1) arithmetic directly in Morton space.",
     [("peclet.morton", [])]),
    ("core.md", "peclet.core — shared infrastructure (MPI halo, AMR, geometry)",
     "The Lagrangian particle halo (`peclet.core.mpi`), the Kokkos AMR octree (`peclet.core.amr`, "
     "present when built with a Kokkos backend + morton) and the analytic-SDF scene authoring + "
     "rigid-body mass properties (`peclet.core.geom`).",
     [("peclet.core.mpi", ["Migrator", "Halo"]),
      ("peclet.core.amr", ["Octree", "Poisson", "Flow", "DistributedOctree"]),
      ("peclet.core.geom", ["SceneBuilder"])]),
]


def clean(doc):
    return textwrap.dedent(doc or "").strip()


def member_doc(obj, name):
    m = getattr(obj, name)
    d = clean(getattr(m, "__doc__", "") or "")
    return d


def emit_class(mod, cname, w):
    cls = getattr(mod, cname, None)
    if cls is None:
        return
    w(f"### `{cname}`\n")
    cd = clean(cls.__doc__)
    # nanobind classes often repeat the signature as first line; keep the doc if meaningful
    if cd and not cd.startswith(cname):
        w(cd + "\n")
    names = [n for n in dir(cls) if not n.startswith("_")]
    if not names:
        return
    w("\n| Method / property | Description |\n|---|---|\n")
    for n in sorted(names):
        d = member_doc(cls, n).replace("\n", " ").strip()
        # nanobind method __doc__ leads with the signature line; show it compactly
        d = d if d else "&nbsp;"
        w(f"| `{n}` | {d} |\n")
    w("\n")


def emit_functions(mod, w, skip):
    """Free functions + module attributes (execution_space, has_mpi ...). nanobind functions carry
    __module__ == "<pkg>._<leaf>" (the private extension), so match on the package prefix, not equality."""
    pkg = mod.__name__
    fns, attrs = [], []
    for n in dir(mod):
        if n.startswith("_") or n in skip:
            continue
        obj = getattr(mod, n)
        if inspect.ismodule(obj) or inspect.isclass(obj):
            continue
        m = getattr(obj, "__module__", None)
        if callable(obj):
            if m is None or str(m).startswith(pkg) or str(m).startswith(pkg.rsplit(".", 1)[0] + "."):
                fns.append(n)
        elif isinstance(obj, (str, bool, int, float)):
            attrs.append(n)
    if attrs:
        w("### Module attributes\n\n| Attribute | Value in this build |\n|---|---|\n")
        for n in sorted(attrs):
            w(f"| `{n}` | `{getattr(mod, n)!r}` |\n")
        w("\n")
    for n in sorted(fns):
        f = getattr(mod, n)
        w(f"### `{n}`\n")
        w("```\n" + (clean(f.__doc__) or "(no docstring)") + "\n```\n\n")


for fname, title, blurb, specs in PAGES:
    lines = []
    w = lines.append
    w(f"# {title}\n\n{blurb}\n\n")
    w("!!! note\n    Auto-generated from the installed module docstrings. "
      "Drive simulations from Python; the full C++ API is on each repo's Doxygen site.\n\n")
    ok = True
    for path, cnames in specs:
        try:
            mod = importlib.import_module(path)
        except Exception as e:
            w(f"## `{path}`\n\n*(not importable in this environment: {e})*\n\n")
            continue
        w(f"## `{path}`\n\n")
        mdoc = clean(getattr(mod, "__doc__", ""))
        if mdoc:
            w(mdoc + "\n\n")
        for c in cnames:
            emit_class(mod, c, w)
        emit_functions(mod, w, skip=set(cnames))
    with open(os.path.join(OUT, fname), "w") as fh:
        fh.write("".join(lines))
    print("wrote", fname)
