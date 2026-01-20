import 'dart:typed_data';

/// Result from fetching a video frame
class FetchResult {
  final Uint8List? bytes;
  final int width;
  final int height;
  final bool success;

  FetchResult(this.bytes, this.width, this.height, this.success);
}

/// Raw frame data from video capture
class RawFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final int
  decodeTimestamp; // When frame was decoded (milliseconds since epoch)

  RawFrame(this.bytes, this.width, this.height, this.decodeTimestamp);
}

/// Processed frame with inference detections and pipeline timestamps
class ProcessedFrame {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final List<dynamic> detections;

  // Pipeline timestamps (milliseconds since epoch)
  final int decodeStartMs; // When frame decode started
  final int preprocessEndMs; // When preprocessing finished
  final int inferenceEndMs; // When inference finished
  final int postprocessEndMs; // When post-processing finished

  ProcessedFrame({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.detections,
    required this.decodeStartMs,
    required this.preprocessEndMs,
    required this.inferenceEndMs,
    required this.postprocessEndMs,
  });

  /// Calculate total pipeline time in milliseconds
  int get totalPipelineMs => postprocessEndMs - decodeStartMs;

  /// Calculate pipeline FPS
  double get pipelineFPS =>
      totalPipelineMs > 0 ? 1000.0 / totalPipelineMs : 0.0;

  /// Get timing breakdown
  Map<String, int> get timingBreakdown => {
    'decode': preprocessEndMs - decodeStartMs,
    'inference': inferenceEndMs - preprocessEndMs,
    'postprocess': postprocessEndMs - inferenceEndMs,
    'total': totalPipelineMs,
  };
}
