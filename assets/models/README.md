# Android TFLite Models

Place your `.tflite` model files here.

## Supported layouts

| Format | Input shape | Output shape |
|--------|------------|-------------|
| YOLOv8 standard | `[1, 640, 640, 3]` float32 NHWC | `[1, 84, 8400]` float32 |
| YOLOv8 transposed | `[1, 640, 640, 3]` float32 NHWC | `[1, 8400, 84]` float32 (auto-detected) |

## Example

```dart
// CPU
ModelManager.instance.androidDevice = InferenceDevice.cpu;

// GPU (OpenGL ES delegate)
ModelManager.instance.androidDevice = InferenceDevice.gpu;

// NNAPI (hardware accelerator / DSP)
ModelManager.instance.androidDevice = InferenceDevice.nnapi;

// Pass the asset path to requestInference:
await ModelManager.instance.requestInference(
  streamId: 'cam0',
  requestId: 1,
  modelPath: 'assets/models/yolov8n.tflite',
  imageBytes: rgbBytes,
  width: frameWidth,
  height: frameHeight,
);
```

## Converting a YOLO model

```bash
# Export YOLOv8n to TFLite float32
yolo export model=yolov8n.pt format=tflite imgsz=640
# Then copy yolov8n_float32.tflite → assets/models/yolov8n.tflite
```
