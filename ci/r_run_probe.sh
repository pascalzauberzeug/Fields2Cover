#!/usr/bin/env bash
# Run ci/r_probe.R against a build produced by ci/r_cmake_build.sh.
#   docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/r_run_probe.sh
set -eu
BUILD=${BUILD:-/tmp/build-r}
cd "$BUILD/swig/r"
F2C_DATA=/work/data/ Rscript /work/ci/r_probe.R
