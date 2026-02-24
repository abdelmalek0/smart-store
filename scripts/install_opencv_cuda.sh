#!/bin/bash
set -e

# ==========================================
# OpenCV 4.10.0 with CUDA & cuDNN 9.0
# Optimized for Ubuntu/Debian
# ==========================================

echo "[INFO] Starting OpenCV with CUDA installation..."

# 1. Install required tools and system-level multimedia libraries
echo "[INFO] Installing prerequisite packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake git wget unzip yasm pkg-config \
    libswscale-dev libtbb-dev libjpeg-dev libpng-dev libtiff-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswresample-dev \
    libpq-dev libv4l-dev libxvidcore-dev libx264-dev \
    libgtk-3-dev libopenblas-dev gfortran gcc-13 g++-13

OPENCV_VERSION="4.10.0"
INSTALL_DIR="/opt/opencv-cuda"
BUILD_DIR="/tmp/opencv_build"

# 2. Prepare Directories
mkdir -p ${BUILD_DIR}
cd ${BUILD_DIR}

# Clean existing build artifacts to prevent -fPIC / Linker errors
if [ -d "opencv-${OPENCV_VERSION}/build" ]; then
    echo "[INFO] Cleaning previous build directory..."
    rm -rf "opencv-${OPENCV_VERSION}/build"
fi

# 3. Download Sources
echo "[INFO] Downloading OpenCV ${OPENCV_VERSION}..."
[ ! -f "opencv.zip" ] && wget -q -O opencv.zip https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip
[ ! -f "opencv_contrib.zip" ] && wget -q -O opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip

if [ ! -d "opencv-${OPENCV_VERSION}" ]; then
    unzip -q opencv.zip
    unzip -q opencv_contrib.zip
fi

# 4. Install cuDNN 9.0 (Redistributable)
echo "[INFO] Setting up cuDNN 9.0..."
if [ ! -f "cudnn.tar.xz" ]; then
    wget -q -O cudnn.tar.xz https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-9.0.0.312_cuda12-archive.tar.xz
fi

tar -xf cudnn.tar.xz
# Use -u (update) to avoid overwriting if newer, and ensure we copy to the correct lib path
sudo cp -v cudnn-linux-x86_64-9.0.0.312_cuda12-archive/include/* /usr/include/
sudo cp -v cudnn-linux-x86_64-9.0.0.312_cuda12-archive/lib/* /usr/lib/x86_64-linux-gnu/

# 5. Set Compiler Alternatives
echo "[INFO] Setting GCC 13 as default..."
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 --slave /usr/bin/g++ g++ /usr/bin/g++-13
sudo update-alternatives --set gcc /usr/bin/gcc-13

# 6. Configure Build
cd opencv-${OPENCV_VERSION}
mkdir build && cd build

echo "[INFO] Running CMake configuration..."

# KEY FIXES APPLIED BELOW:
# - CMAKE_IGNORE_PATH: Prevents picking up broken static ffmpeg in /usr/local
# - CUDA_ARCH_BIN: Kept 8.6/8.9 for modern GPUs (Adjust if using older cards)

cmake -D CMAKE_BUILD_TYPE=RELEASE \
      -D CMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
      -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib-${OPENCV_VERSION}/modules \
      -D WITH_CUDA=ON \
      -D WITH_CUDNN=ON \
      -D OPENCV_DNN_CUDA=ON \
      -D WITH_CUBLAS=ON \
      -D ENABLE_FAST_MATH=ON \
      -D CUDA_FAST_MATH=ON \
      -D BUILD_SHARED_LIBS=ON \
      -D BUILD_opencv_python3=ON \
      -D BUILD_opencv_cudacodec=OFF \
      -D WITH_FFMPEG=ON \
      -D CMAKE_IGNORE_PATH=/usr/local/lib \
      -D CUDA_ARCH_BIN="8.6;8.9" \
      -D CUDA_ARCH_PTX="8.9" \
      -D OPENCV_GENERATE_PKGCONFIG=ON \
      -D OPENCV_EXTRA_CXX_FLAGS="-Wno-error=deprecated-declarations" \
      -D CUDA_NVCC_FLAGS="-allow-unsupported-compiler" \
      -D BUILD_TESTS=OFF \
      -D BUILD_PERF_TESTS=OFF \
      -D BUILD_opencv_apps=OFF \
      ..

# 7. Build and Install
echo "[INFO] Compiling... this uses all available cores."
# We use $(nproc) to speed up, but if it crashes, change to -j1
make -j1

echo "[INFO] Installing to ${INSTALL_DIR}..."
sudo make install
sudo ldconfig

# 8. Environment Setup
echo "[INFO] Configuring Linker..."
sudo sh -c "echo '${INSTALL_DIR}/lib' > /etc/ld.so.conf.d/opencv-cuda.conf"
sudo ldconfig

echo "[SUCCESS] OpenCV ${OPENCV_VERSION} with CUDA installed at ${INSTALL_DIR}"