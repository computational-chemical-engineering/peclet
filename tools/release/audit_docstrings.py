#!/usr/bin/env python3
"""Docstring audit of the bound Python API (docs/RELEASE.md §5.1).

Imports every peclet module it can find on sys.path and lists public callables/properties without
a docstring, plus docstrings that still carry retired names. Run with the family on PYTHONPATH
(build trees or an installed venv):

    PYTHONPATH=flow/build:dem/build:voro/build_dev:pnm/build:core/python/build_geom \
        python tools/release/audit_docstrings.py [--json out.json]

Exit status is the number of modules that failed to import (so a CI step can fail loudly), the
undocumented count is printed, not enforced — the release checklist decides what is acceptable.
"""
import importlib, inspect, json, re, sys

MODULES = ["peclet.flow", "peclet.pnm", "peclet.dem", "peclet.voro", "peclet.morton",
           "peclet.core.mpi", "peclet.core.amr", "peclet.core.geom", "peclet.coupling"]
STALE = re.compile(r"\b(sdflow|vorflow|tpx_|demgpu|peclet\.flow\.pnm|tests/kokkos_mpi suite|CUDA-API alias|TODO|FIXME)\b", re.I)


def doc_of(obj):
    d = inspect.getdoc(obj) or ""
    # nanobind repeats the signature as the first line; a signature-only doc counts as undocumented
    lines = [l for l in d.splitlines() if l.strip()]
    if not lines:
        return ""
    if len(lines) == 1 and re.match(r"^\w+\(.*\)( -> .*)?$", lines[0].strip()):
        return ""
    return d


def audit_module(name):
    mod = importlib.import_module(name)
    undocumented, stale, total = [], [], 0
    def visit(owner, prefix):
        nonlocal total
        for attr in dir(owner):
            if attr.startswith("_") and attr != "__init__":
                continue
            try:
                obj = getattr(owner, attr)
            except Exception:
                continue
            if inspect.ismodule(obj):
                continue
            is_cls = inspect.isclass(obj)
            is_call = callable(obj) or isinstance(obj, property) or type(obj).__name__ in ("nb_func", "nb_method", "getset_descriptor", "nb_static_property")
            if not (is_cls or is_call):
                continue
            if is_cls and not str(getattr(obj, "__module__", "")).startswith("peclet"):
                continue   # a re-exported numpy/stdlib class
            full = f"{prefix}{attr}"
            total += 1
            d = doc_of(obj)
            if not d:
                undocumented.append(full)
            elif STALE.search(d):
                stale.append((full, STALE.search(d).group(0)))
            if is_cls and full.count(".") - name.count(".") < 2:   # module.Class.method, no deeper
                visit(obj, full + ".")
    visit(mod, name + ".")
    return {"total": total, "undocumented": undocumented, "stale": stale}


def main():
    out, failed = {}, 0
    for m in MODULES:
        try:
            out[m] = audit_module(m)
        except Exception as e:  # ImportError, or an MPI-gated module absent from this build
            out[m] = {"error": f"{type(e).__name__}: {e}"}
            failed += 1
    tot = sum(v.get("total", 0) for v in out.values())
    und = sum(len(v.get("undocumented", [])) for v in out.values())
    print(f"{'module':<18}{'callables':>10}{'undocumented':>14}{'stale':>7}")
    for m, v in out.items():
        if "error" in v:
            print(f"{m:<18}  not importable: {v['error']}")
        else:
            print(f"{m:<18}{v['total']:>10}{len(v['undocumented']):>14}{len(v['stale']):>7}")
    print(f"{'total':<18}{tot:>10}{und:>14}")
    for m, v in out.items():
        for n in v.get("undocumented", []):
            print(f"  undocumented  {n}")
        for n, w in v.get("stale", []):
            print(f"  stale ({w})  {n}")
    if "--json" in sys.argv:
        json.dump(out, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
    sys.exit(failed)


if __name__ == "__main__":
    main()
