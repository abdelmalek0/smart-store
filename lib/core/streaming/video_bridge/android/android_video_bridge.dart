import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Android native video bridge via MethodChannel.
///
/// All video operations go through the 'ffmpeg_video' MethodChannel
/// to native Android code.
class AndroidVideoBridge {
  static const MethodChannel _channel = MethodChannel('ffmpeg_video');

  static Future<Map<String, dynamic>?> openVideo(String url) async {
    try {
      final result = await _channel.invokeMethod<Map>('openVideo', {
        'url': url,
      });
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('AndroidVideoBridge.openVideo error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFrame(int id) async {
    try {
      final result = await _channel.invokeMethod<Map>('getFrame', {'id': id});
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('AndroidVideoBridge.getFrame error: $e');
      return null;
    }
  }

  static Future<void> releaseVideo(int id) async {
    try {
      await _channel.invokeMethod('releaseVideo', {'id': id});
    } catch (e) {
      debugPrint('AndroidVideoBridge.releaseVideo error: $e');
    }
  }

  static Future<bool> showFrame(int id, int timestamp) async {
    try {
      final success = await _channel.invokeMethod<bool>('showFrame', {
        'id': id,
        'timestamp': timestamp,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('AndroidVideoBridge.showFrame error: $e');
      return false;
    }
  }
}
