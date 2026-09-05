# Smoke test for the SWIG-generated R bindings of Fields2Cover.
# Mirrors tutorials/python/quick_start.py: build a field, cut headlands,
# generate swaths, order them into a route and plan a path.
#
# Expects fields2cover.so + fields2cover.R (SWIG R output) in getwd().

dyn.load("fields2cover.so")
source("fields2cover.R")

ok <- function(label, value) cat(sprintf("[ok] %-28s %s\n", label, value))

# --- basic types -------------------------------------------------------
p <- Point(1.2, 3.4)
stopifnot(abs(p$getX() - 1.2) < 1e-12, abs(p$getY() - 3.4) < 1e-12)
ok("Point getX/getY", sprintf("(%g, %g)", p$getX(), p$getY()))

pts <- VectorPoint()
for (xy in list(c(0, 0), c(80, 0), c(80, 80), c(0, 80), c(0, 0))) {
  pts$push_back(Point(xy[1], xy[2]))
}
ok("VectorPoint size", pts$size())

ring <- LinearRing(pts)
cell <- Cell(ring)
cells <- Cells(cell)
ok("Cells area", cells$area())

# --- robot -------------------------------------------------------------
robot <- Robot(2.0, 6.0)
ok("Robot width/cov", sprintf("%g / %g", robot$getWidth(), robot$getCovWidth()))

# --- headlands ---------------------------------------------------------
hl <- HG_Const_gen()
no_hl <- hl$generateHeadlands(cells, 3.0 * robot$getWidth())
ok("mainland area", no_hl$area())

# --- swaths ------------------------------------------------------------
bf <- SG_BruteForce()
obj <- OBJ_NSwath()
swaths <- bf$generateBestSwaths(obj, robot$getCovWidth(), no_hl$getGeometry(0L))
ok("n swaths", swaths$size())

# --- route -------------------------------------------------------------
route <- RP_Boustrophedon()$genSortedSwaths(swaths)
ok("sorted swaths", route$size())

# --- path --------------------------------------------------------------
turn <- PP_DubinsCurves()
path <- PP_PathPlanning_planPath(robot, route, turn)
ok("path states", path$size())
ok("path length", sprintf("%.10f", path$length()))

# --- WKT round trip ----------------------------------------------------
ok("cell WKT", substr(cells$exportToWkt(), 1, 40))

cat("SMOKE TEST PASSED\n")
