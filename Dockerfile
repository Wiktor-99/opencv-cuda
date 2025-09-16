FROM ubuntu:24.04 AS jetpack6

ARG L4T_RELEASE_MAJOR=36.4
ARG L4T_RELEASE_MINOR=4
ARG SOC="t234"
ARG L4T_RELEASE=$L4T_RELEASE_MAJOR

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc \
    bzip2 \
    can-utils \
    ca-certificates \
    gnupg2 \
    gstreamer1.0-alsa \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-tools \
    i2c-tools \
    iw \
    kbd \
    kmod \
    language-pack-en-base \
    libcanberra-gtk3-module \
    libdrm-dev \
    libgles2 \
    libglvnd-dev \
    libgtk-3-0 \
    libudev1 \
    libvulkan1 \
    libzmq5 \
    mtd-utils \
    parted \
    pciutils \
    python3 \
    python3-pexpect \
    python3-numpy \
    sox \
    udev \
    vulkan-tools \
    wget \
    curl \
    unzip \
    wireless-tools wpasupplicant \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean


RUN wget -P /etc/apt/trusted.gpg.d https://repo.download.nvidia.com/jetson/jetson-ota-public.asc
RUN wget -P /etc/apt/preferences.d https://repo.download.nvidia.com/jetson/nvidia-repo-pin-600
RUN echo "deb https://repo.download.nvidia.com/jetson/common r${L4T_RELEASE_MAJOR} main" > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list && \
    echo "deb https://repo.download.nvidia.com/jetson/t234 r${L4T_RELEASE_MAJOR} main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-toolkit-12-6 cuda-libraries-12-6 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
RUN apt-get update && apt-get download cuda-compat-12-6 \
    && dpkg-deb -R ./cuda-compat-12-6_*_arm64.deb ./cuda-compat \
    && cp -r ./cuda-compat/usr/local/* /usr/local/ \
    && rm -rf ./cuda-compat-12-6_*_arm64.deb ./cuda-compat
#
# Install nvidia-cudnn-dev for CuDNN developer packages
# Use nvidia-cudnn if need CuDNN runtime only
#
RUN apt-get update && apt-get install -y --no-install-recommends \
    nvidia-cudnn-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean


RUN apt-get update && apt-get download nvidia-l4t-gstreamer \
    && dpkg-deb -R ./nvidia-l4t-gstreamer_*_arm64.deb ./gstreamer \
    && cp -r ./gstreamer/usr/bin/* /usr/bin/ \
    && cp -r ./gstreamer/usr/lib/* /usr/lib/ \
    && rm -rf ./nvidia-l4t-gstreamer_*_arm64.deb ./gstreamer
RUN ldconfig

ENV CUDA_HOME="/usr/local/cuda"
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
RUN echo "/usr/lib/aarch64-linux-gnu/tegra" >> /etc/ld.so.conf.d/nvidia-tegra.conf && \
    echo "/usr/lib/aarch64-linux-gnu/tegra-egl" >> /etc/ld.so.conf.d/nvidia-tegra.conf
RUN rm /usr/share/glvnd/egl_vendor.d/50_mesa.json
RUN mkdir -p /usr/share/glvnd/egl_vendor.d/ && echo '\
{\
    "file_format_version" : "1.0.0",\
    "ICD" : {\
        "library_path" : "libEGL_nvidia.so.0"\
    }\
}' > /usr/share/glvnd/egl_vendor.d/10_nvidia.json
RUN mkdir -p /usr/share/egl/egl_external_platform.d/ && echo '\
{\
    "file_format_version" : "1.0.0",\
    "ICD" : {\
        "library_path" : "libnvidia-egl-wayland.so.1"\
    }\
}' > /usr/share/egl/egl_external_platform.d/nvidia_wayland.json
RUN ldconfig
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES all
# Clean up link to nvidia repo
RUN rm /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
RUN rm /etc/apt/preferences.d/nvidia-repo-pin-600
RUN rm /etc/apt/trusted.gpg.d/jetson-ota-public.asc


ARG OPENCV_VERSION=4.10.0
RUN apt update && \
    apt install -y --no-install-recommends checkinstall && \
    apt clean && rm -rf /var/lib/apt/lists/*

RUN curl -L https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip -o opencv-${OPENCV_VERSION}.zip && \
    curl -L https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip -o opencv_contrib-${OPENCV_VERSION}.zip && \
    unzip opencv-${OPENCV_VERSION}.zip && \
    unzip opencv_contrib-${OPENCV_VERSION}.zip && \
    rm opencv-${OPENCV_VERSION}.zip opencv_contrib-${OPENCV_VERSION}.zip

RUN cmake -B build -S /opencv-${OPENCV_VERSION} \
    -D WITH_CUDA=ON \
    -D WITH_CUDNN=ON \
    -D CUDA_ARCH_BIN="8.7" \
    -D CUDA_ARCH_PTX="" \
    -D OPENCV_GENERATE_PKGCONFIG=ON \
    -D OPENCV_EXTRA_MODULES_PATH=/opencv_contrib-${OPENCV_VERSION}/modules \
    -D WITH_GSTREAMER=ON \
    -D WITH_LIBV4L=ON \
    -D BUILD_opencv_python3=ON \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_EXAMPLES=OFF \
    -D CMAKE_BUILD_TYPE=RELEASE \
    -D PYTHON_DEFAULT_EXECUTABLE=/usr/bin/python3 && \
    cd build && make install -j $(nproc) && \
    checkinstall -y --install=no --pkgname=opencv --pkgversion=${OPENCV_VERSION} --pkgrelease=1 --arch=$BUILDPLATFORM
