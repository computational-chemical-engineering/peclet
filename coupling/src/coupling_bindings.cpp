/// @file
/// @brief nanobind module `peclet.coupling` — CFD-DEM exchange kernels on shared arrays.
///
/// Physics-free glue: the functions here take the particle arrays (from peclet.dem) and the grid
/// fields (from peclet.flow) as ndarrays and run the deposition / drag / feedback kernels IN PLACE,
/// so a coupled run never links the two solvers in C++ — the Python CfdDem driver composes them.
/// Particle arrays are float32 (dem SoA precision), grid fields float64 (flow field precision); each
/// array is wrapped as an unmanaged Kokkos View over the SAME memory (zero-copy on host and, for
/// DLPack device arrays on a GPU build, on device). Kokkos is initialised at import; the arrays are
/// borrowed (owned by the caller), so there is nothing to release at exit.
#include <nanobind/nanobind.h>
#include <nanobind/ndarray.h>

#include <Kokkos_Core.hpp>
#include <stdexcept>

#include "coupling_kernels.hpp"
#include "peclet/core/python/ndarray_interop.hpp"

namespace nb = nanobind;
using peclet::core::MemSpace;
using peclet::core::interp::GridMap;
using Unmanaged = Kokkos::MemoryTraits<Kokkos::Unmanaged>;

namespace {

// Assert the array lives where this build's kernels run (cpu for a host build; the GPU backend for a
// device build) — otherwise the unmanaged View would dangle across the host/device boundary.
void require_here(const nb::ndarray<>& a, const char* who) {
  const int want = peclet::core::python::dlpack_device<MemSpace>().first;
  if (a.device_type() != want)
    throw std::runtime_error(std::string(who) +
                             ": array is on the wrong device for this build (pass a host array on a "
                             "CPU build, a CuPy/DLPack device array on a GPU build)");
}

using FlatV = Kokkos::View<double*, MemSpace, Unmanaged>;
using Vec3V = Kokkos::View<float* [3], Kokkos::LayoutRight, MemSpace, Unmanaged>;
using VecfV = Kokkos::View<float*, MemSpace, Unmanaged>;

// Flat x-fastest field (any shape; the underlying buffer is treated as size() contiguous doubles).
FlatV flatField(const nb::ndarray<>& a, const char* who) {
  peclet::core::python::require_dtype<double>(a, who);
  require_here(a, who);
  return FlatV(static_cast<double*>(a.data()), a.size());
}
// (N,3) C-contiguous float particle array -> row-major unmanaged View.
Vec3V vec3(const nb::ndarray<>& a, const char* who) {
  peclet::core::python::require_dtype<float>(a, who);
  require_here(a, who);
  return Vec3V(static_cast<float*>(a.data()), a.shape(0));
}
// (N,) float particle array.
VecfV vecf(const nb::ndarray<>& a, const char* who) {
  peclet::core::python::require_dtype<float>(a, who);
  require_here(a, who);
  return VecfV(static_cast<float*>(a.data()), a.size());
}

GridMap gmap(double ox, double oy, double oz, double h, int ex, int ey, int ez, int g) {
  return GridMap{ox, oy, oz, 1.0 / h, 1.0 / h, 1.0 / h, ex, ey, ez, g};
}
}  // namespace

NB_MODULE(_coupling, m) {
  m.doc() = "CFD-DEM coupling kernels (deposition, drag, momentum feedback) on shared arrays.";
  if (!Kokkos::is_initialized())
    Kokkos::initialize();

  m.def(
      "deposit_solid_volume",
      [](nb::ndarray<> pos, nb::ndarray<> rad, nb::ndarray<> solidvol, double ox, double oy,
         double oz, double h, int ex, int ey, int ez, int g) {
        auto sv = flatField(solidvol, "deposit_solid_volume(solidvol)");
        Kokkos::deep_copy(sv, 0.0);
        peclet::coupling::depositSolidVolume((int)pos.shape(0), vec3(pos, "pos"), vecf(rad, "rad"),
                                             sv, gmap(ox, oy, oz, h, ex, ey, ez, g));
      },
      nb::arg("pos"), nb::arg("rad"), nb::arg("solidvol"), nb::arg("ox"), nb::arg("oy"),
      nb::arg("oz"), nb::arg("h"), nb::arg("ex"), nb::arg("ey"), nb::arg("ez"), nb::arg("g"),
      "Scatter particle volumes (4/3 pi r^3) onto the flat padded `solidvol` buffer (zeroed here). "
      "Fold the periodic ghosts before compute_void_fraction.");

  m.def(
      "compute_void_fraction",
      [](nb::ndarray<> solidvol, nb::ndarray<> eps, double inv_vcell, double eps_min) {
        peclet::coupling::voidFraction(flatField(solidvol, "solidvol"), flatField(eps, "eps"),
                                       inv_vcell, eps_min);
      },
      nb::arg("solidvol"), nb::arg("eps"), nb::arg("inv_vcell"), nb::arg("eps_min") = 0.2,
      "eps = clamp(1 - solidvol/Vcell, eps_min, 1), elementwise on the flat padded buffers.");

  m.def(
      "interpolate_velocity",
      [](nb::ndarray<> pos, nb::ndarray<> uf, nb::ndarray<> vf, nb::ndarray<> wf, nb::ndarray<> out,
         double ox, double oy, double oz, double h, int ex, int ey, int ez, int g) {
        const GridMap mp = gmap(ox, oy, oz, h, ex, ey, ez, g);
        auto o = vec3(out, "interpolate_velocity(out)");
        const int np = (int)pos.shape(0);
        peclet::core::interp::trilinearGather(np, vec3(pos, "pos"), flatField(uf, "uf"),
                                              Kokkos::subview(o, Kokkos::ALL, 0), mp);
        peclet::core::interp::trilinearGather(np, vec3(pos, "pos"), flatField(vf, "vf"),
                                              Kokkos::subview(o, Kokkos::ALL, 1), mp);
        peclet::core::interp::trilinearGather(np, vec3(pos, "pos"), flatField(wf, "wf"),
                                              Kokkos::subview(o, Kokkos::ALL, 2), mp);
      },
      nb::arg("pos"), nb::arg("uf"), nb::arg("vf"), nb::arg("wf"), nb::arg("out"), nb::arg("ox"),
      nb::arg("oy"), nb::arg("oz"), nb::arg("h"), nb::arg("ex"), nb::arg("ey"), nb::arg("ez"),
      nb::arg("g"), "Gather the fluid velocity (uf,vf,wf) at each particle into `out` (N,3).");

  m.def(
      "compute_drag_feedback",
      [](nb::ndarray<> pos, nb::ndarray<> vel, nb::ndarray<> rad, nb::ndarray<> uf, nb::ndarray<> vf,
         nb::ndarray<> wf, nb::ndarray<> eps, nb::ndarray<> fdrag, nb::ndarray<> fx,
         nb::ndarray<> fy, nb::ndarray<> fz, double ox, double oy, double oz, double h, int ex,
         int ey, int ez, int g, double mu, double rho, double inv_vcell, int drag_kind) {
        const GridMap mp = gmap(ox, oy, oz, h, ex, ey, ez, g);
        auto Fx = flatField(fx, "fx"), Fy = flatField(fy, "fy"), Fz = flatField(fz, "fz");
        Kokkos::deep_copy(Fx, 0.0);
        Kokkos::deep_copy(Fy, 0.0);
        Kokkos::deep_copy(Fz, 0.0);
        peclet::coupling::computeDragFeedback(
            (int)pos.shape(0), vec3(pos, "pos"), vec3(vel, "vel"), vecf(rad, "rad"),
            flatField(uf, "uf"), flatField(vf, "vf"), flatField(wf, "wf"), flatField(eps, "eps"),
            vec3(fdrag, "fdrag"), Fx, Fy, Fz, mp, mu, rho, inv_vcell, drag_kind);
      },
      nb::arg("pos"), nb::arg("vel"), nb::arg("rad"), nb::arg("uf"), nb::arg("vf"), nb::arg("wf"),
      nb::arg("eps"), nb::arg("fdrag"), nb::arg("fx"), nb::arg("fy"), nb::arg("fz"), nb::arg("ox"),
      nb::arg("oy"), nb::arg("oz"), nb::arg("h"), nb::arg("ex"), nb::arg("ey"), nb::arg("ez"),
      nb::arg("g"), nb::arg("mu"), nb::arg("rho"), nb::arg("inv_vcell"), nb::arg("drag_kind"),
      "Gather (uf,vf,wf,eps) at each particle, evaluate the drag law (0 Stokes, 1 Schiller-Naumann, "
      "2 Ergun, 3 Di Felice), write the drag force to `fdrag` (N,3) and the reaction force density "
      "-F/Vcell onto (fx,fy,fz) (zeroed here). Momentum-conserving. EXPLICIT feedback — use "
      "compute_drag_implicit for stiff (dense-bed) drag.");

  m.def(
      "compute_drag_implicit",
      [](nb::ndarray<> pos, nb::ndarray<> vel, nb::ndarray<> rad, nb::ndarray<> uf, nb::ndarray<> vf,
         nb::ndarray<> wf, nb::ndarray<> eps, nb::ndarray<> fdrag, nb::ndarray<> dragbeta,
         nb::ndarray<> fx, nb::ndarray<> fy, nb::ndarray<> fz, double ox, double oy, double oz,
         double h, int ex, int ey, int ez, int g, double mu, double rho, double inv_vcell,
         int drag_kind) {
        const GridMap mp = gmap(ox, oy, oz, h, ex, ey, ez, g);
        auto Db = flatField(dragbeta, "drag_beta"), Fx = flatField(fx, "fx"),
             Fy = flatField(fy, "fy"), Fz = flatField(fz, "fz");
        Kokkos::deep_copy(Db, 0.0);
        Kokkos::deep_copy(Fx, 0.0);
        Kokkos::deep_copy(Fy, 0.0);
        Kokkos::deep_copy(Fz, 0.0);
        peclet::coupling::computeDragImplicit(
            (int)pos.shape(0), vec3(pos, "pos"), vec3(vel, "vel"), vecf(rad, "rad"),
            flatField(uf, "uf"), flatField(vf, "vf"), flatField(wf, "wf"), flatField(eps, "eps"),
            vec3(fdrag, "fdrag"), Db, Fx, Fy, Fz, mp, mu, rho, inv_vcell, drag_kind);
      },
      nb::arg("pos"), nb::arg("vel"), nb::arg("rad"), nb::arg("uf"), nb::arg("vf"), nb::arg("wf"),
      nb::arg("eps"), nb::arg("fdrag"), nb::arg("drag_beta"), nb::arg("fx"), nb::arg("fy"),
      nb::arg("fz"), nb::arg("ox"), nb::arg("oy"), nb::arg("oz"), nb::arg("h"), nb::arg("ex"),
      nb::arg("ey"), nb::arg("ez"), nb::arg("g"), nb::arg("mu"), nb::arg("rho"), nb::arg("inv_vcell"),
      nb::arg("drag_kind"),
      "Implicit (semi-implicit) drag: writes `fdrag` (particle force) and deposits the linear-drag "
      "coefficient density onto `drag_beta` and the target beta*u_p onto (fx,fy,fz) (all zeroed "
      "here) for flow.enable_drag() to treat -beta*(u-u_p) implicitly. Stable for stiff beds.");
}
