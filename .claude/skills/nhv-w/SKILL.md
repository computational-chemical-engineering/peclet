---
name: nhv-w
description: Resume or orchestrate M7 NHV-W — the Lagrangian power-cell two-phase particle method in peclet.voro (generators with mass, OT-held volumes, facet capillary energy E_Γ, offset binding U_b, gauge G⁗, variants F and R). Use whenever the user asks to continue, plan, delegate, gate or report on NHV-W, the binding/statics/gauge work orders (BD*, ST*, G*, T1/T2), or mentions work/M7/STATE.md, EQUATIONS.md or the m7* voro branches. Not for the moving-grid (ALE) branch, which session voronoi_fable orchestrates.
---

# NHV-W: how to orchestrate it

The procedure only. Position and rules live in files; read them, never rely on recollection.

1. Read `~/Codes/peclet-papers/work/M7/STATE.md` (position, next action, gates, open decisions).
2. Read `~/Codes/peclet-papers/work/M7/NHVW_RULES.md` (Frank's constraints, settled/rejected, ownership, running jobs).
3. Only if the task touches the equations: `EQUATIONS.md`; for one decision: `grep -n` in `DECISIONS_LOG.md`.

You hold the formulation, write the briefs, judge the gates and keep STATE.md true. You do not run long jobs in your
own turns and you read logs only by their verdict line.

## Routing by role (agent names change; roles do not)
| role | agent today | give it |
|---|---|---|
| scout | `recon` | where X is in voro, which tests pin it |
| specified work | `spec-implementer` | an option on an existing probe, a ladder, a table generator, a unit test, docs |
| engineering | `engineer` | 2D probes needing numerical judgment, voro implementation, debugging, performance |
| settled design | `design-implementer` | work orders of a committed design note, with its gates |
| design | `architect` | voro design notes (device layout, MPI, integrator); once per package, from a digest |
| derivation check | `derivation-checker` | one load-bearing derivation, written to a file |
| review | `reviewer` | once per landed numerics-changing package |

## One work order
1. Write the pass criterion with numbers into the STATE.md gate table before anything runs.
2. Brief to `work/M7/briefs/WO_<id>.md`: question; "read NHVW_RULES.md first"; pasted excerpts; settled vs open;
   tried and failed with numbers; files; run command; criterion; out of scope; commit trailer; context cap.
3. Spawn with the brief's path. Judge the result yourself; a miss is a miss. Stop the agent when done.

## Closing a milestone
Rewrite STATE.md in place; append to DECISIONS_LOG.md; update EQUATIONS.md if the equations or status changed; named
paths, push. Tell `voronoi_fable` when results bear on its Appendix B or shared headers. Report to Frank briefly, with
numbers; questions carry a default.

## What needs Frank
Decisions go to session `hub` as a DECISION-REQUEST (Decision Desk, user directive 11-14), not to Frank directly; hub's answer is a doorbell, never approval for a push/tag/publish.
A change to his constraints or core idea, a reversal of a registered decision (e.g. D-S4 → global binding), anything
landing on voro main, a public name, billed cluster time. Everything else proceeds on the STATE.md defaults, logged.
