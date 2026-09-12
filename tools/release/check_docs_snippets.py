#!/usr/bin/env python3
"""Do the suite's OWN docs still run against the released peclet? (docs/RELEASE.md §9)

`audit_examples.py` guards the sibling gallery; nothing guarded the landing page. At 1.0.0 the
quick start on `README.md`, `docs/index.md` and the Colab notebook still called `cell_centres()`
and `set_body_force(fx, fy, fz)`, both deleted by the clean break, so the first thing a new user
ran raised `TypeError`. Two checks, because those two breakages need different ones:

  RUN    `README.md`, `docs/index.md` and `docs/notebooks/*.ipynb` are the pages a reader copies
         or opens in Colab, and every python block on them is part of ONE runnable script. They
         are EXECUTED against whatever `--python` imports — point it at a fresh venv holding the
         published wheels and it reproduces Colab exactly. This is the only check that catches a
         SIGNATURE change: `set_body_force(fx, fy, fz)` -> `set_body_force(force)` renamed
         nothing, so a name-based audit waves it through.

  NAMES  every other page under `docs/` is prose with illustrative fragments, not a runnable
         script. Their python blocks are matched by NAME against the binding surface at a git ref,
         as `audit_examples.py` does for the gallery.

    python tools/release/check_docs_snippets.py                       # names only, fast
    python tools/release/check_docs_snippets.py --run --python .venv-release/bin/python

Exit status is non-zero if any page fails. `docs/NAMING.md`, `CHANGELOG.md` and `docs/archive/`
are skipped by design: they RECORD the retired spellings.
"""
import argparse, json, os, re, subprocess, sys, tempfile
from pathlib import Path

SUITE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SUITE / "tools" / "release"))
from audit_examples import BINDINGS, CALL_RE, STOPWORDS, surface  # noqa: E402

# The pages a reader is meant to run verbatim.
RUNNABLE = ["README.md", "docs/index.md", "docs/notebooks/quickstart_sphere.ipynb"]
# amr is the D9 exception: it stays 0.x while the rest of the family is 1.0.0.
REF_OVERRIDE = {"amr": "v0.1.0"}

# Pages that quote retired names on purpose.
SKIP_NAMES = {"docs/NAMING.md", "CHANGELOG.md", "docs/RELEASE_PREP.md"}
SKIP_DIRS = {"archive", "decisions", "notebooks"}

FENCE_RE = re.compile(r"```(?:python|py)\n(.*?)```", re.S)
PRELUDE = (
    "import matplotlib\n"
    "matplotlib.use('Agg')\n"
    "import matplotlib.pyplot as plt\n"
    "plt.show = lambda *a, **k: None\n"
)


def blocks(path: Path):
    """The python source of a page, in reading order."""
    text = path.read_text(errors="ignore")
    if path.suffix == ".ipynb":
        nb = json.loads(text)
        return ["".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"]
    return FENCE_RE.findall(text)


def script(path: Path):
    """One script from a page: its blocks share state, as they do for the reader."""
    out = []
    for b in blocks(path):
        # Colab/Jupyter bootstrap lines are not python.
        out.append("\n".join(l for l in b.splitlines() if not l.lstrip().startswith(("%", "!"))))
    return PRELUDE + "\n".join(out)


def run_pages(python: str, timeout: int) -> int:
    bad = 0
    for rel in RUNNABLE:
        src = script(SUITE / rel)
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "page.py"
            p.write_text(src)
            env = dict(os.environ, OMP_NUM_THREADS=os.environ.get("OMP_NUM_THREADS", "8"),
                       OMP_PROC_BIND="false", MPLBACKEND="Agg")
            r = subprocess.run([python, str(p)], cwd=tmp, env=env, capture_output=True,
                               text=True, timeout=timeout)
        if r.returncode == 0:
            tail = [l for l in r.stdout.splitlines() if l.strip()][-1:] or [""]
            print(f"RUN   PASS  {rel}   {tail[0][:90]}")
        else:
            bad += 1
            err = [l for l in r.stderr.splitlines() if l.strip()][-1:] or [""]
            print(f"RUN   FAIL  {rel}\n            {err[0][:160]}")
    return bad


def check_names(ref: str) -> int:
    known = set()
    for sub in BINDINGS:
        known |= surface(sub, REF_OVERRIDE.get(sub, ref))
    if not known:
        sys.exit(f"no binding surface at ref {ref!r} — is the tag fetched in every submodule?")
    # The umbrella docs plus every submodule README — those are the PyPI project pages, as
    # user-facing as the site and equally able to ship a call that no longer exists.
    pages = ([SUITE / "README.md"] + sorted((SUITE / "docs").rglob("*.md"))
             + [SUITE / sub / "README.md" for sub in sorted(BINDINGS)])
    bad = 0
    for page in pages:
        rel = page.relative_to(SUITE).as_posix()
        if rel in SKIP_NAMES or SKIP_DIRS & set(page.relative_to(SUITE).parts):
            continue
        if not page.exists():
            continue
        gone = sorted({m.group(1) for b in blocks(page) for m in CALL_RE.finditer(b)}
                      - STOPWORDS - known)
        # Anything left is either a retired peclet name or third-party (numpy, matplotlib, ...);
        # only names that look like a peclet call are worth a human's time.
        gone = [n for n in gone if re.match(r"(set_|get_|enable_|disable_|add_|num_|step|init_|"
                                            r"cell_|sphere_|export_|extract_|segment_|solve|"
                                            r"rebalance|relax|vof_|scene_)", n)]
        if gone:
            bad += 1
            print(f"NAMES FAIL  {rel}: {', '.join(gone)}")
    if bad == 0:
        print(f"NAMES PASS  every doc page's peclet calls exist at {ref}")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", default="v1.0.0", help="git ref of the submodule bindings to check "
                                                    "the names against (default v1.0.0; amr is "
                                                    "pinned to its own tag, see REF_OVERRIDE)")
    ap.add_argument("--run", action="store_true", help="also EXECUTE the runnable pages")
    ap.add_argument("--python", default=sys.executable,
                    help="interpreter for --run; use a fresh venv with the published wheels")
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()
    bad = check_names(a.ref)
    if a.run:
        bad += run_pages(a.python, a.timeout)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
