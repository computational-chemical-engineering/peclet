#!/usr/bin/env python3
"""Which gallery pages call peclet API that is NOT in the published release? (docs/RELEASE.md §10)

Static, heuristic and fast: for every page under examples/, benchmarks/ and sanity-checks/ of the
peclet-examples checkout it collects the `.name(` method calls and `module.name` attribute uses in
python cells, and checks each name against the `.def("name"` / `def name(` surfaces of the binding
sources at a git TAG and at HEAD of each submodule. A name present at HEAD but absent at the tag
marks the page NEEDS-NEXT-RELEASE (rendered against a local build; runnable from PyPI only after
the release). Names absent from both are generic Python (numpy etc.) unless they look peclet-ish.

    python tools/release/audit_examples.py --examples ~/Codes/peclet-examples \
        --tag flow=v0.4.0 --tag dem=v0.4.0 --tag voro=v0.4.0 --tag pnm=v0.1.0 --tag core=v0.5.0 --tag coupling=v0.3.0

Prints a markdown table; --md FILE writes it. Review the result by hand — it over-approximates
(common names like `step`, `size` are dropped by the STOPWORDS list, extend it as needed).
"""
import argparse, os, re, subprocess, sys
from pathlib import Path

SUITE = Path(__file__).resolve().parents[2]
BINDINGS = {
    "flow": ["src/flow_bindings.cpp", "packaging/flow_init.py"],
    "dem": ["src/dem_bindings.cpp", "packaging/dem_init.py", "packaging/particle_builder.py", "packaging/scene_particle.py"],
    "voro": ["src/voro_bindings.cpp", "packaging/voro_init.py"],
    "pnm": ["src/pnm_bindings.cpp", "packaging/pnm_init.py"],
    "core": ["python/mpi_bindings.cpp", "python/amr_bindings.cpp", "python/geom_bindings.cpp"],
    "coupling": ["src/coupling_bindings.cpp", "python/peclet_coupling/__init__.py",
                  "python/peclet_coupling/driver.py", "python/peclet_coupling/resolved.py"],
    "morton": ["bindings/python/peclet/morton/__init__.py"],
}
DEF_RE = re.compile(r'\.def(?:_static|_prop_ro|_prop_rw|_ro|_rw|_prop)?\s*\(\s*"([A-Za-z_]\w*)"|^\s*def\s+([A-Za-z_]\w*)\s*\(|^\s*class\s+([A-Za-z_]\w*)\b|nb::class_<[^>]*>\s*\([^,]*,\s*"([A-Za-z_]\w*)"', re.M)
CALL_RE = re.compile(r'\.([a-z_][a-z0-9_]*)\s*\(')
ATTR_RE = re.compile(r'\b(?:flow|dem|voro|pnm|core|coupling|morton|geom|mpi|amr)\.([A-Za-z_]\w*)')
STOPWORDS = set("""append extend insert pop copy get items keys values update join split strip format
replace startswith endswith lower upper sum mean max min abs sqrt exp log dot cross reshape ravel
flatten astype tolist any all where zeros ones full empty arange linspace meshgrid stack hstack vstack
concatenate transpose argmax argmin argsort sort round clip cumsum diff isfinite isnan array asarray
savez load savefig plot scatter imshow set_xlabel set_ylabel set_title legend subplots tight_layout
add_subplot figure show close colorbar text annotate axhline axvline set_xlim set_ylim set_aspect
grid semilogy loglog set_xscale set_yscale fill_between errorbar bar hist contour contourf quiver
print len range enumerate zip open write read seek time perf_counter sleep run check_call
exists mkdir makedirs isdir isfile expanduser resolve parent name stem suffix with_suffix glob
Path get_context put empty_like zeros_like ones_like fill norm inv solve lstsq det eig svd
step rank size shape ndim T item index count remove clear setdefault fromkeys""".split())


def surface(sub, ref):
    names = set()
    for rel in BINDINGS[sub]:
        try:
            src = subprocess.run(["git", "-C", str(SUITE / sub), "show", f"{ref}:{rel}"],
                                 capture_output=True, text=True, check=True).stdout
        except subprocess.CalledProcessError:
            continue
        for m in DEF_RE.finditer(src):
            names.add(next(g for g in m.groups() if g))
    return names


def pages(root):
    for sub in ("examples", "benchmarks", "sanity-checks"):
        for q in sorted((root / sub).rglob("*.qmd")):
            yield q


def python_cells(text):
    return "\n".join(re.findall(r"```\{python\}[^\n]*\n(.*?)```", text, re.S))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--examples", default=os.path.expanduser("~/Codes/peclet-examples"))
    ap.add_argument("--tag", action="append", default=[], help="sub=tag (repeatable)")
    ap.add_argument("--md")
    a = ap.parse_args()
    tags = dict(t.split("=", 1) for t in a.tag)
    head, tagged = {}, {}
    for sub in BINDINGS:
        head[sub] = surface(sub, "HEAD")
        tagged[sub] = surface(sub, tags[sub]) if sub in tags else head[sub]
    all_head = set().union(*head.values()); all_tag = set().union(*tagged.values())
    rows = []
    root = Path(a.examples)
    for q in pages(root):
        code = python_cells(q.read_text(errors="replace"))
        helpers = re.findall(r"^\s*(?:from|import)\s+peclet_examples[.\w]*\s+import\s+(.+)$", code, re.M)
        for h in helpers:  # pull the helper module's code in too, so its calls count
            for mod in re.findall(r"peclet_examples\.(\w+)", code):
                hp = root / "src" / "peclet_examples" / f"{mod}.py"
                if hp.exists():
                    code += "\n" + hp.read_text(errors="replace")
        used = {m for m in CALL_RE.findall(code)} | {m for m in ATTR_RE.findall(code)}
        used -= STOPWORDS
        pkgs = sorted(set(re.findall(r"peclet(?:\.|\s+import\s+)(flow|dem|voro|pnm|core|coupling|morton)", code)))
        only_main = sorted(u for u in used if u in all_head and u not in all_tag)
        status = "NEEDS-NEXT-RELEASE" if only_main else ("OK-on-PyPI" if used & all_tag else "no-peclet-api")
        local = "PECLET_LOCAL_BUILD" in code or "PECLET_LOCAL_BUILD" in q.read_text(errors="replace")
        rows.append((str(q.relative_to(root).parent), ",".join(pkgs), status, " ".join(only_main), "yes" if local else ""))
    out = ["| page | packages | status | symbols only on main | local-build hint |", "|---|---|---|---|---|"]
    out += [f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} |" for r in rows]
    n = sum(1 for r in rows if r[2] == "NEEDS-NEXT-RELEASE")
    out.append(f"\n{len(rows)} pages, {n} need the next release to run from PyPI.")
    text = "\n".join(out)
    print(text)
    if a.md:
        Path(a.md).write_text(text + "\n")


if __name__ == "__main__":
    main()
