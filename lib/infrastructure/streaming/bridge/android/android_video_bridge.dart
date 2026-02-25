import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:smart_store_linux/infrastructure/streaming/bridge/video_bridge.dart';

/// Android implementation of [VideoBridge].
///
/// All calls go through [MethodChannel] to the Java/Kotlin native plugin.
class AndroidVideoBridge implements VideoBridge {
  static const MethodChannel _channel = MethodChannel(
    'smart_store_linux/video_bridge',
  );

  @override
  Future<Map<String, dynamic>?> openVideo(String url) async {
    try {
      final result = await _channel.invokeMethod('openVideo', {'url': url});
      return Map<String, dynamic>.from(result);
    } catch (e) {
      log('AndroidVideoBridge: openVideo error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getFrame(int id) async {
    try {
      final result = await _channel.invokeMethod('getFrame', {'id': id});
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      log('AndroidVideoBridge: getFrame error: $e');
      return null;
    }
  }

  @override
  Future<void> releaseVideo(int id) async {
    try {
      await _channel.invokeMethod('releaseVideo', {'id': id});
    } catch (e) {
      log('AndroidVideoBridge: releaseVideo error: $e');
    }
  }

  @override
  Future<bool> showFrame(int id, int timestamp) async {
    try {
      await _channel.invokeMethod('showFrame', {
        'id': id,
        'timestamp': timestamp,
      });
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'FRAME_NOT_FOUND') {
        log('AndroidVideoBridge: Frame $timestamp missing — ${e.message}');
      } else {
        log('AndroidVideoBridge: showFrame error: ${e.message}');
      }
      return false;
    } catch (e) {
      log('AndroidVideoBridge: showFrame generic error: $e');
      return false;
    }
  }
}
