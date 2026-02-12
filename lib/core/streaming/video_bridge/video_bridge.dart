import 'dart:io';
import 'android/android_video_bridge.dart';
import 'linux/linux_video_bridge.dart';

/// Platform-agnostic bridge to native video operations.
///
/// Dispatches calls to platform-specific implementations:
/// - Android: MethodChannel to Java/Kotlin
/// - Linux: MethodChannel (showFrame) + FFI (via LibVLCBridge)
class VideoBridge {
  static Future<Map<String, dynamic>?> openVideo(String url) {
    if (Platform.isAndroid) {
      return AndroidVideoBridge.openVideo(url);
    } else {
      return LinuxVideoBridge.openVideo(url);
    }
  }

  static Future<Map<String, dynamic>?> getFrame(int id) {
    if (Platform.isAndroid) {
      return AndroidVideoBridge.getFrame(id);
    } else {
      return LinuxVideoBridge.getFrame(id);
    }
  }

  static Future<void> releaseVideo(int id) async {
    if (Platform.isAndroid) {
      await AndroidVideoBridge.releaseVideo(id);
    } else {
      await LinuxVideoBridge.releaseVideo(id);
    }
  }

  static Future<bool> showFrame(int id, int timestamp) {
    if (Platform.isAndroid) {
      return AndroidVideoBridge.showFrame(id, timestamp);
    } else {
      return LinuxVideoBridge.showFrame(id, timestamp);
    }
  }
}
