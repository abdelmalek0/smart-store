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

  RawFrame(this.bytes, this.width, this.height);
}

/// Processed frame with inference detections
class ProcessedFrame {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final List<dynamic> detections;

  ProcessedFrame({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.detections,
  });
}
