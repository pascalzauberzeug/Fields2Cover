# Runtime fix-ups for the SWIG R backend (SWIG 4.4.0).
# Sourced right after the SWIG-generated fields2cover.R.
#
# 1. Scoped enums (`enum class`) are mis-generated: defineEnumeration() calls
#    .Call("R_swig_<Enum>_<VALUE>_get") while the wrapper actually registers
#    "R_swig_<Enum>_<Enum>_<VALUE>_get". Every enum table therefore fails to
#    evaluate, which breaks enum constants, enum-typed return values
#    (Swath$getType()) and enum-typed struct fields (Options$pp_alg).
#    Reproducer: ci/enum_bug_min.i. Upstream SWIG bug; fixed here from R.
#
# 2. `$` with a name the class does not export raises
#    "unable to find an inherited method for function 'addNextMethod'".
#    Replaced by a readable message.
#
# 3. C++ operators are exported under textual names (Plus, Minus, Multiply,
#    Divide, EqualEqual, NotEqual, LessThan). Mapped to R's S4 group generics.
#    `[[` is added as a scalar alias for `[`.

f2c_fix_enums <- function(envir = parent.frame(), pkg = "fields2cover") {
  tables <- ls(envir = envir, all.names = TRUE, pattern = "^\\.__E__")
  for (tbl in tables) {
    type <- sub("^\\.__E__", "", tbl)       # e.g. "_f2c__PPAlg"
    ename <- sub("^.*__", "", type)          # e.g. "PPAlg"
    if (ename == "") next
    prefix <- paste0(ename, "_", ename, "_")
    getters <- ls(envir = envir, pattern = paste0("^", prefix, ".*_get$"))
    if (length(getters) == 0L) next
    values <- vapply(getters, function(g)
      as.integer(.Call(paste0("R_swig_", g), FALSE, PACKAGE = pkg)), integer(1))
    names(values) <- sub("_get$", "", sub(paste0("^", prefix), "", getters))
    assign(tbl, values, envir = envir)
  }
  invisible(tables)
}

f2c_fix_missing_member <- function() {
  setMethod("$", "ExternalReference", function(x, name) {
    # SWIG's own runtime probes for the magic names and expects NULL when a
    # class does not have them (see the `[` / `[<-` methods it generates).
    if (startsWith(name, "__")) return(NULL)
    stop(sprintf("'%s' is not a member of %s", name, class(x)), call. = FALSE)
  })
}

f2c_add_operators <- function() {
  delegate <- function(swig_name) function(e1, e2) {
    fun <- do.call(`$`, list(e1, swig_name))
    if (is.null(fun)) {
      stop(sprintf("%s is not defined for %s", swig_name, class(e1)), call. = FALSE)
    }
    fun(e2)
  }
  setMethod("+",  signature("ExternalReference", "ExternalReference"), delegate("Plus"))
  setMethod("-",  signature("ExternalReference", "ExternalReference"), delegate("Minus"))
  setMethod("*",  signature("ExternalReference", "ExternalReference"), delegate("Multiply"))
  setMethod("*",  signature("ExternalReference", "numeric"), delegate("Multiply"))
  setMethod("/",  signature("ExternalReference", "numeric"), delegate("Divide"))
  setMethod("==", signature("ExternalReference", "ExternalReference"), delegate("EqualEqual"))
  setMethod("!=", signature("ExternalReference", "ExternalReference"), delegate("NotEqual"))
  setMethod("<",  signature("ExternalReference", "ExternalReference"), delegate("LessThan"))
  # SWIG only generates `[`, which returns a list; `[[` gives the element.
  setMethod("[[", "ExternalReference", function(x, i, ...) x[i][[1]])
  # SWIG's own `[<-` does value[n], which is NULL for a wrapped element type.
  setMethod("[<-", "ExternalReference", function(x, i, j, ..., value) {
    setter <- do.call(`$`, list(x, "__setitem__"))
    if (is.null(setter)) stop("this class does not support assignment", call. = FALSE)
    vals <- if (is.list(value)) value else list(value)
    for (n in seq_along(i)) {
      setter(i = as.integer(i[n] - 1), x = vals[[((n - 1) %% length(vals)) + 1]])
    }
    x
  })
}
