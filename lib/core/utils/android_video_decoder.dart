import 'package:flutter/services.dart';

/// Lightweight Android video decoder using MediaCodec
class AndroidVideoDecoder {
  static const MethodChannel _channel = MethodChannel('video_decoder');
  static bool _initialized = false;

  /// Initialize background isolate messenger (call once per isolate)
  static void ensureInitialized(RootIsolateToken token) {
    if (!_initialized) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      _initialized = true;
    }
  }

  /// Open a video stream and return decoder ID
  static Future<int> openVideo(String url, RootIsolateToken token) async {
    ensureInitialized(token); // Initialize before platform channel call
    try {
      final id = await _channel.invokeMethod('openVideo', {'url': url});
      return id as int;
    } catch (e) {
      throw Exception('Failed to open video: $e');
    }
  }

  /// Get next frame from decoder
  /// Returns map with 'data' (Uint8List), 'width' (int), 'height' (int)
  static Future<Map<String, dynamic>?> getFrame(int id) async {
    try {
      final result = await _channel.invokeMethod('getFrame', {'id': id});
      if (result == null) return null;

      return {
        'data': result['data'] as Uint8List,
        'width': result['width'] as int,
        'height': result['height'] as int,
      };
    } catch (e) {
      return null;
    }
  }

  /// Release video decoder
  static Future<void> releaseVideo(int id) async {
    try {
      await _channel.invokeMethod('releaseVideo', {'id': id});
    } catch (e) {
      // Ignore release errors
    }
  }
}
