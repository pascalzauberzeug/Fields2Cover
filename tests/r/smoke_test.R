# Smoke test for the SWIG R bindings (BUILD_R=ON).
# Run from the build directory that holds fields2cover.so, fields2cover.R and
# fixups.R.  Mirrors tutorials/python/quick_start.py.

dyn.load(paste0("fields2cover", .Platform$dynlib.ext))
source("fields2cover.R")
source("fixups.R")
f2c_fix_enums(envir = globalenv())
f2c_fix_missing_member()
f2c_add_operators()

DATA <- Sys.getenv("F2C_DATA", "../../data/")

ok <- function(label, value) cat(sprintf("[ok] %-26s %s\n", label, value))

# --- basic types -------------------------------------------------------
p <- Point(1.2, 3.4)
stopifnot(abs(p$getX() - 1.2) < 1e-12, abs(p$getY() - 3.4) < 1e-12)
stopifnot(abs((p + Point(1, 1))$getX() - 2.2) < 1e-12)   # S4 operator mapping
stopifnot(abs(Point(1L, 2L)$getX() - 1) < 1e-12)          # integer literals
ok("Point", as(p, "character"))

pts <- VectorPoint()
for (xy in list(c(0, 0), c(80, 0), c(80, 80), c(0, 80), c(0, 0))) {
  pts$push_back(Point(xy[1], xy[2]))
}
stopifnot(pts$size() == 5)
stopifnot(abs(pts[2][[1]]$getX() - 80) < 1e-12)   # `[` goes through __getitem__
ok("VectorPoint + `[`", pts$size())

cells <- Cells(Cell(LinearRing(pts)))
stopifnot(abs(cells$area() - 6400) < 1e-9)
ok("Cells$area", cells$area())

# --- robot -------------------------------------------------------------
robot <- Robot(2.0, 6.0)
stopifnot(robot$getWidth() == 2, robot$getCovWidth() == 6)
ok("Robot", sprintf("%g / %g", robot$getWidth(), robot$getCovWidth()))

# --- headlands / swaths / route / path ---------------------------------
no_hl <- HG_Const_gen()$generateHeadlands(cells, 3.0 * robot$getWidth())
stopifnot(no_hl$area() > 0, no_hl$area() < cells$area())
ok("mainland area", no_hl$area())

swaths <- SG_BruteForce()$generateBestSwaths(
  OBJ_NSwath(), robot$getCovWidth(), no_hl$getGeometry(0L))
stopifnot(swaths$size() > 0)
ok("n swaths", swaths$size())

route <- RP_Boustrophedon()$genSortedSwaths(swaths)
stopifnot(route$size() == swaths$size())
ok("sorted swaths", route$size())

path <- PP_PathPlanning_planPath(robot, route, PP_DubinsCurves())
stopifnot(path$size() > 0, path$length() > 0)
ok("path states", path$size())
ok("path length", sprintf("%.6f", path$length()))

# --- enums (need fixups.R) ---------------------------------------------
stopifnot(identical(PPAlg_PPAlg_DUBINS_get(), "DUBINS"))
opts <- Options()
stopifnot(identical(opts$pp_alg, "DUBINS"))
ok("enum PPAlg", opts$pp_alg)

# --- whole-field flow via the parser -----------------------------------
field <- Parser_importFieldGml(file.path(DATA, "test1.xml"), FALSE)
full_path <- planCovPath(robot, field, FALSE)
stopifnot(full_path$length() > 0)
ok("planCovPath(field)", sprintf("%.6f", full_path$length()))

# --- error handling ----------------------------------------------------
err <- tryCatch({ cells$getGeometry(99L); NULL },
                error = function(e) conditionMessage(e))
stopifnot(!is.null(err))
ok("C++ exception -> R error", substr(err, 1, 40))

cat("R SMOKE TEST PASSED\n")
