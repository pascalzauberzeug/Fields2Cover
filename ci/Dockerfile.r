# Experiment image for the R/SWIG feasibility study (GitHub issue #246).
#
# Mirrors the flow of the repo-root Dockerfile (GDAL base + system deps + SWIG +
# or-tools + a full Fields2Cover build) and adds r-base / r-base-dev on top, so
# the SWIG R backend can be exercised against the real library.
#
# or-tools is pulled by CMake itself (USE_ORTOOLS_RELEASE path in
# cmake/F2CUtils.cmake), which picks the right tarball for amd64/arm64.
#
# Build (~20-30 min the first time, then cached):
#   docker build -f ci/Dockerfile.r -t f2c-r .
# Iterate without rebuilding the C++ library:
#   docker run --rm -it -v "$PWD":/work -w /work f2c-r bash

FROM ghcr.io/osgeo/gdal:ubuntu-small-3.13.1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update --allow-insecure-repositories -y && \
    apt-get install -y --allow-unauthenticated --no-install-recommends \
        ca-certificates curl git cmake build-essential g++ \
        libboost-dev libgeos-dev libtbb-dev libeigen3-dev \
        libtinyxml2-dev nlohmann-json3-dev libgtest-dev \
        libpython3-dev python3 python3-pip \
        gnuplot swig \
        r-base r-base-dev \
    && rm -rf /var/lib/apt/lists/*

# BUILD_TESTING=ON needs the gtest static libs, which Ubuntu ships as sources.
RUN cmake -S /usr/src/googletest -B /tmp/gtest-build \
    && cmake --build /tmp/gtest-build -j"$(nproc)" \
    && cmake --install /tmp/gtest-build \
    && rm -rf /tmp/gtest-build

# Record the exact tool versions used by the experiment.
RUN swig -version > /versions.txt && \
    (R --version | head -1) >> /versions.txt && \
    (cmake --version | head -1) >> /versions.txt && \
    (g++ --version | head -1) >> /versions.txt && \
    cat /versions.txt

COPY . /src/fields2cover
WORKDIR /src/fields2cover/build

# BUILD_PYTHON=ON keeps the known-good reference target inside the image.
RUN cmake -DBUILD_PYTHON=ON \
          -DBUILD_TUTORIALS=OFF \
          -DBUILD_TESTING=OFF \
          -DBUILD_DOC=OFF \
          -DCMAKE_BUILD_TYPE=Release .. \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

WORKDIR /work
CMD ["bash"]
