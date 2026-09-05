# Capability probe for the SWIG R bindings: what the R backend covers of the
# Fields2Cover API and where it falls short. Run from the build directory that
# holds fields2cover.so / fields2cover.R / fixups.R, e.g.
#   docker run --rm -v "$PWD":/work -w /work f2c-r bash ci/r_cmake_build.sh
#   docker run --rm -v "$PWD":/work f2c-r \
#       bash -c 'cd /tmp/build-r/swig/r && Rscript /work/ci/r_probe.R'

dyn.load(paste0("fields2cover", .Platform$dynlib.ext))
source("fields2cover.R")
FIXUPS <- Sys.getenv("F2C_FIXUPS", "1") == "1"
if (FIXUPS) {
  source("fixups.R")
  f2c_fix_enums(envir = globalenv())
  f2c_fix_missing_member()
  f2c_add_operators()
}
DATA <- Sys.getenv("F2C_DATA", "/work/data/")

pass <- 0L; fail <- 0L
check <- function(label, expr) {
  res <- tryCatch(expr, error = function(e) structure(conditionMessage(e), class = "probe_err"))
  if (inherits(res, "probe_err")) {
    fail <<- fail + 1L
    cat(sprintf("[FAIL] %-36s %s\n", label, as.character(res)))
  } else {
    pass <<- pass + 1L
    cat(sprintf("[ ok ] %-36s %s\n", label, paste(format(res), collapse = " ")))
  }
  invisible(res)
}

mk_cells <- function() {
  v <- VectorPoint()
  for (xy in list(c(0, 0), c(80, 0), c(80, 80), c(0, 80), c(0, 0))) v$push_back(Point(xy[1], xy[2]))
  Cells(Cell(LinearRing(v)))
}

cat("---- classes & inheritance ----\n")
check("S4 classes generated", length(getClasses(where = globalenv())))
check("derived class sees base method", { p <- Point(1, 2); p$getDimMaxX() })
check("templated base wrapped", class(GeomPoint()))

cat("---- containers ----\n")
v <- VectorPoint(); v$push_back(Point(1, 2)); v$push_back(Point(3, 4))
check("std::vector<Point> wrapper", v$size())
check("R `[` via __getitem__", v[2][[1]]$getX())
check("R `[<-` via __setitem__", { v[1] <- Point(9, 9); v[1][[1]]$getX() })
check("R `[[` on wrapper", tryCatch(v[[1]], error = function(e) stop("not supported")))
check("std::vector<double> as R numeric",
      HG_Const_gen()$generateHeadlands(mk_cells(), Robot(2, 6), c(0.0))$area())
check("Cells `[` (Geometry child)", mk_cells()[1][[1]]$area())
check("length()", length(mk_cells()))

cat("---- operators ----\n")
p <- Point(1, 2); q <- Point(3, 4)
check("operator+ as $Plus", p$Plus(q)$getX())
check("operator== as $EqualEqual", p$EqualEqual(p))
check("native R `+`", tryCatch(p + q, error = function(e) stop("not mapped to S4 group generic")))
check("native R `==`", tryCatch(p == q, error = function(e) stop("not mapped to S4 group generic")))
check("as(x,'character') via __str__", as(p, "character"))
check("print() shows content",
      { s <- paste(capture.output(print(p)), collapse = " ")
        if (grepl("Point\\(", s)) s else stop("prints as: ", s) })

cat("---- overloads ----\n")
check("overload by arity", Parser_importFieldGml(paste0(DATA, "test1.xml"))$getId())
check("overload by argument type",
      { r <- Robot(2, 6); c1 <- mk_cells()
        a <- HG_Const_gen()$generateHeadlands(c1, 3 * r$getWidth())          # (Cells, double)
        b <- HG_Const_gen()$generateHeadlands(c1$getGeometry(0L), r, 0.0)    # (Cell, Robot, double)
        sprintf("%.0f / %.0f", a$area(), b$area()) })
check("integer literal for a double arg",
      tryCatch(Point(1L, 2L), error = function(e) stop("1L rejected: ", conditionMessage(e))))

cat("---- enums ----\n")
check("enum constant", PPAlg_PPAlg_DUBINS_get())
check("enum-typed return value",
      { vv <- VectorPoint(); vv$push_back(Point(0, 0)); vv$push_back(Point(10, 0))
        Swath(LineString(vv), 2)$getType() })
check("enum-typed struct field", Options()$pp_alg)
check("struct field write + use in C++",
      { o <- Options(); o$hg_swaths <- 4L; planCovPath(Robot(2, 6), mk_cells(), o)$length() })

cat("---- std::optional ----\n")
check("std::optional<double> template", class(optional_double()))
check("optional-backed getter", Robot(2, 6)$getTurnVel())

cat("---- errors & lifetime ----\n")
check("C++ exception -> R condition",
      tryCatch({ mk_cells()$getGeometry(99L); stop("no exception") },
               error = function(e) substr(conditionMessage(e), 1, 45)))
check("unknown member message",
      tryCatch({ Point(1, 2)$nope; stop("no error") },
               error = function(e) substr(conditionMessage(e), 1, 45)))
check("20k objects + gc", { for (i in 1:20000) invisible(Point(i + 0, 1)); gc()[1, 1] })

cat("---- full pipeline ----\n")
check("or-tools route planner",
      { r <- Robot(2, 6)
        no_hl <- HG_Const_gen()$generateHeadlands(mk_cells(), 3 * r$getWidth())
        sw <- SG_BruteForce()$generateBestSwaths(OBJ_NSwath(), r$getCovWidth(), no_hl)
        RP_RoutePlannerBase()$genRoute(no_hl, sw)$length() })
check("planCovPath on a parsed field",
      planCovPath(Robot(2, 6), Parser_importFieldGml(paste0(DATA, "test1.xml"), FALSE), FALSE)$length())
check("Visualizer to png",
      { Visualizer_figure(); Visualizer_plot(mk_cells()); Visualizer_save("/tmp/r_probe.png"); TRUE })

cat(sprintf("\nprobe: %d ok, %d failed (fixups=%s)\n", pass, fail, FIXUPS))
