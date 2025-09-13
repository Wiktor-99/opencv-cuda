FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS cross_compile_base_from_amd64_to_amd64
ENV HOST_TARGET=amd64-linux-gnu
ENV NVARCH=arm64

FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS cross_compile_base_from_arm64_to_arm64
ENV HOST_TARGET=arm64-linux-gnu
ENV NVARCH=x86_64

FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS cross_compile_base_from_amd64_to_arm64
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 && \
    sed -i '/^Signed-By:/i Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources && \
    echo $'Types: deb\n\
URIs: http://ports.ubuntu.com/ubuntu-ports/\n\
Suites: noble noble-updates noble-backports\n\
Components: main restricted universe multiverse\n\
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\
Architectures: arm64\n\
\n\
Types: deb\n\
URIs: http://ports.ubuntu.com/ubuntu-ports/\n\
Suites: noble-security\n\
Components: main restricted universe multiverse\n\
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\
Architectures: arm64' > /etc/apt/sources.list.d/ubuntu-arm64.sources

RUN apt update && \
    apt install --no-install-recommends -y \
        gcc-aarch64-linux-gnu=4:13.2.0-7ubuntu1 \
        g++-aarch64-linux-gnu=4:13.2.0-7ubuntu1 \
        gfortran-aarch64-linux-gnu=4:13.2.0-7ubuntu1 \
        crossbuild-essential-arm64=12.10ubuntu1 && \
        apt clean && rm -rf /var/lib/apt/lists/*

ENV CC=aarch64-linux-gnu-gcc
ENV CXX=aarch64-linux-gnu-g++
ENV FC=aarch64-linux-gnu-gfortran
ENV PKG_CONFIG_PATH /usr/lib/aarch64-linux-gnu/pkgconfig
ENV HOST_TARGET=aarch64-linux-gnu
ENV NVARCH=cross-linux-aarch64


FROM --platform=$BUILDPLATFORM cross_compile_base_from_${BUILDARCH}_to_${TARGETARCH} AS opencv_builder
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG BUILDARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential:$TARGETARCH \
    cmake:$TARGETARCH \
    git:$TARGETARCH \
    unzip:$TARGETARCH \
    wget:$TARGETARCH \
    curl:$TARGETARCH \
    pkg-config:$TARGETARCH \
    checkinstall:$TARGETARCH \
    ca-certificates:$TARGETARCH \
    v4l-utils:$TARGETARCH\
    qv4l2:$TARGETARCH \
    python3-dev:$TARGETARCH \
    python3-numpy:$TARGETARCH \
  && apt-get install -y --no-install-recommends \
    libgtk2.0-dev:$TARGETARCH \
    libavcodec-dev:$TARGETARCH \
    libavformat-dev:$TARGETARCH \
    libswscale-dev:$TARGETARCH \
    libgstreamer1.0-dev:$TARGETARCH \
    libgstreamer-plugins-base1.0-dev:$TARGETARCH \
    libjpeg-dev:$TARGETARCH \
    libpng-dev:$TARGETARCH \
    libtiff-dev:$TARGETARCH \
    libv4l-dev:$TARGETARCH \
  && apt-get clean && rm -rf /var/lib/apt/lists/*


RUN apt-get update && apt-get install -y --no-install-recommends gnupg2 && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVARCH}/3bf863cc.pub | apt-key add - && \
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVARCH} /" > /etc/apt/sources.list.d/cuda.list && \
    apt-get update && apt-get install -y --no-install-recommends \
      cuda-toolkit-12-6 \
      cuda-libraries-12-6 \
      cuda-cudart-12-6 \
      cuda-compat-12-6 \
      cuda-cross-aarch64-12-6 && \
    rm -rf /var/lib/apt/lists/*

ARG OPENCV_VERSION=4.10.0
WORKDIR /

RUN curl -L https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip -o opencv-${OPENCV_VERSION}.zip && \
    curl -L https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip -o opencv_contrib-${OPENCV_VERSION}.zip && \
    unzip opencv-${OPENCV_VERSION}.zip && \
    unzip opencv_contrib-${OPENCV_VERSION}.zip && \
    rm opencv-${OPENCV_VERSION}.zip opencv_contrib-${OPENCV_VERSION}.zip

RUN cmake -B build -S /opencv-${OPENCV_VERSION} \
      -D OPENCV_GENERATE_PKGCONFIG=ON \
      -D OPENCV_EXTRA_MODULES_PATH=/opencv_contrib-${OPENCV_VERSION}/modules \
      -D WITH_GSTREAMER=ON \
      -D WITH_LIBV4L=ON \
      -D BUILD_opencv_python3=ON \
      -D BUILD_TESTS=OFF \
      -D BUILD_PERF_TESTS=OFF \
      -D BUILD_EXAMPLES=OFF \
      -D CMAKE_BUILD_TYPE=RELEASE \
      -D PYTHON_DEFAULT_EXECUTABLE=/usr/bin/python3 \
      -D WITH_CUDA=ON \
      -D WITH_CUDNN=OFF \
      -D CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda \
      -D CUDA_ARCH_BIN=8.7 \
      -D CUDA_ARCH_PTX="" && \
    cmake --build build -- -j"$(nproc)" && \
    cd build && \
    checkinstall -y --install=no --fstrans=yes \
      --pkgname=opencv \
      --pkgversion=${OPENCV_VERSION} \
      --pkgrelease=1 \
      --arch=$TARGETARCH \
      --requires="libgstreamer1.0-0,libgstreamer-plugins-base1.0-0,libjpeg8,libpng16-16,libtiff6,libavcodec60,libavformat60,libswscale7" \
      --nodoc \
      make install

RUN mkdir -p /artifacts && mv /build/opencv_*.deb /artifacts/opencv.deb

