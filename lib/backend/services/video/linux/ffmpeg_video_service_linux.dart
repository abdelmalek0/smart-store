import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class LinuxFFmpegVideoService {
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
      // StreamProcessor calls this. Linux might have a method channel handler for this.
      // If not, this is harmless but might just fail.
      // Existing code had: 'textureId': id // Linux expects 'textureId'
      final success = await _channel.invokeMethod<bool>('showFrame', {
        'textureId': id,
        'timestamp': timestamp,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('LinuxFFmpegVideoService.showFrame error: $e');
      return false;
    }
  }

  static Future<Map<String, double>?> getSystemStats() async {
    // Linux stats implementation via channel?
    try {
      debugPrint("Warning: getSystemStats not implemented for Linux yet");
      final result = await _channel.invokeMethod<Map>('getSystemStats');
      if (result != null) {
        final stats = <String, double>{};
        result.forEach((key, value) {
          if (key is String && value is num) {
            stats[key] = value.toDouble();
          }
        });
        return stats;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
