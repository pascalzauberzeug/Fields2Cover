Python API
==========

The ``fields2cover`` python package is generated from the C++ library with
SWIG: same classes, same methods, same signatures. Basic types keep their C++
name (``f2c.Point``, ``f2c.Robot``), algorithm classes carry their module as
a prefix (``f2c.HG_*``, ``f2c.SG_*``, ``f2c.RP_*``, ``f2c.PP_*``,
``f2c.OBJ_*``, ``f2c.DECOMP_*``). Docstrings are translated from the C++
doxygen comments; where they are missing, check the corresponding class in
the :doc:`C++ API <../api/f2c_library>`.

.. toctree::
   :maxdepth: 1
   :glob:

   python_api/*
