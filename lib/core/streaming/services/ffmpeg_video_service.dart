import 'dart:io';
import 'android/ffmpeg_video_service_android.dart';
import 'linux/ffmpeg_video_service_linux.dart';

class FFmpegVideoService {
  static Future<Map<String, dynamic>?> openVideo(String url) {
    if (Platform.isAndroid) {
      return AndroidFFmpegVideoService.openVideo(url);
    } else {
      return LinuxFFmpegVideoService.openVideo(url);
    }
  }

  static Future<Map<String, dynamic>?> getFrame(int id) {
    if (Platform.isAndroid) {
      return AndroidFFmpegVideoService.getFrame(id);
    } else {
      return LinuxFFmpegVideoService.getFrame(id);
    }
  }

  static Future<void> releaseVideo(int id) async {
    if (Platform.isAndroid) {
      await AndroidFFmpegVideoService.releaseVideo(id);
    } else {
      await LinuxFFmpegVideoService.releaseVideo(id);
    }
  }

  static Future<bool> showFrame(int id, int timestamp) {
    if (Platform.isAndroid) {
      return AndroidFFmpegVideoService.showFrame(id, timestamp);
    } else {
      return LinuxFFmpegVideoService.showFrame(id, timestamp);
    }
  }

  static Future<Map<String, double>?> getSystemStats() {
    if (Platform.isAndroid) {
      return AndroidFFmpegVideoService.getSystemStats();
    } else {
      return LinuxFFmpegVideoService.getSystemStats();
    }
  }
}
