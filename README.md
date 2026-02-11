# Smart Store

**Smart Store** is an AI-powered video analytics system designed for real-time store monitoring. It uses hardware-accelerated inference to detect objects, people, and events across multiple video streams.

## Key Features

- **Multi-Stream Support**: Monitor 2-10+ cameras simultaneously.
- **AI Analytics**: Real-time object detection using YOLO models.
- **Event System**: Automated alerts for specific detections (e.g., person count, zone entry).
- **High Performance**: 
  - **Linux**: Zero-copy GPU pipeline (NVDEC + CUDA) for ultra-low latency.
  - **Android**: NPU acceleration (RKNN) on supported hardware.
  
## Architecture

The project follows a clean, layered architecture:

- **`lib/ui`**: Flutter UI components (Screens, Widgets, ViewModels).
- **`lib/core`**: Core engine logic (Streaming, Events, Plugins, Config).
- **`lib/ai`**: AI inference logic (Workers, Backends, Services).
- **`lib/data`**: Data persistence and repositories.

See [ARCHITECTURE.md](ARCHITECTURE.md) for a deep dive into the system design.

## Getting Started

### Linux
```bash
sudo apt install ffmpeg libopencv-dev
flutter build linux --release
./build/linux/x64/release/bundle/smart_store
```

### Android
```bash
flutter build apk --release
flutter install
```