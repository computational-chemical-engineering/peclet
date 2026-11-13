---
name: learned-pnm
description: Resume or orchestrate paper A7, the learned inertial pore-network model on peclet.pnm: a per-pore convex junction law parameterized by ML from network geometry, with extraction from the analytic particle SDF (scene path), labels from peclet.flow CFD mapped by extract_network_flow, and a resolution/scope study. Use whenever the user asks to continue, plan, delegate, gate or report on A7, the junction law, the pnm branch junction-law, the A7 study repo, step 0, WO-D*, O1/G2, or Cristina's MultiScalePBR follow-up.
---

# A7 learned inertial PNM: how to orchestrate it

This skill is the procedure. The position lives in files; read them, do not rely on recollection.

1. Read `~/Codes/peclet-study-A7-learned-pnm/A7_STATE.md` (position, running WOs, next actions, open questions for
   Frank).
2. Read `~/Codes/peclet-study-A7-learned-pnm/A7_RULES.md` (Frank's constraints, settled choices, ownership, git,
   TRS2 jobs, evidence standard).
3. Read the design note only in the sections your task touches: `design/junction_law_design.md` in the private study repo (moved from pnm 11-13)
   (grep `^## Amendment`, `^### `; read by `sed -n` ranges).
4. Grep `DECISIONS_STEP0.md` before changing anything it covers.

You are the orchestrator. You hold the formulation, write the briefs, judge the gates and keep the state file true.
You do not run long jobs in your own turns, and you read logs only for their verdict line.

## Routing by role
The model behind each agent lives in its frontmatter. Do not put model names in briefs.

| Role | Agent today | Give it |
|---|---|---|
| scout | `recon` | locations and patterns in pnm/flow/geom before a brief |
| specified work | `spec-implementer` | a gate script, a table or figure generator, a unit test of defined behavior |
| engineering | `engineer` | analysis or numerics that need judgment; debugging; study-repo tooling |
| settled design | `design-implementer` | work orders of the design note, with their gates |
| design | `architect` | a new amendment to the design note, once per package, from a curated brief in `design/BRIEF_*.md` |
| derivation check | `derivation-checker` | one load-bearing derivation (e.g. convexity, an energy identity), as a file |
| implementation review | `reviewer` | once per landed pnm package that changes numerics (before the pnm merge) |

## One work order
1. Fix the pass criterion with numbers before anything runs, and put it in the WO table of `A7_STATE.md`.
2. Write the brief to `briefs/<WO>.md`. It must say "read `A7_RULES.md` first" and contain: the question; the
   design-note subsections by line range; prior evidence with numbers; the files to create; the gate; what is out
   of scope.
3. Re-read the brief as someone who has seen nothing else, then spawn the agent with the brief's path.
4. Judge the report yourself. A miss is recorded as a miss. An open design choice is either settled by you (if it is
   a consistency fix inside the note: log it in `DECISIONS_STEP0.md` as an isolated, reversible decision) or sent to
   the architect.
5. Stop the agent when its WO is done. A worker past ~250k tokens hands off; continue with a fresh agent from
   `handoff/<WO>.md`.

## Closing a milestone
- Rewrite `A7_STATE.md` in place (one screen) and append to `DECISIONS_STEP0.md`.
- If the milestone changes paper content: regenerate `paper/numbers.tex` (clean tree), then tell session
  `peclet-papers`.
- Merging pnm `junction-law` to main is an umbrella-last push, and needs the reviewer pass first.
- Report to Frank in short physics prose with numbers; each question carries a default.

## What needs Frank
Billed cluster time (Snellius), a public name in a pnm release, a change to his constraints, rerunning a bed
(GPU-days), and pushes on manuscripts with co-authors. Everything else proceeds on defaults and is logged.
