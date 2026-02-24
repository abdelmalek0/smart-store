#!/bin/bash
set -e

# ==========================================
# Download ONNX Runtime GPU v1.22.0
# and populate packages/native_onnx/linux/libs
# ==========================================

ORT_VERSION="1.22.0"
TARGET_DIR=$(realpath "$(dirname "$0")/../packages/native_onnx/linux/libs")
TMP_DIR="/tmp/onnxruntime_setup"

echo "[INFO] Creating target directory at: ${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"

# 1. Download ONNX Runtime GPU
echo "[INFO] Downloading ONNX Runtime GPU v${ORT_VERSION} for Linux x64..."
mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"

if [ ! -f "onnxruntime.tgz" ]; then
    wget -q -O onnxruntime.tgz "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-linux-x64-gpu-${ORT_VERSION}.tgz"
fi

# 2. Extract the archive
echo "[INFO] Extracting..."
tar -zxvf onnxruntime.tgz

# 3. Copy ALL required ONNX Runtime .so files to the flutter package
echo "[INFO] Copying ONNX shared libraries to target directory..."
cp -v "onnxruntime-linux-x64-gpu-${ORT_VERSION}/lib"/libonnxruntime.so* "${TARGET_DIR}/"
cp -v "onnxruntime-linux-x64-gpu-${ORT_VERSION}/lib"/libonnxruntime_providers_cuda.so "${TARGET_DIR}/"
cp -v "onnxruntime-linux-x64-gpu-${ORT_VERSION}/lib"/libonnxruntime_providers_shared.so "${TARGET_DIR}/"
cp -v "onnxruntime-linux-x64-gpu-${ORT_VERSION}/lib"/libonnxruntime_providers_tensorrt.so "${TARGET_DIR}/"

# 4. Copy CUDA & cuDNN dependencies (so Flutter bundles them correctly)
# The user's CMake script expects libcudart.so.12 and libcudnn.so.9 to be in the folder
echo "[INFO] Resolving system CUDA and cuDNN libraries..."

CUDART_SRC="/lib/x86_64-linux-gnu/libcudart.so.12"
CUDNN_SRC="/lib/x86_64-linux-gnu/libcudnn.so.9"

if [ -f "$CUDART_SRC" ]; then
    cp -v "$CUDART_SRC" "${TARGET_DIR}/"
else
    echo "[WARNING] $CUDART_SRC not found. Make sure CUDA is installed system-wide."
fi

if [ -f "$CUDNN_SRC" ]; then
    cp -v "$CUDNN_SRC" "${TARGET_DIR}/"
else
    echo "[WARNING] $CUDNN_SRC not found. Make sure cuDNN is installed system-wide."
fi

# Clean up
rm -rf "${TMP_DIR}"

echo "[SUCCESS] native_onnx/linux/libs has been successfully populated!"
echo "You can now add 'packages/native_onnx/linux/libs/*.so*' to your .gitignore"
