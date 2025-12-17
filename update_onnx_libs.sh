#!/bin/bash
set -e

# Ensure we are in the project root
if [ ! -d "linux/libs" ]; then
  echo "Error: Please run this script from the project root (smart_store_linux)."
  exit 1
fi

LIBS_DIR="linux/libs"

echo "Downloading ONNX Runtime 1.22.0 (GPU)..."
curl -L -o onnxruntime.tgz https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/onnxruntime-linux-x64-gpu-1.22.0.tgz

echo "Extracting..."
tar -xzf onnxruntime.tgz

SRC_LIB_DIR="onnxruntime-linux-x64-gpu-1.22.0/lib"

echo "Updating libraries in $LIBS_DIR..."

# Remove old 1.23.2 specific files to avoid confusion
rm -f "$LIBS_DIR"/libonnxruntime.so.1.23.2
rm -f "$LIBS_DIR"/libonnxruntime.so.1.23.3
rm -f "$LIBS_DIR"/libonnxruntime.so.1.22.0 # Remove symlink if it exists

# Copy new files
cp -v "$SRC_LIB_DIR"/libonnxruntime.so.1.22.0 "$LIBS_DIR/"
cp -v "$SRC_LIB_DIR"/libonnxruntime_providers_cuda.so "$LIBS_DIR/"
cp -v "$SRC_LIB_DIR"/libonnxruntime_providers_shared.so "$LIBS_DIR/"
cp -v "$SRC_LIB_DIR"/libonnxruntime_providers_tensorrt.so "$LIBS_DIR/"

# Create main symlink
cd "$LIBS_DIR"
rm -f libonnxruntime.so
ln -s libonnxruntime.so.1.22.0 libonnxruntime.so
cd - > /dev/null

# Cleanup
rm -rf onnxruntime-linux-x64-gpu-1.22.0
rm -f onnxruntime.tgz

echo "Successfully installed ONNX Runtime 1.22.0 libraries."
