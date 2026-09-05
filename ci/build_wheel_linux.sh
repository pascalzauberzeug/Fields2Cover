#!/usr/bin/env bash
# Build a self-contained ("fat") linux wheel of fields2cover.
#
# Runs inside the osgeo/gdal ubuntu image, builds the wheel against the system
# dependencies and then bundles every shared library it needs -- GDAL/PROJ,
# GEOS, TBB, tinyxml2, or-tools and their transitive dependencies -- into the
# wheel with `auditwheel repair`. The result installs with a plain `pip install`
# on any manylinux-compatible distro without a single system package.
#
#   docker run --rm -v "$PWD":/work -w /work osgeo/gdal:ubuntu-small-3.6.3 \
#       bash ci/build_wheel_linux.sh [python-version] [outdir]
#
# python-version: e.g. 3.11 (default: the image's python3). Versions the image
#                 does not ship are installed from the deadsnakes PPA.
# outdir:         where the repaired wheel is written (default: ./dist).
set -euo pipefail

PYVER="${1:-}"
OUTDIR="${2:-dist}"
ARCH="$(uname -m)"

export DEBIAN_FRONTEND=noninteractive
apt-get update --allow-insecure-repositories -y
apt-get install -y --allow-unauthenticated --no-install-recommends \
  ca-certificates build-essential git wget \
  libboost-dev libeigen3-dev libgeos-dev libtbb-dev libtinyxml2-dev nlohmann-json3-dev \
  python3 python3-dev python3-pip python3-venv

if [[ -n "$PYVER" ]] && ! command -v "python$PYVER" >/dev/null; then
  apt-get install -y --allow-unauthenticated --no-install-recommends \
    software-properties-common gnupg
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update -y
  apt-get install -y --no-install-recommends \
    "python$PYVER" "python$PYVER-dev" "python$PYVER-venv"
fi
PYTHON="python${PYVER}"
command -v "$PYTHON" >/dev/null || PYTHON=python3

# or-tools release tarball, same version as cmake/F2CUtils.cmake
case "$ARCH" in
  x86_64)  ORTOOLS_URL=https://github.com/google/or-tools/releases/download/v9.9/or-tools_amd64_ubuntu-22.04_cpp_v9.9.3963.tar.gz ;;
  aarch64) ORTOOLS_URL=https://github.com/google/or-tools/releases/download/v9.9/or-tools_arm64_debian-11_cpp_v9.9.3963.tar.gz ;;
  *) echo "unsupported arch $ARCH" >&2; exit 1 ;;
esac
if [[ ! -d /opt/ortools/lib ]]; then
  wget -q -O /tmp/ortools.tar.gz "$ORTOOLS_URL"
  mkdir -p /opt/ortools
  tar -zxf /tmp/ortools.tar.gz -C /opt/ortools --strip-components=1
fi
export CMAKE_PREFIX_PATH=/opt/ortools
# auditwheel resolves the extension's DT_NEEDED through the loader search path.
export LD_LIBRARY_PATH=/opt/ortools/lib

VENV="/tmp/f2c-wheel-venv-${PYVER:-default}"
rm -rf "$VENV"
"$PYTHON" -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install build auditwheel patchelf
# auditwheel shells out to the patchelf binary, so it has to be on PATH.
export PATH="$VENV/bin:$PATH"

# The manylinux allowlist assumes libexpat is present on every system. That
# holds for a normal distro but not for minimal images such as python:3-slim,
# and GDAL needs it, so drop it from the policy and let auditwheel bundle it
# together with the rest of the dependency closure.
"$VENV/bin/python" - <<'PY'
import json
import pathlib

import auditwheel.policy

path = pathlib.Path(auditwheel.policy.__file__).parent / "manylinux-policy.json"
policies = json.loads(path.read_text())
for policy in policies:
    if "libexpat.so.1" in policy["lib_whitelist"]:
        policy["lib_whitelist"].remove("libexpat.so.1")
path.write_text(json.dumps(policies))
print("dropped libexpat.so.1 from the manylinux allowlist")
PY

# Bundle the GDAL and PROJ runtime data (proj.db et al.) into the package, so
# coordinate transformations work without a system GDAL/PROJ installation.
export SKBUILD_CMAKE_DEFINE="F2C_BUNDLE_GDAL_DATA=ON"

RAW=/tmp/f2c-wheel-raw
rm -rf "$RAW"
"$VENV/bin/python" -m build --wheel --outdir "$RAW" .

echo "=== unrepaired wheel ==="
ls -l "$RAW"

echo "=== auditwheel show ==="
"$VENV/bin/auditwheel" show "$RAW"/*.whl

mkdir -p "$OUTDIR"
echo "=== auditwheel repair ==="
"$VENV/bin/auditwheel" repair --wheel-dir "$OUTDIR" "$RAW"/*.whl

echo "=== repaired wheel ==="
ls -l "$OUTDIR"
