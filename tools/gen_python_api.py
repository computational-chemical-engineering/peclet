"""Generate static Markdown Python-API reference pages from the installed peclet modules' docstrings."""
import importlib, inspect, os, sys, textwrap

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

# (page-file, title, blurb, [ (import_path, [class names] or None for free-functions) ... ])
PAGES = [
    ("flow.md", "peclet.flow — Eulerian Navier–Stokes solver",
     "The incompressible cut-cell IBM Navier–Stokes solver on a staggered MAC grid. "
     "`execution_space` reports the compiled-in Kokkos backend.",
     [("peclet.flow", ["Solver", "SolverColocated"]),
      ("peclet.flow.pnm", ["SDFReader", "Pore"])]),
    ("dem.md", "peclet.dem — Lagrangian DEM/XPBD packing",
     "XPBD discrete-element packing with SDF point-shell collision. The distributed (MPI) methods "
     "are present only in an MPI-enabled build.",
     [("peclet.dem", ["Simulation"])]),
    ("voro.md", "peclet.voro — dynamic Voronoi tessellation",
     "Moving-cell Voronoi tessellation + moving-cell dynamics, and an unstructured-mesh generator "
     "that can feed `peclet.flow`.",
     [("peclet.voro", ["Tessellation", "Simulation"])]),
    ("morton.md", "peclet.morton — Morton/Z-order arithmetic",
     "Vectorised Morton (Z-order) codes with O(1) arithmetic directly in Morton space.",
     [("peclet.morton", None)]),
    ("core.md", "peclet.core — shared infrastructure (MPI halo + AMR)",
     "The Lagrangian particle halo (`peclet.core.mpi`) and the Kokkos AMR octree "
     "(`peclet.core.amr`, present when built with a Kokkos backend + morton).",
     [("peclet.core.mpi", ["Migrator", "Halo"]),
      ("peclet.core.amr", ["Octree", "Poisson", "Flow", "DistributedOctree"])]),
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


def emit_functions(mod, w):
    fns = [n for n in dir(mod) if not n.startswith("_") and callable(getattr(mod, n))
           and getattr(getattr(mod, n), "__module__", None) in (mod.__name__, None)]
    for n in sorted(fns):
        f = getattr(mod, n)
        w(f"### `{n}`\n")
        w("```\n" + clean(f.__doc__) + "\n```\n\n")


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
        if cnames is None:
            emit_functions(mod, w)
        else:
            for c in cnames:
                emit_class(mod, c, w)
    with open(os.path.join(OUT, fname), "w") as fh:
        fh.write("".join(lines))
    print("wrote", fname)
