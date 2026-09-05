#!/usr/bin/env bash
# Reproduce the SWIG R scoped-enum bug in isolation.
#   docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/enum_bug_min.sh
set -u
OUT=${OUT:-/tmp/enumbug}
mkdir -p "$OUT"
cp /work/ci/enum_bug_min.i "$OUT/enumtest.i"
cd "$OUT" || exit 1

swig -c++ -r -o enumtest_wrap.cpp -outdir . enumtest.i
g++ -c -fpic -std=c++17 $(R CMD config --cppflags) enumtest_wrap.cpp -o enumtest_wrap.o
g++ -shared enumtest_wrap.o $(R CMD config --ldflags) -o enumtest.so

echo "--- names used by the R enumeration table ---"
grep -o "R_swig_[A-Za-z_]*_get" enumtest.R | sort -u
echo "--- names actually registered in the wrapper ---"
grep -o "R_swig_[A-Za-z_]*_get" enumtest_wrap.cpp | sort -u

echo "--- behaviour ---"
R --no-save --quiet -e '
dyn.load("enumtest.so"); source("enumtest.R")
cat("plain enum : "); print(try(Plain_P_A_get(), silent = TRUE))
cat("scoped enum: "); print(try(Scoped_Scoped_A_get(), silent = TRUE))
'
