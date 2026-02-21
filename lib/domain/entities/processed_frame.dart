import 'dart:typed_data';

/// Processed frame with inference detections and pipeline timestamps.
///
/// Domain-level value object. Used by plugins, rendering, and pipeline.
class ProcessedFrame {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final List<dynamic> detections;

  // Pipeline timestamps (milliseconds since epoch)
  final int decodeStartMs;
  final int generationTimeMs;
  final int preprocessEndMs;
  final int inferenceEndMs;
  final int postprocessEndMs;

  ProcessedFrame({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.detections,
    required this.decodeStartMs,
    this.generationTimeMs = 0,
    required this.preprocessEndMs,
    required this.inferenceEndMs,
    required this.postprocessEndMs,
  });

  /// Total pipeline latency in milliseconds.
  int get totalPipelineMs => postprocessEndMs - decodeStartMs;

  /// Pipeline throughput (frames per second).
  double get pipelineFPS =>
      totalPipelineMs > 0 ? 1000.0 / totalPipelineMs : 0.0;

  /// Timing breakdown by pipeline stage.
  Map<String, int> get timingBreakdown => {
    'decode': preprocessEndMs - decodeStartMs,
    'inference': inferenceEndMs - preprocessEndMs,
    'postprocess': postprocessEndMs - inferenceEndMs,
    'total': totalPipelineMs,
  };
}

/// Result from fetching a video frame from native code.
class FetchResult {
  final Uint8List? bytes;
  final int width;
  final int height;
  final bool success;

  FetchResult(this.bytes, this.width, this.height, this.success);
}
