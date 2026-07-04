"""peclet.coupling — unresolved point-particle CFD-DEM coupling.

Composes peclet.flow (Eulerian fluid) + peclet.dem (Lagrangian particles) via the CfdDem driver.
The compute kernels (particle<->grid deposition, drag laws, momentum feedback) live in the _coupling
extension and run in place on the arrays the two solvers expose (zero-copy grid fields; particle
forces round-tripped through the dem host API).
"""
from . import _coupling  # noqa: F401  (deposit_solid_volume, compute_void_fraction, compute_drag_feedback)
from .driver import CfdDem  # noqa: F401

DRAG_STOKES = 0
DRAG_SCHILLER_NAUMANN = 1
DRAG_ERGUN = 2
DRAG_DI_FELICE = 3

__all__ = ["CfdDem", "_coupling", "DRAG_STOKES", "DRAG_SCHILLER_NAUMANN", "DRAG_ERGUN",
           "DRAG_DI_FELICE"]
