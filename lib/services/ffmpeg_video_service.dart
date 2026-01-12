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

  static Future<void> showFrame(int id, int timestamp) async {
    try {
      await _channel.invokeMethod('showFrame', {
        'id': id,
        'timestamp': timestamp,
      });
    } catch (e) {
      print('FFmpegVideoService.showFrame error: $e');
    }
  }
}
