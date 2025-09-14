FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS cross_compile_base_from_amd64_to_amd64
ENV HOST_TARGET=amd64-linux-gnu
ENV NVARCH=x86_64

FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS cross_compile_base_from_arm64_to_arm64
ENV HOST_TARGET=arm64-linux-gnu
ENV NVARCH=arm64

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


RUN apt update && apt install -y --no-install-recommends gnupg2 curl ca-certificates && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/cross-linux-aarch64/3bf863cc.pub | apt-key add - && \
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/cross-linux-aarch64 /" > /etc/apt/sources.list.d/cuda.list && \
    apt update && apt install -y --no-install-recommends \
      cudnn-cross-aarch64=9.12.0-1 \
      libcudnn9-cross-aarch64-cuda-13=9.12.0.46-1 \
      cudnn9-cross-aarch64=9.12.0-1 && \
    rm -rf /var/lib/apt/lists/*

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
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
ENV HOST_TARGET=aarch64-linux-gnu
ENV NVARCH=x86_64

FROM --platform=$BUILDPLATFORM cross_compile_base_from_${BUILDARCH}_to_${TARGETARCH} AS opencv_builder
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG BUILDARCH

ARG OPENCV_VERSION=4.10.0
COPY build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh && \
    BUILDARCH=$BUILDARCH TARGETARCH=$TARGETARCH \
    /usr/local/bin/build.sh --opencv-ubuntu24 --opencv-version ${OPENCV_VERSION} --cuda-arch-bin 8.7
