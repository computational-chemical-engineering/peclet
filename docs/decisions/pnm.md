# Design decisions — pnm

Harvested verbatim from the project's working notes. Each entry records a decision, the
alternative it rejected, and the stated reason. **This file is evidence, not a summary** —
quotes are unedited. Read `docs/DECISIONS.md` first; come here for depth.

Bootstrapped by a one-time harvest of the working notes (2026-09-10); **maintained by hand
from here on** — add an entry when you make a decision a future session could undo. Regenerate
the index with `docs/decisions/build_index.py` after editing.

Do not reverse an entry here without recording a new decision that supersedes it.

### Core/film throat tier criterion must be geometric (both cells fluid-centered), not an openness threshold
- area: pnm
- source: peclet-pnm-split.md:58-61
- decided: 2026-07-25
- status: settled
- quote: |
    KEY LESSON: the core/film tier criterion
    MUST be geometric (core = both cells fluid-centered), NOT an openness threshold — wall films that
    bridged two capsule throats contain staircase faces with opn up to ~0.7 (measured by bisection:
    merged area = exact sum of parts revealed film already counted).
- rejected: an openness-threshold criterion for the core/film tier
- why: "wall films... contain staircase faces with opn up to ~0.7"

### Distributed forest/label algorithm design lessons: pointer-jump must not store gid outside extended block; Jacobi double-buffer required, not in-place
- area: pnm
- source: peclet-pnm-split.md:84-91
- decided: 2026-07-24
- status: settled
- quote: |
    1. Gradient-root pointer jumping MUST NOT store a gid outside the extended block — the chase
       strands mid-chain beyond the ghost ring [...] Fix: `~root` finalization marker; cells hold at
       in-block gids and only adopt FINALIZED ghost values; converges one cross-block hop/round.
    2. CCL needs no iteration-to-convergence: local union-find + ONE allgathered boundary-label
       graph merge (host union-find, min-gid roots).
    3. Single-rank flood fill converted to Jacobi double-buffer (was an in-place device race) so
       distributed flood matches sweep-for-sweep [...] Don't revert to in-place.
- rejected: storing a gid outside the extended block during pointer jumping; in-place flood fill on device
- why: "the chase strands mid-chain beyond the ghost ring"; in-place flood fill "was an in-place device race"

### Network-flow extraction requires cutcell_pressure=True; fluxes must accumulate on flow basins, not seg-keyed
- area: pnm
- source: peclet-pnm-split.md:31-34
- decided: 2026-07-25
- status: settled
- quote: |
    CRITICAL FACTS: flow's u(i,j,k) = **-x face** of cell i; the
    conserved flux is ox·u·A and `set_solid(..., cutcell_pressure=True)` is REQUIRED (else openness
    all 0 → everything silently zero); fluxes MUST accumulate on flow basins (ascent from EVERY cell)
    — seg-keyed accumulation loses the near-wall staircase flux (measured 6% of tube flux)
- rejected: seg-keyed flux accumulation
- why: "seg-keyed accumulation loses the near-wall staircase flux (measured 6% of tube flux)"

### Periodic-image decisions must never depend on float centroids — anchor on integer peak-voxel coordinates
- area: pnm
- source: peclet-pnm-split.md:74-78
- decided: 2026-07-25
- status: settled
- quote: |
    HARD-WON GOTCHA (flaky np4 CUDA, ~1 in 3): periodic-image decisions must NEVER depend on float
    centroids — FMA wobble (1e-8) flips the image at exactly L/2 on symmetric lattices. Anchor face
    min-imaging on integer peak-voxel coords; throat dp image count k from snapped integer-cell
    arithmetic (macro term = (x_j−x_i) − L·k). Same class of bug will recur in any periodic
    centroid/pairing code.
- rejected: float-centroid-based periodic-image decisions
- why: "FMA wobble (1e-8) flips the image at exactly L/2 on symmetric lattices"

### Solid/pore renumbering must reduce min-appearance per label, not first-appearance gid
- area: pnm
- source: peclet-pnm-split.md:94-95
- decided: 2026-07-24
- status: settled
- quote: |
    4. Solid renumbering: first-appearance gid ≠ label (flooded voxel can precede the min marker) —
       reduce min-appearance per label like pores (device UnorderedMap + allgatherv).
- rejected: using first-appearance gid as the label
- why: "first-appearance gid ≠ label (flooded voxel can precede the min marker)"

---

### pnm becomes its own project (peclet.pnm); peclet.flow.pnm removed
- area: pnm
- source: peclet-pnm-split.md:11-16
- decided: 2026-07-24
- status: settled
- quote: |
    **pnm split (2026-07-24):** pore-network extraction was split out of `flow` into its own suite
    project: submodule `pnm/`, repo `computational-chemical-engineering/peclet-pnm`, import
    **`peclet.pnm`** (`peclet.flow.pnm` no longer exists — flow c4e074a removed the target/sources,
    umbrella e52d38d added the submodule). File history was carried over with git-filter-repo (21
    commits, back through the CUDA-era `pore_extraction.cu`); inherited flow tags were deleted, repo
    starts fresh at 0.1.0.
- rejected: keeping pore-network extraction inside flow as peclet.flow.pnm
- why: none stated beyond the split itself
