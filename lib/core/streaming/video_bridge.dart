import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:native_onnx/native_onnx.dart';

/// Platform-agnostic bridge to native video operations.
///
/// Dispatches calls to platform-specific implementations:
/// - Android: MethodChannel to Java/Kotlin
/// - Linux: MethodChannel (showFrame) + FFI (via LibVLCBridge)
class VideoBridge {
  static const MethodChannel _channel = MethodChannel(
    'smart_store_linux/video_bridge',
  );
  static final NativeInferenceService _native = NativeInferenceService();

  static Future<Map<String, dynamic>?> openVideo(String url) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod('openVideo', {'url': url});
      return Map<String, dynamic>.from(result);
    } else {
      // Linux handling - using NativeInferenceService directly
      try {
        await _native.init();
        final id = _native.videoOpen(url);
        if (id != 0) {
          return {'videoId': id};
        }
      } catch (e) {
        // print("Error opening video on Linux: $e");
      }
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFrame(int id) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod('getFrame', {'id': id});
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } else {
      // Linux getFrame is complex (FFI), typically handled by VideoCapture
      // This bridge might be legacy or for simple cases.
      // For now, returning null as VideoCapture handles frame retrieval on Linux.
      return null;
    }
  }

  static Future<void> releaseVideo(int id) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('releaseVideo', {'id': id});
    } else {
      _native.videoRelease(id);
    }
  }

  static Future<bool> showFrame(int id, int timestamp) async {
    debugPrint("VideoBridge: showFrame id=$id ts=$timestamp");
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showFrame', {
          'id': id,
          'timestamp': timestamp,
        });
        return true;
      } on PlatformException catch (e) {
        if (e.code == "FRAME_NOT_FOUND") {
          debugPrint(
            "VideoBridge: Frame $timestamp missing! Native says: ${e.message}",
          );
        } else {
          debugPrint("VideoBridge: showFrame error: ${e.message}");
        }
        return false;
      } catch (e) {
        debugPrint("VideoBridge: showFrame generic error: $e");
        return false;
      }
    } else {
      // Linux implementation
      return _native.showFrame(id, timestamp);
    }
  }
}
