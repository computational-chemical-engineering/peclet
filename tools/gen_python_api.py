"""Generate static Markdown Python-API reference pages from the installed peclet modules' docstrings.

    python3 tools/gen_python_api.py [--strict] docs/python

The Site workflow runs this at build time inside the released peclet-cpu container image (MPI-enabled
builds of the whole family), so the pages are not committed; tools/gen_api_local.sh does the same for a
local `mkdocs serve`. A PAGES module that does not import, or reports `has_mpi` False, gets a stub on its
page and a warning; --strict turns those into exit status 1.
"""
import argparse, importlib, inspect, os, sys, textwrap

# (page-file, title, blurb, [ (import_path, [class names] or None for free-functions) ... ])
PAGES = [
    ("flow.md", "peclet.flow — Eulerian Navier–Stokes solver",
     "The incompressible cut-cell IBM Navier–Stokes solver on a staggered MAC grid (staggered `Solver`, "
     "collocated `SolverColocated`), with geometric VoF two-phase flow, analytic moving geometry (scenes) "
     "and the distributed (MPI) solve. `execution_space` reports the compiled-in Kokkos backend; "
     "`has_mpi` whether this build carries the multi-rank API. Regenerate from an MPI-enabled build.",
     [("peclet.flow", ["Solver", "SolverColocated", "SolverDiagnostics", "SolverColocatedDiagnostics"])]),
    ("pnm.md", "peclet.pnm — pore-network extraction",
     "Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology), "
     "pore-network FLOW data (per-throat flow rates + pore pressures) from a peclet.flow DNS, and the "
     "distributed (MPI) extraction on the core ORB decomposition.",
     [("peclet.pnm", ["SDFReader", "Pore"])]),
    ("dem.md", "peclet.dem — Lagrangian DEM (XPBD + Hertz–Mindlin)",
     "Discrete-element simulation with SDF point-shell collision, analytic SDF walls (static and "
     "moving), scene particles, and the distributed (MPI) step. The MPI methods are present only in "
     "an MPI-enabled build. `Simulation` is the public tier; developer instruments, ablations and "
     "GPU execution policies live on `Simulation.diagnostics` (`Diagnostics` below).",
     [("peclet.dem", ["Simulation", "Diagnostics"])]),
    ("voro.md", "peclet.voro — dynamic Voronoi tessellation + Voronoi-mesh flow",
     "Moving-cell Voronoi tessellation, moving-cell dynamics, the unstructured-mesh generator that "
     "feeds `peclet.flow`, the covolume / collocated Navier–Stokes solver on a Voronoi mesh "
     "(`FlowSolver`) and the distributed moving tessellation (`DistributedTessellation`, over the "
     "`VoronoiHalo` primitive). Developer instruments live on each object's `diagnostics`; the pore-mesh "
     "algorithms are `peclet.voro.pore_mesh`, the scene helpers `peclet.voro.scenes`.",
     [("peclet.voro", ["Tessellation", "Simulation", "FlowSolver", "VoronoiHalo", "DistributedTessellation",
                       "OptimizeResult", "InterfaceResult"]),
      ("peclet.voro._voro", ["TessellationDiagnostics", "SimulationDiagnostics", "FlowSolverDiagnostics",
                             "DistributedTessellationDiagnostics"]),
      ("peclet.voro.pore_mesh", ["RedistributeResult"]),
      ("peclet.voro.scenes", [])]),
    ("coupling.md", "peclet.coupling — CFD-DEM coupling",
     "Two-way coupling of `peclet.flow` and `peclet.dem`: the unresolved point-particle driver "
     "`CfdDem` (void fraction, drag laws, semi-implicit feedback) and the resolved cut-cell driver "
     "`ResolvedCfdDem` (hydrodynamic force/torque reaction on scene particles).",
     [("peclet.coupling", ["CfdDem", "ResolvedCfdDem"])]),
    ("morton.md", "peclet.morton — Morton/Z-order arithmetic",
     "Vectorised Morton (Z-order) codes with O(1) arithmetic directly in Morton space.",
     [("peclet.morton", [])]),
    # The page keeps its file name (mkdocs nav, links), but documents the canonical modules:
    # `peclet.core.mpi` / `peclet.core.geom` are deprecated re-exports since peclet-core 1.3.1
    # (suite/docs/CORE_BOUNDARY.md), and importing them here would trip their DeprecationWarning.
    ("core.md", "peclet.halo and peclet.geom — the particle halo and analytic-SDF geometry",
     "The Lagrangian particle halo (`peclet.halo`, package `peclet-halo`, `pip install peclet[mpi]`) "
     "and the analytic-SDF scene authoring + rigid-body mass properties (`peclet.geom`, package "
     "`peclet-geom`, in plain `pip install peclet`). Until peclet 1.2.0 these were `peclet.core.mpi` "
     "and `peclet.core.geom`; those spellings still import (the same objects) with a "
     "`DeprecationWarning`, and are removed in 2.0.0. The AMR octree and its solver are the separate "
     "`peclet.amr` package since 2026-09-10 (QUALITY_PLAN G.2).",
     [("peclet.halo", ["ParticleMigrator", "ParticleHalo"]),
      ("peclet.geom", ["SceneBuilder"])]),
    ("amr.md", "peclet.amr — block-octree AMR and its collocated cut-cell Navier–Stokes solver",
     "The block-local-Morton AMR octree (`Octree`, distributed `DistributedOctree`), the AMR Poisson "
     "solve and the collocated cut-cell Navier–Stokes solver on it (`Flow`; developer instruments on "
     "`Flow.diagnostics`). Depends on peclet-core and peclet-morton; requires a Kokkos backend and MPI.",
     [("peclet.amr", ["Octree", "DistributedOctree", "Poisson", "Flow", "FlowDiagnostics"])]),
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


def render_page(title, blurb, specs, problems=None):
    """Markdown of one page. A module that does not import, or reports `has_mpi` False (the pages
    document the distributed API), is appended to `problems` when a list is given."""
    problems = [] if problems is None else problems
    lines = []
    w = lines.append
    w(f"# {title}\n\n{blurb}\n\n")
    w("!!! note\n    Auto-generated from the installed module docstrings. "
      "Drive simulations from Python; the full C++ API is on each repo's Doxygen site.\n\n")
    for path, cnames in specs:
        try:
            mod = importlib.import_module(path)
        except Exception as e:
            w(f"## `{path}`\n\n*(not importable in this environment: {e})*\n\n")
            problems.append(f"{path}: not importable ({type(e).__name__}: {e})")
            continue
        if getattr(mod, "has_mpi", True) is False:
            problems.append(f"{path}: has_mpi is False -- the pages must come from MPI-enabled builds")
        w(f"## `{path}`\n\n")
        mdoc = clean(getattr(mod, "__doc__", ""))
        if mdoc:
            w(mdoc + "\n\n")
        for c in cnames:
            emit_class(mod, c, w)
        emit_functions(mod, w, skip=set(cnames))
    return "".join(lines)


def generate(out):
    """Write every page into `out`; return the problems found (see render_page)."""
    os.makedirs(out, exist_ok=True)
    problems = []
    for fname, title, blurb, specs in PAGES:
        with open(os.path.join(out, fname), "w") as fh:
            fh.write(render_page(title, blurb, specs, problems))
        print("wrote", fname)
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", help="output directory (docs/python)")
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if a PAGES module does not import or reports has_mpi False")
    a = ap.parse_args()
    problems = generate(a.out)
    # In GitHub Actions a ::warning:: line becomes an annotation on the run summary.
    tag = "::warning::" if os.environ.get("GITHUB_ACTIONS") == "true" else "WARNING: "
    for pr in problems:
        print(tag + pr, file=sys.stderr)
    return 1 if (problems and a.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
