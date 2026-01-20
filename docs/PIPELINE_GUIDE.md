# Pipeline Guide: Understanding the Video Processing Flow

This guide walks through the complete video processing pipeline from URL input to rendered display with object detection overlays.

---

## Table of Contents

1. [Pipeline Overview](#pipeline-overview)
2. [Component Details](#component-details)
3. [Data Flow Examples](#data-flow-examples)
4. [Performance Optimizations](#performance-optimizations)
5. [Troubleshooting](#troubleshooting)

---

## Pipeline Overview

### The Big Picture

```
User adds RTSP stream URL
         ↓
Stream Manager creates Stream Processor
         ↓
Stream Processor spawns Capture Isolate
         ↓
┌────────────────────────────────────────┐
│      PER-STREAM PROCESSING             │
│                                        │
│  Capture → InferenceQueue → Worker    │
│              ↓                         │
│         DisplayQueue → UI              │
└────────────────────────────────────────┘
```

### Key Principles

1. **One Processor Per Stream**: Each video stream gets its own `HeadlessStreamProcessor`
2. **Shared Inference**: All streams share one `InferenceWorker` isolate
3. **Bounded Queues**: Prevent memory overflow with fixed-size queues
4. **Isolate Isolation**: Video decoding doesn't block UI or other streams

---

## Component Details

### 1. Stream Manager

**File**: `lib/services/stream_process_manager.dart`

**Purpose**: Orchestrates all stream processors

**Lifecycle**:
```dart
// User clicks "Start All"
await StreamProcessManager.instance.startAllInference();
  → Creates HeadlessStreamProcessor for each stream
  → Initializes each processor
  → Starts capture + inference

// User clicks "Stop All"
await StreamProcessManager.instance.stopAllInference();
  → Freezes all processors (stops inference, keeps showing video)
```

---

### 2. Stream Processor

**File**: `lib/stream_processing/headless_stream_processor.dart`

**Purpose**: Manage single stream's capture → inference → display pipeline

**Key Methods**:

#### `initialize()`
Sets up the processing pipeline:
```dart
Future<void> initialize() async {
  // 1. Start inference listener (subscribes to results)
  _inferenceSubscription = InferenceService.instance.resultsStream
    .where((result) => result.streamId == stream.id)
    .listen(_handleInferenceResult);
  
  // 2. Start capture isolate
  _startReadLoop();  // Spawns isolate for video decode
  
  // 3. Start inference processing
  _startInferenceLoop();  // Processes frames from InferenceQueue
  
  // 4. Start display output
  _startDisplayLoop();  // Outputs frames from DisplayQueue
}
```

#### Three Core Loops

**Capture Loop** (runs in isolate):
```dart
while (true) {
  frame = await capture.getFrame(streamId);
  if (frame != null) {
    sendPort.send(['frame', frame.data, frame.width, ...]);
  }
}
```

**Inference Loop** (main isolate):
```dart
while (_isActive) {
  if (_inferenceQueue.isNotEmpty) {
    final frame = _inferenceQueue.last;  // Get latest frame
    _inferenceQueue.clear();              // Drop older frames
    
    InferenceService.instance.enqueueFrame(...);  // Send to worker
  }
}
```

**Display Loop** (main isolate):
```dart
while (_isActive) {
  if (_displayQueue.isNotEmpty) {
    final frame = _displayQueue.removeFirst();
    _frameStreamController.add(frame);  // UI listens to this stream
  }
}
```

---

### 3. Video Capture (Platform-Specific)

**Files**: 
- `lib/platform/video_capture/android_video_capture.dart`
- `lib/platform/video_capture/linux_video_capture.dart`

**Android Path**:
```
User URL → Dart → MethodChannel → Kotlin FFmpegVideoPlugin 
         → JavaCPP FFmpeg → MediaCodec decode 
         → RGBA buffer → Send back to Dart
```

**Linux Path**:
```
User URL → Dart → FFI → C++ inference_bridge.cpp
         → FFmpeg + NVDEC → GPU decode (cv::cuda::GpuMat)
         → RGBA buffer → Send back to Dart
```

**Linux Optimized Path** (when model path provided):
```
User URL → Dart → FFI → C++ videoGetFrameAndInfer()
         → FFmpeg + NVDEC decode
         → CUDA preprocessing (resize, normalize)
         → ONNX Runtime (CUDA EP)
         → Post-process results
         → Return frame + detections together
```

---

### 4. Inference Worker

**File**: `lib/inference/inference_worker.dart`

**Purpose**: Run AI models in background isolate

**Architecture**:
```
Main Isolate                    Worker Isolate
     │                               │
     ├─ enqueueFrame() ──────────────→ Request Queue
     │                               │
     │                               ├─ Batch Collection (10ms window)
     │                               │
     │                               ├─ Backend.run()
     │                               │   ├─ ONNX (Linux)
     │                               │   └─ RKNN (Android)
     │                               │
     │                               ├─ Post-Processing
     │                               │   ├─ Parse YOLO output
     │                               │   └─ NMS
     │                               │
     ←─ resultsStream ────────────────┤ Send results
```

**Batch Processing**:
- Collects requests for same model over 10ms window
- One request per stream per batch (avoids duplicate processing)
- Batch size = 1 for minimal latency

---

### 5. Post-Processing

**File**: `lib/inference/yolo_post_processor.dart`

**Purpose**: Convert raw YOLO output to bounding boxes

**YOLO Output Format** (YOLOv8):
- Shape: [1, 84, 8400] flattened to [705600]
- 84 channels: 4 bbox coords + 80 class probabilities
- 8400 anchor points (from 640x640 input)

**Processing Steps**:
1. **Parse**: Extract bbox coordinates for each anchor
2. **Filter**: Keep only detections above confidence threshold (0.25)
3. **Scale**: Convert from model space (640x640) to original image size
4. **NMS**: Remove overlapping boxes (IoU > 0.45)

---

## Data Flow Examples

### Example 1: Standard Frame (Android)

```
1. RTSP Stream: rtsp://camera:554/stream
   ↓
2. Android FFmpeg Capture
   - Decodes H.264 to RGBA (1920x1080)
   - Takes ~16ms (60 FPS)
   ↓
3. Capture Isolate → Main Isolate
   - Message: ['frame', TransferableTypedData, 1920, 1080, timestamp]
   ↓
4. HeadlessStreamProcessor
   - Adds to InferenceQueue (max 2 frames)
   - If queue full: drops oldest frame
   ↓
5. Inference Loop
   - Takes latest frame from queue
   - Clears queue (latest frame only)
   - Sends to InferenceService
   ↓
6. Inference Worker (separate isolate)
   - RKNN backend preprocesses (resize to 640x640, normalize)
   - Runs model on RK3588 NPU (~40ms)
   - Post-processes YOLO int8 output
   - Applies NMS
   ↓
7. Results sent back via resultsStream
   ↓
8. HeadlessStreamProcessor receives result
   - Pairs result with original frame
   - Creates ProcessedFrame with detections
   - Adds to DisplayQueue (max 10 frames)
   ↓
9. Display Loop
   - Takes frame from DisplayQueue
   - Emits via _frameStreamController
   ↓
10. UI Widget
    - Listens to frameStream
    - Renders video + detection overlays
```

**Total Latency**: ~100-150ms (capture to display)

---

### Example 2: Optimized Frame (Linux)

```
1. RTSP Stream: rtsp://camera:554/stream
   ↓
2. Linux NVDEC Capture (optimized path enabled)
   - Decodes H.264 to GPU (NVDEC) → cv::cuda::GpuMat
   - CUDA preprocessing (resize, normalize) on GPU
   - ONNX Runtime runs model (CUDA EP)
   - Post-processes on CPU
   - Returns frame + detections together
   - Total: ~60ms
   ↓
3. Capture Isolate → Main Isolate
   - Message: ['processed_frame', data, w, h, timestamp, detections, inferenceTime]
   ↓
4. HeadlessStreamProcessor
   - Receives already-processed frame
   - Skips InferenceQueue entirely
   - Directly adds to DisplayQueue
   ↓
5. Display Loop
   - Takes frame from DisplayQueue
   - Emits via _frameStreamController
   ↓
6. UI Widget
   - Renders video + detection overlays
```

**Total Latency**: ~60-80ms (capture to display)
**Benefit**: 40% faster than standard path

---

## Performance Optimizations

### 1. Bounded Queues

**Problem**: Unbounded queues → memory growth → OOM crash

**Solution**:
```dart
// InferenceQueue: max 2 frames
if (_inferenceQueue.length >= 2) {
  _inferenceQueue.removeFirst();  // Drop oldest
}
_inferenceQueue.add(frame);

// DisplayQueue: max 10 frames
if (_displayQueue.length >= 10) {
  _displayQueue.removeFirst();  // Drop oldest
}
_displayQueue.add(processedFrame);
```

**Benefit**: Memory usage stays constant regardless of inference speed

---

### 2. Latest Frame Processing

**Problem**: Processing every frame when inference is slow = wasted work

**Solution**:
```dart
// Inference loop only processes LATEST frame
final frame = _inferenceQueue.last;  // Get most recent
_inferenceQueue.clear();              // Drop older frames
```

**Benefit**: Always shows most recent detections, no lag

---

### 3. Zero-Copy GPU Path (Linux)

**Problem**: CPU ↔ GPU transfers are slow

**Solution**:
```cpp
// Video decode directly to GPU
AVFrame *frame = av_frame_alloc(); // GPU frame
avcodec_receive_frame(ctx, frame); // NVDEC puts frame on GPU

// Keep on GPU for processing
cv::cuda::GpuMat gpuFrame(...);    // Wrap in OpenCV GPU mat
cv::cuda::cvtColor(gpuFrame, ...); // Color convert on GPU

// Upload to GL texture (still on GPU)
cudaGraphicsMapResources(&resource);  // Map GL texture to CUDA
cudaMemcpy2DToArray(...);             // Copy GPU→GPU (fast!)
cudaGraphicsUnmapResources(&resource);
```

**Benefit**: Entire pipeline stays on GPU, 50% faster

---

### 4. Shared Inference Worker

**Problem**: 10 streams × 1 model each = 10GB RAM

**Solution**: One worker services all streams

**Benefit**: 10 streams use same RAM as 1 stream (~1GB)

---

## Troubleshooting

### Issue: Low FPS (<10 FPS)

**Symptoms**:
- Video appears choppy
- FPS counter shows low numbers
- Latency is high

**Possible Causes**:
1. **Slow inference**: Model too large or hardware acceleration not working
2. **Network issues**: RTSP stream buffering
3. **Queue overflow**: Inference queue constantly full

**Debug Steps**:
```dart
// Check FPS in each stage
debugPrint("Capture FPS: $_captureCount / 2"); // Should be 15-30
debugPrint("Inference FPS: $_inferenceFrameCounter / 2"); // Should be 10-30
debugPrint("Display FPS: $_displayCount / 2"); // Should match capture

// Check queue sizes
debugPrint("InferenceQueue length: ${_inferenceQueue.length}"); // Should be 0-2
debugPrint("DisplayQueue length: ${_displayQueue.length}"); // Should be 0-10
```

**Solutions**:
- Use smaller/faster model
- Reduce video resolution at source
- Check network bandwidth for RTSP

---

### Issue: Memory Growth (OOM)

**Symptoms**:
- App memory usage continuously increases
- Eventually crashes with OOM error

**Possible Causes**:
1. **Unbounded queue**: Bug in queue management
2. **FFI leak**: Not freeing native pointers
3. **Frame leak**: Not releasing video frames

**Debug Steps**:
```bash
# Monitor memory over time
watch -n 5 'ps aux | grep flutter'

# Check for memory leaks in native code
valgrind --leak-check=full ./build/linux/x64/release/bundle/smart_store_linux
```

**Solutions**:
- Verify queues are bounded
- Check all `calloc()` have matching `calloc.free()`
- Ensure `videoRelease()` is called

---

### Issue: No Video Display

**Symptoms**:
- Black screen where video should be
- No error messages

**Possible Causes**:
1. **Texture ID mismatch**: Flutter texture not linked to native texture
2. **Video decode failure**: FFmpeg can't open stream
3. **Frame format issue**: Unexpected pixel format

**Debug Steps**:
```dart
// Check if stream opened
debugPrint("Video ID: $_nativeVideoId"); // Should be > 0
debugPrint("Texture ID: $_textureId"); // Should be > 0

// Check if frames arriving
debugPrint("Frames received: $_captureCount"); // Should increment

// Check frame data
debugPrint("Frame size: ${frame.data.length}"); // Should be width*height*4
```

**Solutions**:
- Verify URL is accessible (try in VLC)
- Check texture ID mapping
- Verify pixel format is RGBA

---

## Advanced Topics

### Custom Post-Processing

To add custom post-processing:

1. Create new class in `lib/inference/post_processing/`
2. Implement detection parsing logic
3. Update `inference_worker.dart` to use new processor

Example:
```dart
class CustomPostProcessor {
  static List<Detection> process(List<double> output) {
    // Your custom logic here
    return detections;
  }
}
```

---

### Multi-GPU Support

To distribute streams across GPUs (Linux):

1. Specify GPU in video open:
```cpp
AVDictionary *opts = NULL;
av_dict_set(&opts, "gpu", "0", 0);  // Use GPU 0
avformat_open_input(&ctx, url, NULL, &opts);
```

2. Set CUDA device in preprocessing:
```cpp
cudaSetDevice(gpu_id);
```

---

## Performance Benchmarks

**Test Setup**:
- Hardware: NVIDIA RTX 3090, AMD Ryzen 9 5950X
- Input: 1080p RTSP stream (H.264)
- Model: YOLOv8n (nano)

**Results**:

| Metric | Standard Path | Optimized Path |
|--------|--------------|----------------|
| Decode | 16ms | 10ms (NVDEC) |
| Preprocess | 5ms (CPU) | 2ms (CUDA) |
| Inference | 8ms | 8ms (same) |
| Postprocess | 3ms | 3ms (same) |
| Upload | 20ms (CPU→GPU) | 0ms (already on GPU) |
| **Total** | **52ms** | **23ms** |
| **FPS** | **19 FPS** | **43 FPS** |

---

## Next Steps

- Read [ARCHITECTURE.md](../ARCHITECTURE.md) for system overview
- Explore code with inline documentation
- Try adding a new stream and observe pipeline behavior
- Experiment with different models and parameters
