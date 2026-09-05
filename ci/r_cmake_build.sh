#!/usr/bin/env bash
# Build the prototype BUILD_R target (and the Python target, as a regression
# check) against the Fields2Cover library already installed in the image, then
# run both smoke tests.
#
#   docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/r_cmake_build.sh
set -eu

BUILD=${BUILD:-/tmp/build-r}
mkdir -p "$BUILD"
cd "$BUILD"

cmake -DBUILD_PYTHON=ON \
      -DBUILD_R=ON \
      -DBUILD_TUTORIALS=OFF \
      -DBUILD_TESTING=ON \
      -DBUILD_DOC=OFF \
      -DCMAKE_BUILD_TYPE=Release /work

SECONDS=0
make -j"$(nproc)" fields2cover_r
echo "=== fields2cover_r built in ${SECONDS}s (incl. libFields2Cover) ==="
SECONDS=0
make -j"$(nproc)" fields2cover_python
echo "=== fields2cover_python built in ${SECONDS}s ==="

echo "=== artefacts ==="
ls -la "$BUILD"/swig/r/

echo "=== R smoke test ==="
make check_r

echo "=== Python regression ==="
cd "$BUILD/swig/python"
PYTHONPATH="$BUILD/swig/python" python3 -c "
import fields2cover as f2c
r = f2c.Robot(2.0, 6.0)
pts = f2c.VectorPoint([f2c.Point(0,0), f2c.Point(80,0), f2c.Point(80,80), f2c.Point(0,80), f2c.Point(0,0)])
cells = f2c.Cells(f2c.Cell(f2c.LinearRing(pts)))
no_hl = f2c.HG_Const_gen().generateHeadlands(cells, 3.0*r.getWidth())
sw = f2c.SG_BruteForce().generateBestSwaths(f2c.OBJ_NSwath(), r.getCovWidth(), no_hl.getGeometry(0))
route = f2c.RP_Boustrophedon().genSortedSwaths(sw)
path = f2c.PP_PathPlanning().planPath(r, route, f2c.PP_DubinsCurves())
assert repr(f2c.Point(1,2)) == 'POINT (1 2 0)', repr(f2c.Point(1,2))
assert list(f2c.VectorDouble([1.0, 2.0]))[1] == 2.0
print('python swaths', sw.size(), 'path length', path.length())
"
