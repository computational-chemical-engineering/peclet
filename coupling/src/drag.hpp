/// @file
/// @brief coupling — device-inline fluid drag laws for unresolved point-particle CFD-DEM.
///
/// Each returns the drag FORCE on a particle given the slip velocity vrel = u_fluid - u_particle,
/// the particle radius r, the fluid viscosity mu and density rhof, and the local void fraction eps.
/// All arithmetic in double. Selected by an int `kind` so a single kernel dispatches at runtime.
///
/// Force -> per-unit-volume bookkeeping (how the Ergun/Wen-Yu forms reproduce the packed-bed drop):
/// the interphase momentum-exchange coefficient beta gives a force DENSITY beta*vrel; with number
/// density n = (1-eps)/V_p particles per unit volume (V_p = 4/3 pi r^3), the force per particle is
/// F_p = beta*vrel/n = beta*V_p/(1-eps)*vrel. Substituting the Ergun beta
/// (150(1-eps)^2 mu/(eps^3 d^2) + 1.75(1-eps)rhof|vrel|/(eps^3 d)) makes the summed reaction density
/// equal -dP/dx = Ergun, so a fixed bed driven by a body force settles to the Ergun superficial
/// velocity by construction (validated in tests/test_fixed_bed_ergun.py).
#ifndef PECLET_COUPLING_DRAG_HPP
#define PECLET_COUPLING_DRAG_HPP

#include <Kokkos_Core.hpp>

namespace peclet::coupling {

enum DragKind { STOKES = 0, SCHILLER_NAUMANN = 1, ERGUN = 2, DI_FELICE = 3 };

// vrel = u_fluid - u_particle (3 components in/out). Returns F = drag force ON the particle.
KOKKOS_INLINE_FUNCTION void dragForce(int kind, double vx, double vy, double vz, double r, double mu,
                                      double rhof, double eps, double& fx, double& fy, double& fz) {
  const double d = 2.0 * r;
  const double vmag = Kokkos::sqrt(vx * vx + vy * vy + vz * vz);
  const double Vp = (4.0 / 3.0) * M_PI * r * r * r;
  double beta_over_n;  // coefficient c s.t. F = c * vrel

  if (kind == STOKES) {
    beta_over_n = 6.0 * M_PI * mu * r;  // 3 pi mu d
  } else if (kind == SCHILLER_NAUMANN) {
    const double Re = rhof * d * vmag / mu;
    const double corr = (Re > 1e-9) ? (1.0 + 0.15 * Kokkos::pow(Re, 0.687)) : 1.0;
    beta_over_n = 6.0 * M_PI * mu * r * corr;
  } else if (kind == DI_FELICE) {
    // single-particle (Schiller-Naumann) drag scaled by the Di Felice voidage function eps^-chi
    const double Re = rhof * d * vmag / mu;
    const double corr = (Re > 1e-9) ? (1.0 + 0.15 * Kokkos::pow(Re, 0.687)) : 1.0;
    const double lRe = Kokkos::log10(Re > 1e-9 ? Re : 1e-9);
    const double chi = 3.7 - 0.65 * Kokkos::exp(-0.5 * (1.5 - lRe) * (1.5 - lRe));
    beta_over_n = 6.0 * M_PI * mu * r * corr * Kokkos::pow(eps, -(chi - 1.0));
  } else {  // ERGUN (packed bed): beta*V_p/(1-eps) with the Ergun interphase coefficient
    const double om = 1.0 - eps;         // solid fraction
    const double e3 = eps * eps * eps;   // eps^3
    const double beta = 150.0 * om * om * mu / (e3 * d * d) + 1.75 * om * rhof * vmag / (e3 * d);
    beta_over_n = beta * Vp / (om > 1e-9 ? om : 1e-9);
  }
  fx = beta_over_n * vx;
  fy = beta_over_n * vy;
  fz = beta_over_n * vz;
}

}  // namespace peclet::coupling

#endif  // PECLET_COUPLING_DRAG_HPP
