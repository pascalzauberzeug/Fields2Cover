function(f2c_declare_dependencies)

  include(FetchContent)
  if(${CMAKE_VERSION} VERSION_LESS 3.14)
    macro(FetchContent_MakeAvailable NAME)
      FetchContent_GetProperties(${NAME})
      if(NOT ${NAME}_POPULATED)
        FetchContent_Populate(${NAME})
        add_subdirectory(${${NAME}_SOURCE_DIR} ${${NAME}_BINARY_DIR})
      endif(NOT ${NAME}_POPULATED)
    endmacro(FetchContent_MakeAvailable)
  endif(${CMAKE_VERSION} VERSION_LESS 3.14)


  set(ORTOOLS_TARGET "")
  if(USE_ORTOOLS_FETCH_SRC)
    message(STATUS "or-tools -- Downloading and building from source (static)")
    # Static, so nothing of or-tools has to be installed next to Fields2Cover
    # or found at runtime. Fields2Cover only uses the routing library
    # (ortools/constraint_solver), so the samples, the other language
    # bindings, flatzinc, MathOpt and the extra MIP/LP backends are dead
    # weight here. USE_GUROBI/USE_XPRESS stay at their defaults: or-tools
    # compiles those interfaces unconditionally and only dlopen()s the
    # solvers, so turning them off breaks the link instead of slimming it.
    set(F2C_SAVED_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
    set(BUILD_SHARED_LIBS OFF)
    set(BUILD_DEPS ON)
    set(BUILD_SAMPLES OFF)
    set(BUILD_EXAMPLES OFF)
    set(BUILD_FLATZINC OFF)
    set(BUILD_MATH_OPT OFF)
    set(BUILD_TESTING OFF)
    set(BUILD_DOC OFF)
    set(BUILD_PYTHON OFF)   # or-tools' own option, not Fields2Cover's
    set(BUILD_JAVA OFF)
    set(BUILD_DOTNET OFF)
    set(USE_SCIP OFF)
    set(USE_GLPK OFF)
    set(USE_HIGHS OFF)
    set(USE_COINOR OFF)
    set(USE_PDLP OFF)
    FetchContent_Declare(ortools
      GIT_REPOSITORY https://github.com/google/or-tools.git
      GIT_TAG v9.9
    )
    FetchContent_MakeAvailable(ortools)
    set(BUILD_SHARED_LIBS ${F2C_SAVED_BUILD_SHARED_LIBS})
    set(ORTOOLS_TARGET "ortools")
  elseif(USE_ORTOOLS_VENDOR)
    find_package(ortools_vendor REQUIRED)
  else()
    find_package(ortools_vendor QUIET)
    find_package(ortools CONFIG QUIET)
    if(NOT ortools_FOUND)
      if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
        message(FATAL_ERROR
          "or-tools was not found and the release tarballs below are Linux-only "
          "(current platform: ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR}). "
          "Install or-tools with your package manager (e.g. `brew install or-tools` "
          "on macOS) and pass -DCMAKE_PREFIX_PATH so find_package can locate it, "
          "or build it from source with -DUSE_ORTOOLS_FETCH_SRC=ON.")
      elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
        message(STATUS "or-tools -- Downloading and installing from release tarball")
        message(STATUS "Target architecture is AMD64")
        FetchContent_Declare(ortools FETCHCONTENT_UPDATES_DISCONNECTED
          URL https://github.com/google/or-tools/releases/download/v9.9/or-tools_amd64_ubuntu-22.04_cpp_v9.9.3963.tar.gz
          URL_HASH SHA256=a611133f4e9b75661c637347ebadff79539807cf8966eb9c176c2c560aad0a84
        )
      elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
        message(STATUS "or-tools -- Downloading and installing from release tarball")
        message(STATUS "Target architecture is ARM64")
        FetchContent_Declare(ortools FETCHCONTENT_UPDATES_DISCONNECTED
          URL https://github.com/google/or-tools/releases/download/v9.9/or-tools_arm64_debian-11_cpp_v9.9.3963.tar.gz
          URL_HASH SHA256=f308a06d89dce060f74e6fec4936b43f4bdf4874d18c131798697756200f4e7a
        )
      else()
        message(FATAL_ERROR
          "No or-tools release tarball is available for this architecture "
          "(${CMAKE_SYSTEM_PROCESSOR}). Install or-tools with your package "
          "manager and pass -DCMAKE_PREFIX_PATH so find_package can locate it, "
          "or build it from source with -DUSE_ORTOOLS_FETCH_SRC=ON.")
      endif()
      #NOTE: FetchContent_GetProperties variables only available in called scope
      FetchContent_GetProperties(ortools)
      if(NOT ortools_POPULATED)
        FetchContent_Populate(ortools)
      endif()
      # Set all dependency dirs explicitly for cross-compilation scenarios
      set(ORTOOLS_CMAKE_DIR "${ortools_SOURCE_DIR}/lib/cmake")
      set(ortools_DIR "${ORTOOLS_CMAKE_DIR}/ortools")
      set(absl_DIR "${ORTOOLS_CMAKE_DIR}/absl")
      set(protobuf_DIR "${ORTOOLS_CMAKE_DIR}/protobuf")
      set(Protobuf_DIR "${ORTOOLS_CMAKE_DIR}/protobuf")
      set(re2_DIR "${ORTOOLS_CMAKE_DIR}/re2")
      set(Cbc_DIR "${ORTOOLS_CMAKE_DIR}/Cbc")
      set(Cgl_DIR "${ORTOOLS_CMAKE_DIR}/Cgl")
      set(Clp_DIR "${ORTOOLS_CMAKE_DIR}/Clp")
      set(CoinUtils_DIR "${ORTOOLS_CMAKE_DIR}/CoinUtils")
      set(Osi_DIR "${ORTOOLS_CMAKE_DIR}/Osi")
      set(SCIP_DIR "${ORTOOLS_CMAKE_DIR}/scip")
      set(utf8_range_DIR "${ORTOOLS_CMAKE_DIR}/utf8_range")
      find_package(ortools CONFIG REQUIRED)
      if(NOT ortools_FOUND)
        message(FATAL_ERROR "Failed to find ortools in release tarball")
      endif()

      # libortools.so is the only piece of the tarball that is needed at
      # runtime: the release ships absl, protobuf, re2, Coin-OR and SCIP as
      # static archives that are already linked into it, and or-tools is a
      # private dependency, so its headers and CMake config are not part of
      # the Fields2Cover install interface either. Copying the whole tarball
      # (bin, include, share, examples, ~100 archives) into the install prefix
      # added hundreds of megabytes for no benefit.
      #NOTE: CMake 3.21 introduces IMPORTED_RUNTIME_ARTIFACTS, which would let
      # us install the imported ortools::ortools target directly.
      include(GNUInstallDirs)
      install(
        DIRECTORY "${ortools_SOURCE_DIR}/lib/"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}
        FILES_MATCHING
          PATTERN "libortools.so*"
          PATTERN "cmake" EXCLUDE
          PATTERN "pkgconfig" EXCLUDE
      )
    endif(NOT ortools_FOUND)
  endif()

  # tinyxml2 is a tiny private dependency. Vendoring it as a static library
  # drops one preinstall requirement and one runtime shared library on every
  # platform; it is linked into libFields2Cover, so nothing has to be shipped
  # alongside it.
  set(F2C_SAVED_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
  set(BUILD_SHARED_LIBS OFF)
  set(tinyxml2_BUILD_TESTING OFF)
  FetchContent_Declare(tinyxml2 FETCHCONTENT_UPDATES_DISCONNECTED
    GIT_REPOSITORY https://github.com/leethomason/tinyxml2.git
    GIT_TAG 10.0.0
    GIT_SHALLOW TRUE
  )
  FetchContent_MakeAvailable(tinyxml2)
  set(BUILD_SHARED_LIBS ${F2C_SAVED_BUILD_SHARED_LIBS})

  FetchContent_Declare(steering_functions FETCHCONTENT_UPDATES_DISCONNECTED
    GIT_REPOSITORY https://github.com/Fields2Cover/steering_functions.git
    GIT_TAG 13e3f5658144b3832fb1eb31a0e2f5a3cbf57db9
  )
  FetchContent_Declare(matplot FETCHCONTENT_UPDATES_DISCONNECTED
    GIT_REPOSITORY https://github.com/alandefreitas/matplotplusplus.git
    GIT_TAG 5d01eb3695b07634a2b6642fd423740dea9b026c
  )

  FetchContent_Declare(json FETCHCONTENT_UPDATES_DISCONNECTED
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG 4424a0fcc1c7fa640b5c87d26776d99150dacd10
  )

  FetchContent_MakeAvailable(steering_functions matplot json)
endfunction()
