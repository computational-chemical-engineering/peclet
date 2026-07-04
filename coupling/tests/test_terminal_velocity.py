"""Single-particle terminal velocity — validates the drag law + G2P interpolation.

A sphere settles under gravity through (nearly) quiescent fluid in a large periodic box. At terminal
velocity the drag balances gravity. No buoyancy is modelled (neither the drag law nor the DEM gravity
subtract the displaced-fluid weight), so the reference is the no-buoyancy Stokes value

    v_t = (2/9) (rho_p / mu) r^2 g       (Re -> 0)

and, at finite Re, the Schiller-Naumann root of 6 pi mu r (1 + 0.15 Re^0.687) v_t = m_p g.
The slip velocity |u_fluid - v_particle| is what the drag sees; a large box keeps the fluid drift
small so the particle speed ~ the slip.
"""
import numpy as np
import peclet.flow, peclet.dem
from peclet.coupling import CfdDem


def terminal(drag, g=1e-3, r=1.0, mu=1.0, rho_p=1.0, rho_f=1.0, N=32, steps=120):
    m_p = rho_p * (4.0 / 3.0) * np.pi * r ** 3
    s = peclet.flow.Solver(N, N, N)
    s.set_rho(rho_f); s.set_mu(mu); s.set_dt(0.1)
    s.set_pressure_geometry(np.asfortranarray(np.full((N, N, N), 10.0)))
    d = peclet.dem.Simulation(1)
    d.initialize(shape_type=1, radius=r)
    d.set_domain((0, 0, 0), (N, N, N))
    d.enable_periodicity(True, True, True)
    d.set_gravity(0, 0, -g)  # acceleration
    d.set_positions(np.array([[N / 2, N / 2, N / 2, 1.0 / m_p]], dtype=np.float32))  # w = invMass
    d.set_velocities(np.zeros((1, 3), dtype=np.float32))
    cpl = CfdDem(s, d, fluid_dt=0.1, mu=mu, rho=rho_f, radius=r, drag=drag, dem_substeps=10)
    slip_hist = []
    for _ in range(steps):
        cpl.step()
        vel = d.get_velocities()
        slip_hist.append(abs(cpl.slip(None, vel)[0, 2]))  # |u_fluid - v_p| at the particle
    # the drag law sees the SLIP velocity (the particle drags its own local fluid ~a Stokeslet, so
    # the lab-frame speed ~ 2x the slip; the slip is the physical terminal quantity).
    slip = slip_hist[-1]
    fmag = np.linalg.norm(cpl.last_drag[0])
    uf_max = max(abs(s.get_u()).max(), abs(s.get_v()).max(), abs(s.get_w()).max())
    return slip, fmag, uf_max, m_p


def stokes_ref(g, r, mu, rho_p):
    return (2.0 / 9.0) * (rho_p / mu) * r ** 2 * g


def schiller_ref(g, r, mu, rho_p, rho_f):
    m_p = rho_p * (4.0 / 3.0) * np.pi * r ** 3
    v = stokes_ref(g, r, mu, rho_p)
    for _ in range(100):  # fixed-point: 6 pi mu r (1+0.15 Re^0.687) v = m_p g
        Re = rho_f * 2 * r * v / mu
        v = m_p * g / (6 * np.pi * mu * r * (1 + 0.15 * Re ** 0.687))
    return v, rho_f * 2 * r * v / mu


if __name__ == "__main__":
    # Stokes: deep Stokes regime, expect < 1% (v_t and the drag balance are both linear here)
    vt = stokes_ref(1e-3, 1.0, 1.0, 1.0)
    slip, fmag, ufm, m_p = terminal("stokes", g=1e-3)
    err = abs(slip - vt) / vt
    print(f"[Stokes]  slip={slip:.6e} ref={vt:.6e} err={err*100:.2f}%  drag={fmag:.3e} "
          f"(m_p*g={m_p*1e-3:.3e})  fluid|u|max={ufm:.2e}")
    assert err < 0.01, f"Stokes terminal slip off by {err*100:.2f}%"

    # Schiller-Naumann at moderate Re (bigger g -> Re ~ O(10))
    vref, Reref = schiller_ref(0.3, 1.0, 1.0, 5.0, 1.0)
    slip2, fmag2, ufm2, _ = terminal("schiller_naumann", g=0.3, rho_p=5.0, steps=200)
    err2 = abs(slip2 - vref) / vref
    print(f"[Schiller] slip={slip2:.4f} ref={vref:.4f} (Re~{Reref:.1f}) err={err2*100:.2f}%  "
          f"fluid|u|max={ufm2:.2e}")
    assert err2 < 0.05, f"Schiller-Naumann terminal slip off by {err2*100:.2f}%"
    print("PHASE 6 TERMINAL VELOCITY: PASS")
