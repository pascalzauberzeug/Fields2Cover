#!/usr/bin/env bash
# Install a self-contained fields2cover wheel on a bare python image that has
# none of the system dependencies (no GDAL, GEOS, or-tools, TBB, tinyxml2) and
# run the python test suite against it.
#
#   docker run --rm -v "$PWD":/work -w /work python:3.12-slim \
#       bash ci/test_wheel_clean.sh dist/fields2cover-*-cp312-*.whl
set -euo pipefail

WHEEL="${1:?usage: test_wheel_clean.sh <wheel>}"

pip install --no-cache-dir --upgrade pip
pip install --no-cache-dir "$WHEEL" pytest numpy
python -c "import fields2cover as f2c; print('fields2cover', f2c.__version__)"
# Coordinate transformations need GDAL's and PROJ's data files; make sure the
# bundled copies are picked up rather than a system installation.
python -c "
import os, fields2cover as f2c
print('GDAL_DATA', os.environ.get('GDAL_DATA'))
print('PROJ_DATA', os.environ.get('PROJ_DATA'))
field = f2c.Field(f2c.Cells(f2c.Cell(f2c.LinearRing(f2c.VectorPoint(
    [f2c.Point(4.0, 52.0), f2c.Point(4.001, 52.0),
     f2c.Point(4.001, 52.001), f2c.Point(4.0, 52.0)])))))
field.setEPSGCoordSystem(4326)
f2c.Transform.transform(field, 'EPSG:28992')
print('transformed to', field.getCRS())
"
python -m pytest tests/python -q
