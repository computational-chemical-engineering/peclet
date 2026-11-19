# shellcheck shell=bash
# Build-job body of `sn build`. sn writes the job script as: #SBATCH header + the SN_* settings + this
# file, verbatim, into build/<tree>-<target>/build-job.sh. The steps are install_snellius.sh's
# (validated for releases 1.1.0 and 1.5.0), but from a pushed, read-only tree instead of a clone, and
# with every product OUTSIDE the tree:
#   build/<tree>-<target>/{env.sh,.venv,extern/install/<backend>,cmake/<pkg>,BUILD_INFO,build-*.out}
# Set by sn above this body: SN_TREE SN_TREE_NAME SN_TARGET SN_BUILD SN_PKGS SN_WHERE SN_TOOLKIT
set -euo pipefail
B="$SN_BUILD"; T="$SN_TREE"
_info() { echo "$*" >> "$B/BUILD_INFO.part"; }
[ -f "$B/BUILD_INFO" ] && { echo "FATAL(sn build): $B is already built (BUILD_INFO exists)" >&2; exit 1; }
[ -f "$T/MANIFEST" ] || { echo "FATAL(sn build): $T has no MANIFEST" >&2; exit 1; }
mkdir -p "$B"; cd "$B"
# a failed earlier attempt starts clean (copies of read-only tree files may be read-only)
chmod -R u+w "$B" 2>/dev/null || true
rm -rf "$B/.venv" "$B/cmake" "$B/src" "$B/extern" "$B/tools" "$B/env.sh" "$B/BUILD_INFO.part" "$B/BUILD_INFO.failed"

# --- 1. environment: the tree's snellius_env.sh, copied so every run sources the SAME file -------
install -m 0644 "$T/tools/hpc/snellius_env.sh" "$B/env.sh"     # writable copy: the tree is read-only
# shellcheck disable=SC1091
source "$B/env.sh"
_info "tree $SN_TREE_NAME"
_info "target $SN_TARGET"
_info "$(awk 'BEGIN{printf "MANIFEST"} NF>=2{printf " %s:%s", $1, substr($2,1,12)} END{print ""}' "$T/MANIFEST") ($(basename "$T"))"
_info "built_by job ${SLURM_JOB_ID:-none} on $(hostname) where $SN_WHERE at $(date -Iseconds) toolkit $SN_TOOLKIT"
_info "modules $(module -t list 2>&1 | tr '\n' ' ')"

# --- 2. venv; mpi4py COMPILED against the module's OpenMPI (never a binary wheel) -----------------
python3 -c 'import sys; assert sys.version_info[:2] >= (3, 10), sys.version'
python3 -m venv "$B/.venv"
# shellcheck disable=SC1091
source "$B/.venv/bin/activate"
pip install -q -U pip wheel
pip install -q nanobind numpy scipy matplotlib scikit-build-core hatchling
pip install -q --no-binary=mpi4py mpi4py
[ "$SN_TARGET" = cpu ] || pip install -q cupy-cuda12x
_info "python $(python -c 'import sys; print(sys.version.split()[0])') $(command -v python)"
_info "mpi4py $(python -c 'import mpi4py; print(mpi4py.__version__)') built with $(command -v mpicc) ($(mpirun --version 2>&1 | head -n 1))"

# --- 3. Kokkos (+ArborX) prefix per target, into THIS build dir ----------------------------------
# bootstrap_deps.sh installs to <its dir>/../extern, so a copy in $B/tools puts the prefix in $B and
# leaves the read-only tree alone.
case "$SN_TARGET" in
  h100) BACKEND=nvidia-cuda; KA=HOPPER90; CA=90 ;;
  a100) BACKEND=nvidia-cuda; KA=AMPERE80; CA=80 ;;
  cpu)  BACKEND=host-openmp; KA=; CA= ;;
  *) echo "FATAL(sn build): target '$SN_TARGET'" >&2; exit 1 ;;
esac
install -D -m 0755 "$T/tools/bootstrap_deps.sh" "$B/tools/bootstrap_deps.sh"
if [ "$BACKEND" = nvidia-cuda ]; then
  KOKKOS_ARCH=$KA CUDA_ARCH=$CA CUDA_COMPILER="$(command -v nvcc)" "$B/tools/bootstrap_deps.sh" nvidia-cuda
else
  "$B/tools/bootstrap_deps.sh" host-openmp
fi
PREFIX="$B/extern/install/$BACKEND"
# KokkosConfigCommon.cmake: "set(Kokkos_DEVICES OPENMP;SERIAL)", "set(Kokkos_ARCH HOPPER90)" (unquoted)
_kdev=$(sed -nE 's/^set\(Kokkos_DEVICES "?([^")]*)"?\).*/\1/p' "$PREFIX"/lib*/cmake/Kokkos/KokkosConfigCommon.cmake 2>/dev/null | head -1 || true)
_karch=$(sed -nE 's/^set\(Kokkos_ARCH "?([^")]*)"?\).*/\1/p' "$PREFIX"/lib*/cmake/Kokkos/KokkosConfigCommon.cmake 2>/dev/null | head -1 || true)
_info "kokkos backend $BACKEND arch ${_karch:-${KA:-host}} devices ${_kdev:-?} prefix $PREFIX"

# --- 4. the packages, in dependency order, MPI on, each against the tree's own core ---------------
# The CMAKE_ARGS traps (SNELLIUS.md): capital-P Python_EXECUTABLE (lowercase is silently ignored),
# Python_INCLUDE_DIR (a venv has no Python.h), MPIEXEC_EXECUTABLE (FindMPI may pick a foreign mpiexec).
# Each package's CMake build dir is $B/cmake/<pkg> (fresh: FindPython's artifacts are sticky).
# The packages build from a writable COPY of their repos in $B/src, checked identical to the tree:
# some CMake writes into its source dir (morton drops libpeclet_morton_c.so into
# bindings/python/peclet/morton), which the read-only tree refuses. The siblings are copied too, so
# ../core and ../morton resolve inside the copy; the copy goes after the install.
PYINC=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("INCLUDEPY"))')
export CMAKE_PREFIX_PATH="$PREFIX"
CMAKE_ARGS="-DPython_EXECUTABLE=$B/.venv/bin/python -DPython_INCLUDE_DIR=$PYINC -DMPIEXEC_EXECUTABLE=$(command -v mpirun)"
export CMAKE_ARGS
S="$B/src"; mkdir -p "$S"
for p in $SN_PKGS; do cp -a "$T/$p" "$S/"; done
chmod -R u+w "$S"
# shellcheck disable=SC2086  # SN_PKGS is a word list
_srchash() { (cd "$1" && find $SN_PKGS -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }
_h1=$(_srchash "$T"); _h2=$(_srchash "$S")
[ "$_h1" = "$_h2" ] || { echo "FATAL(sn build): the source copy differs from the tree ($_h1 vs $_h2)" >&2; exit 1; }
_info "src_copy $S = tree ($SN_PKGS) sha256 $_h1"
_pip() {  # <pkg-label> <source dir> [--config-settings ...]
  local p="$1" d="$2"; shift 2
  echo "== pip install $p ($d) $*"
  pip install --no-deps --no-build-isolation --config-settings=build-dir="$B/cmake/$p" "$@" "$d"
}
for p in $SN_PKGS; do
  case "$p" in
    morton|geom|amr|coupling) _pip "$p" "$S/$p" ;;
    core)
      _pip core "$S/core"                                      # -> peclet-halo
      # The peclet-core compatibility shell: core/packaging/pyproject-core.toml over a STAGING copy.
      _shell="$B/cmake/core-shell-src"; rm -rf "$_shell"; mkdir -p "$_shell"
      cp -r "$T/core/packaging" "$T/core/README.md" "$T/core/LICENSE" "$_shell/"; chmod -R u+w "$_shell"
      cp "$T/core/packaging/pyproject-core.toml" "$_shell/pyproject.toml"; chmod u+w "$_shell/pyproject.toml"
      _pip core-shell "$_shell" ;;
    flow) _pip flow "$S/flow" --config-settings=cmake.define.PECLET_FLOW_MPI=ON ;;
    pnm)  _pip pnm  "$S/pnm"  --config-settings=cmake.define.PECLET_PNM_MPI=ON ;;
    dem)  _pip dem  "$S/dem"  --config-settings=cmake.define.PECLET_DEM_MPI=ON ;;
    voro) _pip voro "$S/voro" --config-settings=cmake.define.PECLET_VORO_KOKKOS=ON \
            --config-settings=cmake.define.PECLET_VORO_BUILD_PYTHON=ON --config-settings=cmake.define.PECLET_VORO_MPI=ON ;;
    *) echo "FATAL(sn build): unknown package '$p'" >&2; exit 1 ;;
  esac
done

# --- 4b. proof: the core (and morton) headers each package compiled against: the copy's, whose hash
#     equals the tree's (src_copy line) ---------------------------------------------------------
# Every -I/-isystem directory in the package's generated build files, resolved; a sibling CMake did
# not find would have been FetchContent-fetched (_deps/peclet_sib_*) -- that is a FAILURE here.
_bad=0
for p in $SN_PKGS; do
  d="$B/cmake/$p"; [ -d "$d" ] || continue
  if find "$d" -maxdepth 3 -type d -name 'peclet_sib_*' | grep -q .; then
    _info "core_include $p FETCHED $(find "$d" -maxdepth 3 -type d -name 'peclet_sib_*-src' | tr '\n' ' ') FAIL"; _bad=1; continue
  fi
  for lib in core morton; do
    want=$(realpath -m "$S/$lib/include")
    got=$(find "$d" \( -name flags.make -o -name build.ninja \) -print0 2>/dev/null \
          | xargs -0 -r grep -hoE -- '-(I|isystem)[[:space:]]*/[^[:space:]"]+' \
          | sed -E 's/^-(I|isystem)[[:space:]]*//' | sort -u | xargs -r -n1 realpath -m \
          | grep -E "/$lib/include\$" | sort -u | tr '\n' ' ' || true)
    [ -n "$got" ] || continue
    if [ "${got% }" = "$want" ]; then _info "${lib}_include $p $want OK"
    else _info "${lib}_include $p ${got% } MISMATCH (want $want)"; _bad=1; fi
  done
done
# Every package that compiles core's headers must have shown them (no line = no proof = failure).
for p in $SN_PKGS; do
  case "$p" in morton|core-shell) continue ;; esac
  grep -q "^core_include $p .* OK$" "$B/BUILD_INFO.part" \
    || { _info "core_include $p NOT-FOUND in $B/cmake/$p FAIL"; _bad=1; }
done
[ "$_bad" = 0 ] || { cat "$B/BUILD_INFO.part"; echo "FATAL(sn build): a package compiled against foreign headers" >&2; exit 1; }

# --- 5. import check (on a GPU node for a GPU target; deferred on genoa/cbuild: no libcuda) -------
pip list 2>/dev/null | awk '/^peclet-/{print "package", $1, $2}' >> "$B/BUILD_INFO.part"
_mods=""
for p in $SN_PKGS; do
  case "$p" in core) _mods="$_mods peclet.halo" ;; *) _mods="$_mods peclet.$p" ;; esac
done
if [ "$SN_TARGET" != cpu ] && ! nvidia-smi -L >/dev/null 2>&1; then
  _info "import_check DEFERRED (no GPU on $SN_WHERE; run sn smoke)"
else
  # shellcheck disable=SC2086
  if python -W "error:peclet.core:DeprecationWarning" - $_mods > "$B/import_check.txt" 2>&1 <<'PY'
import importlib, sys
for m in sys.argv[1:]:
    mod = importlib.import_module(m)
    print(m, getattr(mod, "__version__", "?"), "space", getattr(mod, "execution_space", "-"), "mpi", getattr(mod, "has_mpi", "-"))
PY
  then _info "import_check OK $(grep '^peclet\.' "$B/import_check.txt" | tr '\n' ';')"
  else cat "$B/import_check.txt"; _info "import_check FAILED (see $B/import_check.txt)"; mv "$B/BUILD_INFO.part" "$B/BUILD_INFO.failed"; exit 1
  fi
fi

# --- 6. inodes: the Kokkos/ArborX build trees, their download cache and the source copy go ---------
rm -rf "$B/extern/build" "$B/extern/src" "$S"

# --- 7. BUILD_INFO, last: its presence means "built" ----------------------------------------------
mv "$B/BUILD_INFO.part" "$B/BUILD_INFO"
cat "$B/BUILD_INFO"
echo "sn build: OK $B"
