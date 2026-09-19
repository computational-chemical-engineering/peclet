# peclet — JOSS paper outline

Editorial note for the drafter. This is the argument and the section plan, not the prose. Every
sentence of the draft must be testable against Part 1; every number must trace to Part 3's evidence
column. Written 2026-09-19 against family release 1.1.0 and the gallery at the same date.

## 0. Two corrections to the brief that change the plan

Checked against JOSS's live documentation (`joss.readthedocs.io`, `paper.html`, `review_criteria.html`,
`review_checklist.html`, `submitting.html`) on 2026-09-19. **Re-check these pages on the day of
submission; they have changed recently and may again.**

1. **The section list and the word count are not what the brief says.** JOSS currently requires,
   in this order: *Summary*, *Statement of need*, *State of the field*, *Software design*, *Research
   impact statement*, *AI usage disclosure*, then *Acknowledgements* and *References*. The reviewer
   checklist has a checkbox per section by name — a paper missing one fails the checklist. The
   guidance is "between 750–1750 words". The brief's "250–1000" is the old rule. **The ceiling for this
   paper stays at 1000 words** (the user's constraint, and the right length for a citation handle);
   1000 sits inside the current range, and the budget below sums to 940 with the six required
   sections present.

2. **JOSS requires an "AI usage disclosure" section**, and its policy says failure to disclose "may
   be considered an ethical breach" with desk rejection among the consequences. The reviewer
   rubric grades it: "Good: clear, specific disclosure of AI tool usage and verification methods."
   This removes the "whether" from §6 of the brief. Part 5 gives the ruling on *how*.

Two further facts the submission checklist (out of scope here, but load-bearing) must carry:

- **Six-month public-history rule.** JOSS requires the repository to have been public for more than
  six months before submission, with active development across that period. GitHub creation dates:
  `peclet-voro` 2026-03-26, `peclet-dem` and `peclet-flow` 2026-04-11, `peclet-morton` 2026-05-29,
  `peclet-core` and the umbrella `peclet` 2026-05-31, `peclet-coupling` 2026-07-04, `peclet-pnm`
  2026-07-24, `peclet-amr` 2026-09-10. The paper's subject is the suite, whose umbrella clears the
  bar on **2026-12-01**; flow/dem clear it 2026-10-11. Plan the submission date accordingly and
  decide (Frank's call) whether the umbrella is the reviewed repository.
- **Reviewers read `git log`.** The umbrella's 691 commits are authored `Claude <noreply@anthropic.com>`
  (683 of them); flow carries `Co-Authored-By: Claude` on 594 of 690 commits; core on 276 of 291;
  dem on 196 of 249. The disclosure section is therefore describing something the reviewer will
  have already seen in the first minute. Write it accordingly — as a statement of record, not a
  confession.

## 1. The storyline in one paragraph

Pore-scale and particle-laden transport problems — packed and fluidized beds, porous media,
granular flow with interstitial fluid — are not one simulation but a chain: build a particle
packing, turn it into geometry, resolve the flow through it (single- or two-phase), and reduce the
resolved result to the quantities a process engineer uses. Today that chain is three or four
specialist codes joined by conversion scripts and files, each excellent at its own link and
indifferent to the others. `peclet` is one Python-driven, GPU-resident, MPI-distributed suite in
which every link — DEM, signed-distance geometry, cut-cell immersed-boundary Navier–Stokes,
volume-of-fluid, Voronoi meshing, pore-network extraction, and CFD–DEM coupling — runs on the same
block decomposition and halo exchange in the same process, with data crossing between them as
NumPy views rather than files. It is not the fastest code at any single link on a single device
and the paper says so; what it offers, which none of the incumbents does, is the whole chain on
one foundation, from a laptop to 32 GPUs, with every step verified against published references
in a public, executed gallery. The evidence for the "one foundation" claim is that the physics
observable is bit-for-bit stable across 34 runs from 1 to 1536 ranks on two backends.

**Test for every sentence in the draft:** does it advance "one chain, one foundation, evidence
attached"? If it advances "fast", "portable", "Pythonic" or "well tested" *on its own*, it is
supporting material and belongs inside a sentence about the chain, or it goes.

## 2. The claim to distinctiveness, and why the others lost

**Chosen: §4.2.1 — cross-method composition on one decomposition.** It is the only property in the
list that no comparator possesses, it is what the target audience actually lacks, and it is the
property the architecture was built around (one `BlockDecomposer` shared by every method is a
recorded suite-wide decision; `docs/DECISIONS.md`). It also gives the Statement of Need its
"build vs. contribute" answer, which JOSS now asks for by name: you cannot contribute a shared
decomposition to four separate codes.

The others lost, and the drafter must not re-open them:

- **§4.2.2 Performance portability (Kokkos).** AMReX/incflo, MFIX-Exa and CaNS (OpenACC/cuDecomp)
  are already performance-portable; "one source for CUDA/HIP/OpenMP" describes the field's
  baseline, not a distinction. It survives as **one clause in Software design**.
- **§4.2.3 Python-first, zero-copy.** OpenPNM, PoreSpy, PyFR, FEniCS and Dedalus are Python-first;
  the distinction is not the language but that Python is the composition layer for the chain in
  §1 — which is claim 1 again. The zero-copy mechanism (nanobind, views into solver memory) is
  **the enabling detail of claim 1** and appears in Software design as such. "Solvers take physical
  quantities" is a usability property; one clause, no more.
- **§4.2.4 Verification apparatus.** This is not a property of the software; it is the *evidence*
  for whatever the paper claims. Promoting it to the claim invites "so it is well tested — what
  does it do?" It is used everywhere and claimed nowhere.
- **§4.2.5 Device-first, distributed by construction.** True of AMReX, MFIX-Exa, CaNS and LIGGGHTS.
  Not distinctive. It appears as the *reason* claim 1 is possible (a chain can only share a
  decomposition if every link is distributed), inside Software design.

**Why "another GPU CFD code, but in Python" loses on its own terms:** on one H100 CaNS is 2.3×
faster and on one CPU node 3× faster (`benchmarks/parallel-scaling`). A paper that leads with speed
loses to the first reviewer who opens that page.

## 3. Section-by-section outline (budget: 940 of 1000 words)

Section titles are JOSS's exact strings; the checklist matches on them. American spelling.

### 3.1 Summary — 130 words

*Must contain*
- One sentence on what peclet is: a suite of GPU-accelerated, MPI-parallel codes for transport
  phenomena in particle-laden and porous systems, driven from Python.
- The chain, in one sentence, with the package names in parentheses once: DEM (`peclet-dem`),
  geometry as signed-distance fields, cut-cell immersed-boundary incompressible Navier–Stokes
  with volume-of-fluid (`peclet-flow`), dynamic Voronoi tessellation (`peclet-voro`), pore-network
  extraction (`peclet-pnm`), CFD–DEM coupling (`peclet-coupling`), on a shared decomposition,
  halo-exchange and geometry layer (`peclet-core`, `peclet-morton`).
- One sentence on scale: runs on one CPU, one GPU, or across nodes (CUDA, HIP, OpenMP via Kokkos);
  `pip install peclet` / `peclet-cu13`; CPython 3.10–3.14; Linux, Windows, macOS wheels.
- One sentence on evidence: a public gallery of 46 executed examples and eight benchmark
  studies with frozen outputs, validated against published references.

*Evidence used*: §4.1 table (package names only, no versions); §4.4 (wheel platforms, from
`README.md`); gallery counts **46 examples, 8 benchmark pages** (the brief's "11 benchmark
studies" counts directories; two of the ten directories have no page — `momentum-solver`,
`release-1.0.0-scaling` — say eight).

*Must NOT say*: any performance number; any test count; "state of the art"; the word "fast";
`peclet-amr` (0.x, under development — omit from the paper entirely or a reviewer will install
it and test it); version numbers of individual packages (the CITATION.cff / Zenodo DOI carries
them and the paper would go stale).

### 3.2 Statement of need — 220 words

*Must contain*, in this order:
1. **The audience**: researchers in chemical and process engineering, porous-media physics and
   granular flow who simulate transport through particle assemblies — packed beds, fluidized
   beds, trickle beds, pore-scale two-phase displacement, pore-network models.
2. **The problem**: these are chains, not single simulations (the list in §1). Each link has an
   excellent specialist code; no code has the chain. The cost is conversion scripts, file
   handoffs, N geometry conventions, and — when the problem is large — the impossibility of
   distributing a chain whose links do not share a decomposition.
3. **What peclet does about it**: every link is a method on one decomposition and one halo
   exchange, in one process; a DEM packing becomes an SDF becomes cut-cell operators becomes a
   VoF interface's boundary becomes a pore network, with the intermediate results exposed as NumPy
   (or CuPy) views. The gallery demonstrates the chain end to end (cite three pages by name:
   `random-packed-bed` dem→flow; `bubble-through-packing` dem→sdf→VoF; `pore-network-extraction`
   flow→pnm; and `fluidized-bed` for the two-way coupling at 965 000 particles).
4. **The build-vs-contribute sentence** (JOSS asks for it): a shared decomposition cannot be
   contributed to four independently designed codes; it has to be the foundation they are built on.
5. **The concession, in the same paragraph**: peclet is not the fastest code at any single link on
   a single device (see State of the field); it is the only one of these that offers the chain.

*Evidence used*: gallery pages named above; the shared-`BlockDecomposer` design (`docs/ARCHITECTURE.md`).

*Must NOT say*: any comparison numbers (they go in State of the field); "framework" or
"platform" (it is a suite of method codes); that the gallery runs the chain *distributed* — the
gallery examples are single-rank and the shared decomposition is an architecture property
demonstrated by the scaling records, not by the chain pages; anything about how the code was
written (Part 5).

### 3.3 State of the field — 200 words

*Must contain*: the comparison strategy of Part 4, exactly. Nine codes named, in four groups, one
sentence each on what they are best at, one sentence on where peclet stands relative to each
group, and the loss sentence quoted verbatim from Part 4.

*Evidence used*: `benchmarks/parallel-scaling` (CaNS/incflo/OpenFOAM head-to-head; cite as a
study on a **pre-1.0 development build, 2026-08**, because the page itself says every peclet
number predates the multigrid residual-halo fix, and the 1.1.0 record explicitly states it "is not
a comparison against other codes"); `benchmarks/dem-bulk-dosta2024` (DEM8 community benchmark,
Dosta et al. 2024, re-run against MUSEN and LIGGGHTS on one machine — the brief omitted this and
it is the strongest DEM evidence the project has).

*Must NOT say*: "fastest" without the qualifier "general-geometry" and the date/version of the
study; any Mcell/s figure without its GPU count; that CaNS "collapses" (say "its FFT solve's
all-to-all does not survive the node boundary at the settings tested, 5.9 % at 32 GPUs" — the
page's own caveat about cuDecomp's transpose backend must be carried in one clause); anything about
Basilisk, PyFR, YADE, Project Chrono, PoreSpy (not named; no room, and none is the incumbent the
audience would reach for first).

### 3.4 Software design — 190 words

*Must contain* (this is where claims 2, 3 and 5 live as supporting structure):
- The layering: `core` (ORB block decomposition, asynchronous ghost-layer exchange with NBX and
  persistent neighborhood collectives, particle migration, SDF geometry, load balancing) beneath
  every method; the trade-off named: one decomposition for all methods costs each method the
  freedom to choose its own (e.g. a pencil decomposition that would enable an FFT solve), and that
  is the price of the chain.
- Device-first: every method runs on the device and across ranks; host paths exist as test
  oracles only. Kokkos gives CUDA, HIP and OpenMP from one source; the hand-written CUDA
  implementations were retired once the Kokkos port was validated bit-identical (one clause; this
  is the "never change numerics while porting" policy, stated as a fact not a slogan).
- Python as the composition layer: nanobind bindings, fields and particle states as zero-copy
  NumPy/CuPy views into solver memory; solvers take a physical domain and physical properties
  and derive the discretization.
- The correctness contract that the design is built to keep, with the number: the physics
  observable (mean velocity after 13 steps of creeping flow through a 1043-sphere cut-cell packing)
  agrees to a worst relative deviation of 8e-11 across 34 runs, 1 to 1536 ranks, CUDA and OpenMP
  backends, 56.6 M to 1.81 billion cells; the geometry-free control to 4e-16.
- The scaling envelope, in one sentence with both the win and the hole: weak scaling 1 → 32 H100
  at 56.6 M cells per GPU reaches 1.81 billion cells at 64 % efficiency with pressure iterations
  flat (29.7 → 29.8); strong scaling 24 → 1536 cores, 36.3 s → 0.89 s per step; one strong-scaling
  rung (16 GPUs) is reproducibly 2.3× slower than its neighbours and is reported undiagnosed.

*Evidence used*: `benchmarks/release-1.1.0-scaling` (`headline.json` is the source of record for
every number above — quote from it, not from the gallery blurb, which says "27 runs" where the
record says 34); flow/dem README for CUDA retirement.

*Must NOT say*: the 7.7 Gcell/s / 90 % figure (that is the pre-1.0 Taylor–Green head-to-head at a
looser tolerance; it belongs in State of the field with its provenance, not here as the design's
scaling claim); any per-package test count (JOSS reviewers run the tests; a number in the paper
is a number that goes stale); anything about the multigrid depth default or momentum-solver
selection (methods-paper material); API names beyond `peclet.flow.Solver` if one example is needed.

### 3.5 Research impact statement — 90 words

JOSS asks for "evidence of realized impact (publications, external use, integrations) or credible
near-term significance". The honest content is near-term significance; do not inflate.

*Must contain*: the suite is installed as site packages on two national systems (Snellius, LUMI)
and shipped as Apptainer/Docker containers on GHCR; the gallery's validation cases are the
canonical benchmarks of the field (Ghia 1982; Zick & Homsy 1982; ten Cate et al. 2002; Verma et
al. 2014; Moser–Kim–Mansour 1999; Hysing et al. 2009; Dosta et al. 2024) and each is a runnable
page; every example page but a handful opens in a free Colab runtime.

*Evidence used*: `docs/DEPLOYMENT.md`, `docs/SNELLIUS.md`, `docs/LUMI.md`, `docs/containers.md`;
the gallery.

*FLAG FOR FRANK — needed before drafting*: (a) any publication, preprint or thesis that has used
peclet; (b) any external group using it; (c) whether the RingBed surrogate study or a TU/e course
counts as use he wants named; (d) whether the LUMI site package has actually been exercised on AMD
hardware (RELEASE_PREP calls it "still untested on AMD hardware" as of 2026-09-12 — if still true,
say "Snellius" only). Without (a)/(b) this section says "credible near-term significance" and no
more.

*Must NOT say*: "widely used", "adopted", "community" (GitHub shows 1 star and 7 issues as of
2026-09-19); "every example runs in Colab" (43 of 57 pages carry the badge; five examples and all
benchmark pages do not).

### 3.6 AI usage disclosure — 80 words

Content and wording constraints in Part 5. Fixed position: after Research impact statement, before
Acknowledgements — where JOSS lists it.

### 3.7 Acknowledgements — 30 words

*FLAG FOR FRANK*: funding (grant numbers), the Snellius allocation (project id `prjs1022` appears in
the benchmark scripts — confirm the citable form and the NWO/SURF acknowledgement wording), and any
co-author or contributor to be credited. `CITATION.cff` lists one author; JOSS's rule is that
active project direction counts for co-authorship but tool use does not — Claude is not an author
and is not named here (Part 5).

### 3.8 References — not counted

Part 6.

**Sum: 130 + 220 + 200 + 190 + 90 + 80 + 30 = 940.** The 60 spare words are the drafter's, for
transitions; they are not a licence for a seventh section.

## 4. The Statement of Need's comparison strategy (executed in State of the field)

**Framing rule**: every comparator is named for what it does *best*, in one clause, so that the
comparison reads as a map of the field and not as a list of things peclet beats. The sentence
that positions peclet against a group follows the praise, never precedes it.

| Group | Named | Framing (what they are best at) | Where peclet stands |
|---|---|---|---|
| Incompressible CFD | **OpenFOAM**; **AMReX/incflo**; **CaNS** | OpenFOAM: the general unstructured code, ubiquitous. incflo: peclet's own method family (finite-volume, geometric-multigrid projection, embedded boundary) at exascale. CaNS: an exact FFT Poisson solve — the fastest thing there is on a periodic box. | Same method family as incflo; on the pre-1.0 head-to-head (Taylor–Green, 2026-08) peclet ran ~4× incflo per CPU node and 6.3× on one GPU at equal weak-scaling; slower than CaNS on one device, ahead of it once the FFT's all-to-all crosses a node. None of the three composes with a DEM or a pore-network layer in-process. |
| DEM | **LIGGGHTS**; **MercuryDPM** | LIGGGHTS: the reference open-source DEM, MPI, wide contact-model library. MercuryDPM: the research DEM with the richest particle-shape and coarse-graining toolset. | peclet-dem holds the DEM8 (Dosta et al. 2024) envelope on silo, drum and impact against MUSEN and LIGGGHTS re-run on one machine, and adds SDF point-shell collision so a grain can be any shape. It is not the broader contact-model library. |
| CFD–DEM | **MFIX-Exa**; **CFDEM** | MFIX-Exa: DOE-exascale unresolved CFD–DEM on AMReX, the reference for gas–solid beds. CFDEM: OpenFOAM + LIGGGHTS, the widely used open coupling. | peclet-coupling offers both unresolved (volume-averaged) and resolved (cut-cell) coupling on one decomposition shared by fluid and particles; validated on the Verma et al. tomography bed (965 000 particles). CFDEM is the file-and-socket alternative the chain argument is about. |
| Pore networks | **OpenPNM** | The pore-network modeling ecosystem, with extraction via PoreSpy. | peclet-pnm does extraction only, from the same SDF the flow solver used, distributed and bit-exact to single-rank; it does not model on the network — hand the network to OpenPNM. Say this: it is the honest interface and it costs nothing. |
| Voronoi | **Voro++** | The standard serial cell-by-cell tessellator. | peclet-voro tessellates moving particles incrementally on the device, periodic and Lees–Edwards, and meshes pore spaces with it; Voro++ is what it benchmarks against. |

**The sentence that concedes where peclet loses** (verbatim, or as close as the draft allows):

> On a single device peclet is not the fastest code at any one of these methods: CaNS's FFT
> solve is 2.3× faster on one H100 and 3× on one CPU node, and that lead is the price peclet
> pays for general cut-cell geometry — it holds until the problem spans more than one node.

Follow it immediately with the one-line reason the concession does not undercut the paper:
peclet's claim is the chain, not the link.

**Numbers permitted in this section, with their provenance stated in the text**: 2.3× (one H100),
3× (one CPU node), ~4× incflo per node, 6.3× incflo per GPU, 90 % weak efficiency to 32 H100 on
Taylor–Green, 5.9 % for CaNS at 32 GPUs — all from `benchmarks/parallel-scaling`, a pre-1.0
development build, 2026-08, with the cuDecomp caveat in one clause. Nothing else.

## 5. The ruling on §6 — the agent-authorship question

**Decision: yes, it is in the paper — in the required "AI usage disclosure" section, 80 words,
nowhere else.** Not in the Summary, not in the Statement of need, not in the title or the
abstract-level framing, not as a claim to distinctiveness, and not in the Acknowledgements.

**Reasoning.**

1. *The "whether" is not open.* JOSS requires the section, grades it, and treats omission as a
   possible ethical breach with desk rejection among the listed consequences. The brief's
   "against" arguments were written for a world in which disclosure was optional; that world
   ended when JOSS added the rubric. The reviewer will also see it in `git log` in the first
   minute (Part 0). Concealment is not on the table; under-disclosure is a risk, over-disclosure
   is a distraction.

2. *The "how much" is decided by what the paper is for.* The paper is a citation handle for the
   software. The development method is a fact about provenance, not about what the software
   does, who needs it, or how it compares. It therefore belongs exactly where JOSS puts provenance
   facts — in the disclosure section — and its size is set by the rubric's three required
   elements, not by how interesting it is. Eighty words covers the three elements with room for
   one sentence pointing at the evidence.

3. *The brief's "for" arguments argue for the wrong venue.* "It is the most distinctive thing
   about the project" is true of the *project* and false of the *software*: no user chooses a
   solver because of who typed it. The research-software-engineering audience that cares about
   the method is real, and that story — a year of agent-assisted development with a decision
   register, gates, and an executed gallery as the discipline that made it work — is a paper of its
   own (an RSE venue or a section of the CPC/Computers & Fluids methods paper). Spending JOSS
   words on it buys nothing for the citation handle and hands a hostile reviewer a second target.

4. *Asymmetry of error.* Too little in the disclosure risks a request for revision (cheap: one
   paragraph). Too much — the method as a theme — risks a review that evaluates the development
   process instead of the repository (expensive: months, and a review the paper's evidence was
   not assembled to win). The verification apparatus answers "is the code right?" well; it does
   not answer "should agent-written code be published?", and the paper should not pose that
   question.

**What the 80 words must contain**, in this order, so the reviewer can tick the rubric:

- *Tool use*: "Much of the code, documentation and the benchmark/gallery tooling was written with
  Claude (Anthropic; Claude Code, models Opus 4.x through 5 over 2025-12 → 2026-09), working in
  session with the author." State the model range as Frank confirms it; do not guess versions.
  Also disclose GitHub Copilot if the two `Copilot` commits in flow and `copilot-swe-agent` in the
  gallery warrant it (they do — one clause).
- *Nature and scope*: code generation and refactoring, test writing, documentation and the
  benchmark drivers; the paper text itself was drafted with the same assistance and edited by the
  author (say so if true — it will be).
- *Confirmation of review*: the author framed the problems, made the design decisions (recorded in
  `docs/DECISIONS.md`), and reviewed and validated every output; every method is checked against
  the published references and the multi-rank bit-exactness gates in the gallery, and the git
  history attributes agent-assisted commits with a `Co-Authored-By` trailer.

**What it must NOT contain**: any adjective about the method (novel, first, unusual); any claim
that the agent "designed" anything; percentages of code or commits (they invite arithmetic and are
not what JOSS asks for); a link to the release film; a defence. The tone is a customs declaration.

**On the alternative venues the brief asks about**: (a) repository documentation — already the
case via commit trailers; add nothing there for the paper's sake; (b) a separate paper — yes,
that is where the method story goes, and the JOSS disclosure should *not* pre-empt it with claims
about the method's merits.

## 6. The reference list to assemble (`paper.bib`)

Every entry needs a DOI. Group and cite only what the text names; a reference the text does not
cite is a checklist failure ("everything cited appropriately").

**The software itself**
- peclet, Zenodo concept DOI `10.5281/zenodo.21132445` (cite the concept DOI, version-independent).
- The 1.1.0 scaling record dataset — **its Zenodo DOI is not yet issued** (`release-1.1.0-scaling/index.qmd`
  says "added here when the deposit is published"). *FLAG*: publish the deposit before submission
  or cite the GitHub directory.

**Dependencies (Software design)**
- Kokkos: Trott et al., IEEE TPDS 33(4), 2022, `10.1109/TPDS.2021.3097283`.
- nanobind: Jakob, software, `https://github.com/wjakob/nanobind` (Zenodo DOI exists; look it up).
- ArborX: Lebrun-Grandié et al., ACM TOMS 47(1), 2020, `10.1145/3412558`.

**Comparator codes (State of the field)**
- OpenFOAM: Weller, Tabor, Jasak, Fureby, Comput. Phys. 12, 1998, `10.1063/1.168744`.
- AMReX: Zhang et al., JOSS 4(37), 2019, `10.21105/joss.01370`; incflo cite the AMReX-Fluids
  repository (no paper DOI — check for a Zenodo record).
- CaNS: Costa, Comput. Math. Appl. 76, 2018, `10.1016/j.camwa.2018.07.034`.
- LIGGGHTS: Kloss et al., Prog. Comput. Fluid Dyn. 12, 2012, `10.1504/PCFD.2012.047457`.
- MercuryDPM: Weinhart et al., Comput. Phys. Commun. 249, 2020, `10.1016/j.cpc.2019.107129`.
- MFIX-Exa: Musser et al., Int. J. High Perform. Comput. Appl. 36(1), 2022 (`mfixexa2022` in the
  gallery's `references.bib`, line 139).
- CFDEM: Goniva et al., Particuology 10, 2012, `10.1016/j.partic.2012.05.002`.
- OpenPNM: Gostick et al., Comput. Sci. Eng. 18(4), 2016, `10.1109/MCSE.2016.49`.
- Voro++: Rycroft, Chaos 19, 2009, `10.1063/1.3215722`.

**Validation references (Research impact statement / Software design)** — only the seven the
text names; the gallery's `references.bib` (`/home/frankp/Codes/peclet-examples/references.bib`)
already holds `tencate2002`, `zick1982`, `mkm1999`, `hysing2009`, `mfixexa2022` in citable form.
- Ghia, Ghia & Shin, J. Comput. Phys. 48, 1982, `10.1016/0021-9991(82)90058-4`.
- Zick & Homsy, J. Fluid Mech. 115, 1982, `10.1017/S0022112082000627`.
- ten Cate et al., Phys. Fluids 14, 2002, `10.1063/1.1512918`.
- Verma et al., AIChE J. 60, 2014, `10.1002/aic.14393`.
- Moser, Kim & Mansour, Phys. Fluids 11, 1999, `10.1063/1.869966`.
- Hysing et al., Int. J. Numer. Meth. Fluids 60, 2009, `10.1002/fld.1934`.
- Dosta et al., Powder Technol. 2024 (DEM8 benchmark; key from the gallery page's bib).

**Method references** — the approximate projection (Almgren, Bell, Colella et al., 1998/2000) and
the cut-cell IBM are *not* cited in this paper; they belong to the methods paper. If the drafter
finds a sentence that needs them, the sentence is methods material and should be cut.

## 7. What to leave out — true, tempting, and not in 1000 words

- **`peclet-amr`.** 0.x, "API may change between minors", public for nine days. Not mentioned.
  A reviewer who reads "eight packages" will install eight.
- **Schäfer–Turek.** The page gets St = 0.27 against 0.295–0.305 (~10 % low, attributed to
  resolution) and does not compute C_D/C_L. The brief lists it as a validation; it is not one
  the paper can claim. Omit.
- **MFIX-Exa homogeneous cooling.** The quantitative agreement (~8 %) is against Enskog theory;
  the MFIX comparison is a curve overlay with an unresolved stage offset. Not a validation number.
  Omit (MFIX-Exa is still named as a comparator).
- **Verma bubble diameter "within ~10 %".** Holds at H = 10 cm only; ~35 % high at H = 5 cm and
  the page says so. The paper names the case and the particle count (965 000, not "a million");
  it does not quote the 10 %.
- **Ghia "up to Re 1000".** The page runs Re = 100 only. Name the case, no Reynolds number.
- **Per-package test counts** (53/68/6, 100+3, 47, 42, 155). Reviewers run ctest; numbers in the
  paper age within a release.
- **The 7.7 Gcell/s at 90 % headline as the design claim.** Pre-1.0 build, Taylor–Green, looser
  tolerance. It is a State-of-the-field comparison number with its provenance, or nothing.
- **"Every page has a Colab button" / "executed against the released wheels".** 43 of 57 pages;
  freezes were produced from local builds at the release tags (`peclet-examples/README.md`
  "Provenance of the current freezes"). Say "executed at the release tag and frozen".
- **The momentum-solver selection rule, multigrid depth, coarse-level telescoping, the
  1.1.0 "twice as fast" story, VoF method details, the ghost-projection modes, Lees–Edwards,
  the morton arithmetic-in-Morton-space trick.** All methods-paper or changelog material.
- **The FoxBerry and channel-DNS scaling studies.** Two more numbers the reviewer would have to
  check; the 1.1.0 record and the head-to-head are enough.
- **The physical-units API, the naming canon, the clean-break 1.0.0, the decision register as a
  process.** Repository documentation; JOSS reviews it there.
- **The release film, the YouTube channel, the website.** Out of scope by the brief.
- **Any sentence about the development method beyond the disclosure section.** Part 5.
- **Anything about performance on Windows/macOS beyond "wheels exist".** Threads backend detail
  is DEPLOYMENT.md material.

## 8. Open items for Frank before drafting (collected from above)

1. Submission date vs. the six-month rule: umbrella clears 2026-12-01; flow/dem 2026-10-11.
2. Research impact: publications, external users, theses, the RingBed study — anything citable.
3. LUMI: exercised on AMD hardware or still untested? Determines "two national systems" vs one.
4. Funding and allocation acknowledgement wording; co-authors, if any.
5. The exact model range and dates for the AI disclosure; whether to name Copilot.
6. Zenodo DOI for the 1.1.0 scaling dataset (publish the deposit, or cite GitHub).
