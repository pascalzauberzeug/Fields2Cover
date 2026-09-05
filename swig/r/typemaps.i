/* R-specific typemaps. Must be seen before any declaration is parsed, so this
 * file is included near the top of swig/Fields2Cover.i.
 *
 * SWIG's R backend leaves the R-side coercion for float/double empty
 * (Lib/r/rtype.swg) and then calls REAL() on the SEXP in C. An R integer -
 * which is what `1L` and every element of `1:n` is - therefore fails with
 *   REAL() can only be applied to a 'numeric', not a 'integer'
 * even though the R type check (is.numeric) accepted it. Coerce explicitly.
 * Pointers are left alone: they are used for output arguments.
 */
%typemap(scoercein) float, float&, const float&,
                    double, double&, const double&
  %{  $input = as.numeric($input);  %}
