# Smart Store

**Smart Store** is an AI-powered video analytics system designed for real-time store monitoring. It uses hardware-accelerated inference to detect objects, people, and events across multiple video streams.

## Key Features

- **Multi-Stream Support**: Monitor 2-10+ cameras simultaneously.
- **AI Analytics**: Real-time object detection using YOLO models.
- **Event System**: Automated alerts for specific detections (e.g., person count, zone entry).
- **High Performance**:
  - **Linux**: Zero-copy GPU pipeline (NVDEC + CUDA + TensorRT) for ultra-low latency.
  - **Android**: NPU acceleration (RKNN) on supported hardware.

## Architecture

The project follows **Clean Architecture** with four layers:

- **`lib/presentation`**: Flutter UI — Views, Widgets, BLoCs.
- **`lib/application`**: Orchestration — Engine, BLoCs, Events, DI.
- **`lib/domain`**: Business Rules — Entities, Use Cases, Repository interfaces.
- **`lib/infrastructure`**: Implementations — AI, Streaming, Rendering, Repositories.

Native GPU acceleration is provided by local Flutter packages in `packages/`:

- **`native_onnx`** (Linux): C++ Flutter plugin wrapping ONNX Runtime GPU, OpenCV CUDA, FFmpeg/NVDEC.
- **`native_rknn`** (Android): C++ Flutter plugin wrapping the RKNN NPU runtime.

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full deep-dive.

## Getting Started

### Prerequisites

#### Linux (NVIDIA GPU required)

**1. System packages**
```bash
sudo apt install ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
```

**2. OpenCV with CUDA support**

Build and install OpenCV 4.10 with CUDA/cuDNN using the provided script:
```bash
bash scripts/install_opencv_cuda.sh
```
> This installs OpenCV to `/opt/opencv-cuda`. Requires CUDA 12 and cuDNN 9 to be installed first.

**3. ONNX Runtime GPU libraries**

Download and stage the ONNX Runtime GPU shared libraries into the plugin package:
```bash
bash scripts/setup_native_onnx_libs.sh
```
> This downloads ONNX Runtime v1.22.0 (GPU) and copies `libonnxruntime*.so`, `libcudart.so.12`, and `libcudnn.so.9` into `packages/native_onnx/linux/libs/`. These are bundled automatically at build time.

### Building & Running

#### Linux
```bash
flutter build linux --release
./build/linux/x64/release/bundle/smart_store
```

#### Android
```bash
flutter build apk --release
flutter install
```