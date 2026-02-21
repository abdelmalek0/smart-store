import 'dart:developer';

import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/core/streaming/bridge/video_bridge.dart';

/// Linux implementation of [VideoBridge].
///
/// All native calls go through [NativeInferenceService] (FFI/MethodChannel
/// to the bundled ONNX + video runtime).
class LinuxVideoBridge implements VideoBridge {
  static final NativeInferenceService _native = NativeInferenceService();

  @override
  Future<Map<String, dynamic>?> openVideo(String url) async {
    try {
      await _native.init();
      final id = _native.videoOpen(url);
      if (id != 0) return {'videoId': id};
    } catch (e) {
      log('LinuxVideoBridge: openVideo error: $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getFrame(int id) async {
    // On Linux, frame retrieval is handled by the VideoCapture isolate path.
    // This method is present for interface completeness.
    return null;
  }

  @override
  Future<void> releaseVideo(int id) async {
    _native.videoRelease(id);
  }

  @override
  Future<bool> showFrame(int id, int timestamp) async {
    return _native.showFrame(id, timestamp);
  }
}
