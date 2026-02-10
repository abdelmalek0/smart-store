import 'package:flutter/services.dart';

class FFmpegVideoService {
  static const MethodChannel _channel = MethodChannel('ffmpeg_video');

  static Future<Map<String, dynamic>?> openVideo(String url) async {
    try {
      final result = await _channel.invokeMethod<Map>('openVideo', {
        'url': url,
      });
      return result?.cast<String, dynamic>();
    } catch (e) {
      print('FFmpegVideoService.openVideo error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFrame(int id) async {
    try {
      final result = await _channel.invokeMethod<Map>('getFrame', {'id': id});
      return result?.cast<String, dynamic>();
    } catch (e) {
      print('FFmpegVideoService.getFrame error: $e');
      return null;
    }
  }

  static Future<void> releaseVideo(int id) async {
    try {
      await _channel.invokeMethod('releaseVideo', {'id': id});
    } catch (e) {
      print('FFmpegVideoService.releaseVideo error: $e');
    }
  }

  static Future<bool> showFrame(int id, int timestamp) async {
    try {
      final success = await _channel.invokeMethod<bool>('showFrame', {
        'id': id, // Android expects 'id'
        'textureId': id, // Linux expects 'textureId'
        'timestamp': timestamp,
      });
      return success ?? false;
    } catch (e) {
      print('FFmpegVideoService.showFrame error: $e');
      return false;
    }
  }

  static Future<Map<String, double>?> getSystemStats() async {
    try {
      final result = await _channel.invokeMethod<Map>('getSystemStats');
      if (result != null) {
        // Safe conversion
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
      // print('FFmpegVideoService.getSystemStats error: $e'); // Silent fail often on poll
      return null;
    }
  }
}
