import 'dart:isolate';

import 'package:smart_store_linux/infrastructure/ai/backend/android/android_device.dart';

// ============================================================================
// MESSAGE CLASSES - Communication between main isolate and worker isolate
// ============================================================================

/// Worker initialization message
class WorkerInit {
  final SendPort sendPort;

  /// Device to use for Android inference (ignored on other platforms).
  final InferenceDevice androidDevice;

  WorkerInit(this.sendPort, {this.androidDevice = InferenceDevice.rknn});
}

/// Worker ready signal
class WorkerReady {
  final bool success;
  final String? error;
  WorkerReady(this.success, [this.error]);
}

/// Inference request message
class WorkerRequest {
  final String streamId;
  final int requestId;
  final String modelPath;
  final List<int> imageBytes;
  final int width;
  final int height;

  /// Optional: Native video ID for zero-copy inference 2.0
  final int? videoId;

  WorkerRequest({
    required this.streamId,
    required this.requestId,
    required this.modelPath,
    required this.imageBytes,
    required this.width,
    required this.height,
    this.videoId,
  });
}

/// Inference response message
class WorkerResponse {
  final String streamId;
  final int requestId;
  final String modelPath;
  final List<dynamic> detections;
  final String? error;
  final int
  processingStartMs; // When actual processing started (excludes queue wait)

  WorkerResponse({
    required this.streamId,
    required this.requestId,
    required this.modelPath,
    required this.detections,
    this.error,
    required this.processingStartMs,
  });
}

/// Model Labels response message
class WorkerLabels {
  final String streamId;
  final String modelPath;
  final Map<int, String> labels;

  WorkerLabels({
    required this.streamId,
    required this.modelPath,
    required this.labels,
  });
}
