import re, pathlib
OUT = pathlib.Path("/home/frankp/Codes/suite/docs")
AREAS = [("flow","flow — Navier-Stokes, IBM, pressure/velocity solve"),
         ("dem","dem — XPBD, contacts, packing"),
         ("voro","voro — tessellation, ConvexCell, mesh optimizer"),
         ("amr","amr — block octree, mixed-level cut band"),
         ("core","core — decomposition, halo, rebalance"),
         ("coupling","coupling — CFD-DEM"),
         ("pnm","pnm — pore-network extraction"),
         ("suite-wide","suite-wide — naming, layout, provisioning")]
hdr = """# Decision register

What this project **chose**, what it **rejected**, and why. It exists because settled decisions were
being silently reversed — a later session picking the textbook alternative because nothing in front
of it said the project had already rejected that alternative on purpose.

**Read the entry for anything you are about to change.** Reversing a decision here takes a new,
explicit decision recorded the same way, with what changed to justify it — never a judgement call in
the moment.

The highest-risk prohibitions are additionally inlined in each submodule's `CLAUDE.md`, because a
register only works if it is reachable from where the work happens. This file is the index; the
verbatim quotes, provenance and supersession chains live in `docs/decisions/<area>.md`.

Entries marked ⚠️ are unresolved contradictions found during the harvest — do not rely on either
reading until they are settled.

"""
lines=[hdr]
tot=0
for area, title in AREAS:
    f = OUT/"decisions"/f"{area}.md"
    if not f.exists(): continue
    txt=f.read_text()
    ents=[]
    for b in re.split(r"(?m)^(?=### )", txt):
        if not b.startswith("### "): continue
        t=b.split("\n")[0][4:].strip()
        src=re.search(r"^- source:\s*(\S+)", b, re.M)
        rej=re.search(r"^- rejected:\s*(.+)$", b, re.M)
        st=re.search(r"^- status:\s*(\S+)", b, re.M)
        r=(rej.group(1).strip() if rej else "")
        r="" if r.lower().startswith("none") else r
        mark = " *(superseded)*" if st and st.group(1)=="superseded" else ""
        ents.append((t, r, src.group(1) if src else "", mark))
    live = sorted(e for e in ents if not e[3])
    old_ = sorted(e for e in ents if e[3])
    lines.append(f"## {title}\n\n{len(live)} in force, {len(old_)} superseded — full text in "
                 f"[`decisions/{area}.md`](decisions/{area}.md)\n")
    lines.append("### In force\n")
    for t,r,src,mark in live:
        rr = f" **Rejected:** {r[:150]}" if r else ""
        lines.append(f"- **{t}**.{rr}  <sub>{src}</sub>")
    if old_:
        lines.append("\n### Superseded — history, do not re-derive the old reading\n")
        for t,r,src,mark in old_:
            lines.append(f"- {t}.  <sub>{src}</sub>")
    lines.append("")
    tot+=len(ents)
(OUT/"DECISIONS.md").write_text("\n".join(lines))
print(f"docs/DECISIONS.md: {tot} entries, {len(open(OUT/'DECISIONS.md').read())} bytes")
