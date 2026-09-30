#!/usr/bin/env python3
"""Are the generated Python API pages (docs/python/*.md) current, and does every shipped package have one?

    PYTHONPATH=<MPI build trees> tools/release/check_api_pages.py           # report, exit 1 on a finding
    PYTHONPATH=<MPI build trees> tools/release/check_api_pages.py --update  # rewrite docs/python/ in place

WHY THIS EXISTS: docs/RELEASE.md §5.1 used to say "regenerate the pages by hand". At 1.3.0 nobody did:
the pages were last regenerated on 2026-09-12 and flow's page lacked ~30 members. The pages are a
function of the built modules' docstrings, so the check is exact: regenerate every page with
tools/gen_python_api.py's own render function into a temp dir and diff against the committed pages.

WHAT IT CHECKS (each is a blocking finding):

  1. IMPORT. Every module named in `PAGES` must import. Otherwise the generator writes a "not
     importable" stub and the diff would be noise, so this is reported first, by name.
  2. MPI. A module with a `has_mpi` attribute that is False is a non-MPI build; the pages must come
     from MPI builds (they document the distributed API), so that is a failure.
  3. COVERAGE. Every package the family ships has a `PAGES` entry and a mkdocs.yml nav entry. The
     ships list is the metapackage's own: every `peclet-<name>==` pin in the umbrella pyproject.toml
     (base dependencies and extras). `peclet-<name>` documents module `peclet.<name>`, except
     `peclet-core`, the compatibility shell, which has no API of its own (its modules are the
     deprecated re-exports of `peclet.halo` / `peclet.geom`, docs/CORE_BOUNDARY.md) and is covered
     by `peclet.halo`.
  4. STALENESS. The regenerated pages differ from docs/python/ -> unified-diff summary, exit 1.

Exit status: 0 clean, 1 on any finding.
"""
from __future__ import annotations

import argparse
import difflib
import importlib
import re
import sys
import tomllib
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import gen_python_api as gen  # noqa: E402

PAGES_DIR = ROOT / "docs" / "python"
SHELL_DISTS = {"peclet-core": "peclet.halo"}   # compatibility shell -> the module that carries its API


def shipped_modules() -> dict[str, str]:
    """{distribution: module} for every peclet-<name>== pin of the umbrella metapackage."""
    meta = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]
    reqs = list(meta.get("dependencies", []))
    for extra in meta.get("optional-dependencies", {}).values():
        reqs += extra
    out = {}
    for r in reqs:
        m = re.match(r"(peclet-[a-z0-9]+)\s*==", r)
        if m:
            d = m.group(1)
            out[d] = SHELL_DISTS.get(d, "peclet." + d[len("peclet-"):])
    return out


def check_imports() -> list[str]:
    bad = []
    for _, _, _, specs in gen.PAGES:
        for path, _ in specs:
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", DeprecationWarning)
                    mod = importlib.import_module(path)
            except Exception as e:
                bad.append(f"{path}: not importable ({type(e).__name__}: {e}) -- put the MPI build "
                           f"trees of the whole family on PYTHONPATH")
                continue
            if getattr(mod, "has_mpi", True) is False:
                bad.append(f"{path}: importable but has_mpi is False -- the pages must come from "
                           f"MPI-enabled builds")
    return bad


def check_coverage() -> list[str]:
    paths = {p for _, _, _, specs in gen.PAGES for p, _ in specs}
    nav = (ROOT / "mkdocs.yml").read_text()
    bad = []
    for dist, mod in sorted(shipped_modules().items()):
        entry = [f for f, _, _, specs in gen.PAGES if any(p == mod for p, _ in specs)]
        if mod not in paths:
            bad.append(f"{dist}: no PAGES entry for {mod} in tools/gen_python_api.py")
        elif not any(f"python/{f}" in nav for f in entry):
            bad.append(f"{dist}: {entry[0]} (page of {mod}) has no mkdocs.yml nav entry")
    return bad


def regenerate(out: Path) -> None:
    for fname, title, blurb, specs in gen.PAGES:
        (out / fname).write_text(gen.render_page(title, blurb, specs))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--update", action="store_true", help="write the regenerated pages into docs/python/")
    a = ap.parse_args()

    findings = check_imports() + check_coverage()
    if any("not importable" in f or "has_mpi" in f for f in findings):
        for f in findings:
            print(f"  !! {f}")
        print("  (staleness not checked: pages cannot be regenerated from this environment)")
        return 1

    import tempfile
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        regenerate(tmp)
        if a.update:
            PAGES_DIR.mkdir(exist_ok=True)
            for f in sorted(tmp.glob("*.md")):
                (PAGES_DIR / f.name).write_text(f.read_text())
                print(f"  wrote docs/python/{f.name}")
        else:
            for f in sorted(tmp.glob("*.md")):
                cur = PAGES_DIR / f.name
                old = cur.read_text().splitlines(keepends=True) if cur.exists() else []
                diff = list(difflib.unified_diff(old, f.read_text().splitlines(keepends=True),
                                                 f"docs/python/{f.name}", f"regenerated/{f.name}"))
                if diff:
                    add = sum(1 for l in diff if l.startswith("+") and not l.startswith("+++"))
                    rem = sum(1 for l in diff if l.startswith("-") and not l.startswith("---"))
                    findings.append(f"docs/python/{f.name} is STALE: +{add} -{rem} lines")
    for f in findings:
        print(f"  !! {f}")
    if findings:
        if any("STALE" in f for f in findings):
            print("  -> python tools/release/check_api_pages.py --update, review, commit")
        return 1
    print("  API pages current; every shipped package has a page and a nav entry")
    return 0


if __name__ == "__main__":
    sys.exit(main())
