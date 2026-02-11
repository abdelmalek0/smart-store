# Smart Store Architecture

## 1. System Overview

**Smart Store** is a high-performance, real-time video analytics platform designed for retail store monitoring. It leverages hardware-accelerated AI to process multiple video streams simultaneously, detecting objects and events in real-time.

The system is built on a **Layered Architecture** to ensure separation of concerns, maintainability, and scalability. It employs an **Event-Driven** approach to decouple video processing logic from the user interface.

### Key Capabilities
*   **Multi-Stream Processing**: Capable of decoding and analyzing 2-10+ concurrent video streams.
*   **Hardware Acceleration**: Utilizes NVDEC (Linux) and MediaCodec (Android) for efficient video decoding.
*   **AI-Powered Analytics**: Integrates YOLO models for robust object detection and people counting.
*   **Cross-Platform**: Runs natively on Linux (Desktop/Edge) and Android (Mobile/Tablet).
*   **Low Latency**: Features a zero-copy GPU pipeline on Linux for minimal processing delay.

---

## 2. Architectural Layers

The application is organized into four distinct layers, each with a specific responsibility.

### 2.1 UI Layer (`lib/ui`)
The Presentation Layer is built using Flutter. It is responsible for rendering the user interface and handling user interactions.
*   **Screens**: High-level views (e.g., Dashboard, Settings, Camera Grid).
*   **Widgets**: Reusable UI components (e.g., VideoPlayer, EventCard).
*   **State Management**: Uses the Provider pattern and ViewModels to manage UI state and separate business logic from rendering code.
*   **Interaction**: Listens to the Core Layer for updates but does not continuously query it.

### 2.2 Core Layer (`lib/core`)
The Business Logic Layer serves as the central orchestration engine of the application.
*   **Engine**: Manages the video processing pipeline. It coordinates the flow of frames from capture to inference to display.
*   **Events**: A centralized **Event Service** acts as the backbone for application-wide communication. It broadcasts typed events (e.g., `DetectionEvent`, `SystemEvent`) to subscribers.
*   **Plugins**: An extensible **Plugin Manager** allows specific analytic modules (like People Counting) to subscribe to inference results and trigger logic.
*   **Streaming**: Handles the complexity of platform-specific video capture and decoding, providing a unified interface to the rest of the app.
*   **Config**: Manages application settings, pipeline constants, and resource allocation.

### 2.3 AI Layer (`lib/ai`)
The Intelligence Layer is dedicated to machine learning operations.
*   **Isolation**: All inference tasks run in a dedicated background **Isolate**. This ensures that heavy computation never blocks the UI thread.
*   **Abstraction**: A unified **Inference Backend** interface hides the differences between underlying execution providers (ONNX Runtime on Linux, RKNN on Android).
*   **Worker**: A persistent worker process manages model loading, batching, and execution.

### 2.4 Data Layer (`lib/data`)
The Persistence Layer manages long-term data storage.
*   **Repositories**: Provide clean APIs for accessing data, abstracting the underlying storage mechanism.
*   **Services**: Handle direct interactions with databases, file systems, or remote APIs.

---

## 3. Core Subsystems

### 3.1 Video Processing Pipeline
The pipeline is the critical path for video data. It operates in a loop for each active stream:
1.  **Capture**: Video frames are decoded asynchronously. On Linux, this happens directly on the GPU.
2.  **Inference Queue**: Frames are pushed to a bounded queue for analysis.
3.  **Inference**: The AI Layer processes the frame and returns a list of detections.
4.  **Display Queue**: Processed frames, now carrying metadata, are pushed to the UI for rendering.

### 3.2 Event System
The application uses a **Publish-Subscribe** pattern for events.
*   **Producers**: The AI Layer and Plugins produce events based on analysis (e.g., "Person Detected").
*   **Bus**: The `EventService` singleton receives these events.
*   **Consumers**: The UI (specifically `EventsViewModel`) listens to the service and updates the interface in real-time. This ensures the UI is reactive and decoupled from the heavy lifting of video processing.

### 3.3 Zero-Copy Rendering (Linux)
To achieve high performance on Linux, the system avoids copying video frames between CPU and GPU memory.
1.  Video is decoded by **NVDEC** directly into GPU memory.
2.  Preprocessing (resizing, normalization) is performed by **CUDA**.
3.  Inference is run by **TensorRT/CUDA** execution providers.
4.  The frame is passed to OpenGL as a texture resource without ever leaving the GPU.
5.  Flutter renders this texture directly.

---

## 4. Concurrency Model

Understanding the threading model is crucial for performance tuning.

*   **Main Isolate (UI Thread)**: Handles rendering, user input, and state updates. It must never be blocked.
*   **Capture Isolates**: Each video stream runs its decoding loop in a separate isolate. This allows the system to scale to multiple cameras without choking the UI.
*   **Inference Isolate**: A single, shared isolate handles model execution for all streams. This serializes inference requests to prevent GPU memory saturation.

---

## 5. Technology Stack

| Component | Linux Implementation | Android Implementation |
| :--- | :--- | :--- |
| **Language** | Dart (Flutter) + C++ | Dart (Flutter) + Kotlin/Java |
| **Video Decoding** | FFmpeg + NVDEC (Hardware) | FFmpeg + MediaCodec (Hardware) |
| **AI Runtime** | ONNX Runtime (CUDA Execution Provider) | RKNN (Rockchip NPU) |
| **Preprocessing** | OpenCV (CUDA) | Java Native Interface |
| **State Management** | Provider + ChangeNotifier | Provider + ChangeNotifier |
| **Local Storage** | JSON / SQLite | Shared Preferences / SQLite |
