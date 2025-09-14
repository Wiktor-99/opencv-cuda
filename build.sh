#!/bin/bash
set -xe

# Ensure BUILDARCH and TARGETARCH are defined (defaults can be overridden externally)
: "${BUILDARCH:=amd64}"
: "${TARGETARCH:=amd64}"

parse_arguemnts() {
    JETPACK="jetpack6"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --jetpack)
                echo "Jetpack version: $2"
                JETPACK=$2
                shift
                ;;
            --opencv-ubuntu24)
                echo "Enabling OpenCV build for Ubuntu 24.04"
                OPENCV_UBUNTU24="yes"
                ;;
            --opencv-version)
                echo "OpenCV version: $2"
                OPENCV_VERSION="$2"
                shift
                ;;
            --cuda-arch-bin)
                echo "CUDA ARCH BIN: $2"
                CUDA_ARCH_BIN="$2"
                shift
                ;;
            --cuda-version)
                echo "CUDA version override: $2"
                CUDA="$2"
                shift
                ;;
            *)
                echo "Unknown argument: $1"
                exit 1
                ;;
        esac
        shift
    done
}

## Legacy JP4/JP5 setup removed; Ubuntu 24.04 + JP6 only

setup_environment() {
    echo "Setting up environment variables..."
    export PATH="/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH="/usr/local/cuda-$CUDA/bin:${PATH}"
    if [ "$BUILDARCH" = "amd64" ] && [ "$TARGETARCH" = "arm64" ]; then
        export CUDA_HOME="/usr/local/cuda-$CUDA/targets/aarch64-linux"
        export HOST_CUDA="/usr/local/cuda-$CUDA"
    else
        export CUDA_HOME="/usr/local/cuda-$CUDA"
        export HOST_CUDA="/usr/local/cuda-$CUDA"
    fi
    export LD_LIBRARY_PATH="${CUDA_HOME}/lib:/usr/lib/${LIB_DIR_NAME}:${LD_LIBRARY_PATH}"
    export CUDA_STUB_DIR="${CUDA_HOME}/lib/stubs"
    export LIBRARY_PATH="${CUDA_HOME}/lib:/usr/lib/${LIB_DIR_NAME}:${CUDA_STUB_DIR}:${LIBRARY_PATH}"
    export CMAKE_PREFIX_PATH="${CUDA_HOME}:${CMAKE_PREFIX_PATH}"
    export PKG_CONFIG_PATH="/usr/lib/aarch64-linux-gnu/pkgconfig"
}

install_dependencies() {
    echo "Installing dependencies..."
    apt-get update
    apt-get install -y --no-install-recommends \
        git \
        pkg-config \
        build-essential \
        python3 \
        python3-dev \
        ninja-build \
        unzip \
        ca-certificates \
        wget \
        curl \
        gnupg
}

configure_architecture() {
    echo "Configuring architecture and compiler (Ubuntu 24.04 + JP6)..."
    if [ "$BUILDARCH" = "amd64" ]; then
        export NVARCH="x86_64"
        export LIB_DIR_NAME="x86_64-linux-gnu"
        export BUILD_EXTRA_ARG=""
        if [ "$TARGETARCH" = "amd64" ]; then
            export CC="gcc"
            export CXX="g++"
            apt-get install -y gcc g++
        else
            export CC="aarch64-linux-gnu-gcc"
            export CXX="aarch64-linux-gnu-g++"
            export BUILD_EXTRA_ARG="--arm64"
            export LIB_DIR_NAME="aarch64-linux-gnu"
            apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu crossbuild-essential-arm64
        fi
    else
        export NVARCH="arm64"
        export BUILD_EXTRA_ARG="--arm64"
        export LIB_DIR_NAME="aarch64-linux-gnu"
        export CC="gcc"
        export CXX="g++"
        apt-get install -y gcc g++
    fi
}

setup_cuda_repos() {
    echo "Setting up CUDA and Jetson repositories (Ubuntu 24.04 + JP6)..."
    # CUDA repo for Ubuntu 24.04
    curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVARCH}/3bf863cc.pub" | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVARCH} /" > /etc/apt/sources.list.d/cuda.list
    # # Cross-compile CUDA repo (aarch64 targets on x86_64 hosts)
    # if [ "$BUILDARCH" = "amd64" ] && [ "$TARGETARCH" = "arm64" ]; then
    #     curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/cross-linux-aarch64/3bf863cc.pub" | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-cross-keyring.gpg
    #     echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-cross-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/cross-linux-aarch64 /" > /etc/apt/sources.list.d/cuda-cross.list
    # fi
    # JetPack 6 (L4T r36) repos for Jetson (signed-by with Jetson key)
    curl -fsSL "https://repo.download.nvidia.com/jetson/jetson-ota-public.asc" | gpg --dearmor -o /usr/share/keyrings/nvidia-jetson-ota.gpg
    echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/nvidia-jetson-ota.gpg] https://repo.download.nvidia.com/jetson/common r36.3 main" > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
    echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/nvidia-jetson-ota.gpg] https://repo.download.nvidia.com/jetson/t234 r36.3 main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
    apt-get update
}

install_cuda_packages() {
    echo "Installing CUDA packages (Ubuntu 24.04)..."
    apt-get install -y --no-install-recommends \
        cuda-toolkit-12-6 \
        cuda-libraries-12-6 \
        cuda-cudart-12-6 \
        cuda-compat-12-6
}

## ONNX-related steps removed

# Ubuntu 24.04 OpenCV build flow
setup_opencv_ubuntu24() {
    echo "Configuring Ubuntu 24.04 OpenCV build environment..."
    : "${OPENCV_VERSION:=4.10.0}"
    : "${CUDA:=12.6}"
    # Map BUILDARCH to NVARCH for NVIDIA repo
    if [ "$BUILDARCH" = "amd64" ]; then
        export NVARCH="x86_64"
    else
        export NVARCH="arm64"
    fi
    export DEBIAN_FRONTEND=noninteractive
    if [ "$BUILDARCH" = "amd64" ] && [ "$TARGETARCH" = "arm64" ]; then
        dpkg --add-architecture arm64
        if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
            sed -i '/^Signed-By:/i Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources || true
        fi
        cat > /etc/apt/sources.list.d/ubuntu-arm64.sources <<'EOS'
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
Architectures: arm64

Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
Architectures: arm64
EOS
    fi
    apt-get update
    apt-get install -y --no-install-recommends gnupg ca-certificates curl
}

## CUDA repo is configured in setup_cuda_repos

generate_toolchain_if_cross() {
    if [ "$BUILDARCH" = "amd64" ] && [ "$TARGETARCH" = "arm64" ]; then
        echo "Generating CMake toolchain file for aarch64 cross-compilation..."
        cat > /tmp/toolchain-aarch64.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR "aarch64")
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_CUDA_COMPILER nvcc)
set(CMAKE_CUDA_HOST_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_FIND_ROOT_PATH "/usr/aarch64-linux-gnu")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
        export CMAKE_TOOLCHAIN_FILE=/tmp/toolchain-aarch64.cmake
    fi
}

install_opencv_deps_ubuntu24() {
    echo "Installing OpenCV build dependencies (Ubuntu 24.04)..."
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        unzip \
        wget \
        curl \
        pkg-config \
        checkinstall \
        ca-certificates \
        python3-dev \
        python3-numpy \
        libeigen3-dev \
        libgtk2.0-dev:"$TARGETARCH" \
        libavcodec-dev:"$TARGETARCH" \
        libavformat-dev:"$TARGETARCH" \
        libswscale-dev:"$TARGETARCH" \
        libgstreamer1.0-dev:"$TARGETARCH" \
        libgstreamer-plugins-base1.0-dev:"$TARGETARCH" \
        libjpeg-dev:"$TARGETARCH" \
        libpng-dev:"$TARGETARCH" \
        libtiff-dev:"$TARGETARCH" \
        libv4l-dev:"$TARGETARCH"
}

install_cuda_ubuntu24() {
    echo "Installing CUDA ${CUDA} packages..."
    apt-get install -y --no-install-recommends \
        cuda-toolkit-12-6 \
        cuda-libraries-12-6 \
        cuda-cudart-12-6 \
        cuda-compat-12-6
}

build_opencv_ubuntu24() {
    echo "Building OpenCV ${OPENCV_VERSION} with CUDA on Ubuntu 24.04..."
    work_dir="/tmp/opencv-build"
    rm -rf "$work_dir" && mkdir -p "$work_dir"
    cd "$work_dir"
    curl -L "https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip" -o "opencv-${OPENCV_VERSION}.zip"
    curl -L "https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip" -o "opencv_contrib-${OPENCV_VERSION}.zip"
    unzip -q "opencv-${OPENCV_VERSION}.zip"
    unzip -q "opencv_contrib-${OPENCV_VERSION}.zip"
    rm -f "opencv-${OPENCV_VERSION}.zip" "opencv_contrib-${OPENCV_VERSION}.zip"

    ARM_FLAGS=""
    if [ "$TARGETARCH" = "arm64" ]; then
        ARM_FLAGS="-D WITH_IPP=OFF -D OPENCV_ENABLE_IPP=OFF -D ENABLE_NEON=ON -D CPU_BASELINE=NEON -D CPU_DISPATCH= -D CMAKE_SYSTEM_PROCESSOR=aarch64"
    fi

    # Show host CUDA compiler visibility
    nvcc --version || true

    generate_toolchain_if_cross

    cmake -B build -S "${work_dir}/opencv-${OPENCV_VERSION}" \
        -D OPENCV_GENERATE_PKGCONFIG=ON \
        -D OPENCV_EXTRA_MODULES_PATH="${work_dir}/opencv_contrib-${OPENCV_VERSION}/modules" \
        -D WITH_GSTREAMER=ON \
        -D WITH_LIBV4L=ON \
        ${ARM_FLAGS} \
        ${CMAKE_TOOLCHAIN_FILE:+-D CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}} \
        -D BUILD_opencv_python3=ON \
        -D BUILD_TESTS=OFF \
        -D BUILD_PERF_TESTS=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D CMAKE_BUILD_TYPE=RELEASE \
        -D PYTHON_DEFAULT_EXECUTABLE=/usr/bin/python3 \
        -D WITH_CUDA=ON \
        -D WITH_CUDNN=ON \
        -D CUDA_ARCH_BIN="${CUDA_ARCH_BIN:-8.7}" \

    cmake --build build -- -j"$(nproc)"
    mkdir -p /artifacts
    cd build
    checkinstall -y --install=no --fstrans=yes \
        --pkgname=opencv \
        --pkgversion="${OPENCV_VERSION}" \
        --pkgrelease=1 \
        --requires="libgstreamer1.0-0,libgstreamer-plugins-base1.0-0,libjpeg8,libpng16-16,libtiff6,libavcodec60,libavformat60,libswscale7" \
        --nodoc \
        make install
    mv /tmp/opencv-build/build/opencv_*.deb /artifacts/opencv_${OPENCV_VERSION}.deb
}

cleanup() {
    echo "Cleaning up..."
    rm -rf /pdk_files
    rm -rf /workspace
    rm -rf /usr/local/cuda-$CUDA/
    rm -rf /var/cuda-repo-cross-aarch64-$APT_REPO-$CUDA_VERSION_DASH-local
    rm -rf /usr/lib/aarch64-linux-gnu
}

main() {
    parse_arguemnts "$@"

    setup_opencv_ubuntu24
    setup_environment
    install_dependencies
    configure_architecture
    setup_cuda_repos
    install_opencv_deps_ubuntu24
    install_cuda_packages
    build_opencv_ubuntu24
    cleanup
}

main "$@"

