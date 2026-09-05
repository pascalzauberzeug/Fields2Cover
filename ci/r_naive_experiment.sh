#!/usr/bin/env bash
# Step 2 of the R feasibility study (GitHub issue #246):
# run the SWIG R backend on the unmodified swig/Fields2Cover.i, compile the
# generated wrapper and try to load it in R.
#
# Run inside the experiment image:
#   docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/r_naive_experiment.sh
set -u

OUT=${OUT:-/tmp/naive}
# SKIP_BUILD=1 reuses an existing fields2cover.so in $OUT and only re-runs the
# R smoke test (the wrapper is ~116k lines and takes minutes to compile).
SKIP_BUILD=${SKIP_BUILD:-0}
mkdir -p "$OUT"

if [ "$SKIP_BUILD" = "1" ] && [ -f "$OUT/fields2cover.so" ]; then
  cd "$OUT" || exit 1
  echo "=== smoke test only ==="
  Rscript /work/ci/r_smoke_test.R
  exit $?
fi

# On Debian/Ubuntu the R headers live in /usr/share/R/include, not $R_HOME/include.
R_CPPFLAGS=$(R CMD config --cppflags)
R_LDFLAGS=$(R CMD config --ldflags)
GDAL_CFLAGS=$(gdal-config --cflags)

echo "=== 1. swig -c++ -r ==="
swig -c++ -r -I/work/include -outdir "$OUT" -o "$OUT/f2c_wrap.cpp" /work/swig/Fields2Cover.i \
    > "$OUT/swig.log" 2>&1
echo "swig exit=$?"
echo "diagnostics: $(wc -l < "$OUT/swig.log") lines, \
$(grep -c 'Error' "$OUT/swig.log") errors, $(grep -c 'Warning' "$OUT/swig.log") warnings"
cat "$OUT/swig.log"
wc -l "$OUT"/*.cpp "$OUT"/*.R

echo "=== 2. compile wrapper ==="
cd "$OUT" || exit 1
g++ -c -O0 -fpic -std=c++17 $R_CPPFLAGS -I/usr/local/include $GDAL_CFLAGS \
    f2c_wrap.cpp -o f2c_wrap.o > compile.log 2>&1
echo "g++ exit=$?"
echo "errors: $(grep -c 'error:' compile.log)"
grep 'error:' compile.log | head -30

echo "=== 3. link ==="
if [ -f f2c_wrap.o ]; then
  g++ -shared f2c_wrap.o -L/usr/local/lib -lFields2Cover \
      $R_LDFLAGS -o fields2cover.so > link.log 2>&1
  echo "link exit=$?"
  tail -20 link.log
fi

echo "=== 4. load in R ==="
if [ -f fields2cover.so ]; then
  R --no-save --quiet -e 'dyn.load("fields2cover.so"); source("fields2cover.R"); cat("LOADED OK\n")' \
      > rload.log 2>&1
  echo "R exit=$?"
  tail -40 rload.log

  echo "=== 5. smoke test ==="
  Rscript /work/ci/r_smoke_test.R > smoke.log 2>&1
  echo "smoke exit=$?"
  cat smoke.log
fi
