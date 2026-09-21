#!/usr/bin/env python3
"""Do the LANDING PAGES still describe what we are about to publish?

    tools/release/check_landing_pages.py            # report, exit 1 on a finding
    tools/release/check_landing_pages.py --list     # just show what it considers a landing page

WHY THIS EXISTS, and why it must run BEFORE a tag:

  **A PyPI description is baked into the upload and cannot be edited afterwards.** There is no
  "edit README" on pypi.org — the long description is package metadata, fixed at upload time. If a
  README is stale when you tag, the only remedy is to publish another version whose sole purpose is
  to refresh the page (peclet has done exactly that: `peclet 1.1.1 — metapackage only, to refresh a
  page no edit could reach`).

  It has bitten this project repeatedly, most sharply at 1.2.0: `peclet`, `peclet-cu13` and
  `peclet-halo` all shipped landing pages saying scene authoring lived in `peclet.core` behind the
  `[mpi]` extra — which is the precise thing that release existed to fix. The code was right and
  the shop window was wrong.

WHAT IT CHECKS, and why it needs no list of its own:

  1. RETIRED SPELLINGS. `docs/NAMING.md` §2 is the canon: rows of `| former | canonical | status |`
     where a status of removed / aliased / planned means the former spelling is on its way out.
     This tool parses that table and greps every landing page for those former spellings.

     A hit is NOT automatically a failure. Migration prose *should* name the old spelling — "was
     `peclet.core.geom` until 1.2.0" is exactly what a reader needs. So the rule is: mentioning a
     retired spelling is fine **if the canonical replacement is named nearby** (same line, or the
     line before/after). A retired spelling standing alone is a stale page.

  2. SELF-IDENTIFICATION. A package's landing page should name the distribution it actually ships.
     core/README.md badged `peclet-core` while its pyproject published `peclet-halo`; a reader
     landing on the peclet-halo page saw another package's name and version.

  Because the rule set comes from NAMING.md, every future rename is covered the day it is recorded
  there — which is also an incentive to record it.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NAMING = ROOT / "docs" / "NAMING.md"

# Landing pages that are not a package readme but are the first thing a human reads.
EXTRA_PAGES = ["README.md", "docs/index.md"]


def divergences() -> list[tuple[list[str], list[str], str]]:
    """(former spellings, canonical spellings, status) from NAMING.md §2."""
    if not NAMING.exists():
        return []
    rows, in_table = [], False
    for line in NAMING.read_text().splitlines():
        if line.startswith("## 2."):
            in_table = True
            continue
        if in_table and line.startswith("## ") and not line.startswith("## 2."):
            break
        if not in_table or not line.startswith("| `"):
            continue
        cols = [c.strip() for c in line.strip("|").split("|")]
        if len(cols) < 3:
            continue
        status = cols[-1].lower()
        if not any(k in status for k in ("removed", "aliased", "planned")):
            continue
        # ONLY the first backticked token of each column is the spelling; the rest is context.
        # A row like "`peclet.core.geom` (dist `peclet-core`, sdist behind `[mpi]`)" names three
        # things and only the first is the name that retired — taking them all made the gate flag
        # `peclet-core` everywhere, including the REPOSITORY and CMake package, which did not move.
        former_all = re.findall(r"`([^`]+)`", cols[0])
        canon = re.findall(r"`([^`]+)`", cols[1])
        former = former_all[:1]
        former = [f for f in former
                  if len(f) >= 4 and (f.startswith("peclet") or any(c in f for c in "._-("))]
        if former:
            rows.append((former, canon, cols[-1]))
    return rows


def package_dirs() -> list[Path]:
    """The real package checkouts: the umbrella's submodules, plus any sibling package not yet a
    submodule (peclet-geom today). Deliberately NOT every sibling directory — this suite runs a dozen
    git WORKTREES beside the submodules (`flow-aniso`, `core-cpu-budget`, `tel/flow`, …) and each
    carries its own README. Those are copies of a branch, not landing pages; checking them reports
    the same finding a dozen times and, worse, reports findings for branches nobody is publishing."""
    dirs = [ROOT]
    gm = ROOT / ".gitmodules"
    if gm.exists():
        for line in gm.read_text().splitlines():
            line = line.strip()
            if line.startswith("path ="):
                d = ROOT / line.split("=", 1)[1].strip()
                if d.is_dir():
                    dirs.append(d)
    for extra in ("geom",):                  # a package repo that is not (yet) a submodule
        d = ROOT / extra
        if d.is_dir() and d not in dirs:
            dirs.append(d)
    return dirs


def landing_pages() -> list[tuple[Path, str | None]]:
    """(page, the distribution it is the PyPI description of — None for a plain doc page)."""
    pages: list[tuple[Path, str | None]] = []
    candidates = []
    for d in package_dirs():
        candidates.append(d / "pyproject.toml")
        candidates.extend(sorted(d.glob("packaging/pyproject-*.toml")))
    for pp in candidates:
        if not pp.exists() or "/build" in str(pp) or "/.venv/" in str(pp):
            continue
        try:
            data = tomllib.loads(pp.read_text())
        except Exception:
            continue
        proj = data.get("project", {})
        readme, dist = proj.get("readme"), proj.get("name")
        if isinstance(readme, dict):
            readme = readme.get("file")
        if not readme or not dist:
            continue
        # A pyproject under packaging/ (peclet-cu13, the peclet-core shell) is COPIED over the
        # repo's pyproject.toml at build time, so its `readme` is relative to the repo ROOT, not to
        # packaging/. Resolving it relative to its own directory silently finds nothing — and a
        # page that silently is not checked is exactly how peclet-cu13 shipped a stale one.
        base = pp.parent.parent if pp.parent.name == "packaging" else pp.parent
        page = (base / readme).resolve()
        if not page.exists():
            print(f"!! {pp.relative_to(ROOT)} declares readme={readme!r} but {page} does not exist")
            continue
        pages.append((page, dist))
    for rel in EXTRA_PAGES:
        p = (ROOT / rel).resolve()
        if p.exists():
            pages.append((p, None))
    seen, out = set(), []
    for p, d in pages:                       # one entry per (page, dist)
        if (p, d) not in seen:
            seen.add((p, d)); out.append((p, d))
    return out


# Contexts where an old string is NOT a stale claim about what we publish.
# Mark a deliberate mention with `<!-- landing-ok: why -->` on or near the line.
_EXEMPT = (
    "github.com/",            # repository URLs — the peclet-core REPO keeps its name (CORE_BOUNDARY §1.1)
    "github.io/",             # docs-site URLs, likewise
    "find_package(",          # the CMake package name did not move either
    "img.shields.io",         # a badge URL names the thing it badges; the self-identification check covers those
    "zenodo.org",             # DOI lineage is attached to the repository, not the distribution
)


def _is_exempt(line: str) -> bool:
    return any(tok in line for tok in _EXEMPT)


def check(verbose: bool = False, dists: set[str] | None = None) -> int:
    rules = divergences()
    pages = landing_pages()
    if dists:
        # Only the pages this upload CREATES. The umbrella's release publishes `peclet` and
        # `peclet-cu13` and nothing else: a member's PyPI description is created by that member's
        # own release, so gating the umbrella on dem's README blocks a metapackage refresh for a
        # page it does not publish. Worse, it is not even the page CI can see — submodules are
        # checked out at the umbrella's recorded POINTERS, which legitimately lag a member's main
        # whenever that member is deliberately not being re-released.
        pages = [(pg, d) for pg, d in pages if d in dists]
        if not pages:
            print(f"!! --dists {sorted(dists)} matched no landing page — check the names")
            return 1
    if verbose:
        print(f"{len(rules)} retired spellings from NAMING.md §2; {len(pages)} landing pages\n")
        for p, d in pages:
            print(f"  {d or '(doc page)':<22} {p.relative_to(ROOT)}")
        return 0
    if not rules:
        print("!! no divergence rows parsed from docs/NAMING.md §2 — the gate would pass vacuously")
        return 1

    findings = 0
    seen_findings: set = set()
    for page, dist in pages:
        lines = page.read_text().splitlines()
        rel = page.relative_to(ROOT)
        for former_list, canon_list, status in rules:
            for former in former_list:
                pat = re.compile(r"(?<![\w.-])" + re.escape(former) + r"(?![\w])")
                for i, line in enumerate(lines):
                    if not pat.search(line):
                        continue            # word-bounded: `layout()` must not match `tight_layout()`
                    if _is_exempt(line):
                        continue
                    # Migration prose: the canonical replacement named in the neighbourhood. Good
                    # docs DO name the old spelling — "was `peclet.core.geom` until 1.2.0" is what a
                    # reader needs — so the rule is that the replacement must appear beside it.
                    window = "\n".join(lines[max(0, i - 3):i + 4])
                    if canon_list and any(c in window for c in canon_list):
                        continue
                    # Deliberate mention with no replacement to name — a negative statement
                    # ("the module has no `mpi_rank()`"), a historical note, a changelog line.
                    # Opt out explicitly and say why; silence is not an option the gate offers.
                    if "landing-ok:" in window:
                        continue
                    key = (rel, i + 1, former)
                    if key in seen_findings:
                        continue            # one report per (page, line, spelling), not per rule
                    seen_findings.add(key)
                    findings += 1
                    print(f"  !! {rel}:{i + 1}  retired spelling `{former}` ({status})")
                    print(f"     canonical: {', '.join('`%s`' % c for c in canon_list) or '(none recorded)'}")
                    print(f"     {line.strip()[:110]}")
        # Self-identification: does the page name the distribution it ships as?
        if dist and dist not in page.read_text():
            findings += 1
            print(f"  !! {rel}  is the PyPI description of `{dist}` but never names it")
            print(f"     a reader landing on the {dist} page sees another package's name/badges")

    if findings:
        print(f"\n{findings} finding(s). A PyPI description CANNOT be edited after upload — fix these")
        print("BEFORE tagging, or the only remedy is publishing another version to refresh the page.")
        return 1
    print(f"landing pages OK — {len(pages)} pages checked against {len(rules)} retired spellings")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="show the landing pages and rule count, then exit")
    ap.add_argument("--dists", metavar="A,B",
                    help="only the pages of these distributions — what a single upload CREATES. "
                         "Omit for the whole suite (the pre-flight's broader sweep).")
    a = ap.parse_args()
    sys.exit(check(verbose=a.list, dists=set(a.dists.split(",")) if a.dists else None))
