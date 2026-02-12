import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Linux native video bridge via MethodChannel.
///
/// Most Linux video operations use FFI (via LibVLCBridge), so openVideo,
/// getFrame, and releaseVideo are no-ops here. Only showFrame uses the
/// MethodChannel to trigger texture updates.
class LinuxVideoBridge {
  static const MethodChannel _channel = MethodChannel('ffmpeg_video');

  static Future<Map<String, dynamic>?> openVideo(String url) async {
    // Linux uses FFI for video opening, this might be unused or fallback
    return null;
  }

  static Future<Map<String, dynamic>?> getFrame(int id) async {
    // Linux uses FFI for frame retrieval
    return null;
  }

  static Future<void> releaseVideo(int id) async {
    // Linux uses FFI for release
  }

  static Future<bool> showFrame(int id, int timestamp) async {
    try {
      // StreamPipeline calls this to trigger texture update on the native side.
      final success = await _channel.invokeMethod<bool>('showFrame', {
        'textureId': id,
        'timestamp': timestamp,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('LinuxVideoBridge.showFrame error: $e');
      return false;
    }
  }
}
