# Feasibility of an R interface for Fields2Cover via SWIG

Investigation for [issue #246](https://github.com/Fields2Cover/Fields2Cover/issues/246)
("Add Lua and R interfaces via SWIG"). Everything below was executed in Docker;
nothing was installed on the host. Environment: `ghcr.io/osgeo/gdal:ubuntu-small-3.13.1`
(Ubuntu 26.04, linux/arm64), SWIG 4.4.0, R 4.5.2, g++ 15.2.0, CMake 4.2.3,
or-tools 9.9 (release tarball fetched by CMake).

## 1. Verdict

**Feasible, and considerably cheaper than the issue thread suggests.** Running
`swig -c++ -r` on the *unmodified* `swig/Fields2Cover.i` produces zero errors,
the same six warnings the Python target produces, and a wrapper that compiles,
loads in R and runs the complete coverage pipeline — field, headlands, swaths,
route, Dubins path — returning a path length bit-identical to the Python
module's (`819.4157957023`). The single most important reason it works is that
SWIG's R backend reuses the *same* magic-method protocol as the Python backend:
`Lib/r/srun.swg` dispatches R's `[`, `[<-` and `as(x, "character")` to
`__getitem__`, `__setitem__` and `__str__`, so `swig/python/Fields2Cover.i` was
already 80% language-neutral. What remains is a short list of ergonomic defects
in SWIG's R backend — one of them a genuine upstream bug (scoped enums) — all of
which are repaired in this branch by ~60 lines of R and one typemap. The real
difficulty is not the binding, it is **distribution**: or-tools is not packaged
for any Linux distribution, so CRAN is out of reach without making or-tools
optional.

## 2. What was tried and what happened

### 2.1 Baseline

`ci/Dockerfile.r` reproduces the repo-root `Dockerfile` flow (GDAL base, system
deps, SWIG, or-tools via CMake's `USE_ORTOOLS_RELEASE` path, full
`BUILD_PYTHON=ON` build) and adds `r-base`, `r-base-dev` and gtest. The Python
module builds and runs:

```
swaths 11 path length 819.4157957022983
```

### 2.2 Naive `swig -c++ -r` on the unmodified interface

```
swig -c++ -r -I include -outdir /tmp/naive -o /tmp/naive/f2c_wrap.cpp swig/Fields2Cover.i
```

Result: **exit 0, 0 errors, 6 warnings**, all of them the same `Warning 329`
that the Python target already emits:

```
include/fields2cover/types/MultiPoint.h:21: Warning 329: Using declaration
'f2c::types::Geometries< MultiPoint,OGRMultiPoint,wkbMultiPoint,f2c::types::Point >::Geometries'
for inheriting constructors uses base 'Geometries' which is not an immediate base of
'f2c::types::MultiPoint'.
... (same for LinearRing, LineString, MultiLineString, Cell, Cells)
```

Nothing failed on templates, `std::optional`, `std::vector` typemaps, operator
overloads, inheritance, nested classes or the Python-named `%extend` blocks.
`%include <optional.i>`, `<std_shared_ptr.i>`, `<std_pair.i>`, `<exception.i>`
and `<std_vector.i>` all resolve: SWIG ships R implementations of every one of
them (`$(swig -swiglib)/r/` contains `std_vector.i`, `std_shared_ptr.i`,
`std_pair.i`, `exception.i`, `typemaps.i`, `ropers.swg`, …). `swig/optional.i`'s
`#if defined(SWIGPYTHON)` branch falls through to the "simple optional" default,
which is enough because `std::optional` never appears in a public signature —
only in private members of `Robot` and `RoutePlannerBase`.

Generated output, compared with the Python target from the same `.i`:

| | R | Python |
|---|---|---|
| wrapper `.cxx` | 110 363 lines | 145 966 lines |
| script layer | 49 362 lines `.R` | 5 280 lines `.py` |
| classes | 128 S4 `setClass` | ~140 Python classes |
| methods | 256 `setMethod`, 2 332 exported functions | — |

The wrapper compiles and links without a single error:

```
=== 2. compile wrapper ===
g++ exit=0
errors: 0
=== 3. link ===
link exit=0
=== 4. load in R ===
LOADED OK
```

(The only build hiccup was operator error: `$(R RHOME)/include` does not exist
on Debian/Ubuntu — `fatal error: Rdefines.h: No such file or directory`. Use
`R CMD config --cppflags` / `--ldflags`.)

### 2.3 End-to-end smoke test

`ci/r_smoke_test.R` ports `tutorials/python/quick_start.py` to R and passed on
the first attempt against the untouched interface file:

```
[ok] Point getX/getY              (1.2, 3.4)
[ok] VectorPoint size             5
[ok] Cells area                   6400
[ok] Robot width/cov              2 / 6
[ok] mainland area                4624
[ok] n swaths                     11
[ok] sorted swaths                11
[ok] path states                  701
[ok] path length                  819.4157957023
[ok] cell WKT                     MULTIPOLYGON (((0 0 0,80 0 0,80 80 0,0 8
SMOKE TEST PASSED
```

Python for the same field: `819.4157957022983`.

### 2.4 Capability probe

`ci/r_probe.R` exercises the API point by point. An earlier version of it, run
against the *unmodified* interface, scored **19 ok / 6 failed**; the version in
this branch, run against the fixed build, scores **31 ok / 0 failed** (it also
covers more ground, having been extended as each defect was understood). The six
original failures:

**a) Scoped enums are broken (upstream SWIG bug).** For `enum class`, SWIG's
`defineEnumeration()` table references a wrapper name it never registers:

```
Error in .Call("R_swig_PPAlg_DUBINS_get", FALSE, PACKAGE = "fields2cover") :
  "R_swig_PPAlg_DUBINS_get" not available for .Call() for package "fields2cover"
```

Minimal reproducer, independent of Fields2Cover — `ci/enum_bug_min.i`,
`ci/enum_bug_min.sh`:

```
--- names used by the R enumeration table ---
R_swig_Plain_P_A_get
R_swig_Scoped_A_get           <- referenced
--- names actually registered in the wrapper ---
R_swig_Plain_P_A_get
R_swig_Scoped_Scoped_A_get    <- defined
--- behaviour ---
plain enum : [1] "P_A"
scoped enum: Error ... "R_swig_Scoped_A_get" not available for .Call()
```

Blast radius in F2C: every `enum class` — `SwathType`, `PathSectionType`,
`PathDirection`, `CorridorShareMode`, `SGAlg`, `SGObjFunc`, `RPAlg`, `PPAlg`,
`HGAlg`, `DecompAlg` — so enum constants, `Swath$getType()` and every field of
`Options` were unusable.

**b) `%template` on `std::vector` of primitives.** R's `std_vector.i` converts
`std::vector<double|int|size_t|long long>` to and from native R atomic vectors,
so the explicit `%template(VectorDouble)` etc. produce constructors that return
a bare `externalptr`:

```
Error in as.numeric(self) : cannot coerce type 'externalptr' to vector of type 'double'
```

The functions taking those types work fine when called with a plain R vector
(`generateHeadlands(cells, robot, c(0.0))` → `5476`).

**c) Missing member gives an unreadable error.** `$` falls through to
`callNextMethod()`:

```
unable to find an inherited method for function 'addNextMethod' for signature 'method = "function"'
```

**d) Operators are not mapped to R's group generics.** `Point::operator+` is
exported as `p$Plus(q)`; `p + q` raises `non-numeric argument to binary operator`.
Same for `==`, `!=`, `<`, `*`, `/`.

**e) R integers are rejected where C++ wants a `double`.** `Lib/r/rtype.swg`
leaves the `scoercein` typemap for `double` empty and then calls `REAL()`:

```
Point(1L, 2L)
REAL() can only be applied to a 'numeric', not a 'integer'
```

This bites every `for (i in 1:n)` loop, because `1:n` yields integers.

**f) `[<-` is broken for wrapped element types.** SWIG's generated `[<-` does
`value[n]`, which is `NULL` for an S4 wrapper:

```
SWIG:UnknownError invalid null reference in method 'VectorPoint___setitem__',
argument 3 of type 'std::vector< f2c::types::Point >::value_type const &'
```

Everything else worked out of the box: S4 inheritance (a `Point` sees
`Geometry`'s `getDimMaxX`), templated base classes, overload resolution by both
arity and argument type, C++ exceptions surfacing as R conditions
(`SWIG:RuntimeError Geometry does not contain point 99`), `reg.finalizer`-based
memory management (20 000 objects + `gc()` clean), the or-tools route planner,
`Parser`/`Visualizer` statics, and `planCovPath` on a parsed GML field.

### 2.5 Prototype

This branch contains a working `BUILD_R` target:

- `swig/magic_methods.i` — the `__getitem__`/`__setitem__`/`__len__` extends
  moved out of `swig/python/Fields2Cover.i`, because SWIG's R runtime consumes
  the same names. `swig/python/Fields2Cover.i` keeps only the Python-only
  `__repr__` blocks and `%include`s the shared file.
- `swig/Fields2Cover.i` — the trailing `%include "python/Fields2Cover.i"` is now
  a `SWIGPYTHON`/`SWIGR` switch; the primitive `%template(Vector*)`
  instantiations are skipped under `SWIGR`.
- `swig/r/typemaps.i` — `scoercein` for `float`/`double` so R integers are
  accepted (fix for (e)).
- `swig/r/fixups.R` — load-time repair of the enum tables (a), a readable
  missing-member error (c), S4 group generics for the operators (d), `[[`, and a
  working `[<-` (f).
- `swig/r/CMakeLists.txt` + `option(BUILD_R ... OFF)` — mirrors the Python
  target; `make check_r` runs `tests/r/smoke_test.R`.

Both targets build from one interface file and the Python behaviour is
unchanged (`repr(Point(1,2)) == 'POINT (1 2 0)'`, `VectorDouble` still a
sequence, same path length). Build cost is symmetric — on a 10-core machine,
after `cmake` configure: `fields2cover_r` 58 s (including `libFields2Cover`
itself), `fields2cover_python` 50 s. Adding the R target to CI roughly doubles
the SWIG portion of a build; it does not change its order of magnitude.

## 3. The maintainer's hypothesis

> "The Python SWIG module imports the complete ABI without big changes, whereas
> R requires the specific methods that have to be imported, as R is a language
> without classes and needs only methods (or something like this)."

**Refuted as stated, with a nuance that explains where the impression came from.**

- R does have classes here. SWIG's R backend emits 128 S4 classes with a real
  inheritance graph (`setClass('_p_f2c__hg__ConstHL', contains =
  c('_p_f2c__hg__HeadlandGeneratorBase'))`) and 256 `setMethod` definitions. It
  does *not* require the author to enumerate the methods to import; it walks the
  same parse tree as the Python backend.
- Member access is not method-based in the sense feared. Each class gets one
  `setMethod('$', ...)` whose body is a lookup table of the class's methods, so
  `hl$generateHeadlands(cells, 6.0)` works exactly like Python.
- Overloading works: SWIG generates the same runtime dispatch tables it
  generates for Python, matching on arity *and* argument type
  (`extends(argtypes[2], '_p_f2c__types__Cells')`).

The nuance: R *is* the language where SWIG dissolves things into free functions
in three places, and this is very likely what was remembered.

1. **Static members and free functions are flat.** `f2c::Parser::importFieldGml`
   becomes `Parser_importFieldGml(...)`, not `Parser()$importFieldGml(...)`; the
   same goes for `PP_PathPlanning_planPath` and `Visualizer_save`. R gets 2 332
   top-level function names in the global namespace.
2. **Operators become named methods** (`$Plus`, `$EqualEqual`), not operators.
3. **Enum constants become accessor functions** with a doubled prefix
   (`PPAlg_PPAlg_DUBINS_get()`), and — because of the bug above — they do not
   even work until patched.

So: R does not need methods to be listed by hand, but the generated API *reads*
as a pile of functions rather than as objects, and the first thing anyone tries
(`f2c.PPAlg_DUBINS`, `p + q`) is broken or absent. That is enough to make an
exploratory attempt feel like a dead end, especially before writing the R-side
polish layer.

## 4. Blockers and fixes

| # | Blocker | Severity | Fix | Status in this branch |
|---|---------|----------|-----|-----------------------|
| 1 | Scoped enums: `defineEnumeration` references `R_swig_<Enum>_<VAL>_get`, wrapper registers `R_swig_<Enum>_<Enum>_<VAL>_get`. Breaks all 10 `enum class` types, `Options` and `Swath$getType()` | blocking | Rebuild the enum tables at load time from the real accessor names (18 lines of R). Long term: report and patch SWIG's `r.cxx` | fixed, `swig/r/fixups.R` |
| 2 | `%template(VectorDouble/VectorInt/VectorSize/LongLongVector)` collide with R's native atomic-vector typemaps; constructors return a bare `externalptr` | high | Skip those `%template`s under `SWIGR`; pass plain R vectors instead | fixed, `swig/Fields2Cover.i` |
| 3 | R integers rejected for `double` parameters (`REAL() can only be applied to a 'numeric'`) | high (bites every `1:n` loop) | `%typemap(scoercein) double … { $input = as.numeric($input); }` | fixed, `swig/r/typemaps.i` |
| 4 | `[<-` on a wrapped container is broken (SWIG's generated method does `value[n]` on an S4 object) | medium | Override `[<-` for `ExternalReference` | fixed, `swig/r/fixups.R` |
| 5 | Operators exported as `$Plus`/`$EqualEqual`, not `+`/`==`; no `[[` | medium (ergonomics) | `setMethod("+", …)` etc. delegating to the SWIG names | fixed, `swig/r/fixups.R` |
| 6 | Unknown member → `addNextMethod` error | low | Override `$` for `ExternalReference` | fixed, `swig/r/fixups.R` |
| 7 | Enum constants named `PPAlg_PPAlg_DUBINS_get()` | low (ergonomics) | Export `PPAlg_DUBINS <- ...` constants from the package's `zzz.R` | not done |
| 8 | Static methods flattened to `Class_method()` | low (ergonomics, matches SWIG conventions in R) | Optional S4 wrappers, or document | not done |
| 9 | `%extend` blocks use C++17-removed dynamic exception specifications (`throw(std::out_of_range)`) | latent | Drop them; they are ignored by SWIG and rejected by C++20 | not done (pre-existing, affects Python too) |
| 10 | No `__repr__`-equivalent for R's `show()` on Swath/Path/Strip | low | `setMethod("show", …)` per class | not done |
| 11 | or-tools, matplotplusplus and steering_functions are not distro packages; the last two are fetched from GitHub at configure time | blocking for CRAN | see §5 | not addressed |

Nothing on this list is a reason to abandon the R backend. Items 1–6 total about
60 lines of R plus one typemap and are already done.

## 5. Packaging and distribution

The binding is the easy half. Fields2Cover's dependency set is what decides how
far it can ship. Concretely, a build needs GDAL ≥ 3.0, GEOS, Eigen3, TinyXML2,
Boost headers, TBB, and — pulled in by CMake's `FetchContent` at configure time
— `steering_functions`, `matplotplusplus` and `nlohmann_json`, plus or-tools
9.9 either from a system install or from a downloaded release tarball.

### Step 1 — `remotes::install_github()` / `pak::pak()` — realistic today

This is the right first target and needs no new infrastructure. A package under
`swig/r/pkg/` (or a separate `Fields2Cover/fields2cover-r` repo) would carry:

```
DESCRIPTION      Package: fields2cover
                 SystemRequirements: C++17, SWIG (>= 4.0), CMake (>= 3.18),
                   GDAL (>= 3.0.0), GEOS (>= 3.4.0), Eigen3, TinyXML2, TBB,
                   or-tools (>= 9.9)
NAMESPACE        useDynLib(fields2cover); exportPattern(".") ; import(methods)
configure        locates the deps, then runs cmake/make on the vendored C++ tree
src/Makevars.in  PKG_CPPFLAGS/PKG_LIBS filled in by configure
R/fields2cover.R the SWIG-generated file
R/zzz.R          .onLoad() -> f2c_fix_enums(); f2c_fix_missing_member();
                 f2c_add_operators()
```

`src/Makevars` alone is not enough. GDAL and GEOS can be found the way `sf`
does it (`gdal-config --cflags/--libs`, `geos-config`); or-tools ships neither a
`pkg-config` file nor an `*-config` script, only a CMake package config. So the
package needs a `configure` script that either (a) shells out to CMake to build
the bundled library and then reports the flags, or (b) requires
`ORTOOLS_ROOT`/`CMAKE_PREFIX_PATH` from the user. Option (a) is what actually
works unattended, and it is close to what `ci/r_cmake_build.sh` already does.

User-visible cost: `apt install libgdal-dev libgeos-dev libeigen3-dev
libtinyxml2-dev libtbb-dev libboost-dev cmake swig`, plus either or-tools
installed by hand or letting the configure step download the 9.9 release tarball
(~200 MB). Network access is needed at install time in any case, because the
CMake build fetches `steering_functions`, `matplotplusplus` and `nlohmann_json`.
That is acceptable for `install_github`, and is roughly the deal the Python
source install already offers.

### Step 2 — r-universe — probably fails today, fixable

r-universe builds straight from GitHub, needs no human review, and produces a
CRAN-compatible repository, so it is the natural second step. Its build images
install system dependencies by resolving the `SystemRequirements` field through
`pak`/`r-system-requirements`, which maps declared names to `apt install`
commands. Two problems:

- **or-tools has no Ubuntu package.** Verified in the experiment image:
  `apt-cache search or-tools` and `apt-cache policy libortools-dev` return
  nothing on Ubuntu 26.04. There is no rule in `r-system-requirements` that can
  install it, and the discussion in
  [r-universe-org#519](https://github.com/orgs/r-universe-org/discussions/519)
  confirms there is no escape hatch for installing arbitrary unmapped apt
  packages. The package would therefore have to fetch and build or-tools itself
  inside the r-universe build, which is slow (or-tools from source is a
  multi-hour build) but not impossible with the pre-built release tarball.
- **GDAL/GEOS are fine** — they are exactly the dependencies `sf` declares and
  they resolve.

Verdict: r-universe is reachable *if* the `configure` script downloads the
or-tools release tarball (a fixed, checksummed version — the same one
`cmake/F2CUtils.cmake` already pins). Expect build-time limits and a large
artefact. Worth trying once step 1 works; not worth designing around.

### Step 3 — CRAN — long-term only, and it requires a change inside F2C

Specific blockers, in order of severity:

1. **or-tools.** CRAN's policy is that external libraries should be part of the
   common distributions installed on CRAN's build machines (Debian/Ubuntu/Fedora
   on Linux, rtools/msys2 on Windows, a custom distribution on macOS); vendoring
   the sources is acceptable, downloading pre-compiled software during install
   is explicitly a last resort requiring CRAN's agreement. or-tools is in none of
   those distributions, is far too large to vendor, and pulls in abseil,
   protobuf, re2, SCIP and the COIN-OR stack. As it stands, a CRAN submission is
   not possible.
2. **Configure-time `FetchContent`.** CRAN builds must not download anything.
   `steering_functions`, `matplotplusplus` and `nlohmann_json` would have to be
   vendored into the package tarball (all three are small and permissively
   licensed, so this is mechanical).
3. **Windows and macOS.** CRAN requires the package to build on all three
   platforms. F2C's CI already covers macOS via Homebrew, but there is no
   Windows build at all today.
4. **`R CMD check` cleanliness.** 2 332 exported symbols with no documentation
   is an immediate `WARNING` (undocumented objects); the generated code also
   assigns into the global namespace in ways `R CMD check` complains about. A
   curated `NAMESPACE` exporting a hand-picked subset, plus `.Rd` files for it,
   is required work — this is where most of the human effort would go.

Compare with `sf`: it depends on GDAL, GEOS and PROJ, which *are* on CRAN's
machines (`SystemRequirements: GDAL (>= 2.0.1), GEOS (>= 3.4.0), PROJ (>= 4.8.0)`)
and are found by a `configure` script using `gdal-config`/`geos-config`. That is
precisely the situation Fields2Cover is *not* in for or-tools.

**Could or-tools be made optional?** Yes, and cheaply. or-tools appears in
exactly one translation unit:

```
$ grep -rl ortools src include
src/fields2cover/route_planning/route_planner_base.cpp
```

14 lines in one file, all inside `RoutePlannerBase::computeBestRoute`, reached
from the public API only via `RoutePlannerBase::genRoute` (and therefore
`f2c::planCovRoute`/`planCovPath` with the default `RPAlg::SHORTEST_ROUTE`).
Everything else — all geometry types, the parser, the visualizer, the headland
generators, `SG_BruteForce`, `RP_Boustrophedon`/`Snake`/`Spiral`/`CustomOrder`,
Dubins and Reeds-Shepp path planning, the decomposition algorithms — is
or-tools-free. A `-DUSE_ORTOOLS=OFF` build that compiles `computeBestRoute` to a
`throw std::runtime_error("built without or-tools")` (and drops the target link)
is a bounded change: one `.cpp`, one CMake option, one `%ignore` in the SWIG
interface. That would make a CRAN-compliant subset possible, at the price of
losing the optimal TSP route ordering. It would also be worth having for the
Python wheels.

### SWIG output vs. an R package

The CMake target in this branch produces `fields2cover.so` + `fields2cover.R`
and expects `dyn.load()` + `source()`. That is fine for CI and for developers,
but is not how R software is consumed. Note one hard constraint: SWIG hardcodes
`PACKAGE='fields2cover'` in every `.Call`, so the shared object must keep that
base name — the CMake target sets `PREFIX ""` and `OUTPUT_NAME fields2cover`
for exactly that reason. Turning this into a package is mostly moving the two
generated files into `R/` and `src/`, adding `configure`, and writing `zzz.R`.

### SWIG vs. Rcpp

Rcpp would mean hand-writing `RCPP_MODULE` declarations for ~140 classes and
several hundred methods, including the templated `Geometry`/`Geometries`
hierarchy that Rcpp cannot introspect. It buys nicer R idioms and no dependency
on SWIG's least-maintained backend — but it also buys a second, permanently
divergent description of the API that must be updated by hand on every C++
change, while the SWIG path gets those updates for free from the existing `.i`
file. Given that `swig -r` already produces a *working* module from the existing
interface, and given that the remaining ergonomic gaps are fixed by ~60 lines of
R sitting on top of the generated code, **Rcpp would be substantially more work
and more maintenance for a marginally nicer API**. It is not the right trade
here. (It would become the right trade if SWIG's R backend turned out to
regress across SWIG versions — see the open questions.)

## 6. Recommended path and effort

**Recommendation: SWIG, shipped first via `install_github`, with the
`BUILD_R` CMake option upstreamed.** Do not start with Rcpp. Do not aim at CRAN
until or-tools is made optional.

Effort, phrased for a Claude-plus-agents workflow (wall-clock, agent doing the
work, human reviewing):

| Step | Wall clock | Iterations | Human needed |
|---|---|---|---|
| Upstream what is in this branch (`BUILD_R`, `magic_methods.i`, `fixups.R`, `typemaps.i`, smoke test) | 2–3 h | 3–5 build/test cycles | review of the `.i` split, because it touches the Python target |
| CI job (`BUILD_R=ON` in `build.yml`, one gcc × one SWIG version) | 1–2 h | 2–4 (CI feedback loop dominates) | secrets/runner policy only |
| Polish layer: `show()` methods, `PPAlg_DUBINS`-style constants, an R-side `f2c$` namespace object, 10 tutorial ports | 4–6 h | 5–8 | API-naming decisions — genuinely a human call |
| R package (`DESCRIPTION`, `NAMESPACE`, `configure`, `zzz.R`) installable with `remotes::install_github` | 4–8 h | 8–15 (each `R CMD INSTALL` is a full C++ build) | deciding what the exported surface is |
| `USE_ORTOOLS=OFF` build option in the C++ library | 2–4 h | 3–5 | design call on what `computeBestRoute` should do when disabled |
| r-universe | 3–6 h, mostly waiting on remote builds | unbounded, remote | needs someone with the r-universe org set up |
| CRAN | not estimable until or-tools and documentation are resolved; the `R CMD check` documentation work alone is days of human review | — | substantial |

The first two rows are the ones worth doing now: they are cheap, they are
verified in this branch, and they turn "we tried and never managed" into a
maintained, tested target.

### CI job sketch

`.github/workflows/build.yml` already installs GDAL, SWIG and or-tools in a
container; an R job only adds `r-base-dev`:

```yaml
  build-r:
    name: "R bindings (gdal 3.6.3, swig 4.2.1)"
    runs-on: ubuntu-latest
    container: "osgeo/gdal:ubuntu-full-3.6.3"
    steps:
      - uses: actions/checkout@v4
      - uses: lukka/get-cmake@latest
      - name: System dependencies
        run: |
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -y
          apt-get install -y --no-install-recommends build-essential g++ git \
            libboost-dev libeigen3-dev libgeos-dev libtbb-dev libtinyxml2-dev \
            nlohmann-json3-dev gnuplot swig r-base r-base-dev wget
      - name: Or-tools
        run: |
          wget -q https://github.com/google/or-tools/releases/download/v9.9/or-tools_amd64_ubuntu-22.04_cpp_v9.9.3963.tar.gz -O /tmp/ortools.tar.gz
          mkdir -p /tmp/ortools && tar -zxf /tmp/ortools.tar.gz -C /tmp/ortools --strip-components=1
          cp -r /tmp/ortools/include/. /usr/include && cp -r /tmp/ortools/lib/. /usr/lib
          cp -r /tmp/ortools/lib/cmake/. /usr/share
      - name: Configure and build
        run: |
          cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_R=ON -DBUILD_PYTHON=OFF -DBUILD_TUTORIALS=OFF \
            -DBUILD_TESTING=OFF -DBUILD_DOC=OFF
          cmake --build build -j2 --target fields2cover_r
      - name: R smoke test
        run: cmake --build build --target check_r
```

One SWIG version is enough at first; the repo's 8-way SWIG matrix should *not*
be applied to the R target until it is known which versions the R backend
behaves on (see below).

### Open questions

- **SWIG version sensitivity.** Everything here was measured on SWIG 4.4.0 only.
  The repo's CI matrix spans 4.0.0 → 4.5.0. The R backend is SWIG's least
  exercised; the scoped-enum bug may be absent in some versions and the
  `fixups.R` heuristic (deriving accessor names as `<Enum>_<Enum>_<VALUE>_get`)
  would then mis-fire. `f2c_fix_enums()` should be made to detect which naming
  the module actually uses before it rewrites a table.
- **Is the scoped-enum bug already reported upstream?** Not checked. Worth
  filing with `ci/enum_bug_min.i`, which is a five-line reproducer.
- **Windows.** Not attempted. R on Windows uses rtools/mingw; whether
  `libFields2Cover` + or-tools build there at all is unknown.
- **What should the exported R surface be?** 2 332 top-level functions is not a
  usable API and is a `R CMD check` problem. Someone has to decide the subset.
- **Lua** (the other half of issue #246) was not investigated.

## 7. How to reproduce

All of this runs in Docker; nothing is installed on the host.

```bash
# 1. Build the experiment image (~10 min cold, cached afterwards).
#    Works on amd64 and arm64: CMake picks the matching or-tools tarball.
docker build -f ci/Dockerfile.r -t f2c-r .

# 2. Baseline: the Python module in the image.
docker run --rm f2c-r python3 -c "import fields2cover; print('ok')"

# 3. Naive `swig -r` on the interface file, compile, link, load, smoke test.
docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/r_naive_experiment.sh
#    (SKIP_BUILD=1 re-runs only the smoke test against an existing build)

# 4. Minimal reproducer for the scoped-enum bug.
docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/enum_bug_min.sh

# 5. The BUILD_R prototype: builds both SWIG targets, runs the R smoke test
#    (`make check_r`) and a Python regression check.
docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/r_cmake_build.sh

# 6. The 31-point capability probe (needs the build from step 5; mount a
#    persistent build dir so it survives the container).
mkdir -p /tmp/f2c-build-r
docker run --rm -v "$PWD":/work -v /tmp/f2c-build-r:/tmp/build-r -w /work \
  f2c-r bash ci/r_cmake_build.sh
docker run --rm -v "$PWD":/work -v /tmp/f2c-build-r:/tmp/build-r -w /work \
  f2c-r bash ci/r_run_probe.sh
#    F2C_FIXUPS=0 shows the unpatched behaviour.
```

Files produced by this investigation:

```
ci/Dockerfile.r            experiment image (repo Dockerfile flow + R + gtest)
ci/r_naive_experiment.sh   step 2/3/4 above: swig -r, compile, link, load, smoke
ci/r_smoke_test.R          quick_start.py ported to R (standalone variant)
ci/r_probe.R               31-point capability probe
ci/r_run_probe.sh          probe runner against a ci/r_cmake_build.sh build
ci/r_cmake_build.sh        builds the BUILD_R + BUILD_PYTHON targets, runs tests
ci/enum_bug_min.i/.sh      minimal reproducer for the SWIG scoped-enum bug
swig/magic_methods.i       extends shared by the Python and R backends
swig/r/Fields2Cover.i      R-specific interface layer
swig/r/typemaps.i          R integer -> C++ double coercion
swig/r/fixups.R            load-time repairs (enums, operators, [[, [<-, $)
swig/r/CMakeLists.txt      BUILD_R target + `make check_r`
tests/r/smoke_test.R       smoke test wired into the CMake target
```
