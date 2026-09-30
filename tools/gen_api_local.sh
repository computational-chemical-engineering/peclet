#!/usr/bin/env bash
# Generate the Python API pages (docs/python/<pkg>.md, not committed) for a local `mkdocs serve`,
# exactly as the Site workflow does: tools/gen_python_api.py run inside the released peclet-cpu image.
#
#   tools/gen_api_local.sh              # oras://ghcr.io/computational-chemical-engineering/peclet-cpu:latest
#   tools/gen_api_local.sh 1.3.0        # a pinned release tag
#   tools/gen_api_local.sh ./peclet-cpu_latest.sif   # an image already pulled (faster: no download)
#
# Needs Apptainer (the images are SIFs published as ORAS artifacts; Docker/Podman cannot run them).
# Without it, generate from your own MPI-enabled build trees instead:
#   PYTHONPATH=<flow/build>:<dem/build>:... python3 tools/gen_python_api.py docs/python
set -euo pipefail
cd "$(dirname "$0")/.."

ref="${1:-latest}"
case "$ref" in
  *.sif|*/*) image="$ref" ;;   # a local image file or a full URI
  *)         image="oras://ghcr.io/computational-chemical-engineering/peclet-cpu:$ref" ;;
esac

runner=$(command -v apptainer || command -v singularity || true)
[ -n "$runner" ] || { echo "error: apptainer (or singularity) not found; see the header of $0" >&2; exit 1; }

echo ">> $image"
exec "$runner" exec "$image" python3 tools/gen_python_api.py docs/python
