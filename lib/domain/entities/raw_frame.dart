import 'dart:typed_data';

/// Raw frame data from video capture.
///
/// Domain-level value object. Used by streaming, plugins, and pipeline.
class RawFrame {
  final Uint8List bytes;
  final int width;
  final int height;

  /// Video timestamp (0-based PTS from decoder).
  final int decodeTimestamp;

  /// System timestamp when the frame was captured (epoch ms).
  final int generationTimeMs;

  RawFrame(
    this.bytes,
    this.width,
    this.height,
    this.decodeTimestamp, {
    this.generationTimeMs = 0,
  });
}
