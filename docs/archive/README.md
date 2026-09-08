# Archive — design notes and campaign records

These are **dated design notes, campaign plans and session handoffs**, kept for the record and
moved out of the live documentation set on 2026-09-08 (QUALITY_PLAN.md decision D7: *docs describe
the code that exists*). Each one was written to steer a piece of work that has since landed, been
superseded, or been folded into a reference document; the authority on how the suite behaves today
is the code plus the reference docs in the parent directory
([ARCHITECTURE](../ARCHITECTURE.md), [CONVENTIONS](../CONVENTIONS.md),
[INTERFACES](../INTERFACES.md), [STYLE](../STYLE.md), [NAMING](../NAMING.md),
[DECOMPOSITION_AND_MULTIGRID](../DECOMPOSITION_AND_MULTIGRID.md),
[SCALING_ISSUES](../SCALING_ISSUES.md), [PORTABILITY](../PORTABILITY.md)) and the active work list
in [QUALITY_PLAN](../QUALITY_PLAN.md). Nothing here is maintained: `file:line` citations,
status lines and "next step" sections are snapshots of their date — re-read the source before
acting on any of them. Nothing here is deleted either — the AMR notes in particular document work
that is still under active development (D6).

| note | date | what it is |
|---|---|---|
| [AMR.md](AMR.md) | 2026-06/07 | Design and status of the block-local octree AMR in `core` — phases, data structures, the morton/ORB foundation. AMR development continues; this is its founding design note. |
| [AMR_GEOMETRY_SETUP_REQUIREMENTS.md](AMR_GEOMETRY_SETUP_REQUIREMENTS.md) | 2026-08 | What `AmrFlow::setSolid` needs from the shared SDF scene layer — the AMR consumer's requirements and measurements for ANALYTIC_SDF_GEOMETRY's Layer-2 rung. |
| [ANALYTIC_SDF_GEOMETRY.md](ANALYTIC_SDF_GEOMETRY.md) | 2026-08/09 | Inventory and plan for one device-callable analytic-SDF layer shared by `flow`, `dem` and `voro` (static, moving and resolved-particle geometry). |
| [COMMUNICATION_SCALING.md](COMMUNICATION_SCALING.md) | 2026-08 | Communication cost per iteration of the distributed IBM step, from the porous-scaling campaign, and the plan that closed the gap. Companion to DECOMPOSITION_AND_MULTIGRID (which governs iteration *counts*). |
| [DEFECT_CORRECTION_PLAN.md](DEFECT_CORRECTION_PLAN.md) | 2026-09 | The suite-wide "exact residual, approximate preconditioner" campaign: why float operator storage broke the row-sum identity, and the rungs that fixed it. |
| [DEFECT_CORRECTION_PROMPT.md](DEFECT_CORRECTION_PROMPT.md) | 2026-09 | The session prompt that executed the plan above. Kept as the record of how the campaign was run. |
| [DEVICE_RESIDENCY_PLAN.md](DEVICE_RESIDENCY_PLAN.md) | 2026-06/07 | Suite-wide audit of host↔device data movement and the plan to keep computation on the GPU. Largely executed by the Kokkos migration. |
| [MG_TELESCOPING_PLAN.md](MG_TELESCOPING_PLAN.md) | 2026-09 | Design and implementation plan for coarse-level telescoping of the pressure multigrid (`set_pressure_telescope`), answering open problem 1 of DECOMPOSITION_AND_MULTIGRID. |
| [MULTIPHYSICS_PLAN.md](MULTIPHYSICS_PLAN.md) | 2026-07 | The eight-phase multiphase/multiphysics framework plan (variable ρ/μ, scalar transport, CFD-DEM coupling, shared decomposition). All phases done and validated 2026-07-05. |
| [VOF_PLAN.md](VOF_PLAN.md) | 2026-08/09 | The approved VoF plan — sharp-interface two-phase flow, rungs V0–V11, plus Part II (phase change: boiling and evaporation). |
| [VOF_NEXT_SESSION.md](VOF_NEXT_SESSION.md) | 2026-08/09 | Handoff note for the VoF campaign's continuing session: item-by-item state as of 2026-09-02. |
| [VORONOI_METHODS_PLAN.md](VORONOI_METHODS_PLAN.md) | 2026-09 | The approved Voronoi/convex-cell methods plan — one differentiable cell complex carrying many methods — with the §12 rulings. |
| [peclet_cuda_wheel_prototype.md](peclet_cuda_wheel_prototype.md) | 2026-07 | Validated proof-of-concept for a pip-installable single-GPU CUDA wheel; the recipe now lives in RELEASE.md and DEPLOYMENT.md. |
