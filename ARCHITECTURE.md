# Architecture Overview

## System Purpose

Smart Store is a real-time multi-stream video processing system with hardware-accelerated AI inference. It enables simultaneous monitoring of multiple video streams with object detection overlays.

**Key Capabilities**:
- ✅ Multi-stream video processing (2-10 concurrent streams)
- ✅ Hardware-accelerated video decoding (NVDEC/MediaCodec)
- ✅ Real-time object detection (YOLO models)
- ✅ Zero-copy GPU pipeline (Linux)
- ✅ Cross-platform (Linux desktop, Android mobile)

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter UI Layer                         │
│  (Screens, Widgets, State Management via Provider)          │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│                   Application Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Stream       │  │ Inference    │  │ Config       │      │
│  │ Manager      │  │ Service      │  │ Service      │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│                Processing Pipeline Layer                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Stream Processor (per stream)                         │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │ │
│  │  │ Capture  │→ │Inference │→ │ Display  │            │ │
│  │  │ Isolate  │  │  Queue   │  │  Queue   │            │ │
│  │  └──────────┘  └──────────┘  └──────────┘            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Inference Worker (shared isolate)                     │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │ │
│  │  │ Backend  │→ │  Model   │→ │  Post-   │            │ │
│  │  │ Select   │  │  Run     │  │ Process  │            │ │
│  │  └──────────┘  └──────────┘  └──────────┘            │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              Platform Abstraction Layer                      │
│  ┌──────────────────┐        ┌──────────────────┐          │
│  │ Video Capture    │        │ Inference        │          │
│  │ ┌──────┐┌──────┐│        │ ┌──────┐┌──────┐│          │
│  │ │Android││Linux ││        │ │ONNX  ││RKNN  ││          │
│  │ └──────┘└──────┘│        │ └──────┘└──────┘│          │
│  └──────────────────┘        └──────────────────┘          │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│                  Native Layer (C++/Kotlin)                   │
│  Linux: FFmpeg+NVDEC+OpenCV+ONNX+CUDA                       │
│  Android: FFmpeg JavaCPP+MediaCodec+RKNN                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Video Capture (`lib/platform/video_capture/`)

**Responsibility**: Platform-specific video stream decoding

**Implementations**:
- **Android**: FFmpeg via MethodChannel → Kotlin → JavaCPP
- **Linux**: FFmpeg + NVDEC via FFI → C++ → GPU decode

**Key Features**:
- Supports RTSP, HTTP, local files
- Hardware-accelerated decode
- Frame rate throttling (15-30 FPS)

**Interface**:
```dart
abstract class VideoCapture {
  Future<VideoCaptureResult> open(String url);
  Future<VideoCaptureFrame?> getFrame(int streamId);
  Future<void> release(int streamId);
}
```

---

### 2. Stream Processor (`lib/stream_processing/headless_stream_processor.dart`)

**Responsibility**: Manage per-stream capture, inference, and display pipeline

**Architecture**:
```
Capture Isolate → InferenceQueue(2) → Inference Worker
                                     ↓
                      DisplayQueue(10) → UI Display
```

**Key Features**:
- Bounded queues prevent OOM
- Freeze/unfreeze for start/stop inference
- Performance tracking (FPS counters)

---

### 3. Inference Worker (`lib/inference/inference_worker.dart`)

**Responsibility**: Run AI model inference in background isolate

**Architecture**:
```
Request Queue → Batch Collection → Backend Run → Post-Process → Results
```

**Backends**:
- **ONNX** (Linux): CUDA Execution Provider
- **RKNN** (Android): RK3588 NPU acceleration

**Post-Processing**:
- YOLO output parsing
- Non-Maximum Suppression (NMS)
- Coordinate scaling

---

### 4. Texture Management (`packages/native_onnx/linux/texture_manager.cpp`)

**Responsibility**: Zero-copy GPU texture rendering (Linux only)

**Zero-Copy Path**:
```
GPU Decode (NVDEC) → cv::cuda::GpuMat → CUDA-GL Interop → GL Texture → Flutter
```

**Performance**: ~2-5ms per frame (vs ~20ms with CPU copy)

---

## Data Flow

### Standard Path (Android & Linux fallback)

```
1. Video Stream (RTSP/file)
   ↓
2. Platform Video Decoder
   ↓
3. CPU Frame Buffer (RGBA)
   ↓
4. Capture Isolate → InferenceQueue
   ↓
5. Inference Worker (isolate)
   ↓
6. Post-Processing (NMS, scaling)
   ↓
7. DisplayQueue → UI Thread
   ↓
8. Flutter Widget Rendering
```

### Optimized Path (Linux with GPU)

```
1. Video Stream (RTSP/file)
   ↓
2. NVDEC Hardware Decoder
   ↓
3. GPU Frame Buffer (cv::cuda::GpuMat)
   ↓
4. CUDA Preprocessing (resize, normalize)
   ↓
5. ONNX Runtime (CUDA EP)
   ↓
6. Post-Processing on CPU
   ↓
7. CUDA-GL Interop (zero-copy to texture)
   ↓
8. Flutter Texture Widget
```

**Benefit**: Entire pipeline stays on GPU, reducing latency by ~50%

---

## Technology Stack

| Component | Linux | Android |
|-----------|-------|---------|
| **Video Decode** | FFmpeg + NVDEC | FFmpeg JavaCPP |
| **Hardware Accel** | NVIDIA CUDA | MediaCodec |
| **Inference** | ONNX Runtime | RKNN |
| **Inference Accel** | CUDA EP | RK3588 NPU |
| **Preprocessing** | OpenCV CUDA | Java/JNI |
| **UI** | Flutter (GL) | Flutter (Texture) |

---

## Concurrency Model

### Isolates

1. **Main Isolate**: UI thread, state management
2. **Capture Isolates**: One per stream, video decoding
3. **Inference Isolate**: Shared across streams, model execution

### Threading (Native)

1. **Capture Thread** (Linux): FFmpeg decoding, CUDA preprocessing
2. **UI Thread**: GL texture upload, Flutter rendering
3. **ONNX Thread Pool**: Model execution (managed by ONNX Runtime)

### Synchronization

- **Bounded Queues**: Backpressure via fixed-size queues
- **Mutex**: Protects GPU frame in TextureManager
- **Message Passing**: Isolate communication via SendPort

---

## Configuration

All tunable parameters in `lib/config/pipeline_constants.dart`:

```dart
class PipelineConstants {
  // Queue sizes
  static const int inferenceQueueMaxSize = 2;   // Low latency
  static const int displayQueueMaxSize = 10;     // Smooth playback
  
  // Model parameters
  static const int modelInputSize = 640;         // YOLO input
  
  // Detection thresholds
  static const double confidenceThreshold = 0.25;
  static const double nmsIouThreshold = 0.45;
}
```

---

## Design Decisions

### 1. Why Isolates for Capture?

**Problem**: Video decoding is compute-intensive and blocks UI

**Solution**: Run each stream's capture in a separate isolate

**Benefit**: UI remains responsive even with 10 concurrent streams

---

### 2. Why Bounded Queues?

**Problem**: Fast capture + slow inference = unbounded memory growth → OOM

**Solution**: Fixed-size queues (inference=2, display=10) with drop-oldest strategy

**Trade-off**: May drop frames under heavy load, but prevents crashes

---

### 3. Why Shared Inference Worker?

**Problem**: Each stream running its own model → high memory (10 streams = 10× model size)

**Solution**: Single inference worker servicing all streams

**Benefit**: 10 streams use same memory as 1 stream

---

### 4. Why Zero-Copy GPU Path?

**Problem**: CPU ↔ GPU transfers are slow (~20ms per frame)

**Solution**: Keep frames on GPU from decode to render using CUDA-GL interop

**Benefit**: 50% reduction in per-frame latency

---

## Performance Characteristics

**Target**:
- Video Decode: 30-60 FPS per stream
- Inference: 10-30 FPS (model-dependent)
- Display: 30-60 FPS
- Latency: <100ms (capture to display)

**Actual** (Linux with NVIDIA RTX):
- Decode: 60 FPS (NVDEC)
- Inference: 25 FPS (YOLOv8)
- Display: 60 FPS
- Latency: ~60ms

---

## Future Extensions

1. **iOS Support**: Add `IOSVideoCapture` implementation
2. **Cloud Inference**: Add remote inference backend
3. **Recording**: Add video export with detections
4. **Multi-GPU**: Distribute streams across GPUs
5. **Custom Models**: Support non-YOLO architectures

---

## Additional Documentation

- [Pipeline Guide](./docs/PIPELINE_GUIDE.md) - Step-by-step walkthrough
- [Code Documentation](./docs/API.md) - API reference
- [Pipeline Explanation](./brain/.../pipeline_explanation.md) - Detailed component breakdown

---

## Quick Reference

**Directory Structure**:
```
lib/
├── platform/video_capture/    # Platform-specific video decode
├── inference/                 # Model inference & post-processing
├── stream_processing/         # Pipeline management
├── services/                  # Shared services
└── config/                    # Configuration constants
```

**Key Files**:
- `video_capture.dart` - Video capture abstraction
- `inference_worker.dart` - Background inference
- `headless_stream_processor.dart` - Per-stream pipeline
- `yolo_post_processor.dart` - Shared YOLO utilities
- `pipeline_constants.dart` - All configuration

**Build Commands**:
```bash
# Linux
flutter run -d linux --release

# Android  
flutter run -d android --release
```
