---
name: moving-grid
description: Resume or orchestrate the M7 "moving grid" branch — two-phase flow on a grid of convex (power) cells that may move, with flux across like facets, material interface facets and facet surface energy (also called the ALE or moving covolume variant). Use whenever the user asks to continue, plan, delegate, gate or report on that branch, or mentions ALE_STATE.md, FABLE_ALE_FORMULATION.md or the pilots/fable probes. Not for the particle formulation NHV-W, which another session orchestrates.
---

# Moving-grid branch: how to orchestrate it

This skill is the procedure. The position lives in files; read them, do not rely on recollection.

1. Read `~/Codes/peclet-papers/work/M7/ALE_STATE.md` (where we are, next action, gates, open decisions).
2. Read `~/Codes/peclet-papers/work/M7/ALE_RULES.md` (Frank's constraints, ownership, git, running jobs, evidence).
3. Only if the task touches the equations: `FABLE_ALE_FORMULATION.md` in the same directory.

You are the orchestrator. You hold the formulation, write the briefs, judge the gates and keep the state file true.
You do not run long jobs in your own turns and you do not read logs beyond their verdict line.

## Routing by role
The session may run on different models at different times; do not assume which one you are, and do not put a model
name in a brief, a file or an agent name. Roles are stable; the agent that fills a role today is in the second column
and is the only thing to edit when agents are renamed or re-tiered. Each agent's model and effort live in its own
frontmatter and nowhere else.

| role | agent today | give it |
|---|---|---|
| scout | `recon` | "where is X in voro, which tests pin it, what pattern to follow" before any brief that touches voro |
| specified work | `spec-implementer` | an option or diagnostic on an existing probe, a parameter ladder, a number or table generator, a unit test of defined behavior, documentation |
| engineering | `engineer` | a new probe whose method is written down but whose numerics need judgment; voro implementation; debugging with several live hypotheses; accelerator-kernel performance |
| settled design in voro | `design-implementer` | work orders of a committed design note, with its gates |
| design | `architect` | the voro design note: data layout for a changing face set, device residency, MPI contract. Once per package, from a digest |
| derivation check | `derivation-checker` | one load-bearing derivation, as a file with claim, assumptions and outline |
| implementation review | `reviewer` | once per landed package that changes numerics |

Choose by risk, not size. When specified work and engineering are a close call, choose engineering.

## Formulation decisions (independent of which model the session is)
- A change to the equations is accepted only when three things agree: the session's derivation, an independent
  `derivation-checker` verdict, and the cheapest numerical falsifier. Write the claim to
  `work/M7/briefs/ALE_D<n>.md` before asking for the check.
- If they disagree, or the checker returns NOT ESTABLISHED twice, do not settle it by repetition or by majority.
  Put the question, both arguments and the failing number under "Open formulation questions" in `ALE_STATE.md`,
  and go on with work that does not depend on it.
- Performance tuning of device kernels is measured and checked against the Kokkos documentation, never done from
  recall.

## One work order
1. State the pass criterion with numbers before anything runs. Add it to the gate table in `ALE_STATE.md`.
2. Write the brief to `work/M7/briefs/ALE_<id>.md`: the question in one sentence; "read `ALE_RULES.md` first"; the
   current state with the excerpts that matter pasted in; what is settled and what is open; what was tried and failed,
   with numbers; the exact files to create or change; the command that runs it (`pilots/fable/run_probe.sh ...`); the
   pass criterion; what is out of scope; the commit trailer to use; a context cap (commit, 40-line handoff, stop).
3. Re-read the brief as someone who has seen nothing else. Then spawn the agent with the brief's path.
4. Judge the result against the criterion yourself. A miss is reported as a miss; an unexpected number goes to
   engineering or to you, never to the specified-work agent.
5. Stop the agent when its work order is done. Follow-ups go to the same agent only while its context is small.

## Closing a milestone
- Rewrite `ALE_STATE.md` in place (one screen). Append a dated entry to `DECISIONS_LOG.md` (decision, rejected
  alternative, reason, evidence path). Update `FABLE_ALE_FORMULATION.md` only if the equations changed.
- Commit named paths in the hub and push. Tell session `voronoi` only when shared code or its work is affected.
- Report to Frank in short physics-language prose with numbers; questions for him carry a default.

## What needs Frank, and what does not
Proceed on the defaults in `ALE_STATE.md` and log the choice. Only these wait for him: a change to his constraints or
core idea, anything landing on voro main, a public name, billed cluster time, and a parked formulation question that
blocks everything else.
