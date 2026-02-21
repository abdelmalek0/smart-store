import 'dart:isolate';

// ============================================================================
// MESSAGE CLASSES - Communication between main isolate and worker isolate
// ============================================================================

/// Worker initialization message
class WorkerInit {
  final SendPort sendPort;
  WorkerInit(this.sendPort);
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

  WorkerRequest({
    required this.streamId,
    required this.requestId,
    required this.modelPath,
    required this.imageBytes,
    required this.width,
    required this.height,
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
