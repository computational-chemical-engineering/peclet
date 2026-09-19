---
title: 'peclet: a Python-driven, GPU-accelerated suite for coupled particle and pore-scale transport'
tags:
  - Python
  - C++
  - computational fluid dynamics
  - discrete element method
  - immersed boundary method
  - porous media
  - GPU
  - MPI
authors:
  - name: E.A.J.F. Peters
    orcid: 0000-0001-6099-3583
    affiliation: 1
affiliations:
  - name: Eindhoven University of Technology, The Netherlands
    index: 1
date: 19 September 2026
bibliography: paper.bib
---

# Summary

`peclet` is a suite of GPU-accelerated, MPI-parallel codes for transport phenomena in
particle-laden and porous systems, driven from Python. It is a chain of methods rather than
one: discrete-element granular dynamics and packing (`peclet-dem`); geometry carried as
signed-distance fields; incompressible Navier–Stokes with a cut-cell immersed boundary and
geometric volume-of-fluid (`peclet-flow`); dynamic Voronoi tessellation of moving particles
(`peclet-voro`); pore-network extraction (`peclet-pnm`); and two-way CFD–DEM coupling
(`peclet-coupling`) — each built on one shared decomposition, halo-exchange and geometry layer
(`peclet-core`, `peclet-morton`). One source runs on a laptop CPU, one GPU or across nodes (CUDA,
HIP and OpenMP through Kokkos [@kokkos]) and installs with `pip install peclet` for CPython
3.10–3.14. A public gallery [@gallery] of 46 executed examples and eight benchmark studies freezes
outputs at a release tag, validated against published references where they exist.

# Statement of need

Researchers in chemical and process engineering, porous-media physics and granular flow rarely
simulate one thing. A packed-, trickle- or fluidized-bed study is a chain: pour a packing, turn it
into resolvable geometry, solve the single- or two-phase flow through the pore space, and reduce
the result to a permeability, a pressure drop, a pore network. Every link has an excellent
specialist code and no code has the chain. The cost is conversion scripts, file handoffs and
incompatible geometry conventions — and, past one node, a full redistribution at every handoff
between links that do not share a decomposition.

`peclet` makes each link a method on one decomposition and one halo exchange, inside one process.
A DEM packing becomes a signed-distance field; the cut-cell immersed boundary turns it into
openness-weighted operators; a volume-of-fluid interface moves through those cells; the same pore
space reduces to a network — every intermediate a NumPy or CuPy view into solver memory, never a
file. The gallery runs these end to end: `random-packed-bed` (DEM to flow),
`bubble-through-packing` (DEM to geometry to volume-of-fluid), `pore-network-extraction` (flow to
network) and `fluidized-bed`, a two-way coupled bed of 965,000 particles.

A shared decomposition cannot be contributed to four independently designed codes; it has to be
what they are built on. `peclet` is not the fastest code at any single link on a single device;
of the codes named below, it alone offers the chain.

# State of the field

In incompressible CFD, OpenFOAM [@openfoam] is the ubiquitous general unstructured solver; incflo,
on AMReX [@amrex], is `peclet`'s own method family (finite-volume, geometric-multigrid projection,
embedded boundary) at exascale; CaNS [@cans] sets the throughput reference on a periodic box with
an exact FFT solve. In granular dynamics, LIGGGHTS [@liggghts] is the reference open-source DEM
and MercuryDPM [@mercurydpm] the richest in particle shape and coarse-graining. In gas–solid
coupling, MFIX-Exa [@mfixexa] is the exascale reference and CFDEM [@cfdem] the widely used
OpenFOAM–LIGGGHTS pairing. OpenPNM [@openpnm] is the pore-network modeling ecosystem and Voro++
[@voropp] the standard serial tessellator.

On a single device `peclet` is not the fastest code at any one of these methods: CaNS's FFT solve
is 2.3 times faster on one H100 and 3 times on a 24-core workstation — the price `peclet` pays
for general cut-cell geometry, and a lead that holds until the problem spans more than one node.
These figures are from a head-to-head study on a pre-1.0 build
(August 2026) [@gallery], with CaNS on cuDecomp's autotuned MPI transposes, which
understates its multi-GPU points. `peclet`'s claim is the chain, not the link: CFDEM couples two
codes with two decompositions, `peclet-coupling` places fluid and particles on one; `peclet-pnm`
extracts networks for OpenPNM to model on. On the DEM8 bulk-process benchmark [@dosta2024], re-run
against MUSEN and LIGGGHTS on one machine, `peclet-dem`'s Hertz–Mindlin engine reproduces the
references on every case and its impulse-based solver on all but two documented residuals.

# Software design

`peclet-core` carries what every method shares: an orthogonal-recursive-bisection block
decomposition, asynchronous ghost-layer exchange, particle migration, signed-distance geometry and
dynamic load balancing. One decomposition denies each method its own — including the pencils an
FFT solve wants; that is the price of the chain.

Every method runs on the device and across ranks; host paths exist only as test oracles. Kokkos
supplies CUDA, HIP and OpenMP from one source (ArborX [@arborx] for the discrete-element broad
phase); the original CUDA implementations were retired once the Kokkos ports were validated
against them, bit-identical for the flow solver. Python is the composition layer: nanobind
bindings [@nanobind] expose fields and particle state as zero-copy views, and solvers take a
physical domain and properties and derive the discretization.

The design keeps one contract: the physics must not depend on the partition. Creeping
flow through a 1043-sphere cut-cell packing returns the same mean velocity after 13 steps to a
worst relative deviation of 8e-11 across 34 runs, from 1 to 1536 ranks, on CUDA and OpenMP
backends, from 56.6 million to 1.81 billion cells [@scaling2026]. Weak scaling to 32 H100 GPUs
holds 64% efficiency with the pressure iteration count flat; strong scaling from 24 to 1536 CPU
cores takes the step from 36.3 s to 0.89 s. One rung, 16 GPUs, is reproducibly over twice as slow
as its neighbors and reported undiagnosed.

# Research impact statement

`peclet` is installed as a site package on the Snellius national supercomputer, distributed as
Apptainer and Docker containers, and its documented quick start runs in CI against each
release's published wheels. Its validation cases are the field's canonical
references — Ghia et al. [@ghia1982], Zick and Homsy [@zick1982], ten Cate et al. [@tencate2002],
Moser et al. [@mkm1999], Hysing et al. [@hysing2009], Verma et al. [@verma2014] and the DEM8 suite
[@dosta2024] — each a runnable, executed page rather than a reproduced figure; most example pages
open in Colab.

<!-- TODO-FRANK: if any publication, preprint, thesis or external group has used peclet, name it
     here — realized impact outweighs everything above. Also confirm whether the LUMI site package
     has been exercised on AMD hardware (docs/LUMI.md still says UNTESTED as of 2026-09-19); if
     so, say "two national systems". -->

# AI usage disclosure

Much of `peclet`'s code, documentation and benchmark tooling was written with Claude (Anthropic),
through Claude Code, in session with the author, from December 2025 to September 2026; GitHub
Copilot contributed a few commits. This paper was drafted with the same assistance and edited by
the author. The author framed the problems, made and recorded the design decisions, and reviewed
and validated all output; agent-assisted commits carry a `Co-Authored-By` trailer, and the methods
are checked against the published references and the multi-rank equivalence gate described above.

<!-- TODO-FRANK: confirm the model range and dates, and whether Copilot warrants naming.
     What git shows (2026-09-19): the earliest `Co-Authored-By: Claude` trailer is flow 2026-01-05;
     dem's history begins 2025-11-28; Claude-authored commits begin 2026-05-29/30 (morton, core).
     Copilot: 2 commits authored "Copilot" in flow, 2 by copilot-swe-agent[bot] in peclet-examples,
     and voro's first commits after the 2015 import (2026-03-26) are by copilot-swe-agent[bot]. -->

# Acknowledgements

<!-- TODO-FRANK: funding (grant numbers), the SURF/Snellius allocation wording and project id,
     and any contributor to credit. Keep to ~30 words. -->

# References
