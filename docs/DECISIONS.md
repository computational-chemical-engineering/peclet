# Decision register

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


## flow — Navier-Stokes, IBM, pressure/velocity solve

164 in force, 37 superseded — full text in [`decisions/flow.md`](decisions/flow.md)

### In force

- **"Hand the stopping level to GraphAMG" telescoping idea is retired**. **Rejected:** handing the MG-telescoping stopping level to GraphAMG  <sub>mg-decomposition-alignment.md:75</sub>
- **(1,2) mixed closure order is the recommended default going forward**. **Rejected:** binary-M lagging (divergent, ρ=1.087) and linear-everywhere (1,1) (worse pointwise near the IB)  <sub>flow-ghost-projection.md:50</sub>
- **A masked solid cell is not a fluid sample**.  <sub>sdf-scene-campaign.md:44</sub>
- **API/ordering: x-fastest is fixed; PyVista/VTK [x,y,z] + F-contiguous convention**. **Rejected:** order='F' as the user-facing default and [z,y,x] indexing  <sub>suite-distributed-status.md:177-184</sub>
- **Agglomerated redundant coarse solve deferred pending multi-rank hardware**. **Rejected:** shipping the agglomerated coarse solve untested at np<=4  <sub>suite-distributed-status.md:296-299</sub>
- **Agglomerated/"auto" bottom solve default is gated to the singular (mean-removed) path only, not enabled universally**. **Rejected:** enabling "auto" bottom solve on Dirichlet-anchored/outflow operators  <sub>agglomerated-bottom-ibm-fix.md:45</sub>
- **Agreement across configurations sharing a floor is not proof of convergence**. **Rejected:** treating cross-config agreement alone as sufficient evidence of convergence  <sub>defect-correction-campaign.md:65-70</sub>
- **All level-0 partitioning must go through one shared factory; never hand-build a BlockDecomposer for the solver**. **Rejected:** hand-building a separate BlockDecomposer at any of the three call sites  <sub>mg-decomposition-alignment.md:56</sub>
- **Allreduce diet: fuse mean-removal sum+count; 'fine' mean-removal scope as bench/pack default, 'all' stays solver default pending Snellius validation**.  <sub>parallel-scaling-study.md:81-86</sub>
- **Anisotropic MG coarsening order: coarsen axis a iff H_a < 2·min H over coarsenable axes, engaged only under `aniso`**. **Rejected:** applying the anisotropic coarsening rule to the isotropic path (would change isotropic bits)  <sub>physical-units-phase2-aniso.md:47-51</sub>
- **Anisotropic wall-gradient normal/foot-point convention (⚑B)**.  <sub>physical-units-phase2-aniso.md:52-54</sub>
- **Body-force ghost policy: Neumann copy, pinned to ρ's policy**.  <sub>vof-campaign.md:145-154</sub>
- **Boiling scope addition did not resurrect transported-φ CLSVOF**. **Rejected:** transported-φ CLSVOF  <sub>vof-campaign.md:101-106</sub>
- **Byte-identical gating is unmeasurable for atomic-add paths — gate against the path's own run-to-run spread instead**. **Rejected:** a byte-identical regression gate for atomic-add code paths  <sub>defect-correction-campaign.md:55-57</sub>
- **CA (event-halving) smoothing ships default ON with an env kill switch**.  <sub>comm-scaling-plan.md:23</sub>
- **CSF force is exact; curvature error is the real budget — improve κ, never the force**. **Rejected:** arithmetic cell-force interpolation (set_csf_mode(1)); improving the force term to chase lower Ca  <sub>vof-campaign.md:430-444</sub>
- **CUDA wheel dependency name: nvidia-cuda-runtime, not the deprecated -cu13 suffix**. **Rejected:** depending on the `nvidia-cuda-runtime-cu13` package name  <sub>peclet-cuda-wheel-feasible.md:28-30</sub>
- **Cell-average IBM scheme, not point-value, for Poiseuille validation**. **Rejected:** point-value scheme (ibmFillEntry<0>)  <sub>cuda-kokkos-migration.md:285-287</sub>
- **Channel DNS IC must seed streamwise rolls/streaks in wall units, not cold random noise**. **Rejected:** cold random-noise initial condition; perturbation cutoff specified in cycles/cell  <sub>channel-dns-isotropic-grid.md:46</sub>
- **Chebyshev pressure driver's apparent win was a placement artifact, not a real gain**. **Rejected:** adopting the Chebyshev pressure driver based on the uncontrolled 36% win  <sub>momentum-solve-residual-stop.md:39</sub>
- **Clean-fluid-interior mask required on both restriction and prolongation for IBM velocity-MG correctness**. **Rejected:** θ-weighting the diagonal's identity (I) term; coupling the coarse grid at cut/solid cells (masking cut cells only, not solid cells, was tried and stil  <sub>velocity-mg-design.md:54-64</sub>
- **Coarse-first decomposition ships opt-in, legacy remains the default**. **Rejected:** making coarse-first decomposition the default  <sub>mg-decomposition-alignment.md:22</sub>
- **Coarse-level solve policy default stays "smoother", not "auto", because auto regresses the cut-cell IBM path**. **Rejected:** making "auto" the default coarse-level solve policy  <sub>mg-decomposition-alignment.md:28</sub>
- **Collocated pressure coupling is the ABC (MAC) approximate projection, NOT Rhie–Chow**. **Rejected:** Rhie–Chow interpolation as the collocated coupling  <sub>sdflow-collocated-solver.md:37-39</sub>
- **Container slab half-extent must equal L/2 + wall thickness, never more (periodic-image rule)**. **Rejected:** an oversized slab half-extent  <sub>advective-cutwall-flux-plan.md:57</sub>
- **Correction: the raw field registry hands out internal (unconverted) arrays**.  <sub>physical-units-plan.md:28</sub>
- **Coupling partial/cut+solid cells to the coarse grid fails regardless of coarsening depth — capping depth cannot fix it**. **Rejected:** capping coarsening depth as a fix for partial-cell coupling divergence  <sub>velocity-mg-design.md:118-135</sub>
- **Crank-Nicolson ported then reverted; backward-Euler is the right default**. **Rejected:** Crank-Nicolson (θ=0.5) time integration with the plain explicit Laplacian  <sub>suite-distributed-status.md:320-324</sub>
- **Cut-cell C convention: liquid fraction of fluid volume, openness-weighted**.  <sub>vof-campaign.md:98-100</sub>
- **Deferred correction is not viable as an undamped fallback**. **Rejected:** undamped deferred correction as the C/F / ghost solve fallback  <sub>flow-ghost-projection.md:29</sub>
- **Design constraints for any collocated-plateau fix**. **Rejected:** Basilisk's dt·a face event and both embed-note salvage approaches (ruled out by C2); any fix that fragments the CG graph (ruled out by C4)  <sub>collocated-second-order-verdict.md:51-55</sub>
- **Distributed cut-cell MG coarse levels must be nested, not independently re-decomposed**. **Rejected:** independent per-level BlockDecomposer ORB for MG coarse levels  <sub>channel-dns-isotropic-grid.md:52</sub>
- **DistributedNS declared canonical; clean API; periodic BCs only; MPI a true build option**. **Rejected:** keeping pnm_backend API compatibility; a halo-BC system for future boundary conditions  <sub>suite-distributed-status.md:247-251</sub>
- **DistributedNS solves in physical units (ρ, dynamic μ, force/volume), not kinematic ν**. **Rejected:** the kinematic (ρ≡1, single-ν) formulation as the solved system  <sub>sdflow-dt-divided-convention.md:46-59</sub>
- **DistributedStokes renamed to DistributedNS**.  <sub>suite-distributed-status.md:14-18</sub>
- **Divergence in mixed-order ghost projection (GPORDER 1,2) is caused by the incremental-rotational pressure accumulation, not the linear solve**. **Rejected:** attributing the (1,2) divergence to the linear solve tolerance or resolution  <sub>ghost-hardening-plan.md:50-59</sub>
- **Divergence uses flux openness (beta); MG uses operator openness (alpha)**. **Rejected:** using the same openness definition for both divergence and MG operator  <sub>cuda-kokkos-migration.md:325-327</sub>
- **Do not make the preconditioner rho-aware — harmful, and no compatibility floor exists in practice**. **Rejected:** making the preconditioner rho-aware; the H1 hypothesis that GP_THETA_MIN fires and causes the trouble  <sub>ghost-hardening-plan.md:26-37</sub>
- **Domain-BC all-fluid velocity must use double diffSmoothColor, not float IBM stencil**. **Rejected:** float IBM stencil for domain-BC all-fluid velocity  <sub>cuda-kokkos-migration.md:318-320</sub>
- **Domain-BC paths stay blocking, following the VelocityMG precedent**. **Rejected:** applying halo-compute overlap to domain-BC paths  <sub>comm-scaling-plan.md:22</sub>
- **Double operator storage is the DEFAULT (SCALING_ISSUES #1 closed by decision)**. **Rejected:** (a) leaving float as the default and documenting the limitation — rejected because the  <sub>flow/CMakeLists.txt:48-72</sub>
- **Drag must be included in bcStencilPath() whenever advection is off**.  <sub>porous-cfddem-cuda-two-bugs.md:14</sub>
- **E2 resolved: the aspect coarsening rule alone fixes MG-PCG stall on stretched grids — no auto-FCG/symmetric-V-cycle decision needed**. **Rejected:** needing a separate symmetric-V-cycle-under-aniso or auto-FCG-on-aniso decision  <sub>physical-units-phase2-aniso.md:28-31</sub>
- **Earlier "slow convergence / non-converged" worry was a multiplied-dt float-precision artifact, fixed by the divided-dt engine convention**. **Rejected:** the multiplied-dt momentum-operator convention  <sub>ringbed-cfd-surrogate.md:63</sub>
- **Embed momentum + mode-3 projection (mode 5) does not converge — over-drags**. **Rejected:** mode 5 (embed momentum + mode-3 projection) as a viable configuration  <sub>embed-port-progress.md:23</sub>
- **Escalation rule: a twice-failed gate stops the work order, never gets its numerics tweaked to pass**. **Rejected:** tweaking numerics to force a failing gate to pass  <sub>vof-campaign.md:495-496</sub>
- **Exact-crossing openness overrides must be masked to 0 at solid velocity points**. **Rejected:** unmasked exact apertures at solid-velocity-point faces  <sub>flow-ghost-projection.md:61</sub>
- **FV viscous operator confirmed 2nd-order-consistent — "face-flux placement" hypothesis refuted; barrier is the pressure coupling**. **Rejected:** the "face-flux placement" hypothesis; the wall-pressure-term-on-momentum-force fix (both signs)  <sub>sdflow-collocated-solver.md:152-166</sub>
- **Face-primary uf reconstruction (mode 8) attempted and reverted — incompatible with flow's divided time convention**. **Rejected:** mode 8 (face-primary uf via Basilisk's acceleration-event reconstruction) under flow's current divided momentum-operator convention  <sub>embed-port-progress.md:33</sub>
- **Final default: momentum residual tolerance follows the pressure solver's rtol, not a fixed constant**. **Rejected:** a fixed residual-stop constant (1e-5), decided earlier the same day  <sub>momentum-solve-residual-stop.md:53</sub>
- **Fine-scope MG-PCG promoted to default after lever ablation**. **Rejected:** 'all'-scope mean removal as the default; Chebyshev smoother; GraphAMG bottom solve (on GPU)  <sub>parallel-scaling-study.md:162-164</sub>
- **Fix: refresh the MG halo before computing the residual, not only before each colour sweep**. **Rejected:** computing the MG residual from ghosts left stale by the pre-smooth's own halo exchange  <sub>cpu-fat-rank-optimization.md:14-22</sub>
- **Float MReal operator storage silently breaks A*1=0 at high MG contrast; peer's FCG/S3-indefiniteness fix is refuted for this case**. **Rejected:** the VoF peer's indefinite-pivot S3 model as the explanation for this case's MG degradation  <sub>collocated-attractor-campaign.md:56</sub>
- **Fragmentation guard: BFS-isolated pockets are treated as solid for the projection only**.  <sub>flow-ghost-projection.md:81</sub>
- **Free-variable fix: pin phi=0 at decoupled cells after the solve**. **Rejected:** leaving free variables (solid-centered / BC_ONLY rows) unpinned after the Krylov solve  <sub>flow-ghost-projection-mpi-plan.md:19</sub>
- **Fresh (newly-uncovered) cells must be seeded with the local wall velocity, not inherit the solid value**. **Rejected:** inheriting the solid's prior value in a freshly-uncovered cell  <sub>sdf-scene-campaign.md:97</sub>
- **GPU binding must let SLURM cgroup-isolate; manual CUDA_VISIBLE_DEVICES remap fights SLURM**. **Rejected:** PECLET_BIND_GPU=1 manual remap  <sub>channel-dns-isotropic-grid.md:45</sub>
- **GPU-aware MPI is not the shipped default on Snellius 2024a due to a toolchain conflict**. **Rejected:** building the solver against the GPU-aware-validated CUDA 12.1.1 stack  <sub>channel-dns-isotropic-grid.md:44</sub>
- **Geometric const-coeff + masking are the validated defaults; Galerkin/CG is opt-in**. **Rejected:** making Galerkin/CG the default  <sub>suite-distributed-status.md:98-100</sub>
- **Ghost-plane MASK must be exchanged under motion, not just velocity fields**. **Rejected:** exchanging only uBc_/velocity without exchanging the mask ("uBc_ exchange alone changed nothing"); inner-only or ghost-only mask fill (both insufficie  <sub>advective-cutwall-flux-plan.md:75</sub>
- **Ghost-projection MPI design: gp-row ownership = inner-block cell; BiCGStab stages the iterate on a g=2 block rather than doing a second exchange**. **Rejected:** a second separate exchange to satisfy the ±2 overlay reach  <sub>flow-ghost-projection-mpi-plan.md:13-16</sub>
- **Gibou-style NS scheme identified as a trap (adopted MAC/staggered for stability, not a collocated precedent)**. **Rejected:** the Gibou-path literature precedent for a collocated 2nd-order scheme  <sub>sdflow-collocated-solver.md:169-174</sub>
- **GraphAMG re-enabled as porous+drag default after two BC-blind defects fixed**. **Rejected:** leaving GraphAMG gated off for domain-BC problems  <sub>porous-cfddem-cuda-two-bugs.md:27</sub>
- **Grid-convergence studies must report dimensionless permeability k* = k/N², not dimensional k**. **Rejected:** reporting dimensional k_cells directly as a convergence metric  <sub>sdflow-regression-suite.md:20-22</sub>
- **Grid-dimension convention: MG per-axis coarsening depends on factors of two; always check halvings before proposing a grid**. **Rejected:** choosing benchmark grid dimensions without checking per-axis halving depth (led to a "WORSE" refine ladder caught before burning GPU hours)  <sub>channel-scaling-rebenchmark.md:182-200</sub>
- **Guidance: ghost for resolved/smooth IBM geometry, cutcell aperture for tight-throat porous media**. **Rejected:** using ghost projection for under-resolved tight-throat porous media  <sub>flow-ghost-projection.md:86</sub>
- **Host-serial-kernel threshold lever kept despite measuring as marginal at the fat-rank size**. **Rejected:** cutting reductions over to serial-below-threshold execution; a larger serial-cutoff (131072)  <sub>cpu-fat-rank-optimization.md:43-49</sub>
- **How to apply: staggered recommended for accuracy-critical drag/permeability; collocated for structural wins, at the cost of first order at curved walls**.  <sub>sdflow-collocated-solver.md:202-207</sub>
- **IBM overlay needs no separate scaling change — linear in the base stencil**.  <sub>sdflow-dt-divided-convention.md:24-26</sub>
- **IBM velocity-MG must NEVER un-scale the residual by 1/D_rescale**. **Rejected:** un-scaling the restricted residual by 1/D_rescale to fix the +2-4% Z&H drag bias  <sub>velocity-mg-design.md:24-35</sub>
- **If a pressure method clearly wins at scale, make it the default**.  <sub>parallel-scaling-study.md:11-17</sub>
- **Incremental (rotational) pressure now default ON in C++ DistributedNS, matching the Python binding**. **Rejected:** classical (non-rotational) pressure as the C++ default  <sub>sdflow-dt-divided-convention.md:40-44</sub>
- **Incremental-rotational pressure default ON in sdflow, OFF in DistributedNS**.  <sub>suite-distributed-status.md:325-332</sub>
- **Instability fix: a wall-banded rotational-term blend, not the full rotational update everywhere**. **Rejected:** the unblended full rotational update on the cell-centered approximate projection (unstable, PM-II instability)  <sub>collocated-attractor-campaign.md:14</sub>
- **Invariant: the ORB must never split the wall-normal axis (y) in wall-bounded flow**. **Rejected:** allowing the ORB to split the wall-normal axis  <sub>channel-scaling-rebenchmark.md:85-88</sub>
- **Keep the staircase velocity-MG despite modest current efficiency win — it is the right operator for future AMR near contact points**. **Rejected:** removing the staircase velocity-MG for lack of current efficiency win  <sub>velocity-mg-design.md:113-116</sub>
- **Lattice-plane trap: an SDF exactly 0 at a staggered point is invisible to both the fluid mask and the ghost detector**. **Rejected:** face-aperture-based detector for the degenerate lattice-plane condition  <sub>sdf-scene-campaign.md:150</sub>
- **Level-0 BC hook must use fold=0 (reflection) for the unfolded stencil**. **Rejected:** fold=1  <sub>momentum-solve-residual-stop.md:24</sub>
- **M2 chosen as plain Richardson, not BiCGStab**. **Rejected:** BiCGStab for M2  <sub>defect-correction-campaign.md:31</sub>
- **MG telescoping ships off by default, byte-identical when off**.  <sub>mg-decomposition-alignment.md:79</sub>
- **MG-PCG stalls on ρ- and eps/drag-scaled coefficient operators; Chebyshev is the default driver for those paths**. **Rejected:** MG-PCG as the default driver for variable-density (and, per line 379/382, porous+drag) coefficient operators  <sub>multiphysics-framework-plan.md:391</sub>
- **MG-PCG's relative stopping test never fires on a near-quiescent field; a fixed-iteration cap is the workaround, not a proper fix**. **Rejected:** relying on the relative (rtol) stopping criterion alone near a quiescent field  <sub>flow-thermal-convection-validated.md:20</sub>
- **MPI-optional single-source build: default is single-rank with no MPI linked**.  <sub>suite-distributed-status.md:332-345</sub>
- **Marching-squares (order-2) apertures are now the shipped default in both flow and AMR**. **Rejected:** order-1 (single-sample) apertures as default; an ungated marching-squares aperture (opens masked-DOF staggered faces)  <sub>collocated-attractor-campaign.md:56</sub>
- **Masking must exclude BOTH cut cells and solid cells, not cut cells alone**. **Rejected:** masking cut cells only (without also masking solid cells)  <sub>velocity-mg-design.md:64-75</sub>
- **Method verdict: WY-split PLIC (B) chosen; CICSAM (A) rejected; CLSVOF (D) dropped**. **Rejected:** CICSAM (A); CLSVOF (D)  <sub>vof-campaign.md:89-92</sub>
- **Mixed ghost widths require CutcellMG::parityOg to correct red-black colour parity**.  <sub>comm-scaling-plan.md:33</sub>
- **Mode 10 (open-centroid quadrature) is dead — worse on Z&H and diverges on RCP slivers**. **Rejected:** mode 10 open-centroid quadrature constraint  <sub>flow-ghost-projection.md:119</sub>
- **Mode 4 (fully-FV via defect correction) implemented and is a negative milestone — not 2nd order**. **Rejected:** mode 4 as shipped (face-centre flux placement retained on the 6 axis faces)  <sub>sdflow-collocated-solver.md:133-150</sub>
- **Mode-10 quadrature, Seo-Mittal pressure-only split, and ghost-as-production are all dead ends**. **Rejected:** mode 10 quadrature; Seo-Mittal pressure-only split; ghost scheme as the production path  <sub>collocated-second-order-verdict.md:40-41</sub>
- **Momentum solve uses the divided (1/dt-scaled) convention, replacing the dt-multiplied form**. **Rejected:** the dt-multiplied form `I - nu*dt*Lap`  <sub>sdflow-dt-divided-convention.md:10-16</sub>
- **Momentum tolerance-stop: adaptive tolerance instead of a fixed sweep cap**. **Rejected:** a fixed sweep cap of 5 (user's own suggestion)  <sub>parallel-scaling-study.md:74-77</sub>
- **Momentum-advection kernels must use the actual wall velocity field, not maskVelocity's solid zeros**. **Rejected:** reading maskVelocity's solid-zero convention as the wall velocity for a moving wall  <sub>advective-cutwall-flux-plan.md:15</sub>
- **Multiphysics assembly is runtime-dispatched flags on existing kernels, not a Solver<Grid,Props> template**. **Rejected:** a templated Solver<Grid,Props> design  <sub>multiphysics-framework-plan.md:403</sub>
- **Must re-mask solid velocity after grad(phi) correction**. **Rejected:** skipping the re-mask  <sub>cuda-kokkos-migration.md:354-355</sub>
- **Non-incremental Chorin projection gives wrong steady Z&H drag — incremental-rotational required**. **Rejected:** non-incremental Chorin projection (−40% error, splitting-error); the warm-detector convergence protocol  <sub>embed-port-progress.md:21-22</sub>
- **Old single-GPU CFDSolver reference retired; pnm_backend is pore-network extraction only**. **Rejected:** keeping the CFDSolver single-GPU reference implementation; pnm_backend carrying a CFD solver  <sub>sdflow-dt-divided-convention.md:29-38</sub>
- **Only upwind/dissipative advection schemes exist — no central/energy-conserving option**. **Rejected:** central/energy-conserving advection scheme (does not exist)  <sub>channel-dns-isotropic-grid.md:15</sub>
- **Owner-boundary attribution fix: remove shared-cell pressure from both sides of cross-owner faces**. **Rejected:** leaving the shared-cell pressure flux attributed through owner mid-surfaces  <sub>sdf-scene-campaign.md:82</sub>
- **P1 passed: double-diagonal fallback retired as measurably worse, not merely unnecessary**. **Rejected:** the double-diagonal fallback (converges to the float-face operator, not the true one)  <sub>defect-correction-campaign.md:33-38</sub>
- **PCG selector fixed; Chebyshev stays varRho/porous default (S0/S1 outcome)**. **Rejected:** PCG as the varRho/porous default driver  <sub>vof-campaign.md:172-201</sub>
- **Pairing lesson: stability needs (G,D) structural match, accuracy needs closure-value consistency — only the ghost architecture has both**. **Rejected:** Design B (star) — "SPD-but-scheme-unstable"; B+ gates ("dead")  <sub>collocated-attractor-campaign.md:35</sub>
- **Part II phase-change architecture: Robin IHTR, PLIC plane-shift regression, transported-φ CLSVOF stays dead**. **Rejected:** hard T_sat interface condition; volume-source-in-C interface regression; transported-φ CLSVOF  <sub>vof-campaign.md:115-125</sub>
- **Part III bubbly-flow container reuses V0–V4 kernels; Dodd–Ferrante FFT not needed**. **Rejected:** Dodd–Ferrante constant-coefficient FFT pressure solve  <sub>vof-campaign.md:107-114</sub>
- **Per-kernel space.fence() removed — default-exec-space kernels are stream-ordered**. **Rejected:** per-kernel fence() calls  <sub>cuda-kokkos-migration.md:534-539</sub>
- **Phase B/C explicitly must not touch GP_THETA_MIN, the sliver branch, or the preconditioner scaling**. **Rejected:** touching GP_THETA_MIN, the sliver branch, or the preconditioner scaling in phases B/C  <sub>ghost-hardening-plan.md:60-64</sub>
- **Porous pressure correction must use drag-consistent relaxation (SIMPLE/PISO-with-implicit-drag), not a drag-free coefficient**. **Rejected:** the drag-free pressure-correction coefficient (open*eps) used against a drag-loaded momentum diagonal  <sub>multiphysics-framework-plan.md:381</sub>
- **Porous projection must run even with no immersed solid — flow now throws, CfdDem auto-installs set_pressure_geometry**. **Rejected:** silently running porous mode without any pressure-geometry / projection  <sub>porous-cfddem-cuda-two-bugs.md:62</sub>
- **Port production physics onto the distributed solver rather than retrofit MPI into production kernels**. **Rejected:** retrofit MPI into the production kernels  <sub>suite-distributed-status.md:101-104</sub>
- **Pre-fix porous coefficient pair kept for A/B only, never for publishable results**. **Rejected:** publishing results computed with the pre-fix (buildPorousCoeffDrag) pair  <sub>porous-eps-conservative-momentum.md:38-39</sub>
- **Precision policy rule: identity-bearing quantities stored in the precision the identity is asserted; ship double-diagonal, not fp64 default**. **Rejected:** full fp64 default operator storage  <sub>vof-campaign.md:307-312</sub>
- **Pressure solve must be PCG (Krylov), not RB-GS, for cut-cell IBM**. **Rejected:** RB-GS for pressure; rotational pressure-update variant  <sub>cuda-kokkos-migration.md:352-358</sub>
- **Public API renames: pressure_potential() → pressure() (returns physical pressure)**. **Rejected:** the name pressure_potential() for the physical-pressure accessor  <sub>sdflow-dt-divided-convention.md:36-38</sub>
- **Published parallel-scaling iteration count is 4.0, not the earlier 12.2**. **Rejected:** the e861010 figures (12.2), which predate the stale-ghost V-cycle residual fix  <sub>parallel-scaling-study.md:119</sub>
- **Random-array drag deviation is a genuine method difference, not finite-size or arrangement effects**. **Rejected:** finite-size effects and arrangement/crystallization as explanations for the deviation  <sub>ibm-accuracy-sphere-validation.md:57-64</sub>
- **Reaction torque leak fix is a closed-form cut-cell moment; adding the pressure moment term makes it worse**. **Rejected:** adding the pressure moment Σ r×grad(pi) to close the torque gap  <sub>sdf-scene-campaign.md:70</sub>
- **Repair attempts (modes 1–3b) inside the unidirectional IBM all fail to reach 2nd order**. **Rejected:** mode 1 (wall-anchored weighted-LSQ), mode 2 (transpose pairing), mode 3a (open-centroid, unstable), mode 3b (o-weighted adjoint, stable but worse cons  <sub>sdflow-collocated-solver.md:79-108</sub>
- **Report K normalized by superficial velocity (Zick-Homsy convention), not interstitial**. **Rejected:** reporting an interstitial-normalized K without conversion  <sub>ibm-accuracy-sphere-validation.md:110-112</sub>
- **Resolved: the cell-average velocity scheme was a porting bug, not a real discrepancy — point-value is correct**. **Rejected:** the cell-average velocity scheme (buildIbmOverlay<1>) as used in the Kokkos port  <sub>migration-faithful-port.md:31</sub>
- **Richardson extrapolation is ill-conditioned for this dense-bed data; do not rely on a free-parameter fit**. **Rejected:** relying on an unconstrained Richardson-extrapolation fit for k_inf on this data  <sub>ringbed-cfd-surrogate.md:31</sub>
- **Root cause of the RB-GS stall: update-criterion (max|du| <= rtol*first-sweep-update) chases noise on a warm-started step**. **Rejected:** the update-criterion stop (max|du| <= rtol * first sweep's update)  <sub>momentum-solve-residual-stop.md:8</sub>
- **Rung 3 fix: openness-weighted centered gradient replaces plain ½(g⁻+g⁺) projection correction for embed mode**. **Rejected:** plain projectCorrectCenter's ½(g⁻+g⁺) correction (with closed faces zeroed) for the embed-momentum mode  <sub>embed-port-progress.md:24-25</sub>
- **S-ladder plan; Dodd–Ferrante splitting rejected for the pressure driver**. **Rejected:** Dodd–Ferrante splitting for the pressure driver  <sub>vof-campaign.md:473-479</sub>
- **S3 coarsening indefiniteness is real, but coarsenOpenAvg must NOT switch to harmonic**. **Rejected:** switching coarsenOpenAvg's face-coefficient averaging to harmonic  <sub>vof-campaign.md:253-260</sub>
- **SdflowIbm MPI requires constructing each rank with local ORB block dims (ctor refactor, not a gated add-on)**.  <sub>cuda-kokkos-migration.md:558-570</sub>
- **Sequencing: "VoF vs multiphysics first" dissolves — VoF is the next multiphysics phase**.  <sub>vof-campaign.md:480-484</sub>
- **Sign convention: closed divergence of the corrected field equals Aφ − b = −residual**.  <sub>flow-ghost-projection.md:43</sub>
- **Sliver mask must pin only cells with cs<1e-6, not every cell with sdf(center)<0**. **Rejected:** the mode-0-style mask (zero every cell with sdf(center)<0, including solid-centred cut cells) for embed mode  <sub>embed-port-progress.md:27</sub>
- **SolverColocated is the ABC approximate projection, NOT Rhie–Chow — user correction**. **Rejected:** describing SolverColocated's coupling as Rhie–Chow  <sub>vof-campaign.md:485-489</sub>
- **Staggered converges onto Zick & Homsy; collocated is bias-dominated (irreducible ~0.9%)**.  <sub>peclet-examples-gallery.md:165-171</sub>
- **Staircase coarse operator (binary classification, no volume-fraction coefficients) is the DEFAULT for the IBM volfrac path, removing the dt ceiling**. **Rejected:** the volume-fraction-weighted (area-fraction) coarse operator as coefficients; the plain const-coeff coarse op without staircase classification  <sub>velocity-mg-design.md:77-98</sub>
- **Staircase is consolidated as the ONLY IBM velocity-MG coarse op — const and area-fraction paths removed from the code**. **Rejected:** geometry-blind const-coarse (setDiffusionCoarse) and area-fraction (setVelocityVolfracCoarse) IBM coarse operators — both deleted from the code  <sub>velocity-mg-design.md:100-116</sub>
- **Star half fix: phibar mean was not bitwise-annihilating even in double — replaced by flux form**. **Rejected:** the phibar=Sum(a*x)/Sum(a) formulation  <sub>defect-correction-campaign.md:52-54</sub>
- **Strict staggered bit-identical guard must be held through every change; AMR must work for both velocity placements or be explicitly scoped**.  <sub>sdflow-octree-amr-next.md:19-20</sub>
- **TRAP: -DPECLET_FLOW_MREAL_DOUBLE=ON on the cmake command line silently builds float**. **Rejected:** passing -DPECLET_FLOW_MREAL_DOUBLE=ON as a normal cmake cache variable  <sub>defect-correction-campaign.md:45-46</sub>
- **Telescoping is default on for the pressure MG since 2026-09-02; the velocity solve does not need it**. **Rejected:** telescoping the velocity solve  <sub>momentum-solve-residual-stop.md:18</sub>
- **Ten-Cate periodic-image bug: periodic images are a union, not independent slabs**. **Rejected:** the earlier CSG-slab-per-image geometry construction (implicitly non-union)  <sub>sdf-scene-campaign.md:131</sub>
- **The agglomerated-bottom MG anomaly required a per-fluid-component null-space projector, a double row-sum, and a looser inner tolerance**. **Rejected:** projecting the all-cell mean (rather than per-connected-fluid-component); leaving MG coefficients in single-precision row sums uncorrected; an inner t  <sub>agglomerated-bottom-ibm-fix.md:15</sub>
- **The defect-correction rule: Krylov matvec/residual must be the exact double operator in flux form; preconditioners below may stay float**.  <sub>defect-correction-campaign.md:14-17</sub>
- **The rotational (Timmermans) pressure update must be restored, not the non-rotational Goda form substituted**. **Rejected:** non-rotational Goda pressure update form; diagonal-preconditioned CG in place of geometric MG/MG-PCG; double-precision pressure operator storage  <sub>migration-faithful-port.md:61</sub>
- **The standalone V-cycle pressure driver does not honor set_pressure_solver_params(n) and is ~30x slower at small grids**.  <sub>flow-thermal-convection-validated.md:25</sub>
- **UCX_RNDV_THRESH tuning is falsified as an explanation for the np8 anomaly — leave UCX defaults**. **Rejected:** tuning UCX_RNDV_THRESH=256k  <sub>comm-scaling-plan.md:57</sub>
- **User decision: port Basilisk embed.h, not Trebotich–Graves, for 2nd-order collocated walls**. **Rejected:** Trebotich–Graves/EBChombo as the primary port target  <sub>sdflow-collocated-solver.md:186-191</sub>
- **User directive: ghost-cell IBM must become production-grade (it generalizes to AMR better than cut-cell)**.  <sub>ghost-hardening-plan.md:11-14</sub>
- **V-cycle stale-ghost bug made MG convergence decomposition-dependent; fixed, now iteration count is decomposition-independent**. **Rejected:** reading stale ghosts in the V-cycle residual  <sub>channel-scaling-rebenchmark.md:67-73</sub>
- **Variable-viscosity rotational correction stays incremental (constant-μ) under varProps, not full pointwise**. **Rejected:** 'full' pointwise variable-μ rotational correction  <sub>multiphysics-framework-plan.md:397</sub>
- **Velocity domain BCs must be applied before divergence in project()**. **Rejected:** applying divergence before the velocity domain BCs  <sub>cuda-kokkos-migration.md:332-335</sub>
- **Velocity masking must be OFF with the cut-cell pressure operator**. **Rejected:** masking velocity with the cut-cell operator active  <sub>suite-distributed-status.md:94-95</sub>
- **Velocity-diffusion MG rediscretization diverges; velocity RB-GS is the exact default**. **Rejected:** rediscretized velocity-diffusion multigrid coarse operator  <sub>suite-distributed-status.md:291-296</sub>
- **Viscous term left plain (not epsilon-weighted) — a deliberate, documented scope choice**. **Rejected:** epsilon-weighting the viscous term  <sub>porous-eps-conservative-momentum.md:31</sub>
- **VoF execution model: no new submodule, kernels live in flow/src/vof/**. **Rejected:** a new submodule for VoF  <sub>vof-campaign.md:491-496</sub>
- **WO-H fix: CutcellMG::applyNeumannGhost; PCG selector now throws (MG-PCG is the terminal fallback)**.  <sub>vof-campaign.md:236-251</sub>
- **WY advection CFL default corrected to Weymouth's proven 3D bound 0.25**. **Rejected:** CFL<0.5 (Weymouth's 2D value, mistakenly applied to 3D)  <sub>vof-campaign.md:128-130</sub>
- **Weak efficiency must be computed from per-GPU throughput, not raw step time**. **Rejected:** computing weak efficiency directly from step time when cells/GPU varies ±8%  <sub>channel-scaling-rebenchmark.md:208-209</sub>
- **What was disproved in the agglomerated-bottom investigation**. **Rejected:** solid-rhs deposit contamination, sliver-row threshold mismatch, and multi-component pockets as causes for THIS case  <sub>agglomerated-bottom-ibm-fix.md:29</sub>
- **bcStencilPath() and implicitAdv() must agree with the actual solver in use**.  <sub>momentum-solve-residual-stop.md:21</sub>
- **cylinder-vortex-street dropped from the gallery; confirmed flow bug pins the fix location**. **Rejected:** shipping a sub-resolution "steady" wake result (would misrepresent physics)  <sub>peclet-examples-gallery.md:106-118</sub>
- **fillPorousEpsGhosts: mirror-around-1 at inflow/outflow, zero-gradient at walls — one policy for RHS/coeffs/residual**. **Rejected:** reading eps ghosts in three different states across RHS/coeffs/residual  <sub>porous-cfddem-cuda-two-bugs.md:36</sub>
- **flow's grid is isotropic unit spacing with no wall-normal stretching**. **Rejected:** wall-normal grid stretching  <sub>channel-dns-isotropic-grid.md:14</sub>
- **set_exact_crossings and set_openness_override remain single-rank-guarded (v1 scope exclusions unchanged)**. **Rejected:** extending this MPI landing to cover set_exact_crossings/set_openness_override or the v1-excluded modes  <sub>flow-ghost-projection-mpi-plan.md:17</sub>
- **set_face_interp(9) hybrid (aperture projection + gpCenterGrad) is the throat-safe collocated scheme**. **Rejected:** pure collocated ghost projection (mode-0 with gpCenterGrad only) for tight-throat porous media — it inherits the throat defect  <sub>flow-ghost-projection.md:115</sub>
- **set_ghost_projection(True) must be called before set_solid**.  <sub>flow-ghost-projection.md:33</sub>
- **set_pressure_warmstart(True) diverges on the steady Stokes march; bench default is WARMSTART=0**. **Rejected:** set_pressure_warmstart(True) as a benchmark default  <sub>porous-scaling-benchmark.md:106-109</sub>
- **⚠️ UNRESOLVED — interstitial vs superficial drag normalisation**. **Rejected:** nothing — these two statements in the SAME note assign Zick-Homsy and vdH to OPPOSITE  <sub>ibm-accuracy-sphere-validation.md:45-50</sub>

### Superseded — history, do not re-derive the old reading

- "Intrinsic ~1% gap, don't chase it" corrected: collocated IBM is first-order at curved walls, staggered is second-order.  <sub>sdflow-collocated-solver.md:46-56</sub>
- "No portable GPU wheel" was a policy choice, not a hard limit — single-GPU CUDA wheels are feasible.  <sub>peclet-cuda-wheel-feasible.md:10-13</sub>
- (superseded) fp32-floor-explains-everything hypothesis.  <sub>vof-campaign.md:366-381</sub>
- (superseded) precision-vs-indefiniteness verdict corrected — S3 indefiniteness is real and separate from the float-storage floor.  <sub>vof-campaign.md:346-347</sub>
- 1/2-1/2 constraint truncation exonerated as the plateau cause — a previously-published claim was wrong.  <sub>collocated-second-order-verdict.md:29-34</sub>
- 2nd order finally resolved by ghost-cell projection FD family, not the full Basilisk embed rewrite.  <sub>sdflow-collocated-solver.md:10-27</sub>
- Agreed IBM velocity-MG coarse-op scheme: volume-fraction Helmholtz, coarse-only solid masking, masked volume-weighted transfers.  <sub>velocity-mg-design.md:37-52</sub>
- Aperture weighting (A1) is not indicated as a fix for the confined finite-Re deficit.  <sub>advective-cutwall-flux-plan.md:26</sub>
- Area fractions (proper face α, not min(θ)) extend the stable dt ceiling for the (now-removed) area-fraction coarse op.  <sub>velocity-mg-design.md:118-124</sub>
- Correction/supersession: plan §9.3 U5 was wrong about VoF spacing.  <sub>physical-units-plan.md:32</sub>
- Correction: §9.3 U3's setter list was incomplete, causing silent physical errors.  <sub>physical-units-plan.md:35</sub>
- Defect-correction proposal: float hierarchy demoted to pure preconditioner, evaluate before double-diagonal.  <sub>vof-campaign.md:293-306</sub>
- E3 decided: v3 wall-torque uses the area factor V'/h_b', not h_a'V', correcting the design note's §4.4.  <sub>physical-units-phase2-aniso.md:34-37</sub>
- Earlier "+13-83% above 2024" deviation was a normalization error, not a real discrepancy.  <sub>ibm-accuracy-sphere-validation.md:79-81</sub>
- Falling-drop gate: WO-K's under-resolved-momentum-solve suspicion is refuted.  <sub>vof-campaign.md:459-464</sub>
- Galilean identity (A−idiag·I)·1=0 is false in general — corrects the plan's inventory.  <sub>defect-correction-campaign.md:27-28</sub>
- Ghost's rho scalar is not a partial cut-cell transplant — premise correction.  <sub>ghost-hardening-plan.md:21-25</sub>
- Interstitial vs superficial drag normalization: our K is interstitial (Zick-Homsy); literature (vdH/Tenneti/van Wachem) reports superficial F_D=(1-phi)K, not "friction".  <sub>ibm-accuracy-sphere-validation.md:45-50</sub>
- Old "inter-node reduction tax" diagnosis for the channel 8-GPU scaling drop is superseded.  <sub>channel-scaling-rebenchmark.md:59-61,</sub>
- Old grid-convergence table retired; Galerkin=True / set_pressure_pcg not for production.  <sub>suite-distributed-status.md:311-316</sub>
- Plain incompressible continuity with ε only in drag is the WRONG constraint for a porous bed; volume-averaged (Model-A) continuity is required.  <sub>multiphysics-framework-plan.md:379</sub>
- Ring convergence failure was a solver-tolerance artifact, not a cut-cell/geometry limitation.  <sub>ibm-accuracy-sphere-validation.md:14-30</sub>
- Ring-bed k convergence slowness is intrinsic dense-packing near-contact Stokes stiffness, not a thin-wall/cut-cell IBM defect.  <sub>ringbed-cfd-surrogate.md:33</sub>
- Stale-ghost pressure V-cycle bug invalidated the entire published parallel-scaling page's peclet numbers.  <sub>parallel-scaling-study.md:206-213</sub>
- Success criterion for any A·1=0 repair: match the full-double floor, never demand rtol 1e-8.  <sub>vof-campaign.md:413-427</sub>
- Superseded same-day decision: residual stop default was fixed at 1e-5.  <sub>momentum-solve-residual-stop.md:32</sub>
- The 47%-at-8-GPU "reduction tax" diagnosis is stale, superseded by 2026-08 solver fixes.  <sub>snellius-parallel-benchmark-campaign.md:25-27</sub>
- The earlier "staircase not suited for packed materials" caveat is retracted.  <sub>velocity-mg-design.md:90-98</sub>
- The ten-cate confined-flow deficit was a geometry (oversized periodic slab) bug, not a solver/advection defect.  <sub>advective-cutwall-flux-plan.md:49</sub>
- The ~0.3% collocated accuracy "plateau" is not a truncation ceiling — it is an instability + an invisible pressure-subspace attractor family.  <sub>collocated-attractor-campaign.md:11</sub>
- Wall-band "1/h amplitude growth" was a unit artifact, not a real localization signal.  <sub>collocated-second-order-verdict.md:36-39</sub>
- Weak-scaling ladder must refine a fixed physical box, not grow box length at fixed cross-section (methodology correction).  <sub>channel-scaling-rebenchmark.md:156-168</sub>
- get_ox/oy/oz are openness fields, not origin aliases — NAMING.md correction.  <sub>suite-quality-plan-1-0-0.md:101-102</sub>
- poiseuille-ibm reframed: flat-wall cut-cell IBM is pointwise exact, not a 2.8% error case.  <sub>peclet-examples-gallery.md:48-50</sub>
- rtol rule: max(1e-8, C·eps·0.18N²·Δρ/ρ) — later re-stated as a lower bound, not an achievability guarantee.  <sub>vof-campaign.md:289-292,</sub>
- sdflow accuracy resolved; default cut-cell RB-GS path matches Zick & Homsy; velocity-MG (not pressure) was the drift source.  <sub>suite-distributed-status.md:268-283</sub>
- sdflow-vs-pnm_backend "efficiency gains" correction — internal only, not a real speed gap.  <sub>suite-distributed-status.md:264-269</sub>

## dem — XPBD, contacts, packing

82 in force, 2 superseded — full text in [`decisions/dem.md`](decisions/dem.md)

### In force

- **Acceptance bar for solver-internals changes is run-scatter parity + gated defaults, not bit-identity**. **Rejected:** bit-identity as the acceptance bar  <sub>dem-sweep-efficiency-plan.md:246</sub>
- **Adaptive multilevel stop uses the quasi-static (QS) residual, not the full fine residual or coarse-only**. **Rejected:** gating the adaptive stop on the full fine residual (over-converges flowing scenes); gating on coarse-only residual (statics degrade)  <sub>dem-multilevel-contact-solver.md:27</sub>
- **Blanket persistent-contact e=0 is rejected; restitution is one-sided-only when grounded and not rising**. **Rejected:** blanket persistent-contact e=0 for all persistent contacts  <sub>packing-velocity-position-split.md:17</sub>
- **Body-body friction accumulates normal impulse across velocity-solve iterations; plane/wall uses one-shot post-gravity load**. **Rejected:** a velocity-approach-only proxy for body-body; accumulating normal impulse for plane/wall contacts  <sub>packing-velocity-position-split.md:45</sub>
- **Body-body multi-contact friction is quantitatively too weak (by ~coordination number Z); the fix is deferred sequential-impulse friction**. **Rejected:** dividing each contact's friction bound by the per-body contact count (Jacobi count-averaging) as adequate for multi-contact bulk friction  <sub>packing-friction-followup.md:17</sub>
- **Both-asleep contacts are excluded from colouring by seeding colour = -2**.  <sub>dem-sweep-efficiency-plan.md:95</sub>
- **Boundary contact alignment must use the absolute wall contact point (rAavg), not rAavg−rBavg**. **Rejected:** using diffCenters = rAavg − rBavg uniformly for boundary and body-body contacts  <sub>dem-sdf-walls-moving.md:43</sub>
- **Bug fix: hertzCommitHistory must not wipe carried previous state on the post-migration sentinel**.  <sub>dem-mpi-solver-port-plan.md:50</sub>
- **Cleared hypotheses during the H100 corruption investigation**. **Rejected:** pair-buffer capacity, sleeping, boundary/ghost-slab handling, compile-flag/toolchain differences, execution-mode (graph/fused/etc.) differences, color  <sub>porous-scaling-benchmark.md:60-84</sub>
- **Collision solve moved from count-averaged Jacobi to graph-colored Gauss-Seidel**. **Rejected:** count-averaged Jacobi (min(1,2/count) velocity / 1/count position damping factors) as the primary over-relaxation fix  <sub>dem-colored-gauss-seidel-solver.md:10-23</sub>
- **Colouring stall-break needs a filtered count-averaged-Jacobi fallback for uncolourable manifolds**. **Rejected:** silently skipping uncolourable manifolds/contacts (the pre-fix behaviour)  <sub>dem-colored-gauss-seidel-solver.md:64-67</sub>
- **Contact/manifold buffer sizing must scale with per-particle shell point count**. **Rejected:** fixed capacity*16 sizing regardless of shell point count  <sub>dem-sdf-general-particles.md:65</sub>
- **Core principle: velocity solve owns all dissipation, position solve only removes overlap, no back-coupling**. **Rejected:** back-coupling from the position correction into velocity  <sub>packing-velocity-position-split.md:27</sub>
- **Cube-drum confinement requires a z-periodic barrel with no end caps — corner rounding does not work**. **Rejected:** rounding the cube corner to prevent tunneling at the barrel/cap join; a closed (capped) drum for cubes  <sub>dem-cubes-gpu-pyvista.md:20-24</sub>
- **DEM particle radius/halo sizing must derive from baseRadius*scale*globalScale, not globalScale alone**. **Rejected:** sizing broadphase/halo/margin off globalScale alone; the prior workaround of forcing set_global_scale(rp)  <sub>multiphysics-framework-plan.md:376</sub>
- **DEM velocity solve: over-relaxed min(1, 2/count) average, not raw Jacobi sum — needed together with a resting-contact threshold**. **Rejected:** raw Jacobi sum of manifold impulses in the velocity solve; threshold alone  <sub>porous-cfddem-cuda-two-bugs.md:44</sub>
- **Direction-aware (vector) orphan accounting is a measured negative result; scalar orphan stays production**. **Rejected:** direction-aware (vector) orphan accounting  <sub>dem-event-level-restitution.md:83</sub>
- **Distributed (MPI) sleeping is out of scope for the first pass**. **Rejected:** implementing distributed sleeping in the first pass  <sub>dem-sweep-efficiency-plan.md:188</sub>
- **Drum stick/slip is a position-channel Coulomb-bound carry problem, not missing elasticity**. **Rejected:** attributing the drum lag to missing Mindlin sustained-contact elasticity (the prior Hertz-control conclusion)  <sub>dem-dosta-benchmark.md:272</sub>
- **During the CUDA→Kokkos migration, the velocity/position split must be ported faithfully; physical validation and the friction fix are separate post-migration tasks**. **Rejected:** changing numerics/friction behavior during the backend migration  <sub>packing-friction-followup.md:12</sub>
- **Forward predicted position, not committed position, through ghost gather**. **Rejected:** gathering committed `d_pos`  <sub>suite-distributed-status.md:23-26</sub>
- **Friction consolidated into one per-contact Coulomb friction in the velocity solve, replacing three overlapping patches**. **Rejected:** Fix A (manifold-only), Fix B (position-solve tangential friction), Fix C (velocity feedback from position solve's friction_lambda_n)  <sub>packing-velocity-position-split.md:41</sub>
- **Friction stability fix: Jacobi count-averaging instead of Jacobi-summed impulses**. **Rejected:** Jacobi-summed per-contact friction impulses  <sub>packing-velocity-position-split.md:53</sub>
- **Fused colour sweeps: CUDA-graph replay stays the solo default; fused auto-on only where capture is unavailable**. **Rejected:** making fused loop-kernels the universal default; a per-block-flag + block0-scan barrier variant (measured slower)  <sub>dem-perf-campaign.md:33-37</sub>
- **Gallery fixes: dem OOB writes, wrong docstrings, opt-in reaction torque — root-caused, not worked around**.  <sub>peclet-examples-gallery.md:256-264</sub>
- **General-particle shells must be voxel-decimated to a target point count**. **Rejected:** using the raw marching-cubes point count directly  <sub>dem-sdf-general-particles.md:60</sub>
- **Grain-radius units remain an acceptable, but no longer required, convention**. **Rejected:** requiring grain-radius units (global_scale=1) as the only correct usage  <sub>dem-global-scale-sphere-limitation.md:23-26</sub>
- **Grid-SDF particle data is flat and x-fastest**.  <sub>dem-sdf-general-particles.md:49</sub>
- **Growth-view sizing bug: every maxContacts-sized view must be grown together, not just contacts+manifolds**. **Rejected:** growing only contacts+manifolds while leaving other maxContacts-sized views at the old size  <sub>dem-sdf-general-particles.md:69</sub>
- **HCS benchmark contact-solver exonerated via the colored-GS A/B**. **Rejected:** the contact solver as the source of the residual factor-2 stage offset  <sub>hcs-mfix-benchmark-evidence.md:31-32</sub>
- **Incremental colouring gated OFF under MPI, and position conflict detection avoids a host sync**. **Rejected:** enabling incremental colouring under MPI as-is; a host readback for conflict detection  <sub>dem-sweep-efficiency-plan.md:47</sub>
- **Interim DEM back-coupling commit reverted on user instruction**. **Rejected:** the interim back-coupling commit 374565d  <sub>porous-cfddem-cuda-two-bugs.md:76-77</sub>
- **Interim dx→dv back-coupling was reverted on explicit user instruction — the no-back-coupling clause stands absolutely**. **Rejected:** interim dx→dv back-coupling (commit 374565d)  <sub>packing-velocity-position-split.md:10</sub>
- **Island sleeping shipped default-OFF, then found to explode statics to NaN, fixed and flipped to default-ON**. **Rejected:** making a sleeping body exactly immovable (invMass=0)  <sub>dem-perf-campaign.md:96-109</sub>
- **Kinetic-separation unloading gate beats eager v0til<0 gate**. **Rejected:** eager v0til<0 unloading gate  <sub>dem-event-level-restitution.md:47</sub>
- **Legacy one-shot friction cluster stays gated off on the PGS path**. **Rejected:** running the legacy one-shot friction cluster on the PGS path  <sub>dem-dosta-benchmark.md:154</sub>
- **MPI drum geometry must use a rounded profile, not a sharp barrel+flat-cap min-SDF**. **Rejected:** a sharp barrel+flat-cap min-composited SDF for a drum under MPI  <sub>dem-sdf-walls-moving.md:33</sub>
- **Mode "ordered" (level-ordered symmetric sweeps) is measured insufficient and kept only for A/B, not shipped as default**. **Rejected:** "ordered" mode as a production stabilization mode  <sub>dem-multilevel-contact-solver.md:67</sub>
- **Multilevel slip gate ships at 8·g·dt, not ungated, persistent+cone, or 2·g·dt**. **Rejected:** ungated aggregation (fake bulk viscosity, silo 16.7); persistent+cone gate (pour CRUSH); slip @ 2 g dt (pour CRUSH)  <sub>dem-multilevel-contact-solver.md:52</sub>
- **Never use get_max_overlap() as the sole packing-quality gate**. **Rejected:** using get_max_overlap() alone to validate packing quality  <sub>porous-scaling-benchmark.md:53-56,</sub>
- **New per-pair/experimental features must default off and reduce bit-identically**.  <sub>dem-dosta-benchmark.md:107</sub>
- **Newton-e-alive-on-persistent-contacts plus banking beats bank-owns-restitution**. **Rejected:** bank-owns-restitution / Newton-off  <sub>dem-event-level-restitution.md:42</sub>
- **One fence after the whole GS sweep suffices — per-colour fencing is a needless host stall**. **Rejected:** fencing after every colour sweep  <sub>dem-colored-gauss-seidel-solver.md:36-38</sub>
- **One-sided grounded contacts are a momentum sink; the resolution is a staged symmetric+one-sided solver**. **Rejected:** "the naive per-pair ballistic gate" (any one-sided contact at the moving/static interface is a momentum sink); pure symmetric PGS (crushes deep static  <sub>dem-dosta-benchmark.md:182</sub>
- **Orphan credit is mass-weighted to the heavier endpoint**. **Rejected:** even/unweighted crediting between endpoints  <sub>dem-event-level-restitution.md:69</sub>
- **Orphan decay constant is 1/64 per substep, not 1/256**. **Rejected:** decay constant 1/256  <sub>dem-event-level-restitution.md:73</sub>
- **PGS friction bound must come from the converged normal accumulator, not from live approach velocity**. **Rejected:** deriving the Coulomb friction bound from current approach velocity each iteration  <sub>dem-dosta-benchmark.md:91</sub>
- **Particle data layout: plain Kokkos SoA Views, backend-default layout, not float4, not Cabana**. **Rejected:** float4 packed layout; adopting Cabana  <sub>cuda-kokkos-migration.md:152-158</sub>
- **Per-pair material rebound gap was a material-approximation error, not a solver defect**. **Rejected:** the assumption that the rebound deficit was a solver-level defect  <sub>dem-dosta-benchmark.md:114</sub>
- **Persistent-pair keys under MPI are gid-based, not index-based**. **Rejected:** index-based persistent-pair keys under MPI  <sub>dem-mpi-solver-port-plan.md:22</sub>
- **Phase-B stabilization budget of 2x is the shipped default**. **Rejected:** Phase-B budget 4x (over-stiffens to -0.075); 1x (fails the violent pour)  <sub>dem-dosta-benchmark.md:201</sub>
- **Position solve is translation-only; overlap removal stays decoupled from velocity**.  <sub>dem-colored-gauss-seidel-solver.md:31-34</sub>
- **Root cause of H100-only DEM corruption: Particles::ensureCapacity never resized materialId**.  <sub>porous-scaling-benchmark.md:85-96</sub>
- **Sleep hysteresis must use a wake threshold far above the jitter tail (40x vRest), not close to the sleep threshold**. **Rejected:** wakeScale=4 (causes 32%<->3% oscillation, no freeze); rule (b) contact-flicker wake enabled by default  <sub>dem-sweep-efficiency-plan.md:100</sub>
- **Sleepers must carry finite (not exactly zero) inverse mass**. **Rejected:** exactly-zero inverse mass for sleepers (invMass=0) — "made EXACTLY immovable"; an earlier attempted fix ("overload-wake rule d + sleep-overlap gate vi  <sub>dem-sweep-efficiency-plan.md:133</sub>
- **Sleeping default flipped ON**. **Rejected:** sleeping default OFF (the prior state)  <sub>dem-sweep-efficiency-plan.md:146</sub>
- **Sleeping is implemented as an invMassEff swap around the solve call, not a per-manifold kinematic flag**. **Rejected:** threading an invMassEff flag through ~15 call sites; a per-manifold kinematic flag  <sub>dem-sweep-efficiency-plan.md:89</sub>
- **Sleeping pairs must remain in the pair ledger (broadphase/narrowphase keep tracking them)**. **Rejected:** dropping sleeping pairs from the pair ledger  <sub>dem-sweep-efficiency-plan.md:180</sub>
- **Stabilization iteration cap K=64, not 16**. **Rejected:** K=16  <sub>dem-sweep-efficiency-plan.md:106</sub>
- **Statics fix: persistent-contact tracking + grounded rise-gated inelastic shock; interim back-coupling reverted on user instruction**. **Rejected:** the interim back-coupling approach  <sub>dem-colored-gauss-seidel-solver.md:64-70</sub>
- **Strategy B: build standalone Kokkos units, then one clean cut to flip demgpu**. **Rejected:** making cuBQL and Kokkos coexist incrementally in demgpu  <sub>cuda-kokkos-migration.md:143-146</sub>
- **Symmetric release beats one-sided grounded release**. **Rejected:** one-sided grounded release  <sub>dem-event-level-restitution.md:45</sub>
- **The MPI velocity/position solve reuses the single-GPU driver via a Hooks template, not a separate implementation**. **Rejected:** a rank-local adaptive-stop break under MPI  <sub>dem-mpi-solver-port-plan.md:15</sub>
- **The correct fix, if needed, is proper sequential-impulse friction with an accumulated per-contact tangential impulse clamped to the total Coulomb bound**. **Rejected:** the current Jacobi count-averaged friction scheme, for quantitative frictional-packing studies  <sub>packing-friction-followup.md:26</sub>
- **The force engine was generalized into a Law/Hooks-templated driver per the device-first + MPI directive**. **Rejected:** a Hertz-only, non-generalized implementation  <sub>dem-mpi-solver-port-plan.md:40</sub>
- **The multilevel-stabilizer rebound loss is an under-convergence artifact, not a momentum-sink effect — refuting the project's original premise**. **Rejected:** the mission brief's premise that a momentum-conserving stabilizer sink was deleting the rebound  <sub>dem-multilevel-contact-solver.md:42</sub>
- **Uncapped grid is the default for the fused kernel launch**. **Rejected:** capping the launch grid to fewer blocks  <sub>dem-perf-campaign.md:31-32</sub>
- **Verlet-cached broadphase gated to non-periodic single-GPU only**. **Rejected:** enabling the Verlet-cached pair list under periodic ghosts / MPI  <sub>dem-sweep-efficiency-plan.md:201</sub>
- **Wall SDF resolution must be finer than the colliding cube, and seeded cubes must start axis-aligned**. **Rejected:** a coarser wall SDF than the cube size; random initial cube orientations at lattice spacing 2.1  <sub>dem-cubes-gpu-pyvista.md:25-28</sub>
- **Wall SDF sign convention: val − residual (container convention), not val + residual**. **Rejected:** object-SDF sign convention (val + residual) applied to a container wall SDF  <sub>porous-cfddem-cuda-two-bugs.md:43</sub>
- **Wall friction must accumulate the transmitted force-chain load over velocity iterations, like body-body contacts**. **Rejected:** bounding wall friction by each grain's own one-shot gravity approach load  <sub>dem-sdf-walls-moving.md:52</sub>
- **WallSdf sign convention: positive in the void, negative inside the solid wall**.  <sub>dem-sdf-walls-moving.md:15</sub>
- **dem set_positions (N,4): w==0 does not mean fixed — invMass remap convention**. **Rejected:** assuming w==0 in set_positions means invMass=0 (fixed)  <sub>stale-build-mphys-trees.md:14</sub>
- **dem set_positions resets every particle to shape 0 — set_shape_ids must be called after**.  <sub>sdf-scene-campaign.md:32</sub>
- **dem.step() with no argument advances nothing**.  <sub>sdf-scene-campaign.md:19</sub>
- **globalScale folded into effScaleA/effScaleB throughout body-body narrowphase**. **Rejected:** the prior narrowphase code that omitted globalScale from B's canonical remap  <sub>dem-global-scale-sphere-limitation.md:10-18</sub>
- **packing broad-phase: ArborX replaces cuBQL**. **Rejected:** cuBQL (NVIDIA-only BVH)  <sub>cuda-kokkos-migration.md:82-86</sub>
- **random-packed-bed example: use effective radius including growth_factor; use annealed pack.py protocol**. **Rejected:** baseRadius*scale alone (omitting growth_factor); phi_ref 0.66 crude-feedback protocol  <sub>peclet-examples-gallery.md:58-71</sub>
- **set_restitution_model default is "newton", bit-identical to prior behaviour**. **Rejected:** making "poisson" the default  <sub>dem-event-level-restitution.md:11</sub>
- **set_velocity_use_gs defaults to True; False reverts to legacy Jacobi**.  <sub>dem-colored-gauss-seidel-solver.md:13</sub>
- **step(0.0) settling must skip the velocity solve, friction, and thermostat, and zero the growth velocity**. **Rejected:** running the full velocity pipeline during a dt==0 settle  <sub>packing-velocity-position-split.md:57</sub>
- **step_mpi stays on count-averaged Jacobi — distributed colouring across ghosts is a separate problem**.  <sub>dem-colored-gauss-seidel-solver.md:55-57</sub>

### Superseded — history, do not re-derive the old reading

- Drum-lag "faceted-wall" geometry explanation was falsified; root cause is missing sustained-contact tangential elasticity.  <sub>dem-dosta-benchmark.md:251</sub>
- Symmetric PGS alone cannot hold deep statics; one-sided alone breaks ballistic dynamics.  <sub>dem-dosta-benchmark.md:167</sub>

## voro — tessellation, ConvexCell, mesh optimizer

81 in force, 8 superseded — full text in [`decisions/voro.md`](decisions/voro.md)

### In force

- **-ffast-math based reciprocal speedups are a ceiling, not shippable**. **Rejected:** shipping -ffast-math-based reciprocal speedups  <sub>vorflow-cpu-migration-discussion.md:52-54</sub>
- **4th-face restored: cert made complete again, per-step displacement gate and brute fallback removed**. **Rejected:** the per-step displacement gate + brute-cert fallback from the TrackAdj-only design  <sub>vorflow-dynamic-updater-phase01.md:170</sub>
- **A1 curved-wall shift: in-loop shift and post-pass plane translation rejected on measurement**. **Rejected:** in-loop shift application; post-pass plane translation  <sub>voronoi-methods-plan.md:50-52</sub>
- **A2 re-scoped: exact power diagram not needed for non-overlapping packings**. **Rejected:** treating A2 (exact power diagram at large weights) as a load-bearing prerequisite for tracks D/E/F/G  <sub>voronoi-methods-plan.md:74-78</sub>
- **Any per-rank branch between two MPI collectives must be a global (allreduced) decision**. **Rejected:** per-rank local skin-trip decision of which collective pattern to run  <sub>vorflow-dynamic-updater-phase01.md:248</sub>
- **Backend-aware grid seed density: 2 seeds/cell on CPU (Voronoi), 1/cell on GPU and for Power**. **Rejected:** a single fixed seeds/cell density across backends and weight types  <sub>vorflow-kokkos-migration.md:1091-1095</sub>
- **Backend-specialise the Voronoi gather: CPU uses worklist, GPU keeps legacy expanding-shell gather**. **Rejected:** the worklist gather on the device (GPU) path  <sub>vorflow-worklist-into-tessellator.md:48-58</sub>
- **Blanket reclip-every-cell (S6) does not pay off — persistent Verlet list must be paired with GATED reclip**. **Rejected:** blanket reclip of every cell each step (S6) as the production strategy  <sub>vorflow-dynamic-update-strategy-study.md:72-77</sub>
- **C2b collocated is the ABC approximate projection, NOT Rhie-Chow**. **Rejected:** Rhie-Chow interpolation for the collocated pressure coupling  <sub>voronoi-methods-plan.md:96-97</sub>
- **C4 closed: quadratic wall gradient (wallGradientLS) is the default viscous wall flux**. **Rejected:** the plain two-point wall flux as the viscous wall flux  <sub>voronoi-methods-plan.md:147-153</sub>
- **Candidate-array shrink tried and reverted — array size cannot shrink below full-sphere gather need**. **Rejected:** shrinking the candidate array below 1024 (tried 512, safe-min ~896)  <sub>vorflow-kokkos-migration.md:1141-1147</sub>
- **Clip designs must be valid-by-construction; the topological inconsistency is the bug class to design out, not geometric imprecision**. **Rejected:** fixing topological-inconsistency bugs (e.g. dead-triangle phantom-horizon cascades) by using more-accurate geometric predicates  <sub>robustness-topology-oriented-sugihara.md:26</sub>
- **Cold-build construct is DONE at ~14.5 M/s ceiling — do not reopen; Part II (moving points) is the real remaining win**. **Rejected:** further cold-build construct optimization  <sub>vorflow-gpu-voronoi-build-engine.md:156-161</sub>
- **Cold-build gather cost (~70 distance tests/cell) is near-optimal, not wasteful — stop chasing gather tweaks**. **Rejected:** Morton/Z-order point ordering; branchless wrap vs int-modulo; caching secR2; shrinking MAXP/MAXT caps; further gather tuning generally  <sub>vorflow-gpu-voronoi-build-engine.md:34-50</sub>
- **ConnectivityArena 2-ring surgical retry is also a negative result**. **Rejected:** ConnectivityArena 2-ring candidate set for surgical repair  <sub>vorflow-dynamic-updater-phase01.md:76</sub>
- **Construct is bound by intrinsic clip-chain work; packing and warp-cooperative rejected**. **Rejected:** packed/compact cell representation; warp-cooperative register-resident cell construction; explicit adjacency; incremental security radius  <sub>vorflow-gpu-voronoi-build-engine.md:52-66</sub>
- **ConvexCell (dual-triangle) chosen as the GPU topology, not the half-edge cell representation**. **Rejected:** half-edge cell representation as the GPU topology (kept only as CPU oracle)  <sub>vorflow-kokkos-migration.md:1233-1241</sub>
- **ConvexCell foot-point representation cannot represent live d<0 faces — large-weight power deferred, small-weight solver stays d>0**.  <sub>vorflow-power-cells-deferred.md:20</sub>
- **ConvexCell geometry decoupled from plane-definition: calculus is a function of {n_k} only**. **Rejected:** 4×T fused kernels (one kernel per geometry-tier × cell-type combination); inlining plane-from-dofs into the hot geometry kernel  <sub>vorflow-convexcell-geometry-split.md:10-17</sub>
- **Convexity certificate alone is insufficient — propagation to neighbours is essential**. **Rejected:** independent local repair without propagation (S3 alone)  <sub>vorflow-dynamic-update-strategy-study.md:52-55</sub>
- **Cooperative/warp-parallel half-edge cut is a dead end — do not re-attempt**. **Rejected:** cooperative/warp-parallel half-edge cut (team-per-cell intra-cut parallelism)  <sub>vorflow-kokkos-migration.md:1181-1192</sub>
- **DEC viscous term shelved — first-order on skewed meshes, unstable explicitly**. **Rejected:** DEC viscous term as an explicit covolume viscous operator  <sub>voronoi-methods-plan.md:174-179</sub>
- **Device Power/Laguerre diagrams dropped — no ConvexCell radical-plane geometry yet**. **Rejected:** device Power/Laguerre diagrams under the current ConvexCell foot-point half-space representation  <sub>vorflow-scratchcell-retired-dynamic-cells-next.md:33-37</sub>
- **Device kernel must scalarize small dynamically-indexed arrays to registers via #pragma unroll, not leave them local-memory**. **Rejected:** naive analytic dAreaTri implementation with dynamically-indexed local arrays (2.4x slower on GPU)  <sub>vorflow-convexcell-geometry-split.md:68-72</sub>
- **Distributed cold build: only build cells for original-index < nBuild; ghosts stay candidates only**. **Rejected:** tessellating ghost cells that get discarded  <sub>vorflow-worklist-into-tessellator.md:38-45</sub>
- **Dynamic cell-update study scoped to topology+geometry only, no physics**. **Rejected:** including physics/forces/dynamics in this study  <sub>vorflow-dynamic-update-strategy-study.md:12-13</sub>
- **Explicit standing instruction: do not propose Shewchuk/SoS robust predicates as the voro robustness plan**. **Rejected:** Shewchuk/SoS robust (exact) predicates as the robustness plan  <sub>robustness-topology-oriented-sugihara.md:32</sub>
- **Filtered prolongator smoothing is required (unfiltered densifies/destabilizes the hierarchy)**. **Rejected:** unfiltered prolongator smoothing  <sub>voro-graph-amg-next.md:28-30</sub>
- **Fixed-K=64 kNN via ArborX BVH is the cold-build engine; best-first traversal rejected**. **Rejected:** best-first BVH traversal for the cold build  <sub>vorflow-gpu-voronoi-build-engine.md:20-32</sub>
- **Free-energy objective (e=−V_ref·log(V)) is the elegant right formulation for graded equal-pressure meshing**. **Rejected:** the earlier relative-energy + explicit log-barrier (μ Σ log(V/V_ref)) formulation as the primary objective  <sub>voro-mesh-optimizer-wall-force.md:86-91</sub>
- **GPU lever "warp-shares-one-worklist" is a net loss and was reverted**. **Rejected:** lever #1, warp-shares-one-worklist sorting by sub-position+Morton  <sub>vorflow-worklist-gather-next.md:19</sub>
- **GPU tessellator granularity redesign: team/warp-per-cell landed at ~0.6x default, wall is the sequential half-edge cut**.  <sub>vorflow-kokkos-migration.md:1176-1180</sub>
- **GPU-vs-CPU tessellator optimizations diverge: reducing work helps GPU, cheaper ops help only CPU**. **Rejected:** triangle adjacency (O(1) horizon) and incremental security-radius as GPU optimizations  <sub>vorflow-kokkos-migration.md:1213-1215</sub>
- **GraphAMG built standalone, not on top of core::amr::MomentumMG**. **Rejected:** building the mesh-optimizer's O(N) solve on core::amr::MomentumMG  <sub>voro-graph-amg-next.md:20-25</sub>
- **GraphAMG is not worth it for the mesh-optimizer solve; colored-GS-CG / Jacobi-CG win in wall-clock**. **Rejected:** GraphAMG as the preconditioner for this mesh-optimizer solve; plain (unpreconditioned) CG  <sub>voro-mesh-optimizer-wall-force.md:1699-1703</sub>
- **GraphAMG strength criterion must compare squared Frobenius norm against sqrt of the diagonal product, not the raw product**. **Rejected:** `θ²·ddiag_I·ddiag_J` as the strength-of-connection threshold  <sub>voro-graph-amg-next.md:35-37</sub>
- **GraphAMG strength threshold default θ=0.05**.  <sub>voro-graph-amg-next.md:41-42</sub>
- **GraphAMG λ_max power-iteration seed must be a well-mixed random ±1 vector, not smooth or degenerate**. **Rejected:** a smooth seed vector; an `i·odd & 1` seed vector  <sub>voro-graph-amg-next.md:37-40</sub>
- **Interface FORCE (gradFacetAreaSq) retired; ConvexCell replacement is geomVolumeAreaGrad**. **Rejected:** gradFacetAreaSq (half-edge-only interface force)  <sub>vorflow-scratchcell-retired-dynamic-cells-next.md:38-39</sub>
- **KOKKOS_LAMBDA capturing `this` for a member read is illegal on CUDA only**.  <sub>voronoi-methods-plan.md:79</sub>
- **Legacy half-edge Voronoi engine retired; device-only ConvexCell architecture is production**. **Rejected:** the legacy half-edge CPU-oracle engine and its associated test/golden data tree  <sub>vorflow-dynamic-updater-phase01.md:264</sub>
- **Legacy half-edge engine kept only as test oracle; production path must stay legacy-free (enforced)**. **Rejected:** porting the legacy Incompressible stub faithfully; letting production code include voronoi/simulation  <sub>vorflow-kokkos-migration.md:1034-1039</sub>
- **Local Newton-on-positions cannot equalize or grade cell volumes from a random seeding — needs global seed redistribution**. **Rejected:** local Newton-on-positions alone (without global seed redistribution) for equalizing/grading volumes  <sub>voro-mesh-optimizer-wall-force.md:69-72</sub>
- **M0/D0 derivation doc deferred by the user — do not start unprompted**. **Rejected:** starting the M2/D0 derivation doc unprompted  <sub>voronoi-methods-plan.md:234-236</sub>
- **Montgomery-batch reciprocal reduction reverted — FP32-unsafe**. **Rejected:** the 3-divide-to-1 Montgomery-batch-inversion reciprocal reduction  <sub>vorflow-cpu-migration-discussion.md:44-56</sub>
- **Morton (Z-order) grid indexing kept GPU-only, not for CPU backend**. **Rejected:** using Morton grid indexing on the CPU/host backend  <sub>vorflow-kokkos-migration.md:1104-1109</sub>
- **No-op-clip avoidance (culling pre-clip candidates) prototyped and rejected**. **Rejected:** the AABB/6-DOP mayCut pre-clip culling test  <sub>vorflow-gpu-voronoi-build-engine.md:147-154</sub>
- **Nondeterministic miss root cause: plane-count cap and facet over-buffer both miscounted; fixed to compact/rebuild at exact demand**. **Rejected:** capping on raw plane count without compaction; sizing the facet buffer by an N×18 mean estimate  <sub>voronoi-methods-plan.md:181-191</sub>
- **Order-free volume walk without stored adjacency does not help; atan2 is not the bottleneck**. **Rejected:** order-free volume walk without stored adjacency, as a performance win  <sub>vorflow-gpu-voronoi-build-engine.md:176-189</sub>
- **Per-sub-position rmin worklist gather replaces the adaptive shell-offset walk, on the host build path**. **Rejected:** the adaptive shell-offset walk  <sub>vorflow-worklist-into-tessellator.md:14-19</sub>
- **Phase-3 gate: churn thresholds and dilate() default**.  <sub>vorflow-dynamic-updater-phase01.md:61</sub>
- **Plan of record §12 rulings (approved 2026-09-03)**. **Rejected:** an OpenFOAM writer; picking only one of covolume/collocated; picking only one moving-cell integrator up front  <sub>voronoi-methods-plan.md:8-13</sub>
- **Power-cell solver physics deliberately not built yet — user wants it brainstormed first**. **Rejected:** building the solver physics before the design is brainstormed  <sub>vorflow-power-cells-deferred.md:10</sub>
- **Production dynamic-update strategy is S5: persistent Verlet skin-list + propagating repair**. **Rejected:** S3/S4 (which re-gather the grid every step) as the production strategy  <sub>vorflow-dynamic-update-strategy-study.md:80-88</sub>
- **Reconstructing the clipped cell externally for dV/dn was unnecessary — use the tessellator's published facet areas**. **Rejected:** externally reconstructing the clipped cell (buildConvexCell/initBox+clip) to get dV/dn  <sub>voro-mesh-optimizer-wall-force.md:53-56</sub>
- **Robustness approach: topology-oriented (Sugihara), valid-by-construction, NOT exact predicates**. **Rejected:** exact-arithmetic predicates for robustness  <sub>vorflow-gpu-voronoi-build-engine.md:232-233</sub>
- **SDF wall force uses Option A (exact flat / first-order curved), user's choice**. **Rejected:** an alternative (presumably higher-order curved) SDF wall-force option, not detailed in the note  <sub>vorflow-power-cells-deferred.md:16</sub>
- **SDF wall term still stalls the optimizer — diagnosed as the approximate wall-gradient's first-order error, not the objective**.  <sub>voro-mesh-optimizer-wall-force.md:92-97</sub>
- **SOTA adjacency-based cell structure loses on GPU; linear findSharing wins for ~28-triangle cells**. **Rejected:** the Ray-et-al/geogram adjacency-pointer cell representation on GPU  <sub>vorflow-gpu-voronoi-build-engine.md:68-82</sub>
- **ScratchCell half-edge device cutter retired in favor of ConvexCell**. **Rejected:** the half-edge ScratchCell device cutter  <sub>vorflow-scratchcell-retired-dynamic-cells-next.md:10-16</sub>
- **Seeding heuristic: grade a Voronoi mesh by placing seeds at target spacing (shells), not by rejection-sampling a density**. **Rejected:** rejection-sampling seeds proportional to 1/V_ref density (old seed_pore_space)  <sub>voro-mesh-optimizer-wall-force.md:109-120</sub>
- **Single-face surgical re-clip is a negative result vs gated gather**. **Rejected:** single-face surgical re-clip (stored∪partner candidate set)  <sub>vorflow-dynamic-updater-phase01.md:69</sub>
- **Smoother is 4th-kind Chebyshev, not colored-GS**. **Rejected:** colored Gauss-Seidel smoother (for GPU/MPI reasons, decided earlier); 1st-kind Chebyshev (needs a lower-bound guess)  <sub>voro-graph-amg-next.md:31-34</sub>
- **Steepest descent (plain −g), not Newton, is the robust move direction — GN Hessian is rank-deficient**. **Rejected:** relying on the Gauss-Newton Hessian direction (H⁻¹g) when it is rank-deficient  <sub>voro-mesh-optimizer-wall-force.md:76-79</sub>
- **Test equivalence contract: 1e-9 volume tolerance + exact neighbour set, NOT bit-exactness — cut order is free to change**. **Rejected:** requiring bit-exact agreement with the legacy serial cutter  <sub>vorflow-worklist-into-tessellator.md:28-31</sub>
- **Topology decisions must be computed in FP64; geometry/volume can be FP32**. **Rejected:** doing the topology (convexity) decision in FP32  <sub>vorflow-dynamic-update-strategy-study.md:58-61</sub>
- **Use geomVolumeGrad (3-array), not geomVolumeArea, for force-only computation**. **Rejected:** geomVolumeArea (6-array, single-pass) for force-only use cases  <sub>vorflow-convexcell-geometry-split.md:48-55</sub>
- **Use the sqrt-free area-vector formula for physics, not facetAreasPerVertex's magnitude form**. **Rejected:** using facetAreasPerVertex's sqrt-based scalar magnitude for physics computations  <sub>vorflow-cpu-migration-discussion.md:59-61</sub>
- **Voro++-style worklist gather is now the default engine on both CPU and GPU backends**. **Rejected:** the whole-block-accept approach for the earlier deficit; the prior assumption that branching would hurt GPU throughput  <sub>vorflow-worklist-gather-next.md:11</sub>
- **Voronoi robustness follows Sugihara's topology-oriented approach; exact/robust predicates are explicitly rejected**. **Rejected:** exact/adaptive robust predicates (Shewchuk-style orientation/incircle tests)  <sub>robustness-topology-oriented-sugihara.md:10</sub>
- **VoronoiHalo disables periodic self-images (includePeriodicSelf=false) — device tessellator is periodic-native**. **Rejected:** enabling periodic self-images in the halo (redundant with the tessellator's own minimal-image periodicity)  <sub>vorflow-kokkos-migration.md:1014</sub>
- **Wall-facet foot uses the general Newton foot n=−φ∇φ/|∇φ|², not the SDF-only n=−φû**. **Rejected:** addSdfWallForce's n=−φû foot (has an extra |∇φ| term)  <sub>voro-mesh-optimizer-wall-force.md:57-59</sub>
- **Warp-cooperative clip / shared-memory neighbour staging (lever #2) was deliberately not pursued**. **Rejected:** implementing warp-cooperative clip / shared-memory neighbour staging  <sub>vorflow-worklist-gather-next.md:22</sub>
- **Whole-block-accept (rmax) is a net loss on the fine grid and stays gated off by default**. **Rejected:** whole-block-accept (CC_WBA) as a default optimization  <sub>vorflow-worklist-gather-next.md:30</sub>
- **dAreaTri kernel renamed to geomVolumeAreaGrad; policy named Voronoi, not PlaneVoronoi (user naming decision)**. **Rejected:** the names dAreaTri and PlaneVoronoi  <sub>vorflow-convexcell-geometry-split.md:74-77</sub>
- **geomVolumeGrad: sqrt-free 3-array form chosen over per-vertex normalization or a 4th scratch array**. **Rejected:** normalizing inside the per-vertex scatter (6x the sqrts); a separate raw sacc[MAXP] 4th scratch array  <sub>vorflow-convexcell-geometry-split.md:36-46</sub>
- **nvcc: no first-capture inside `if constexpr`**.  <sub>voronoi-methods-plan.md:29-30</sub>
- **poke4 caching makes the new (TrackAdj) certificate uniformly beat the old poke design**. **Rejected:** the plain TrackAdj adjacency-derivation-per-query approach (pricier cert) and the OLD poke approach (expensive gather with findSharing)  <sub>vorflow-dynamic-updater-phase01.md:191</sub>
- **vorflow get_num_neighbors must read the explicit cellFacetCount, not diff the device cellFacetOffset**. **Rejected:** computing neighbour count as off(i+1)-off(i) over the device cellFacetOffset  <sub>nanobind-zero-copy-migration.md:28</sub>
- **voronoi_dynamics Kokkos port is OpenMP-first, no GPU backend this effort**. **Rejected:** doing a GPU backend for voronoi in this effort  <sub>cuda-kokkos-migration.md:90-91</sub>
- **voronoi_dynamics renamed to vorflow, not "voronoi"**. **Rejected:** naming it "voronoi"  <sub>cuda-kokkos-migration.md:65-67</sub>

### Superseded — history, do not re-derive the old reading

- C1 gate metric was wrong: cellwise-residual "2nd order" is not the right convergence gate.  <sub>voronoi-methods-plan.md:85-88</sub>
- C3 wall Poiseuille is not exact to round-off; the plan's claim was wrong.  <sub>voronoi-methods-plan.md:128-130</sub>
- Convexity certificate replaced by local-Delaunay (4-poke) test.  <sub>vorflow-dynamic-updater-phase01.md:106</sub>
- Inline reshape repair: tried, reverted as marginal, but the local-Delaunay certificate is retained.  <sub>vorflow-dynamic-updater-phase01.md:122</sub>
- Per-vertex flag/divergence geometry (sort-free, adjacency-free) adopted as the default re-eval kernel, superseding the atan2 and stored-adjacency paths.  <sub>vorflow-gpu-voronoi-build-engine.md:190-229</sub>
- Reframe: the neighbour-query GATHER, not the topology decision/repair, is the core problem to solve next.  <sub>vorflow-dynamic-update-strategy-study.md:92-94</sub>
- The voro mesh optimizer's host-orchestrated first cut was a violation of the device-first principle and had to be re-architected.  <sub>device-first-mpi-design-principle.md:20</sub>
- TrackAdj/adjacency-maintained Lawson certificate replaces the 4-poke local-Delaunay certificate.  <sub>vorflow-dynamic-updater-phase01.md:140</sub>

## amr — block octree, mixed-level cut band

61 in force, 2 superseded — full text in [`decisions/amr.md`](decisions/amr.md)

### In force

- **AMR NS advection keeps the fluid-fluid scheme unchanged; uf stays the face-averaged form**.  <sub>amr-ghost-collocated-ns-plan.md:83</sub>
- **AMR gets its own separate Python binding module (tpx_amr), not folded into tpx_mpi**. **Rejected:** extending tpx_mpi to include AMR bindings  <sub>amr-python-bindings-next.md:14-17,</sub>
- **AMR keeps ORB block decomposition, not a global SFC partition**. **Rejected:** one global SFC partitioned by index range (p4est/Dendro style)  <sub>amr-octree-status.md:12-15</sub>
- **AMR pressure "near-nullspace" stall under advection was an un-deflated incompatible RHS mean plus a stale PCG gate — not an SPD or coarsest-level defect**. **Rejected:** an SPD violation as the cause; the coarsest-MG-level as the cause (both explicitly refuted by measurement)  <sub>amr-aperture-advection-resolved.md:11</sub>
- **AMR rebalance weight grid is defined over root cells, not fine cells**. **Rejected:** weighting over fine cells  <sub>dynamic-load-balancing.md:67</sub>
- **All world-coordinate evaluation must use the global frame, never per-rank local coordinates**. **Rejected:** per-rank local-frame world-coordinate evaluation  <sub>amr-distributed-flow-campaign.md:22</sub>
- **Bind host AMR classes before the Kokkos device path**. **Rejected:** binding the Kokkos device AMR classes first  <sub>amr-python-bindings-next.md:203-204</sub>
- **C/F scheme pressure matrix/MG/PCG stays standard order — placement is (1,2)**. **Rejected:** moving the matrix itself to quadratic C/F order  <sub>amr-ghost-collocated-ns-plan.md:71</sub>
- **C/F-consistent flow operators fix graded-mesh drag (supersedes the "momentum only" attempt)**. **Rejected:** solveQuad projection (quadratic coarse-fine flux) for the graded flow's pressure solve; momentum-only C/F fix  <sub>amr-octree-status.md:947-958</sub>
- **Cell-count savings did not reduce march time — the saving is a spent, not lost, quantity**. **Rejected:** H-iters and H-mg as explanations for the flat step time (both REFUTED)  <sub>amr-mixed-level-cut-band-plan.md:238</sub>
- **Changing a default that affects numerics re-blesses bed references — treat as a decision, not a tuning knob**.  <sub>amr-march-distributed-campaign.md:18-23</sub>
- **Cloud-economy variant selection: bed permeability alone is the wrong discriminator**. **Rejected:** N≤24 and N≤16 cloud-economy variants (look better on permeability alone but fail seam/stability gates)  <sub>amr-mixed-level-cut-band-plan.md:382</sub>
- **Coarsening/covering construction must use c.find(f.code(i)) suite-wide, not ancestor(level+1)**. **Rejected:** ancestor(level+1)+find for covering construction  <sub>amr-distributed-flow-campaign.md:32</sub>
- **Collocated pressure coupling is ABC (Almgren-Bell-Colella), never Rhie-Chow**. **Rejected:** Rhie-Chow interpolation for the collocated pressure-velocity coupling  <sub>amr-octree-status.md:56-68</sub>
- **Compat-RHS repair works but is rejected for production in favor of deflation, due to a resolution-independent bias**. **Rejected:** the compat-RHS repair (computing divergence on all operator DOF) as the production fix  <sub>amr-aperture-advection-resolved.md:49</sub>
- **Cut-cell openness α must be evaluated at the finer neighbour's actual lower corner, not the probe point**. **Rejected:** using the probe point's lower corner for computing sub-face α  <sub>amr-octree-status.md:871-874</sub>
- **D1' host parallelism is pure Kokkos over an OpenMP host space, not OpenMP pragmas**. **Rejected:** "my first-draft OpenMP-pragma route"  <sub>amr-mixed-level-cut-band-plan.md:152</sub>
- **Distributed MG deadlock fixed by padding the hierarchy to the global-max level count**. **Rejected:** per-rank-local level counts driving a collective loop  <sub>amr-testing-benchmarking-resume.md:31-49</sub>
- **Distributed fragmentation guard design: halo label-propagation + Allreduce, not rank-local BFS**. **Rejected:** rank-local BFS for the distributed fragmentation guard  <sub>amr-distributed-flow-campaign.md:67</sub>
- **Distributed momentum preconditioner is rank-local Galerkin MG, not Jacobi**. **Rejected:** a Jacobi fallback preconditioner  <sub>amr-distributed-flow-campaign.md:40</sub>
- **Extend core's AmrFlow rather than build octree AMR into flow itself**. **Rejected:** "build octree AMR into flow itself"  <sub>amr-ghost-collocated-ns-plan.md:134</sub>
- **Fix: remove the stale presPCG_ && !advect_ gate — the PCG's per-iteration deflation already handles the incompatible RHS**. **Rejected:** keeping the presPCG_ && !advect_ gate that forced the (unconverging) V-cycle path under advection  <sub>amr-aperture-advection-resolved.md:28</sub>
- **Fragmentation guard: pocket cells pinned and excluded from the mean and gradients, not zero-forced**. **Rejected:** gating pocket creep as exactly zero  <sub>amr-ghost-collocated-ns-plan.md:112</sub>
- **GOTCHA/invariant: detect non-finite explicitly — max|u| via std::max(0,NaN) hides blowup**. **Rejected:** relying on max|u| alone to detect solver blowup  <sub>amr-octree-status.md:781-782</sub>
- **Gap-floor policy default n=4 is the calibrated floor, not sharper**. **Rejected:** n=8 or sharper (non-monotone, not a reliable improvement)  <sub>amr-mixed-level-cut-band-plan.md:102</sub>
- **Geometric octree-walk kernels kept as an independent oracle alongside the shared-CSR kernels**. **Rejected:** deleting the geometric octree-walk implementations once the shared CSR body existed  <sub>amr-host-device-kernel-consolidation.md:31-32</sub>
- **Ghost metadata must be re-installed into builders at the top of every discovery round**.  <sub>amr-distributed-flow-campaign.md:77</sub>
- **Ghost projection is retired suite-wide; ghost_closure has no production consumer**. **Rejected:** AUTO-selecting ghost projection as a production scheme  <sub>amr-aperture-advection-resolved.md:36</sub>
- **Ghost-closure pure functions are lifted into core, not duplicated**. **Rejected:** duplicating the pure closure functions in flow and core separately  <sub>amr-ghost-collocated-ns-plan.md:36</sub>
- **Host AMR must stay Kokkos-free; consolidation done via shared MORTON_HD kernel bodies over a templated accessor**. **Rejected:** making the host AMR reference depend on Kokkos  <sub>amr-host-device-kernel-consolidation.md:14-19</sub>
- **Host pressure runtime deliberately kept geometric (not switched to shared CSR kernels) for performance reasons**. **Rejected:** switching the host pressure runtime to the shared assembled-CSR kernel  <sub>amr-host-device-kernel-consolidation.md:33-36</sub>
- **Implicit-FOU deferred correction defaults ON for AmrFlow advection**. **Rejected:** pure explicit advection (default before this change)  <sub>amr-octree-status.md:777-782</sub>
- **Incremental rotational pressure projection replaces non-incremental Chorin (removes dt-dependent error)**. **Rejected:** plain non-incremental Chorin projection  <sub>amr-octree-status.md:763-767</sub>
- **Invariant: faceNeighborGather slot layout is [+x,-x,+y,-y,+z,-z]**. **Rejected:** a [-x,+x,-y,+y,-z,+z] slot ordering  <sub>amr-python-bindings-next.md:34-35</sub>
- **Island-corner C/F stencils sample a finer tangential neighbour by child-volume average**.  <sub>amr-ghost-collocated-ns-plan.md:109</sub>
- **M2/D3 verdicts: H-launch accepted as a small-mesh tax; np>1 ~3e-7 residual class accepted**. **Rejected:** reworking H-launch cost immediately (deferred instead to device-assembly campaign)  <sub>amr-mixed-level-cut-band-plan.md:357</sub>
- **MG hierarchy must share one h0 (level already encodes width)**. **Rejected:** doubling h0 per level  <sub>amr-octree-status.md:34-35</sub>
- **MG-as-solver + Picard outer loop: project ONCE per step, not inside the loop**. **Rejected:** projecting inside the Picard outer loop  <sub>amr-gpu-smoother-flow-port.md:56-67</sub>
- **Minimum-image period for cloud membership is fineExt·h0, an off-by-one fix not a convention change**. **Rejected:** "none stated" (bug fix, not an alternative choice)  <sub>amr-mixed-level-cut-band-plan.md:281</sub>
- **Mixed-level cut-band overlay CSR growth spends the cell savings, not lost — H-iters/H-mg refuted**. **Rejected:** the pre-registered H-iters and H-mg hypotheses for where the mixed-level band's speed benefit comes from  <sub>amr-march-distributed-campaign.md:30-37</sub>
- **Multicolor-GS smoother: symmetrize the adjacency before coloring; sweep must be symmetric (SGS), undamped**. **Rejected:** forward-only (non-symmetric) GS colouring/sweep as a BiCGStab preconditioner; damped GS (omega=0.7)  <sub>amr-gpu-smoother-flow-port.md:40-55</sub>
- **Mutex-on-miss fix: guard only the pre-freeze emplace, not the wider candidate fixes**. **Rejected:** "Neither candidate fix was needed" (the two originally-proposed candidate fixes for the race)  <sub>amr-mixed-level-cut-band-plan.md:135</sub>
- **OpenMP backend is the bit-exact determinism reference; GPU is tolerance-based only**. **Rejected:** the earlier belief that CUDA/HIP were bit-exact to host  <sub>amr-gpu-smoother-flow-port.md:142-146</sub>
- **Poisson operator sign convention unified suite-wide: L=∇² (negative-definite)**. **Rejected:** A=−∇² convention (used previously in DistributedPoisson/deviceJacobiSweep)  <sub>amr-octree-status.md:861-865</sub>
- **Pressure smoother chosen: MG-PCG, NOT multicolor-GS; Chebyshev not pursued for pressure**. **Rejected:** multicolor-GS for the pressure smoother; a Chebyshev pressure driver  <sub>amr-gpu-smoother-flow-port.md:128-133</sub>
- **Projection, MG transfers and V-cycle orchestration deliberately NOT consolidated onto a shared body**. **Rejected:** consolidating the projection/MG-transfer/V-cycle code onto a shared body  <sub>amr-host-device-kernel-consolidation.md:47-52</sub>
- **Rediscretized coarse momentum operators fail — must coarsen the exact assembled operator (Galerkin)**. **Rejected:** rediscretized openness/Neumann Helmholtz coarse operator (with and without the shift-floor fix)  <sub>amr-gpu-smoother-flow-port.md:153-159</sub>
- **SOU (second-order-upwind) is the default advection flux; Koren TVD becomes an option**. **Rejected:** Koren TVD as the default (now opt-in)  <sub>amr-octree-status.md:770-776</sub>
- **Sign convention: the AMR ghost operator is +L (negative-definite)**.  <sub>amr-ghost-collocated-ns-plan.md:44</sub>
- **Staircase velocity-MG fixed by the clean-fluid exclude mask; Galerkin stays the robust default**.  <sub>amr-gpu-smoother-flow-port.md:29-38</sub>
- **Volume-weighted superficial velocity is required on graded meshes**. **Rejected:** non-volume-weighted superficial velocity on graded meshes  <sub>amr-ghost-collocated-ns-plan.md:57</sub>
- **Zero pressure after finish_adapt rather than carry the accumulated pressure through coarsening**. **Rejected:** carrying the transferred/accumulated pressure through a coarsening adapt event  <sub>amr-ghost-collocated-ns-plan.md:121</sub>
- **cf=1 (quadratic C/F flux) is not optional on graded meshes**. **Rejected:** standard (cf=0) two-point C/F flux on graded/throat meshes  <sub>amr-mixed-level-cut-band-plan.md:113</sub>
- **cfDiv/cfGrad row gate must be rowRegular, not rowFluid**. **Rejected:** rowFluid gate under the assumption "cut rows are finest-band"  <sub>amr-mixed-level-cut-band-plan.md:70</sub>
- **mpi4py rule: never call a collective inside a rank-0-only block**.  <sub>amr-distributed-flow-campaign.md:84</sub>
- **np=1 bit-exactness is the gate for every distributed default**.  <sub>amr-distributed-flow-campaign.md:75</sub>
- **setGhostProjection default is AUTO (tri-state), not always-on or always-off**.  <sub>amr-ghost-collocated-ns-plan.md:98</sub>
- **setSolid bottleneck diagnosed as SDF evaluation cost, not builder logic**. **Rejected:** a scalar std::function SDF evaluation API (locks in serial host evaluation forever)  <sub>performance-sota-yardstick.md:21-28</sub>
- **transferField prolongation gradients must be halo-completed, not block-local**. **Rejected:** block-local prolongation gradients  <sub>amr-distributed-flow-campaign.md:47</sub>
- **κ-restrict re-tested on Dirichlet: floor gone but still no win over plain — plain stays default**. **Rejected:** κ-weighted restriction as default (confirmed again)  <sub>amr-octree-status.md:899-910</sub>
- **κ-weighted MG restriction evaluated and rejected as default; plain volume-average stays default**. **Rejected:** κ-weighted restriction as the default MG restriction operator  <sub>amr-octree-status.md:888-898</sub>

### Superseded — history, do not re-derive the old reading

- G.2 decision changed: the whole core/amr tree becomes its own package peclet-amr, depending on core alone.  <sub>suite-quality-plan-1-0-0.md:68-80</sub>
- Graded-mesh flow requires ALL flow operators (momentum, divergence/gradient, advection) to be C/F-consistent — momentum-only fix insufficient.  <sub>amr-octree-status.md:947-958</sub>

## core — decomposition, halo, rebalance

23 in force, 1 superseded — full text in [`decisions/core.md`](decisions/core.md)

### In force

- **AMR PCG must mask solid AND project onto the fluid range (mask + fluid-only mean), not just deflate the constant mode**. **Rejected:** deflating only the constant/all-cell mean without masking solid cells  <sub>device-naming-retirement.md:89-95</sub>
- **Anisotropic coarse-grid partitioning requires cellExtent, not raw cell-count kLargest**. **Rejected:** partitioning by raw cell-count kLargest on an anisotropic coarse grid  <sub>mg-decomposition-alignment.md:43</sub>
- **Convention: keep NBX tag families >= 64 apart**.  <sub>nbx-round-tag-race.md:28</sub>
- **Device-vs-host numerical comparison policy: bit-exact assembly, tolerance-based apply on CUDA/HIP**. **Rejected:** requiring bit-exact apply/V-cycle results on CUDA/HIP (impossible given FMA contraction)  <sub>kokkos-cuda-constexpr-required.md:27-30</sub>
- **GPU-aware MPI auto-detection uses query + checksum loopback probe, never blind probing**. **Rejected:** blind device-pointer probing to auto-detect CUDA-aware MPI  <sub>suite-mpi-gpu-campaign.md:16</sub>
- **Gate the CUDA-aware MPI device path on an explicit env var, not the MPI query API**. **Rejected:** relying on MPIX_Query_cuda_support() to detect CUDA-aware MPI  <sub>suite-distributed-status.md:353</sub>
- **Halo topology vs exchange split: topology stays host MPI plumbing, exchange is the device kernel**.  <sub>device-naming-retirement.md:32-40</sub>
- **Kokkos CUDA installs MUST set Kokkos_ENABLE_CUDA_CONSTEXPR=ON**. **Rejected:** building the nvidia-cuda Kokkos install without Kokkos_ENABLE_CUDA_CONSTEXPR  <sub>kokkos-cuda-constexpr-required.md:10-22</sub>
- **NBX consecutive rounds must use distinct message tags**. **Rejected:** sharing tag 0 across NBX request/reply rounds  <sub>amr-octree-status.md:786-791</sub>
- **NBX inter-round tag race fixed by rotating the tag per round; buildTopology now verifies promised==requested cells**. **Rejected:** running consecutive NBX consensus rounds on one communicator with a single fixed tag  <sub>nbx-round-tag-race.md:17-19</sub>
- **NBX tag interaction: two standing rules for wire tags**.  <sub>amr-march-distributed-campaign.md:66-77</sub>
- **ParticleHalo gather() throws on capacity overflow instead of silently truncating**. **Rejected:** silent truncation of ghost count on overflow  <sub>cuda-kokkos-migration.md:627-629</sub>
- **ParticleHalo periodic self-ghosts default OFF for byte-identical compatibility**. **Rejected:** making periodic self-ghosts on by default  <sub>cuda-kokkos-migration.md:618-621</sub>
- **Periodic axis needs >=2 ranks**.  <sub>suite-distributed-status.md:27-28</sub>
- **Port transport-core's device layer first (foundation-first sequencing)**. **Rejected:** porting each consumer's halo independently (double-porting)  <sub>cuda-kokkos-migration.md:79-82</sub>
- **Rebalance is pure migration (same global mesh, new owners) and must never use transferField**. **Rejected:** using transferField (same-domain old→new octree conservative remap) to implement rebalance migration  <sub>dynamic-load-balancing.md:62</sub>
- **Treat nvcc warnings #20013/#20015 as errors, not style noise**. **Rejected:** treating #20013/#20015 as benign style warnings  <sub>kokkos-cuda-constexpr-required.md:26-27</sub>
- **Weighted ORB dynamic load balancing is one shared primitive that lives in the core layer**. **Rejected:** implementing separate load-balancing logic per consumer (AMR, dem)  <sub>dynamic-load-balancing.md:18</sub>
- **Weighted ORB split boundary must remain on integer cell boundaries**.  <sub>dynamic-load-balancing.md:65</sub>
- **block_decomposer retired/archived, replaced by transport-core (core)**.  <sub>cuda-kokkos-migration.md:57-58</sub>
- **coarsenAlignment bug: natural-max alignment over-constrains ORB; cap alignment at 2^4**. **Rejected:** natural-max alignment for ORB decomposition snapping  <sub>parallel-scaling-study.md:60-64</sub>
- **peclet-core sdist must vendor its own SuiteNanobind copy, not depend on the umbrella cmake/**. **Rejected:** the core sdist referencing the umbrella's cmake/ directory for SuiteNanobind  <sub>release-workflow-prep.md:93</sub>
- **toVector must repack a strided device subview to a contiguous buffer before cross-space deep_copy**. **Rejected:** cross-space deep_copy directly on a strided device subview  <sub>dem-cubes-gpu-pyvista.md:30-34</sub>

### Superseded — history, do not re-derive the old reading

- No Rhie-Chow update at cell centres — RC is purely the face term, automatic once uf is separate from interp(u).  <sub>device-naming-retirement.md:106-108</sub>

## coupling — CFD-DEM

17 in force, 1 superseded — full text in [`decisions/coupling.md`](decisions/coupling.md)

### In force

- **CFD-DEM couples flow and dem in Python only, via DLPack, with no C++ link**. **Rejected:** a direct C++ link between flow and dem  <sub>multiphysics-framework-plan.md:408</sub>
- **Causes ruled out before finding the epsilon-conservative-momentum fix**. **Rejected:** ∂ε/∂t RHS term as the cause; conservative-flux advection compensation alone as sufficient; PCG/Chebyshev/GraphAMG solver choice as the cause  <sub>porous-eps-conservative-momentum.md:17-19</sub>
- **Centre-of-rotation convention: NaN follows the body, any finite point (including origin) pins**. **Rejected:** the old zeros-follow rule as ambiguous going forward (kept only for legacy 17-real array decode)  <sub>sdf-scene-campaign.md:139</sub>
- **Coupled decomposition uses weight-field-based rebalance, never exposing decomposition objects to Python**. **Rejected:** passing/crossing BlockDecomposer objects to Python  <sub>multiphysics-framework-plan.md:371</sub>
- **Drag coupling must be implicit (semi-implicit on the momentum diagonal), not explicit**. **Rejected:** explicit −βu drag forcing  <sub>multiphysics-framework-plan.md:387</sub>
- **Exponential-integrator effective drag replaces plain explicit particle-side drag exchange**. **Rejected:** explicit particle-side drag exchange (β·dt/m unconstrained)  <sub>porous-eps-conservative-momentum.md:46-54</sub>
- **Kuipers deposit-after-push reorder tested, not adopted**. **Rejected:** Deen/Kuipers synchronous eps-update ordering  <sub>porous-cfddem-cuda-two-bugs.md:39</sub>
- **Model-B drag conversion: β_B = β_A/ε; CfdDem defaults changed (advection=True, eps_min 0.4)**. **Rejected:** eps_min=0.2 or 0.3  <sub>porous-cfddem-cuda-two-bugs.md:25-26</sub>
- **Porosity clip changed from a 0.4 floor to [0,1]-only, per user directive; MFIX-faithful smoothing/drag law added instead**. **Rejected:** clamping ε at a 0.4 floor  <sub>porous-cfddem-cuda-two-bugs.md:59-62</sub>
- **Reaction torque coupling stays off by default despite being resolved**. **Rejected:** turning reaction-torque coupling on by default  <sub>sdf-scene-campaign.md:56</sub>
- **Rebuild all three mphys host trees before diagnosing a coupling test failure**.  <sub>stale-build-mphys-trees.md:10</sub>
- **The CFD-DEM coupling force is the discrete reaction (route b), not the traction integral**. **Rejected:** hydro_force_torque (the traction integral) as the production coupling force  <sub>sdf-scene-campaign.md:18</sub>
- **The cross-module CUDA porous-CFD-DEM crash was an async stream race, not a GraphAMG bug**. **Rejected:** "NOT graphAMG (my initial guess was WRONG)"  <sub>multiphysics-framework-plan.md:382</sub>
- **USER DIRECTIVE: porous=True (volume-averaged NS) is the default for CFD-DEM**. **Rejected:** porous=False (plain incompressible NS with ε only in the drag closure) as the default  <sub>cfddem-porous-default-directive.md:10</sub>
- **Volume-averaged gas momentum must be epsilon-weighted with a matched projection pair**. **Rejected:** the old plain-u momentum path with epsilon only in drag/constraint/coefficients  <sub>porous-eps-conservative-momentum.md:10-31</sub>
- **porous=False is NOT "Model B" — terminology correction**. **Rejected:** calling porous=False "Model B"  <sub>porous-cfddem-cuda-two-bugs.md:22</sub>
- **porous=False is only a justified cheap approximation, never for published benchmark comparisons**. **Rejected:** using porous=False in published benchmark comparisons  <sub>cfddem-porous-default-directive.md:23</sub>

### Superseded — history, do not re-derive the old reading

- GraphAMG default restricted to !hasBc_ (domain-BC path defect).  <sub>porous-cfddem-cuda-two-bugs.md:13</sub>

## pnm — pore-network extraction

6 in force, 0 superseded — full text in [`decisions/pnm.md`](decisions/pnm.md)

### In force

- **Core/film throat tier criterion must be geometric (both cells fluid-centered), not an openness threshold**. **Rejected:** an openness-threshold criterion for the core/film tier  <sub>peclet-pnm-split.md:58-61</sub>
- **Distributed forest/label algorithm design lessons: pointer-jump must not store gid outside extended block; Jacobi double-buffer required, not in-place**. **Rejected:** storing a gid outside the extended block during pointer jumping; in-place flood fill on device  <sub>peclet-pnm-split.md:84-91</sub>
- **Network-flow extraction requires cutcell_pressure=True; fluxes must accumulate on flow basins, not seg-keyed**. **Rejected:** seg-keyed flux accumulation  <sub>peclet-pnm-split.md:31-34</sub>
- **Periodic-image decisions must never depend on float centroids — anchor on integer peak-voxel coordinates**. **Rejected:** float-centroid-based periodic-image decisions  <sub>peclet-pnm-split.md:74-78</sub>
- **Solid/pore renumbering must reduce min-appearance per label, not first-appearance gid**. **Rejected:** using first-appearance gid as the label  <sub>peclet-pnm-split.md:94-95</sub>
- **pnm becomes its own project (peclet.pnm); peclet.flow.pnm removed**. **Rejected:** keeping pore-network extraction inside flow as peclet.flow.pnm  <sub>peclet-pnm-split.md:11-16</sub>

## suite-wide — naming, layout, provisioning

27 in force, 1 superseded — full text in [`decisions/suite-wide.md`](decisions/suite-wide.md)

### In force

- **All coupled methods must share one BlockDecomposer; static-only co-decomposition is rejected**. **Rejected:** "Static-only co-decomposition"  <sub>multiphysics-framework-plan.md:410</sub>
- **CMake suite_require_nanobind must be a macro, not a function**. **Rejected:** implementing suite_require_nanobind as a CMake function  <sub>nanobind-zero-copy-migration.md:15</sub>
- **Collocated default is AUTO ghost projection (in both flow and AMR), with documented fallbacks**.  <sub>collocated-attractor-campaign.md:53</sub>
- **Convention going forward: never add cell-unit API surface; new setters take physical inputs**. **Rejected:** adding new cell-unit-only API surface  <sub>physical-units-plan.md:44</sub>
- **Cross-backend gate for "ported"**.  <sub>cuda-kokkos-migration.md:94</sub>
- **D1–D9: clean break at 1.0.0 — no aliases, two API tiers, no numerics-changing env vars, single version source, honest CI, AMR relocated**. **Rejected:** keeping compatibility aliases; letting env vars change numerics; multiple version sources; deleting AMR  <sub>suite-quality-plan-1-0-0.md:15-21</sub>
- **Design: keep index-native kernels, fold the metric into constants at the API boundary via reference scales**. **Rejected:** reworking the kernels themselves to be metric-aware (rejected in favor of index-native kernels + boundary conversion)  <sub>physical-units-plan.md:16</sub>
- **Device-resident class duals take a data-structure suffix "View", not a location word**. **Rejected:** a location-word suffix (e.g. "Device") for these class duals  <sub>peclet-v0.1-release.md:78</sub>
- **Do not change numerics while porting (faithful port principle)**. **Rejected:** changing scheme/numerics mid-port  <sub>cuda-kokkos-migration.md:304-307</sub>
- **Every peclet numerical method must run fully on-device and be MPI-distributable; host paths are oracles/tests only**. **Rejected:** host-orchestration bottlenecks — per-iteration host↔device downloads, host assembly, host linear solves  <sub>device-first-mpi-design-principle.md:10</sub>
- **Feature-completion option A: Kokkos takes canonical names only after full parity; no merge until then**. **Rejected:** other unnamed options (not detailed in note) — merging/renaming before parity was confirmed  <sub>cuda-kokkos-migration.md:290-292</sub>
- **Host serial paths are permitted only as oracles/unit tests, never as the production path**. **Rejected:** any host serial path as a production code path  <sub>device-first-mpi-design-principle.md:18</sub>
- **KEPT exceptions to the device-naming ban: transfer verbs and prose**.  <sub>peclet-v0.1-release.md:87</sub>
- **Kokkos device sources must be .cpp, not .cu**. **Rejected:** forcing LANGUAGE CUDA / .cu extension  <sub>cuda-kokkos-migration.md:109-112</sub>
- **Kokkos migration requires C++20**. **Rejected:** staying on C++17  <sub>cuda-kokkos-migration.md:104-105</sub>
- **Migration considered complete: user decision option c**. **Rejected:** other unnamed completion options  <sub>cuda-kokkos-migration.md:582-586</sub>
- **Naming convention: identifiers name what a thing is, never where it runs; "device"/"Kokkos" are banned qualifiers**. **Rejected:** identifiers naming a thing by its execution location (e.g. "Kokkos"/"Device" qualifiers)  <sub>peclet-v0.1-release.md:62</sub>
- **Naming convention: one short lowercase identity, drop "-gpu"**. **Rejected:** keeping the "-gpu" suffix; GitLab remotes  <sub>cuda-kokkos-migration.md:48-63</sub>
- **No `Device*`/`*Kokkos` class names for exposed kernels; host code is an unexposed oracle only**. **Rejected:** class names containing `Device*` or `*Kokkos`; exposing host-only kernel code to Python  <sub>device-naming-retirement.md:10-14</sub>
- **Provisioning via shared install prefix + find_package, not FetchContent**. **Rejected:** FetchContent  <sub>cuda-kokkos-migration.md:105-109</sub>
- **Suite-wide migration from pybind11 to nanobind + scikit-build-core, on a shared zero-copy bridge**. **Rejected:** pybind11 as the binding framework  <sub>nanobind-zero-copy-migration.md:11-13</sub>
- **USER DIRECTIVE: peclet must match/exceed SOTA massively-parallel-code performance in every component, including setup**. **Rejected:** judging performance only by the per-step solve/march, ignoring setup-path cost  <sub>performance-sota-yardstick.md:11-22</sub>
- **USER DIRECTIVE: peclet.flow is the reference for shared-method design elsewhere in the suite, not Basilisk or the literature**. **Rejected:** taking Basilisk (or a paper) as the reference for a shared method design; the Basilisk face-acceleration form for the collocated projection  <sub>flow-is-the-method-reference.md:8-19</sub>
- **USER DIRECTIVE: quality is the prime objective; next release is a clean-break 1.0.0, API-breaking allowed; AMR preserved not deleted**. **Rejected:** preserving backward compatibility / a minor version bump  <sub>suite-quality-plan-1-0-0.md:11-13</sub>
- **USER DIRECTIVE: solvers take a physical domain + physical properties; spatial discretization must not influence physical property values**.  <sub>physical-units-plan.md:11</sub>
- **morton stays on ctypes by design; vorflow's legacy host bindings stay on pybind11**. **Rejected:** migrating morton's bindings to nanobind; migrating vorflow's legacy host bindings to nanobind  <sub>nanobind-zero-copy-migration.md:17</sub>
- **nanobind Kokkos+CUDA modules require NOMINSIZE (nanobind's default -Os breaks nvcc)**. **Rejected:** nanobind's default -Os compile flag for Kokkos CUDA modules  <sub>nanobind-zero-copy-migration.md:24</sub>

### Superseded — history, do not re-derive the old reading

- atexit Kokkos::finalize is required on CUDA, not just optional as on OpenMP.  <sub>nanobind-zero-copy-migration.md:23-25</sub>
