/// @file
/// @brief coupling — CFD-DEM exchange kernels: void-fraction deposition + fused drag/feedback.
///
/// Built on core's trilinear particle<->grid primitive (interp/particle_grid.hpp) and the drag laws
/// (drag.hpp). Two device operations per fluid step:
///   1. depositSolidVolume + voidFraction: scatter each particle's volume to the grid -> eps.
///   2. computeDragFeedback (fused): gather the fluid velocity + eps at each particle, evaluate the
///      drag law, write the drag FORCE to the particle array (-> dem extForce), and scatter the
///      equal-opposite reaction as a force DENSITY (-F/Vcell) onto the fluid momentum-source fields
///      (-> flow cellForce). Momentum is conserved: sum_particles F == -sum_cells feedback*Vcell.
/// Atomics make the deposits order-dependent (tolerance-, not bit-exact).
#ifndef PECLET_COUPLING_COUPLING_KERNELS_HPP
#define PECLET_COUPLING_COUPLING_KERNELS_HPP

#include <Kokkos_Core.hpp>

#include "drag.hpp"
#include "peclet/core/interp/particle_grid.hpp"

namespace peclet::coupling {

using peclet::core::interp::GridMap;

// Trilinear gather of one flat cell-centred field at a precomputed stencil (device helper).
template <class FieldV>
KOKKOS_INLINE_FUNCTION double gatherAt(const FieldV& f, long b, long sx, long sy, long sz, double wx,
                                       double wy, double wz) {
  auto F = [&](long o) { return (double)f(b + o); };
  const double c00 = F(0) * (1 - wx) + F(sx) * wx;
  const double c10 = F(sy) * (1 - wx) + F(sy + sx) * wx;
  const double c01 = F(sz) * (1 - wx) + F(sz + sx) * wx;
  const double c11 = F(sz + sy) * (1 - wx) + F(sz + sy + sx) * wx;
  return (c00 * (1 - wy) + c10 * wy) * (1 - wz) + (c01 * (1 - wy) + c11 * wy) * wz;
}

// Scatter q onto the 8 stencil cells with the trilinear weights (atomic).
template <class FieldV>
KOKKOS_INLINE_FUNCTION void scatterAt(const FieldV& f, long b, long sx, long sy, long sz, double wx,
                                      double wy, double wz, double q) {
  using T = typename FieldV::value_type;
  const double w[2] = {1.0 - wx, wx}, wj[2] = {1.0 - wy, wy}, wk[2] = {1.0 - wz, wz};
  for (int dk = 0; dk < 2; ++dk)
    for (int dj = 0; dj < 2; ++dj)
      for (int di = 0; di < 2; ++di)
        Kokkos::atomic_add(&f(b + di * sx + dj * sy + dk * sz),
                           (T)(q * w[di] * wj[dj] * wk[dk]));
}

// Scatter each particle's volume (4/3 pi r^3) onto `solidvol` (pre-zeroed). Trilinear -> conserves
// the total solid volume.
template <class PosV, class RadV, class FieldV>
void depositSolidVolume(int np, PosV pos, RadV rad, FieldV solidvol, GridMap m) {
  using Exec = Kokkos::DefaultExecutionSpace;
  const int nx = m.ex - 2 * m.g, ny = m.ey - 2 * m.g, nz = m.ez - 2 * m.g;
  Kokkos::parallel_for(
      "peclet::coupling::deposit_vol", Kokkos::RangePolicy<Exec>(0, np), KOKKOS_LAMBDA(int p) {
        int i0, j0, k0;
        double wx, wy, wz;
        peclet::core::interp::detail::axisStencil((double)pos(p, 0), m.ox, m.idx, nx, i0, wx);
        peclet::core::interp::detail::axisStencil((double)pos(p, 1), m.oy, m.idy, ny, j0, wy);
        peclet::core::interp::detail::axisStencil((double)pos(p, 2), m.oz, m.idz, nz, k0, wz);
        const long sx = 1, sy = m.ex, sz = (long)m.ex * m.ey;
        const long b = (long)(i0 + m.g) + (long)(j0 + m.g) * sy + (long)(k0 + m.g) * sz;
        const double r = (double)rad(p);
        scatterAt(solidvol, b, sx, sy, sz, wx, wy, wz, (4.0 / 3.0) * M_PI * r * r * r);
      });
}

// eps = clamp(1 - solidvol/Vcell, epsMin, 1) over the whole (padded) field.
template <class FieldV>
void voidFraction(FieldV solidvol, FieldV eps, double invVcell, double epsMin) {
  using Exec = Kokkos::DefaultExecutionSpace;
  Kokkos::parallel_for(
      "peclet::coupling::void_fraction", Kokkos::RangePolicy<Exec>(0, (long)eps.extent(0)),
      KOKKOS_LAMBDA(long i) {
        double e = 1.0 - (double)solidvol(i) * invVcell;
        if (e < epsMin)
          e = epsMin;
        if (e > 1.0)
          e = 1.0;
        eps(i) = (typename FieldV::value_type)e;
      });
}

// Fused drag + feedback. Gathers (uf,vf,wf,eps) at each particle, evaluates the drag law, writes the
// drag force to fdrag(p,:) (dem external force), and scatters the reaction -F*invVcell onto the
// (pre-zeroed) grid force-density fields fx,fy,fz. rho/mu physical; dragKind per drag.hpp.
template <class PosV, class VelV, class RadV, class FieldV, class OutV>
void computeDragFeedback(int np, PosV pos, VelV vel, RadV rad, FieldV uf, FieldV vf, FieldV wf,
                         FieldV eps, OutV fdrag, FieldV fx, FieldV fy, FieldV fz, GridMap m,
                         double mu, double rhof, double invVcell, int dragKind) {
  using Exec = Kokkos::DefaultExecutionSpace;
  const int nx = m.ex - 2 * m.g, ny = m.ey - 2 * m.g, nz = m.ez - 2 * m.g;
  Kokkos::parallel_for(
      "peclet::coupling::drag_feedback", Kokkos::RangePolicy<Exec>(0, np), KOKKOS_LAMBDA(int p) {
        int i0, j0, k0;
        double wx, wy, wz;
        peclet::core::interp::detail::axisStencil((double)pos(p, 0), m.ox, m.idx, nx, i0, wx);
        peclet::core::interp::detail::axisStencil((double)pos(p, 1), m.oy, m.idy, ny, j0, wy);
        peclet::core::interp::detail::axisStencil((double)pos(p, 2), m.oz, m.idz, nz, k0, wz);
        const long sx = 1, sy = m.ex, sz = (long)m.ex * m.ey;
        const long b = (long)(i0 + m.g) + (long)(j0 + m.g) * sy + (long)(k0 + m.g) * sz;
        const double uF = gatherAt(uf, b, sx, sy, sz, wx, wy, wz);
        const double vF = gatherAt(vf, b, sx, sy, sz, wx, wy, wz);
        const double wF = gatherAt(wf, b, sx, sy, sz, wx, wy, wz);
        const double eP = gatherAt(eps, b, sx, sy, sz, wx, wy, wz);
        const double vrx = uF - (double)vel(p, 0), vry = vF - (double)vel(p, 1),
                     vrz = wF - (double)vel(p, 2);
        double Fx, Fy, Fz;
        dragForce(dragKind, vrx, vry, vrz, (double)rad(p), mu, rhof, eP, Fx, Fy, Fz);
        fdrag(p, 0) = (typename OutV::value_type)Fx;
        fdrag(p, 1) = (typename OutV::value_type)Fy;
        fdrag(p, 2) = (typename OutV::value_type)Fz;
        scatterAt(fx, b, sx, sy, sz, wx, wy, wz, -Fx * invVcell);
        scatterAt(fy, b, sx, sy, sz, wx, wy, wz, -Fy * invVcell);
        scatterAt(fz, b, sx, sy, sz, wx, wy, wz, -Fz * invVcell);
      });
}

// Implicit-drag feedback (fused). Same as computeDragFeedback but instead of scattering the explicit
// reaction force it deposits the linear-drag COEFFICIENT density (beta_over_n * invVcell) onto
// `dragBeta` and the drag TARGET (beta_over_n * u_p * invVcell) onto (fx,fy,fz) — so the fluid solve
// treats -beta*(u - u_p) implicitly (unconditionally stable for a stiff bed). The particle drag
// force (evaluated at the current slip) still goes to `fdrag` (explicit on the particle side).
// beta_over_n = |F_p| / |vrel|, recovered from the drag law by a unit-slip evaluation.
template <class PosV, class VelV, class RadV, class FieldV, class OutV>
void computeDragImplicit(int np, PosV pos, VelV vel, RadV rad, FieldV uf, FieldV vf, FieldV wf,
                         FieldV eps, OutV fdrag, FieldV dragBeta, FieldV fx, FieldV fy, FieldV fz,
                         GridMap m, double mu, double rhof, double invVcell, int dragKind) {
  using Exec = Kokkos::DefaultExecutionSpace;
  const int nx = m.ex - 2 * m.g, ny = m.ey - 2 * m.g, nz = m.ez - 2 * m.g;
  Kokkos::parallel_for(
      "peclet::coupling::drag_implicit", Kokkos::RangePolicy<Exec>(0, np), KOKKOS_LAMBDA(int p) {
        int i0, j0, k0;
        double wx, wy, wz;
        peclet::core::interp::detail::axisStencil((double)pos(p, 0), m.ox, m.idx, nx, i0, wx);
        peclet::core::interp::detail::axisStencil((double)pos(p, 1), m.oy, m.idy, ny, j0, wy);
        peclet::core::interp::detail::axisStencil((double)pos(p, 2), m.oz, m.idz, nz, k0, wz);
        const long sx = 1, sy = m.ex, sz = (long)m.ex * m.ey;
        const long b = (long)(i0 + m.g) + (long)(j0 + m.g) * sy + (long)(k0 + m.g) * sz;
        const double uF = gatherAt(uf, b, sx, sy, sz, wx, wy, wz);
        const double vF = gatherAt(vf, b, sx, sy, sz, wx, wy, wz);
        const double wF = gatherAt(wf, b, sx, sy, sz, wx, wy, wz);
        const double eP = gatherAt(eps, b, sx, sy, sz, wx, wy, wz);
        const double upx = (double)vel(p, 0), upy = (double)vel(p, 1), upz = (double)vel(p, 2);
        const double vrx = uF - upx, vry = vF - upy, vrz = wF - upz;
        double Fx, Fy, Fz;
        dragForce(dragKind, vrx, vry, vrz, (double)rad(p), mu, rhof, eP, Fx, Fy, Fz);
        fdrag(p, 0) = (typename OutV::value_type)Fx;
        fdrag(p, 1) = (typename OutV::value_type)Fy;
        fdrag(p, 2) = (typename OutV::value_type)Fz;
        // beta_over_n = |F|/|vrel| (isotropic linear coefficient at the frozen slip)
        const double vmag = Kokkos::sqrt(vrx * vrx + vry * vry + vrz * vrz);
        const double Fmag = Kokkos::sqrt(Fx * Fx + Fy * Fy + Fz * Fz);
        const double bon = (vmag > 1e-30) ? Fmag / vmag : 0.0;
        scatterAt(dragBeta, b, sx, sy, sz, wx, wy, wz, bon * invVcell);
        scatterAt(fx, b, sx, sy, sz, wx, wy, wz, bon * upx * invVcell);
        scatterAt(fy, b, sx, sy, sz, wx, wy, wz, bon * upy * invVcell);
        scatterAt(fz, b, sx, sy, sz, wx, wy, wz, bon * upz * invVcell);
      });
}

}  // namespace peclet::coupling

#endif  // PECLET_COUPLING_COUPLING_KERNELS_HPP
