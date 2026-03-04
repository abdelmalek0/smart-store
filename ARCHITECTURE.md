# Smart Store Architecture

## 1. System Overview

**Smart Store** is a high-performance, real-time video analytics platform designed for retail store monitoring. It leverages hardware-accelerated AI to process multiple video streams simultaneously, detecting objects and events in real-time.

The system is built on **Clean Architecture** to enforce a strict dependency rule (outer layers depend inward, never the reverse) and an **Event-Driven** approach to decouple video processing from the user interface.

### Key Capabilities
*   **Multi-Stream Processing**: Capable of decoding and analyzing 2-10+ concurrent video streams.
*   **Hardware Acceleration**: Utilizes NVDEC (Linux) and MediaCodec (Android) for efficient video decoding.
*   **AI-Powered Analytics**: Integrates YOLO models for robust object detection and people counting.
*   **Cross-Platform**: Runs natively on Linux (Desktop/Edge) and Android (Mobile/Tablet).
*   **Low Latency**: Features a zero-copy GPU pipeline on Linux for minimal processing delay.

---

## 2. Architectural Layers

The application is organized into four layers. Dependencies **only flow inward** — outer layers know about inner layers, never the other way around.

```
┌──────────────────────────────────┐
│         Presentation             │  Flutter UI, BLoCs, Widgets
├──────────────────────────────────┤
│         Application              │  Engine, Orchestration, Events, DI
├──────────────────────────────────┤
│            Domain                │  Entities, Use Cases, Repository Interfaces
├──────────────────────────────────┤
│        Infrastructure            │  AI, Streaming, Rendering, Repositories
└──────────────────────────────────┘
        ↑  Native Packages (FFI)
  native_onnx (Linux) / native_rknn (Android)
```

### 2.1 Presentation Layer (`lib/presentation`)
The UI layer is built with Flutter and is responsible only for rendering and user input.
*   **Views**: High-level screens (e.g., Playback Screen, Settings).
*   **Widgets**: Reusable UI components (e.g., Camera Grid, Stream Player, Event Cards).
*   **BLoCs**: React to application-layer events and user actions, then emit new UI states. The presentation layer **never calls use cases directly** — it dispatches events to BLoCs.

### 2.2 Application Layer (`lib/application`)
The orchestration hub of the application. Contains no domain business rules and no infrastructure details.
*   **Engine**: The `Pipeline` and `RenderingOrchestrator` coordinate frame flow from capture → inference → display for each active stream.
*   **BLoCs**: Bridge between the presentation and domain layers. They invoke domain use cases and translate results into UI-ready state.
*   **Events**: An `EventBus` singleton provides publish-subscribe messaging across the application (e.g., `DetectionEvent`, `StreamStatusEvent`).
*   **DI**: Dependency injection wiring that assembles concrete infrastructure implementations against domain interfaces.

### 2.3 Domain Layer (`lib/domain`)
The innermost layer. Contains pure business logic with **zero Flutter or platform dependencies**.
*   **Entities**: Core data models — `StreamSource`, `Detection`, `PluginConfig`, etc.
*   **Use Cases**: Single-responsibility operations — `AddStream`, `StartInference`, `GetDetections`, etc. Each use case depends only on repository interfaces.
*   **Repository Interfaces**: Contracts (abstract classes) that the infrastructure layer must implement. The domain never imports infrastructure.

### 2.4 Infrastructure Layer (`lib/infrastructure`)
Concrete implementations of everything domain and application layers need.
*   **AI** (`infrastructure/ai`): ONNX Runtime worker and inference coordinator. Runs inference in a background isolate to keep the UI thread free.
*   **Streaming** (`infrastructure/streaming`): Platform-specific video capture — FFmpeg/NVDEC on Linux, MediaCodec on Android — exposed through a unified interface.
*   **Rendering** (`infrastructure/rendering`): OpenGL texture management and the `RenderingOrchestrator` that wires GPU textures into Flutter.
*   **Plugins** (`infrastructure/plugins`): Analytic modules (e.g., People Counter) that post-process detections and fire domain events.
*   **Repositories** (`infrastructure/repositories`): Concrete data access — config file I/O, SQLite, etc.
*   **System** (`infrastructure/system`): Low-level helpers (permissions, platform diagnostics).

---

## 3. Native Packages

GPU acceleration is provided by two local Flutter FFI plugins in `packages/`:

### `packages/native_onnx` (Linux only)
A C++ Flutter plugin that forms the hot path for GPU inference.

| Component | Library |
| :--- | :--- |
| AI Runtime | ONNX Runtime v1.22 (CUDA + TensorRT execution providers) |
| Video Decoding | FFmpeg (libavcodec/avformat) + NVDEC hardware decoder |
| GPU Preprocessing | OpenCV 4.10 (CUDA modules: cudaimgproc, cudawarping) |
| Texture Sharing | OpenGL / EGL (zero-copy GPU→Flutter texture) |
| CUDA Runtime | CUDA 12 (`libcudart.so.12`) |
| cuDNN | cuDNN 9 (`libcudnn.so.9`) |

All shared libraries (`libonnxruntime*.so`, `libcudart`, `libcudnn`) are staged in `packages/native_onnx/linux/libs/` and bundled into the app at build time via Flutter's plugin CMake system.

### `packages/native_rknn` (Android only)
A C++ Flutter plugin wrapping the RKNN NPU SDK for Rockchip-based Android devices (e.g., Orange Pi 5). It provides a Flutter FFI interface to hardware-accelerated neural network inference on the NPU.

---

## 4. Core Subsystems

### 4.1 Video Processing Pipeline
The pipeline is the critical hot path for each active stream:
1.  **Capture**: `VideoManager` (C++) decodes frames via FFmpeg+NVDEC directly into GPU memory.
2.  **Preprocess**: `ImageProcessor` (C++/CUDA) resizes and normalizes the GPU frame in-place.
3.  **Inference**: `InferenceManager` (C++) dispatches the GPU tensor to ONNX Runtime; results are returned as detection boxes.
4.  **Display**: `TextureManager` (C++) registers the processed GPU frame as an OpenGL texture, which Flutter renders zero-copy.

The Dart-side `Pipeline` (application layer) coordinates the isolate lifecycle and back-pressure between these stages.

### 4.2 Event System
The application uses a **Publish-Subscribe** pattern via `EventBus`.
*   **Producers**: The inference pipeline and analytic plugins emit typed events (e.g., `PersonDetectedEvent`).
*   **Consumers**: BLoCs and the presentation layer subscribe to relevant event streams and update UI state reactively.

### 4.3 Zero-Copy Rendering (Linux)
To achieve maximum throughput, frames never touch CPU memory:
1.  NVDEC decodes the video directly into a CUDA GPU buffer.
2.  OpenCV CUDA kernels preprocess the frame (resize → normalize) in-place on the GPU.
3.  ONNX Runtime (CUDA EP) runs inference on the GPU buffer.
4.  The output frame is imported into OpenGL as an `EGLImage`/`GL_TEXTURE_2D` without a CPU round-trip.
5.  Flutter renders the texture directly via the platform texture registry.

---

## 5. Concurrency Model

| Thread / Isolate | Responsibility |
| :--- | :--- |
| **Main Isolate (UI Thread)** | Flutter rendering, user input, BLoC state updates. Must never block. |
| **Capture Isolates** | One isolate per active stream. Runs the decode → preprocess → inference → display loop independently. |
| **Inference Isolate** | Single shared isolate that serializes model execution across streams to prevent GPU memory saturation. |
| **C++ Threads** | Native plugin threads managed by the C++ layer for async NVDEC decode callbacks. |

---

## 6. Technology Stack

| Component | Linux Implementation | Android Implementation |
| :--- | :--- | :--- |
| **Language** | Dart (Flutter) + C++ (FFI plugin) | Dart (Flutter) + C++ (FFI plugin) |
| **Video Decoding** | FFmpeg + NVDEC (Hardware GPU) | FFmpeg + MediaCodec (Hardware) |
| **AI Runtime** | ONNX Runtime 1.22 (CUDA + TensorRT EP) | RKNN SDK (Rockchip NPU) |
| **GPU Preprocessing** | OpenCV 4.10 (CUDA modules) | JNI / Native |
| **Texture Sharing** | OpenGL / EGL (zero-copy) | SurfaceTexture |
| **State Management** | BLoC + EventBus | BLoC + EventBus |
| **Local Storage** | JSON / SQLite | Shared Preferences / SQLite |
| **Architecture Pattern** | Clean Architecture | Clean Architecture |
