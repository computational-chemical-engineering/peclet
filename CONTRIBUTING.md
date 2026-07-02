# Contributing to peclet

Thanks for your interest in contributing! `peclet` is an **umbrella repository** of five method/infrastructure
codes as git **submodules** (`core`, `flow`, `dem`, `voro`, `morton`), each its own repo with its own build.
Work happens *inside* a submodule; the umbrella only pins compatible commits and holds the shared docs.

## Getting set up

```bash
git clone --recurse-submodules https://github.com/computational-chemical-engineering/peclet.git
cd peclet
# Build the pinned Kokkos (+ArborX) once into extern/install/<backend>:
tools/bootstrap_deps.sh host-openmp            # or nvidia-cuda / lumi-hip
```

Then build a code against that prefix (example: `flow`):

```bash
cd flow && python -m venv .venv && source .venv/bin/activate && pip install nanobind numpy
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/../extern/install/host-openmp"
cmake --build build -j
PYTHONPATH=$PWD/build python scripts/verify_poiseuille_sdflow.py
```

Each code has its own `README`/`CLAUDE.md` with build + test commands. Header-only codes (`core`, `morton`,
`voro`) run their tests via `ctest`; the Kokkos codes are driven from Python (`verify_*.py`, `tests/`).

## Making changes

1. **Branch** from `main` in the relevant submodule.
2. **Keep the numerical method intact** when changing backends/build — port exactly, don't silently change schemes.
3. **Add or run a test/validator** for your change (the `tests/` suites and the `verify_*.py` scripts).
4. **Match the code style** — see [`docs/STYLE.md`](docs/STYLE.md). C++ is clang-format-enforced (Google-style,
   e.g. `clang-format --dry-run --Werror`); Python follows the surrounding code. Identifiers name *what a thing
   is*, not *where it runs* (see [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md)).
5. **Open a PR** against the submodule. Once merged, the umbrella's submodule pointer is bumped to the new commit.

For multi-rank (MPI) changes, validate at `np=1,2,4` and keep the result bit-exact to single-rank where the
code claims it (the `tests/kokkos_mpi` suites do this).

## Reporting issues

Open an issue on the relevant repository with a minimal reproducer (grid size / inputs, backend, `np`), the
observed vs expected behaviour, and your environment (OS, compiler, Kokkos backend, GPU/MPI if relevant).

## Conduct & licensing

By contributing you agree your contributions are licensed under the project's [MIT License](LICENSE), and
to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).
