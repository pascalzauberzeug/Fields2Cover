# SWIG R bindings (prototype, BUILD_R=OFF by default).
#
# Produces two artefacts that belong together:
#   fields2cover.so  - the compiled wrapper (SWIG names the .Call symbols
#                      PACKAGE='fields2cover', so the library MUST keep that
#                      base name)
#   fields2cover.R   - the generated S4 class / method layer
# plus swig/r/fixups.R, which repairs SWIG 4.4's broken scoped-enum tables.
#
# Usage from R:
#   dyn.load("fields2cover.so"); source("fields2cover.R"); source("fixups.R")
#   f2c_fix_enums(globalenv()); f2c_fix_missing_member()

find_program(R_EXECUTABLE R REQUIRED)

execute_process(COMMAND ${R_EXECUTABLE} CMD config --cppflags
  OUTPUT_VARIABLE R_CPPFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND ${R_EXECUTABLE} CMD config --ldflags
  OUTPUT_VARIABLE R_LDFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
separate_arguments(R_CPPFLAGS UNIX_COMMAND "${R_CPPFLAGS}")
separate_arguments(R_LDFLAGS UNIX_COMMAND "${R_LDFLAGS}")

set_source_files_properties(../${PROJECT_NAME}.i PROPERTIES CPLUSPLUS ON)

swig_add_library(fields2cover_r
  TYPE MODULE
  LANGUAGE r
  OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}
  OUTFILE_DIR ${CMAKE_CURRENT_BINARY_DIR}
  SOURCES ../${PROJECT_NAME}.i
)
target_include_directories(fields2cover_r PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../include
)
set_property(TARGET fields2cover_r PROPERTY SWIG_USE_TARGET_INCLUDE_DIRECTORIES TRUE)
target_compile_options(fields2cover_r PRIVATE ${R_CPPFLAGS})
target_link_libraries(fields2cover_r PRIVATE Fields2Cover ${R_LDFLAGS})

# .Call(..., PACKAGE='fields2cover') requires exactly this file name.
set_target_properties(fields2cover_r PROPERTIES
  PREFIX ""
  OUTPUT_NAME "fields2cover"
)

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/fixups.R
               ${CMAKE_CURRENT_BINARY_DIR}/fixups.R COPYONLY)

# `make check_r`. A plain add_test() would be ignored here: the root
# CMakeLists adds swig/ before it calls enable_testing().
add_custom_target(check_r
  COMMAND ${CMAKE_COMMAND} -E env
          F2C_DATA=${CMAKE_CURRENT_SOURCE_DIR}/../../data/
          ${R_EXECUTABLE} --no-save --quiet -f
          ${CMAKE_CURRENT_SOURCE_DIR}/../../tests/r/smoke_test.R
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS fields2cover_r
  COMMENT "Running the R smoke test"
)

set(F2C_R_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/R/site-library/fields2cover" CACHE PATH
    "Install directory of the fields2cover R bindings")
install(TARGETS fields2cover_r
  LIBRARY DESTINATION ${F2C_R_INSTALL_DIR}/libs
  COMPONENT r
)
install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/fields2cover.R
  ${CMAKE_CURRENT_SOURCE_DIR}/fixups.R
  DESTINATION ${F2C_R_INSTALL_DIR}/R
  COMPONENT r
)
