#!/usr/bin/env python3
"""Weak-scaling MPI communication-overhead benchmark for the distributed staggered-MAC CFD.

Idea
----
Each rank/GPU simulates an **identical** periodic sphere-packing tile of ``L^3`` cells. The tiles are
**glued periodically** into one global domain (global grid = ``L * (px, py, pz)`` for a ``px*py*pz = np``
rank grid), so the geometry is seamless and **every rank does exactly the same work**. Per-rank work is
therefore constant as ``np`` grows, so the change in per-step wall-time isolates:

  * the **MPI halo-exchange** overhead (the velocity ghost layer every step), and
  * any **non-O(N) growth in the global pressure solve** (the MG-PCG Poisson couples all ranks — if it
    is not weak-scalable its iteration count / all-reduce cost climbs with np).

Ideal weak scaling ⇒ per-step time is *flat* vs np; the rise you measure is the communication (and
solver) tax. The **packing geometry is generated once and is NOT part of the timing.**

Run
---
  # local (CPU / OpenMP build), sweep np and compare the per-step time:
  for n in 1 2 4; do mpirun -np $n python benchmarks/profile_mpi_flow.py --L 48 --steps 100 --csv out.csv; done

  # on a cluster, launch through the site bind-wrapper (see containers/), e.g. Snellius:
  srun containers/snellius-run.sh peclet-cuda_0.1.0-sm80.sif benchmarks/profile_mpi_flow.py --L 96 --steps 200

Requires a peclet.flow built with PECLET_FLOW_MPI=ON (``flow.has_mpi``) and mpi4py.
"""
from __future__ import annotations

import argparse
import os

import numpy as np
from mpi4py import MPI

import peclet.flow as flow


# --------------------------------------------------------------------------------------------------
def factorize3(n: int) -> tuple[int, int, int]:
    """Balanced (px,py,pz) with px*py*pz == n, as close to cubic as possible (prefers 2s)."""
    best = (n, 1, 1)
    for px in range(1, int(round(n ** (1 / 3))) + 2):
        if n % px:
            continue
        m = n // px
        for py in range(px, int(round(m ** 0.5)) + 2):
            if m % py:
                continue
            pz = m // py
            trip = tuple(sorted((px, py, pz)))
            if max(trip) - min(trip) < max(best) - min(best):
                best = trip
    return best


def periodic_packing_tile(L: int, phi: float, seed: int) -> np.ndarray:
    """A random periodic sphere packing as an (L,L,L) float64 SDF (negative inside solid).

    Rejection-places non-overlapping spheres in a unit-cell of L grid-cells to ~phi solid fraction, then
    evaluates the periodic signed distance to the sphere surfaces. Periodic in every axis (period L), so
    it tiles seamlessly. Deterministic in ``seed`` (identical on every rank). Not timed.
    """
    rng = np.random.default_rng(seed)
    R = 0.11 * L                       # sphere radius in grid cells
    vsph = (4.0 / 3.0) * np.pi * R ** 3
    ntarget = max(1, int(phi * L ** 3 / vsph))
    centers: list[np.ndarray] = []
    attempts = 0
    while len(centers) < ntarget and attempts < 200 * ntarget:
        attempts += 1
        c = rng.uniform(0, L, 3)
        ok = True
        for c2 in centers:                       # periodic min-image non-overlap (gap = 2R)
            d = c - c2
            d -= L * np.round(d / L)
            if np.dot(d, d) < (2.0 * R) ** 2:
                ok = False
                break
        if ok:
            centers.append(c)
    xs = np.arange(L)
    X, Y, Z = np.meshgrid(xs, xs, xs, indexing="ij")
    best = np.full((L, L, L), 1e30)
    for c in centers:
        dx = X - c[0]; dx -= L * np.round(dx / L)
        dy = Y - c[1]; dy -= L * np.round(dy / L)
        dz = Z - c[2]; dz -= L * np.round(dz / L)
        best = np.minimum(best, np.sqrt(dx * dx + dy * dy + dz * dz) - R)
    return best, len(centers)


def configure(s: "flow.Solver", mu: float, dt: float, fx: float) -> None:
    s.set_rho(1.0)
    s.set_mu(mu)
    s.set_dt(dt)
    s.set_body_force(fx, 0.0, 0.0)
    s.set_advection(False)                       # Stokes: the pressure solve is the cost we profile
    s.set_velocity_solver_params(80)
    s.set_pressure_multigrid(True, 4)
    s.set_pressure_pcg(True, 200, 1e-9)


# --------------------------------------------------------------------------------------------------
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--L", type=int, default=48, help="per-rank grid cells per axis (constant work/rank)")
    ap.add_argument("--steps", type=int, default=100, help="timed CFD steps")
    ap.add_argument("--warmup", type=int, default=10, help="untimed warmup steps")
    ap.add_argument("--phi", type=float, default=0.30, help="target solid fraction of the packing")
    ap.add_argument("--mu", type=float, default=0.1)
    ap.add_argument("--dt", type=float, default=60.0)
    ap.add_argument("--fx", type=float, default=1e-3, help="body force driving the flow")
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--csv", type=str, default="", help="append one result row to this CSV")
    args = ap.parse_args()

    comm = MPI.COMM_WORLD
    rank, size = comm.Get_rank(), comm.Get_size()

    if not getattr(flow, "has_mpi", False):
        if rank == 0:
            raise SystemExit("peclet.flow was built without PECLET_FLOW_MPI — rebuild with -DPECLET_FLOW_MPI=ON")
        return

    L = args.L
    px, py, pz = factorize3(size)
    gnx, gny, gnz = L * px, L * py, L * pz

    # --- geometry (NOT timed): identical periodic tile on every rank -----------------------------
    tile, nsph = periodic_packing_tile(L, args.phi, args.seed)

    # this rank's ORB block of the global grid; fill it from the periodic tile (seamless glue)
    (ox, oy, oz), (lnx, lny, lnz) = flow.mpi_block(gnx, gny, gnz)
    ax = (np.arange(lnx) + ox) % L
    ay = (np.arange(lny) + oy) % L
    az = (np.arange(lnz) + oz) % L
    lsdf = np.asfortranarray(tile[np.ix_(ax, ay, az)].astype(np.float64))

    s = flow.Solver(lnx, lny, lnz)
    s.init_mpi(gnx, gny, gnz)
    configure(s, args.mu, args.dt, args.fx)
    s.set_solid(lsdf, cutcell_pressure=True)

    # --- warmup (NOT timed) ----------------------------------------------------------------------
    for _ in range(args.warmup):
        s.step()

    # --- timed loop (barrier-bracketed; report the slowest rank) ---------------------------------
    comm.Barrier()
    t0 = MPI.Wtime()
    for _ in range(args.steps):
        s.step()
    comm.Barrier()
    per_step = (MPI.Wtime() - t0) / args.steps

    piters = s.last_pressure_iterations()
    tmax = comm.reduce(per_step, op=MPI.MAX, root=0)
    tmin = comm.reduce(per_step, op=MPI.MIN, root=0)
    cells = lnx * lny * lnz

    if rank == 0:
        space = flow.execution_space
        print(f"[{space}] np={size:<3d} grid={px}x{py}x{pz}  global={gnx}x{gny}x{gnz}  "
              f"per-rank={lnx}x{lny}x{lnz}={cells} cells  (~{nsph} spheres/tile)")
        print(f"    per-step: max {tmax*1e3:8.3f} ms  min {tmin*1e3:8.3f} ms  imbalance {100*(tmax-tmin)/tmax:4.1f}%"
              f"   pressure_iters={piters}   {cells/tmax/1e6:.2f} Mcell/s/rank")
        if args.csv:
            new = not os.path.exists(args.csv)
            with open(args.csv, "a") as fh:
                if new:
                    fh.write("backend,np,px,py,pz,L,cells_per_rank,steps,per_step_ms_max,per_step_ms_min,pressure_iters\n")
                fh.write(f"{space},{size},{px},{py},{pz},{L},{cells},{args.steps},"
                         f"{tmax*1e3:.4f},{tmin*1e3:.4f},{piters}\n")


if __name__ == "__main__":
    main()
