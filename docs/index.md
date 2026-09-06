# Peclet

[![PyPI version](https://img.shields.io/pypi/v/peclet.svg)](https://pypi.org/project/peclet/)
[![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)](https://pypi.org/project/peclet/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/computational-chemical-engineering/peclet/blob/main/LICENSE)
[![Docs build](https://github.com/computational-chemical-engineering/peclet/actions/workflows/site.yml/badge.svg)](https://github.com/computational-chemical-engineering/peclet/actions/workflows/site.yml)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21132445.svg)](https://doi.org/10.5281/zenodo.21132445)

**A suite of GPU-accelerated and parallel codes for the simulation of transport phenomena** —
Eulerian (CFD / Navier–Stokes, single- and two-phase), Lagrangian (DEM / granular dynamics), mixed
(Voronoi) and coupled (CFD-DEM) methods, sharing one MPI **block domain decomposition** with
asynchronous **ghost-layer exchange**, **SDF**-described solids, a common **immersed-boundary**
methodology, **GPU** support (Kokkos: CUDA / HIP / OpenMP), and **Python bindings** everywhere.

The name nods to the [Péclet number](https://en.wikipedia.org/wiki/P%C3%A9clet_number) — the ratio of
advective to diffusive transport, the dimensionless heart of transport phenomena.

## Quick start (Python)

The codes are driven from **Python** — one `peclet.*` namespace, installable from PyPI. The multicore-CPU
(OpenMP) build ships as self-contained wheels, and so does the single-GPU CUDA build:

```bash
pip install peclet          # CPU family: peclet-morton + peclet-flow + peclet-pnm + peclet-dem + peclet-voro
pip install peclet-cu13     # the same family as CUDA wheels (NVIDIA driver only; not alongside `peclet`)
pip install peclet-flow     # or any single package
```

Stokes flow past a sphere in a box of side `L`, start to finish (about half a minute on two cores). The
physical problem is stated in your own units and `N` sets the resolution, so a grid-refinement study is one
number away. Run it as is, or open the same steps as a notebook in Colab — the first cell installs the wheels:

[![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/computational-chemical-engineering/peclet/blob/main/docs/notebooks/quickstart_sphere.ipynb)

```python
import numpy as np
import peclet.flow as flow

# --- the physical problem, in any consistent unit system -------------------------------------
L, R = 1.0, 0.2              # side of the periodic box and radius of the sphere at its centre
rho, mu = 1.0, 0.1           # fluid density and viscosity
F = 1.0                      # driving pressure gradient along x (force per unit volume)
N = 48                       # cells per side: change this for a grid-refinement study

# --- the grid: the solver works in CELL units, so every length is divided by h = L / N --------
h = L / N
x = (np.arange(N) + 0.5) * h                                   # cell-centre coordinates
X, Y, Z = np.meshgrid(x, x, x, indexing="ij")
sdf = (np.sqrt((X - L/2)**2 + (Y - L/2)**2 + (Z - L/2)**2) - R) / h   # signed distance in cells, < 0 in the solid

s = flow.Solver(N, N, N)                                       # a periodic box: a cubic lattice of spheres
s.set_rho(rho); s.set_mu(mu / h**2); s.set_dt(1e3)             # mu and F rescaled to cell units; a large dt
s.set_body_force(F / h, 0.0, 0.0)                              #   marches straight to the steady Stokes flow
s.set_solid(sdf, cutcell_pressure=True)                        # no-slip cut-cell immersed boundary
u_prev = 0.0
for it in range(200):
    s.step()
    u_mean = s.get_u().mean()
    if it > 5 and abs(u_mean - u_prev) < 1e-5 * abs(u_mean):   # steady: the mean velocity has settled
        break
    u_prev = u_mean
u, v, w = s.get_u() * h, s.get_v() * h, s.get_w() * h          # back to physical velocity
p = s.get_p() * h**2                                           # and pressure
k = mu * u.mean() / F                                          # Darcy permeability of the sphere lattice
print(f"{flow.execution_space}: N = {N}, h = {h:.4f}, {it + 1} steps, permeability k = {k:.5e}")

# --- a look at the flow: speed and streamlines on the mid-plane through the sphere ---------------
import matplotlib.pyplot as plt
c = N // 2
speed = np.hypot(u[:, :, c], v[:, :, c])
plt.figure(figsize=(5, 4.2))
plt.imshow(np.ma.masked_where(sdf[:, :, c] < 0, speed).T, origin="lower", cmap="viridis",
           extent=[0, L, 0, L])
plt.streamplot(x, x, u[:, :, c].T, v[:, :, c].T, color="w", density=1.2, linewidth=0.6)
plt.colorbar(label="|u|"); plt.title("Stokes flow past a sphere (periodic box)")
plt.xlabel("x"); plt.ylabel("y"); plt.tight_layout()
plt.show()
```

<img src="img/quickstart_sphere.png" width="420" alt="Stokes flow past a sphere: speed and streamlines on the mid-plane">


→ **[Examples gallery](https://computational-chemical-engineering.github.io/peclet-examples/)** (runnable,
validated notebooks) · **[Python API reference](python/index.md)** · **[Install & run](DEPLOYMENT.md)**
(GPU / MPI / HPC containers).

## The codes

| Code | PyPI · import | Role |
|------|---------------|------|
| [**core**](https://github.com/computational-chemical-engineering/peclet-core) | `peclet-core` · `peclet.core` | Shared infrastructure: ORB block decomposition, async grid/particle halo, analytic + sampled SDF geometry (`core.geom` scenes), VTI I/O, AMR octree |
| [**flow**](https://github.com/computational-chemical-engineering/peclet-flow) | `peclet-flow` · `peclet.flow` | Incompressible Navier–Stokes for porous media (staggered MAC or collocated grid, cut-cell IBM, multigrid), geometric VoF two-phase flow, moving analytic geometry |
| [**pnm**](https://github.com/computational-chemical-engineering/peclet-pnm) | `peclet-pnm` · `peclet.pnm` | Pore-network extraction from SDF geometry (pores, watershed segmentation, throat topology) and network flow data from a `flow` DNS |
| [**dem**](https://github.com/computational-chemical-engineering/peclet-dem) | `peclet-dem` · `peclet.dem` | Discrete Element Method (XPBD and Hertz–Mindlin) with SDF point-shell collision for spheres and arbitrary SDF shapes |
| [**voro**](https://github.com/computational-chemical-engineering/peclet-voro) | `peclet-voro` · `peclet.voro` | Dynamic 3D Voronoi tessellation of moving particles (periodic & Lees–Edwards), mesh generation, Navier–Stokes on a Voronoi mesh |
| [**coupling**](https://github.com/computational-chemical-engineering/peclet-coupling) | `peclet-coupling` · `peclet.coupling` | CFD-DEM: unresolved (volume-averaged drag) and resolved (cut-cell) two-way coupling of `flow` and `dem` |
| [**morton**](https://github.com/computational-chemical-engineering/peclet-morton) | `peclet-morton` · `peclet.morton` | Morton/Z-order codes with arithmetic *in Morton space* — the spatial-index primitive |

The GPU codes are **Kokkos**-based: the same source runs on CUDA, HIP (AMD/LUMI) and OpenMP, chosen at
build time by the install prefix, the wheel flavour (`peclet` vs `peclet-cu13`) or the container.

## Examples gallery

**[computational-chemical-engineering.github.io/peclet-examples](https://computational-chemical-engineering.github.io/peclet-examples/)**
is the worked-examples site: every page is a notebook executed against the released package, with an
*Open in Colab* button and the validation numbers in the open —

- **Single-phase flow** — exact and canonical benchmarks (Poiseuille, Taylor–Green, lid-driven cavity,
  Schäfer–Turek cylinder, Rayleigh–Bénard, turbulent channel DNS) and moving-body drag / torque cases.
- **Packings & porous media** — Zick–Homsy sphere arrays, random and ring packed beds (dem → flow),
  pore-space Voronoi meshes, pore-network extraction.
- **Two-phase flow (VoF)** — advection benchmarks, parasitic currents, capillary waves, rising bubble,
  wetting, bubbles and trickle flow through packings.
- **Granular (DEM)** — SDF-shaped particles, rotating drum, tumbling cubes, Pall rings, stirred column.
- **CFD-DEM** — fluidized bed, bubble injection, segregation, homogeneous cooling (MFIX-Exa comparisons).
- **Benchmarks** — the multi-GPU and CPU scaling studies (Snellius) and a DEM bulk-flow benchmark.

## Documentation

- **[Examples gallery](https://computational-chemical-engineering.github.io/peclet-examples/)** — start here if you want to *use* the suite.
- **[Python API reference](python/index.md)** — the classes and methods you call from Python (the primary interface).
- **[Install & run](DEPLOYMENT.md)** — the backend × MPI matrix, `pip install` recipes (CPU wheels, CUDA wheels, source builds) and the HPC routes.
- **[Containers (HPC)](containers.md)** — pull the pre-built Apptainer images from GHCR (or build your own) and run on a laptop, Snellius, or LUMI.
- **[Snellius](SNELLIUS.md)** · **[LUMI](LUMI.md)** — the site runbooks.
- **[Architecture](ARCHITECTURE.md)** · **[Conventions](CONVENTIONS.md)** · **[Interfaces](INTERFACES.md)** · **[Roadmap](ROADMAP.md)** — the cross-cutting design contract.
- **C++ API (Doxygen)** — the full C++ API per code:
  [core](https://computational-chemical-engineering.github.io/peclet-core/) ·
  [morton](https://computational-chemical-engineering.github.io/peclet-morton/) ·
  [flow](https://computational-chemical-engineering.github.io/peclet-flow/) ·
  [pnm](https://computational-chemical-engineering.github.io/peclet-pnm/) ·
  [dem](https://computational-chemical-engineering.github.io/peclet-dem/) ·
  [voro](https://computational-chemical-engineering.github.io/peclet-voro/)
- **[Changelog](https://github.com/computational-chemical-engineering/peclet/blob/main/CHANGELOG.md)** — what each family release contains; the PyPI badge above shows the current version.

## Citing

If you use Peclet in your research, please cite it. Each release is archived on Zenodo:

- **Concept DOI (all versions):** [10.5281/zenodo.21132445](https://doi.org/10.5281/zenodo.21132445) —
  always resolves to the latest release; use this unless you need to pin an exact version.
- **A specific version:** the Zenodo record above lists a version DOI for every release, and each
  [GitHub release](https://github.com/computational-chemical-engineering/peclet/releases) links to its own.

Machine-readable metadata lives in [`CITATION.cff`](https://github.com/computational-chemical-engineering/peclet/blob/main/CITATION.cff)
— use GitHub's "Cite this repository" button for ready-made BibTeX/APA.
