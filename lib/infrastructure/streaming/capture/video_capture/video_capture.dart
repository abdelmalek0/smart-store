/// Video Capture Abstraction
///
/// Platform-agnostic interface for video stream capture and decoding.
/// Implementations handle platform-specific video backends (FFmpeg, NVDEC, etc.)
library;

import 'dart:io';
import 'dart:typed_data';

import 'android/android_video_capture.dart';
import 'linux/linux_video_capture.dart';

/// Result of opening a video stream
class VideoCaptureResult {
  /// Unique identifier for the video stream
  final int streamId;

  /// Flutter texture ID (Android only - for native texture rendering)
  final int? textureId;

  /// Native FPS of the source (file sources only).
  /// 0.0 for live RTSP streams — no pacing should be applied.
  final double nativeFps;

  VideoCaptureResult(this.streamId, {this.textureId, this.nativeFps = 0.0});
}

/// A single decoded video frame
class VideoCaptureFrame {
  /// Frame data in RGBA format
  final Uint8List data;

  /// Frame width in pixels
  final int width;

  /// Frame height in pixels
  final int height;

  /// Frame timestamp in milliseconds since epoch
  final int timestamp;

  VideoCaptureFrame(this.data, this.width, this.height, this.timestamp);
}

/// Abstract interface for video capture
///
/// Platform-specific implementations:
/// - Android: FFmpeg via MethodChannel ([AndroidVideoCapture])
/// - Linux: NVDEC + OpenCV via FFI ([LinuxVideoCapture])
abstract class VideoCapture {
  /// Open a video stream from URL
  ///
  /// Supports:
  /// - RTSP streams (rtsp://...)
  /// - Local files (file://... or absolute paths)
  /// - HTTP streams (http://...)
  ///
  /// Returns [VideoCaptureResult] with stream ID and optional texture ID
  Future<VideoCaptureResult> open(String url);

  /// Get the next frame from the video stream
  ///
  /// Returns:
  /// - [VideoCaptureFrame] if frame available
  /// - `null` if no frame ready or stream ended
  Future<VideoCaptureFrame?> getFrame(int streamId);

  /// Release the video stream and free resources
  Future<void> release(int streamId);

  /// Factory constructor - creates platform-specific implementation
  ///
  /// Returns:
  /// - [AndroidVideoCapture] on Android
  /// - [LinuxVideoCapture] on Linux/Desktop
  factory VideoCapture() {
    if (Platform.isAndroid) {
      return AndroidVideoCapture();
    } else {
      return LinuxVideoCapture();
    }
  }
}
