/* Minimal reproducer for the SWIG 4.4.0 R-backend scoped-enum bug.
 * See ci/enum_bug_min.sh. Independent of Fields2Cover.
 *
 * For `enum class Scoped`, SWIG emits
 *   defineEnumeration("_ns__Scoped", .values = c("A" = .Call('R_swig_Scoped_A_get', ...)))
 * but registers the wrapper as R_swig_Scoped_Scoped_A_get, so every enum table
 * fails to evaluate. Plain `enum Plain` is unaffected.
 */
%module enumtest
%{
namespace ns {
enum class Scoped { A = 0, B = 1 };
enum Plain { P_A = 0, P_B = 1 };
inline int useScoped(Scoped s) { return static_cast<int>(s); }
inline Scoped retScoped() { return Scoped::B; }
}
%}

namespace ns {
enum class Scoped { A = 0, B = 1 };
enum Plain { P_A = 0, P_B = 1 };
int useScoped(Scoped s);
Scoped retScoped();
}
