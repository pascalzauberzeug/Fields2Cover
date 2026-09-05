/* Magic-method extensions shared by the Python and the R backend.
 *
 * These look Python-specific but are not: SWIG's R runtime (Lib/r/srun.swg)
 * dispatches R's `[` and `[<-` to __getitem__ / __setitem__ and
 * as(x, "character") / print() to __str__, i.e. it uses the same magic names
 * as the Python backend. Keep this file language-neutral; anything that only
 * Python understands (__repr__, __add__) belongs in swig/python/Fields2Cover.i.
 */

%define GeometryExtend(VT, T)
%extend VT {
  inline size_t __len__() const {return self->size();}
  T __getitem__(int i)  throw(std::out_of_range) {
    if (i >= self->size() || i < 0) {
      throw std::out_of_range("out of bounds access");
    }
    return (*self).getGeometry(i);
  }
  inline void __setitem__(size_t i, const T& v) throw(std::out_of_range) {
    if (i >= self->size() || i < 0) {
      throw std::out_of_range("out of bounds access");
    }
    self->setGeometry(i, v);
  }
}
%enddef

%define ArrayExtend(VT, T)
%extend VT {
  T __getitem__(int i)  throw(std::out_of_range) {
    if (i >= self->size() || i < 0) {
      throw std::out_of_range("out of bounds access");
    }
    return self->at(i);
  }
  inline void __setitem__(size_t i, const T& v) throw(std::out_of_range) {
    if (i >= self->size() || i < 0) {
      throw std::out_of_range("out of bounds access");
    }
    (*self)[i] = v;
  }
}
%enddef

%define VectorExtend(T)
  ArrayExtend(std::vector<T>, T)
%enddef

#if !defined(SWIGR)
// R converts std::vector of primitives to/from native atomic vectors
// (Lib/r/std_vector.i), so there is no wrapper class to extend.
VectorExtend(double)
VectorExtend(int)
VectorExtend(size_t)
#endif
VectorExtend(f2c::types::Point)
VectorExtend(f2c::types::MultiPoint)
VectorExtend(f2c::types::Swath)
VectorExtend(f2c::types::Swaths)
VectorExtend(f2c::types::Cell)
VectorExtend(f2c::types::Cells)
VectorExtend(f2c::types::LinearRing)
VectorExtend(f2c::types::LineString)
VectorExtend(f2c::types::Strip)
VectorExtend(f2c::types::PathState)
VectorExtend(f2c::types::Field)
VectorExtend(f2c::types::PathDirection)
VectorExtend(f2c::types::PathSectionType)

GeometryExtend(f2c::types::Cells, f2c::types::Cell)
GeometryExtend(f2c::types::Cell, f2c::types::LinearRing)
GeometryExtend(f2c::types::LinearRing, f2c::types::Point)
GeometryExtend(f2c::types::LineString, f2c::types::Point)
GeometryExtend(f2c::types::MultiPoint, f2c::types::Point)
GeometryExtend(f2c::types::MultiLineString, f2c::types::LineString)

ArrayExtend(f2c::types::Swaths, f2c::types::Swath)
ArrayExtend(f2c::types::SwathsByCells, f2c::types::Swaths)

%extend f2c::types::Path {
  f2c::types::PathState __getitem__(int i) {
    return (*self).getState(i);
  }
}
