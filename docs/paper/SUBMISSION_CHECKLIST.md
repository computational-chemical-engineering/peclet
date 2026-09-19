# JOSS submission checklist for `peclet`

*Audited against the repositories on 2026-09-19, not against a generic template. Each item says
what a reviewer will actually do, what they will find today, and what to change.*

JOSS reviews the **repository**, not the manuscript: a reviewer installs the software, runs the
tests, reads the docs and the API, and opens issues against the repo. The paper is a citation
handle. So most of this list is about the repository, and only §C is about the paper.

---

## A. Blocking — a submission is not complete without these

### A1. `paper.md` and `paper.bib` in the repository
Present in this directory (JOSS finds `docs/paper/` or the root). Drafted from `OUTLINE.md`,
corrected in a review round on 2026-09-19 (every number re-traced to `headline.json`,
`parallel-scaling`, `dem-bulk-dosta2024` and the gallery; bibliography resolved against Crossref).

- [ ] Resolve every `TODO-FRANK` comment in `paper.md` and `paper.bib`: ORCID, department,
      research impact (publications / external users / LUMI-on-AMD status), the AI-disclosure
      model range and Copilot naming, acknowledgements, and the Zenodo DOI of the 1.1.0 scaling
      record (`@scaling2026` currently cites the GitHub directory, as the page itself instructs
      until the deposit is published).
- [ ] JOSS's **required section names**, in this order, are what the reviewer checklist ticks:
      *Summary*, *Statement of need*, *State of the field*, *Software design*, *Research impact
      statement*, *AI usage disclosure*, then *Acknowledgements* and *References*. The draft has
      all of them; do not rename or merge any. Length guidance is 750–1750 words; the draft is
      ~1000 excluding front matter, comments and references. Re-check `joss.readthedocs.io` on the
      day of submission — the section list changed recently and may again.

### A1b. The six-month public-history rule
JOSS requires the repository to have been public for more than six months, with active
development across that period. GitHub creation dates: `peclet-voro` 2026-03-26, `peclet-dem` and
`peclet-flow` 2026-04-11, `peclet-morton` 2026-05-29, `peclet-core` and the umbrella `peclet`
2026-05-31, `peclet-coupling` 2026-07-04, `peclet-pnm` 2026-07-24, `peclet-amr` 2026-09-10.

- [ ] Decide which repository is submitted (the umbrella is the paper's subject; it clears the bar
      on **2026-12-01**; flow/dem clear it 2026-10-11) and plan the submission date accordingly.
- [ ] Reviewers read `git log`. The umbrella's commits are overwhelmingly authored
      `Claude <noreply@anthropic.com>`; flow carries `Co-Authored-By: Claude` on ~86 % of commits.
      The disclosure section describes what the reviewer sees in the first minute — nothing to
      hide, but nothing to be surprised by either.

### A2. An archived release with its own DOI, matching the version under review
`CITATION.cff` carries the **concept** DOI `10.5281/zenodo.21132445`, which always resolves to the
newest release. JOSS asks for the **version** DOI of the exact archive it reviewed, and the version
under review must be the one the paper describes.

- [ ] Confirm a Zenodo archive exists for **1.1.0** and note its version DOI (the concept DOI
      <https://doi.org/10.5281/zenodo.21132445> resolves — HTTP 302 on 2026-09-19 — but the
      version DOI was not read here; take it from the record's sidebar).
- [ ] Note a version mismatch a reviewer may raise: the gallery's frozen outputs were re-executed
      against **1.0.0** builds (`peclet-examples/README.md`, "Provenance of the current freezes",
      2026-09-14) while the scaling record the paper quotes is **1.1.0**. Either re-freeze at
      1.1.0 or be ready to say why it moves nothing (only `flow` changed for 1.1.0).
- [ ] Confirm the archive's title, author list and licence match `CITATION.cff`.
- [ ] Expect to cut one more release *after* review: reviewers routinely ask for changes, and the
      archived version must be the reviewed one. Plan to re-archive at the end.

### A3. ORCID for the submitting author — DONE 2026-09-19
`0000-0001-6099-3583`, now in `paper.md` and in the umbrella `CITATION.cff`.

- [x] Umbrella `CITATION.cff` and `paper.md`.
- [ ] **The eight package `CITATION.cff` files still have no ORCID** (`core`, `flow`, `dem`, `voro`,
      `pnm`, `morton`, `coupling`, `amr`) — each is its own repository and needs its own commit.
      Not a JOSS blocker (the umbrella is the submission), but it is the citation metadata every
      package's Zenodo record inherits.
- [ ] **Name form is inconsistent and worth settling once.** ORCID's primary name is *Frank
      Peters*; *E.A.J.F. Peters* is an other-name on the same record and is what the 1.1.0 scaling
      deposit uses (set by the author himself). Every `CITATION.cff` says `given-names: Frank`.
      Either is defensible — pick one for the paper byline and make the deposits agree.

### A4. Community guidelines: contribute / report issues / **seek support**
`CONTRIBUTING.md` has *Getting set up*, *Making changes*, *Reporting issues*, *Conduct &
licensing*, and `CODE_OF_CONDUCT.md` exists. JOSS's checklist names three things and the third is
missing: **how to seek support**.

- [ ] Add a short *Getting help* section — where to ask a usage question as opposed to filing a
      bug (GitHub Discussions, or issues with a `question` label, or an email address). One
      paragraph is enough, but the reviewer ticks a box for it.

### A5. Tests a reviewer can actually run — **without a GPU, without building Kokkos**
This is the biggest practical gap. Today the only documented test route is `docs/RELEASE.md`,
which is a maintainer's release-verification matrix: it starts by bootstrapping a Kokkos install
prefix and building each package with CMake. A reviewer with a laptop will not do that, and JOSS's
checklist explicitly asks whether automated tests can be run *by the reviewer*.

- [ ] Add a **Testing** section to the docs (and link it from `README.md` and `CONTRIBUTING.md`)
      that a reviewer can follow in minutes on CPU only:
      - `pip install peclet` then a documented `pytest` invocation against the installed wheels, or
      - a container: `apptainer run ghcr.io/…` with the test command baked in, or
      - the smallest CMake path that needs no GPU (`OpenMP` backend), stated as such.
- [ ] State plainly which parts **cannot** be run without a GPU or MPI, and what the CI covers
      instead. Reviewers accept documented limits; they do not accept silence.
- [ ] Point at the CI workflows as evidence of what runs automatically
      (`.github/workflows/` in each package, and the family quick-start job).

---

## B. Strongly recommended — the things reviewers ding

### B1. Make the repository layout obvious on arrival
`peclet` is an **umbrella**: the code lives in eight submodule repositories, and a clone without
`--recursive` yields empty directories. `README.md` does say `git clone --recursive`, which is good,
but a reviewer's first confusion will be "where is the code?".

- [ ] One short paragraph near the top of `README.md`: this is a meta-repository, the eight
      packages live at these URLs, each is independently versioned and pip-installable, and the
      suite is the unit of release.
- [ ] Say the same thing in one sentence in the paper, so the reviewer is not surprised.

### B2. Version numbering will look inconsistent unless explained
The family release is **1.1.0**, but `core` is 1.0.2, `dem`/`voro`/`pnm` 1.0.2, `morton` 1.0.1,
`coupling` 1.0.1, and `amr` **0.1.1**. That is deliberate (each package versions independently and
only `flow` changed for 1.1.0), but it reads as sloppy if unexplained.

- [ ] State the policy once, in `README.md` and in the paper: the *family* version names a tested
      combination; packages carry their own semantic versions.

### B3. `amr` (0.1.1) is outside the claim
It is explicitly under development, public for nine days. `OUTLINE.md` §7 rules that the paper
does not mention it at all, and the draft does not: the Summary names seven packages. A reviewer
who clones the umbrella will still find eight submodules.

- [ ] Say in `README.md` (not the paper) that `peclet-amr` is experimental and not part of the
      1.x release contract, so the omission reads as deliberate.

### B4. A "statement of need" a reviewer can find in the README
The README describes what the suite *is*. JOSS wants the *need* — who it is for and what problem it
solves — visible in the documentation as well as the paper.

- [ ] Add two or three sentences high in `README.md`, reusing the paper's Statement of Need.

### B5. Installation, verified from clean
Good position already: wheels for CPython 3.10–3.14 (CPU and CUDA), containers on GHCR, site
installs on Snellius and LUMI, and a CI job that runs the documented quick start against the
**published** wheels on every tag.

- [ ] Nothing to change; do point the reviewer at that CI job in the paper or README, because it is
      unusually strong evidence and costs one sentence.

---

## C. The paper itself

### C1. Author list, affiliation, funding
- [ ] Confirm the author list. `CITATION.cff` lists one author (Frank Peters, TU Eindhoven).
- [ ] Add a funding statement if any grant supported the work — JOSS papers normally carry one.
- [ ] Use the institutional email, not the gmail address in `CITATION.cff`, if that is preferred
      for the published record.

### C2. The AI usage disclosure
This is no longer an editorial choice: JOSS **requires** an "AI usage disclosure" section, grades
it (rubric: "clear, specific disclosure of AI tool usage and verification methods"), and lists
desk rejection among the consequences of non-disclosure. `OUTLINE.md` Part 5 fixes the content
(tool use; nature and scope; confirmation of author review) and the tone (a customs declaration —
no adjectives, no defence, no percentages). The draft carries it, ~85 words, nowhere else.

- [ ] An AI system **cannot be an author**; the byline stays as it is.
- [ ] Confirm the model range and dates in the section (see the `TODO-FRANK` comment there for what
      git shows) and whether Copilot is named.

### C3. `paper.bib`
- [x] Validation references harvested from `peclet-examples/references.bib` (`zick1982`,
      `tencate2002`, `mkm1999`, `hysing2009`). **`ghia1982`, `verma2014` and `dosta2024` are not in
      the gallery bib** — the gallery pages cite them by URL or in prose — so those were built from
      Crossref. A first draft of `verma2014` had merged two papers (the 2015 "bed size" title,
      volume and pages with the 2014 tomography DOI `10.1002/aic.14393`); the fluidized-bed page
      cites the 2014 tomography paper, and `paper.bib` now carries that one, with all eight authors.
- [x] Every multi-author entry carries the full Crossref author list; no "and others".
- [x] **Software and comparator references** added; the nine DOIs below were verified against
      doi.org / Crossref:

      | key | work | DOI |
      |---|---|---|
      | Kokkos | Kokkos 3: Programming Model Extensions for the Exascale Era | `10.1109/TPDS.2021.3097283` |
      | ArborX | ArborX: A Performance Portable Geometric Search Library | `10.1145/3412558` |
      | CaNS | Costa, FFT-based finite-difference solver | `10.1016/j.camwa.2018.07.034` |
      | AMReX | AMReX: block-structured AMR framework | `10.21105/joss.01370` |
      | OpenFOAM | Weller et al., tensorial approach | `10.1063/1.168744` |
      | LIGGGHTS | Kloss et al. | `10.1504/PCFD.2012.047457` |
      | MercuryDPM | Weinhart et al. | `10.1016/j.cpc.2019.107129` |
      | OpenPNM | Gostick et al. | `10.1109/MCSE.2016.49` |
      | Voro++ | Rycroft | `10.1063/1.3215722` |

      `nanobind` has no DOI (none on Zenodo either, checked 2026-09-19) — the repository is cited.
- [ ] Every reference in a JOSS paper should carry a DOI where one exists; the bot checks. Two
      entries are URL-only by necessity: `gallery` (the executed gallery site) and `scaling2026`
      (the 1.1.0 record, DOI pending — see A1).

### C4. A defect found while assembling the above
`peclet-examples/references.bib` gives `mfixexa2022` the DOI `10.1177/10943420211009156`, which
**404s**. The correct DOI is `10.1177/10943420211009293` (verified, HTTP 200). The entry is not
currently cited by any page, so nothing renders it.

- [ ] Fix it in the gallery bibliography (still unfixed as of 2026-09-19); `paper.bib` carries the
      correct DOI.

---

## D. Worth doing, not required for JOSS

- [ ] **conda-forge feedstock** — a large part of the CFD and scientific-Python audience never uses
      pip. Highest reach-per-hour item after the paper itself.
- [ ] **PyPI metadata** is thin: no keywords, six classifiers, and only *Documentation* and
      *Homepage* in `project_urls` — no Source, Issues, Changelog or examples gallery. PyPI is where
      search traffic lands; this is a 20-minute fix across the package `pyproject.toml` files.
- [ ] A **"How to cite"** section in `README.md` and on the docs home page, pointing at the JOSS
      paper once it has a DOI.

---

## The order I would do them in

1. **A3, A4, C1** — minutes each, and they unblock the submission form.
2. **A5** — the real work, and the item most likely to cost a review round if skipped.
3. **C3** — assemble `paper.bib` from the two sources above.
4. **B1, B2, B4** — three short README edits that prevent three predictable reviewer questions.
5. **A2** — archive and record the version DOI immediately before submitting.
6. **D** — after acceptance, when the paper gives each of them something to point at.
