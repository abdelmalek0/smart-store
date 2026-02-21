import 'dart:io';

import 'package:smart_store_linux/core/streaming/bridge/linux/linux_video_bridge.dart';
import 'package:smart_store_linux/core/streaming/bridge/android/android_video_bridge.dart';

/// Platform-agnostic bridge to native video operations.
///
/// Use the factory constructor to get the correct platform implementation.
/// Matches the abstract+factory pattern used by [VideoCapture] and
/// [StreamSyncManager] — no inline if/else in call sites.
abstract class VideoBridge {
  /// Open a video stream from URL.
  /// Returns a map with at least `'videoId'` on success, or null.
  Future<Map<String, dynamic>?> openVideo(String url);

  /// Get the next frame info for an open video by its ID.
  Future<Map<String, dynamic>?> getFrame(int id);

  /// Release a video stream and free native resources.
  Future<void> releaseVideo(int id);

  /// Display the frame at [timestamp] for the video identified by [id].
  /// Returns true if the frame was found and displayed.
  Future<bool> showFrame(int id, int timestamp);

  /// Factory: returns the correct platform implementation.
  ///
  /// - Android → [AndroidVideoBridge] (MethodChannel)
  /// - Linux/Desktop → [LinuxVideoBridge] (FFI via NativeInferenceService)
  factory VideoBridge() {
    if (Platform.isAndroid) return AndroidVideoBridge();
    return LinuxVideoBridge();
  }
}
