"""Fixed-bed pressure drop vs Ergun — validates the two-way momentum feedback.

A random packing of FIXED point particles (invMass 0) fills a periodic box; the fluid is driven
through it by a uniform body force f_drive in z. The particles' drag reaction (deposited onto the
fluid momentum-source field) resists the flow, so the fluid reaches a finite superficial velocity U
where f_drive = the bed resistance. With the Ergun drag closure the summed reaction density equals
the Ergun pressure gradient by construction, so the measured (f_drive, U) pair must lie on the Ergun
curve:

    dP/L = 150 mu (1-eps)^2 / (eps^3 d^2) U  +  1.75 rho (1-eps) / (eps^3 d) U^2 .

This exercises the full loop end to end: volume deposition -> eps, drag, reaction feedback, periodic
fold, and the fluid solver balancing a uniform source — a sign/units/fold error would move the point
off the curve. eps is MEASURED from the deposited field (isolating the coupling from packing
statistics). Atomic deposition => tolerance-based (not bit-exact).
"""
import numpy as np
import peclet.flow, peclet.dem
from peclet.coupling import CfdDem


def ergun(U, eps, mu, rho, d):
    om = 1.0 - eps
    return (150.0 * mu * om * om / (eps ** 3 * d * d) * U
            + 1.75 * rho * om / (eps ** 3 * d) * U * U)


def run_bed(f_drive, eps_target=0.6, N=16, mu=1.0, rho=1.0, dt=0.5, steps=120):
    # Uniform bed: one FIXED particle at each cell centre with volume V_p = (1-eps)*Vcell, so the
    # trilinear deposit gives a uniform void fraction eps_target with NO clamping (a random packing
    # clumps -> cells hit the eps floor -> the deposited eps stops matching the number density the
    # drag closure assumes). Cell size h=1 => Vcell=1.
    Vp = (1.0 - eps_target)  # Vcell = 1
    r = (Vp * 3.0 / (4.0 * np.pi)) ** (1.0 / 3.0)
    xs = np.arange(N) + 0.5
    X, Y, Z = np.meshgrid(xs, xs, xs, indexing="ij")
    pos = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1).astype(np.float32)
    Np = pos.shape[0]
    posw = np.concatenate([pos, np.zeros((Np, 1), dtype=np.float32)], axis=1)  # w=invMass=0 -> fixed

    s = peclet.flow.Solver(N, N, N)
    s.set_rho(rho); s.set_mu(mu); s.set_dt(dt)
    s.set_body_force(0.0, 0.0, f_drive)
    s.set_pressure_geometry(np.asfortranarray(np.full((N, N, N), 10.0)))
    d = peclet.dem.Simulation(Np)
    d.initialize(shape_type=1, radius=r)
    d.set_domain((0, 0, 0), (N, N, N))
    d.enable_periodicity(True, True, True)
    d.set_positions(posw)
    d.set_velocities(np.zeros((Np, 3), dtype=np.float32))
    cpl = CfdDem(s, d, fluid_dt=dt, mu=mu, rho=rho, radius=r, drag="ergun", eps_min=0.05,
                 move_particles=False)  # fixed bed: no DEM dynamics
    for _ in range(steps):
        cpl.step()
    U = s.get_w().mean()  # superficial velocity (mean over the box)
    eps_mean = float(cpl.last_eps[cpl.g:cpl.g + N, cpl.g:cpl.g + N, cpl.g:cpl.g + N].mean())
    return U, eps_mean, ergun(U, eps_mean, mu, rho, 2 * r)


if __name__ == "__main__":
    print("f_drive     U         eps    Ergun(U,eps)  rel-err")
    ok = True
    for f_drive in (0.2, 20.0, 1000.0):
        U, eps, dP = run_bed(f_drive)
        err = abs(dP - f_drive) / f_drive
        r = ((1 - 0.6) * 3 / (4 * np.pi)) ** (1 / 3)
        Re = 2 * r * abs(U) / 1.0
        print(f"{f_drive:8.2f}  {U:.4e}  {eps:.3f}  {dP:.4e}   {err*100:5.1f}%  (Re_p~{Re:.2f})")
        ok = ok and err < 0.10
    assert ok, "fixed-bed drag does not reproduce Ergun within 10%"
    print("PHASE 6 FIXED-BED ERGUN: PASS")
