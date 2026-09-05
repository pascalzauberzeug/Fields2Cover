
cmake_minimum_required(VERSION 3.12.4...3.22)

project(Fields2Cover
  VERSION 2.1.0
  DESCRIPTION "Fields2Cover is a complete coverage path planning package for autonomous robots"
  HOMEPAGE_URL "http://fields2cover.github.io"
  LANGUAGES CXX
)



option(ALLOW_PARALLELIZATION "Allow parallel algorithms" ON)
option(BUILD_TUTORIALS "Build tutorials" ON)
option(BUILD_PYTHON "Build Python SWIG module" ON)
option(BUILD_DOC "Build Documentation" OFF)
# Declared here so that a vendored dependency's include(CTest) cannot flip it
# on behind our back and pull Fields2Cover's own GTest-based tests into a
# build that did not ask for them.
option(BUILD_TESTING "Build the tests" OFF)
option(BUILD_SHARED_LIBS "Build shared library(.so)" ON)
option(USE_ORTOOLS_RELEASE "Get or-tools from release tarball" OFF)
option(USE_ORTOOLS_FETCH_SRC "Get or-tools from source" OFF)
option(USE_ORTOOLS_VENDOR "Get or-tools from ortools_vendor" OFF)


# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)



if(POLICY CMP0094)
  cmake_policy(SET CMP0094 NEW)
endif(POLICY CMP0094)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif(POLICY CMP0135)


if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
  # set(CMAKE_BUILD_TYPE Testing)
  # set(CMAKE_BUILD_TYPE Debug)
endif(NOT CMAKE_BUILD_TYPE)


list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules")


# Dependencies
find_package(Threads REQUIRED)
find_package(Gnuplot)
find_package(GDAL 3.0 REQUIRED)
find_package(Eigen3 REQUIRED)
find_library(MATH_LIBRARY m)

# Prefer the imported target from GEOS' CMake config (available since GEOS 3.8);
# fall back to the bare linker flag for distros that don't ship the config.
find_package(GEOS CONFIG QUIET)
set(F2C_GEOS_FROM_CONFIG ${GEOS_FOUND})  # consumed by Fields2CoverConfig.cmake.in
if(GEOS_FOUND)
  set(F2C_GEOS_C_LIBRARY GEOS::geos_c)
else()
  set(F2C_GEOS_C_LIBRARY -lgeos_c)
endif()


set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(THREADS_PREFER_PTHREAD_FLAG ON)


include(cmake/F2CUtils.cmake)
f2c_declare_dependencies()


file(GLOB_RECURSE fields2cover_src
  "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp"
)

add_library(Fields2Cover ${fields2cover_src})


target_include_directories(Fields2Cover
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(Fields2Cover
  PUBLIC
    GDAL::GDAL
    ${CMAKE_THREAD_LIBS_INIT}
    ${F2C_GEOS_C_LIBRARY}
    ${MATH_LIBRARY}
  PRIVATE
    ortools::ortools
    nlohmann_json::nlohmann_json
    tinyxml2
    steering_functions
    matplot
)

if(ALLOW_PARALLELIZATION)
  # Prefer the imported target from oneTBB's CMake config. If oneTBB is not
  # installed, vendor it as a static library instead of guessing a bare -ltbb:
  # that drops a preinstall requirement and leaves no runtime shared library.
  find_package(TBB CONFIG QUIET)
  set(F2C_TBB_FROM_CONFIG ${TBB_FOUND})  # consumed by Fields2CoverConfig.cmake.in
  if(NOT TBB_FOUND)
    message(STATUS "oneTBB -- not found, building it from source as a static library")
    include(FetchContent)
    set(F2C_SAVED_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
    set(BUILD_SHARED_LIBS OFF)
    # oneTBB still declares cmake_minimum_required(VERSION 3.5), so CMP0077 is
    # OLD inside it and its option() calls ignore plain variables. These have
    # to be cache entries to take effect -- without them oneTBB builds its
    # whole test suite.
    set(TBB_TEST OFF CACHE BOOL "" FORCE)
    set(TBB_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(TBB_STRICT OFF CACHE BOOL "" FORCE)
    set(TBBMALLOC_BUILD OFF CACHE BOOL "" FORCE)  # only TBB::tbb is used
    FetchContent_Declare(tbb FETCHCONTENT_UPDATES_DISCONNECTED
      GIT_REPOSITORY https://github.com/uxlfoundation/oneTBB.git
      GIT_TAG v2022.0.0
      GIT_SHALLOW TRUE
    )
    FetchContent_MakeAvailable(tbb)
    set(BUILD_SHARED_LIBS ${F2C_SAVED_BUILD_SHARED_LIBS})
    set(F2C_TBB_VENDORED TRUE)
  endif()
  target_link_libraries(Fields2Cover PRIVATE TBB::tbb)
endif(ALLOW_PARALLELIZATION)




# Compiler options
include(cmake/F2CCompilerOptions.cmake)
f2c_set_compiler_options(Fields2Cover)


include(GNUInstallDirs)
set(F2C_INSTALL_CMAKEDIR ${CMAKE_INSTALL_LIBDIR}/cmake/Fields2Cover)

# Vendored static private dependencies have to travel in the export set so
# that Fields2CoverTargets.cmake can resolve them for C++ consumers.
set(F2C_VENDORED_TARGETS steering_functions matplot tinyxml2)
if(F2C_TBB_VENDORED)
  list(APPEND F2C_VENDORED_TARGETS tbb)
endif()

install(TARGETS Fields2Cover ${F2C_VENDORED_TARGETS}
  EXPORT Fields2CoverTargets
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(DIRECTORY include/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Wheels install only COMPONENT python, and with BUILD_SHARED_LIBS=OFF the
# export set would miss Fields2Cover's private deps (nlohmann_json, matplot).
if(NOT DEFINED SKBUILD)
  include(CMakePackageConfigHelpers)
  configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/Fields2CoverConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/Fields2CoverConfig.cmake
    INSTALL_DESTINATION ${F2C_INSTALL_CMAKEDIR}
    PATH_VARS CMAKE_INSTALL_INCLUDEDIR CMAKE_INSTALL_LIBDIR
  )

  write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/Fields2CoverConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
  )

  install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/Fields2CoverConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/Fields2CoverConfigVersion.cmake
    DESTINATION ${F2C_INSTALL_CMAKEDIR}
  )

  install(EXPORT Fields2CoverTargets
    FILE Fields2CoverTargets.cmake
    NAMESPACE Fields2Cover::
    DESTINATION ${F2C_INSTALL_CMAKEDIR}
  )
endif()


#####################################################
#################### tutorials ######################
#####################################################

if (BUILD_TUTORIALS)
  add_subdirectory(tutorials)
endif(BUILD_TUTORIALS)

#####################################################
######################### swig ######################
#####################################################

if (BUILD_PYTHON)
  add_subdirectory(swig)
endif(BUILD_PYTHON)

#####################################################
######################### test ######################
#####################################################

if(BUILD_TESTING AND GNUPLOT_FOUND)
  find_package(GTest REQUIRED)
  include(CTest)
  enable_testing()
  add_custom_target(check COMMAND
    GTEST_COLOR=1 ${CMAKE_CTEST_COMMAND} --verbose --test-dir tests/
  )
  add_subdirectory(tests)
endif(BUILD_TESTING AND GNUPLOT_FOUND)

#####################################################
######################### docs ######################
#####################################################


if(BUILD_DOC)
  add_subdirectory(docs)
endif(BUILD_DOC)

set(CMAKE_EXPORT_PACKAGE_REGISTRY ON)
export(PACKAGE Fields2Cover)

# Packaging support
set(CPACK_PACKAGE_VENDOR "Wageningen University & Research")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY ${PACKAGE_DESCRIPTION})
set(CPACK_PACKAGE_VERSION_MAJOR ${FIELDS2COVER_VERSION_MAJOR})
set(CPACK_PACKAGE_VERSION_MINOR ${FIELDS2COVER_VERSION_MINOR})
set(CPACK_PACKAGE_VERSION_PATCH ${FIELDS2COVER_VERSION_PATCH})
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_RESOURCE_FILE_README "${CMAKE_CURRENT_SOURCE_DIR}/README.md")
set(CPACK_PACKAGE_CONTACT "gonzalo.miermunoz@wur.nl")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Gonzalo Mier<${CPACK_PACKAGE_CONTACT}>")

set(CPACK_SOURCE_GENERATOR "TGZ;ZIP")
set(CPACK_SOURCE_IGNORE_FILES .git dist .*build.* \\\\.DS_Store .dockerignore)
include(CPack)

