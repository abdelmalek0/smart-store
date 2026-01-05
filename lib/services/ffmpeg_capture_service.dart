import 'dart:async';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';
import 'package:flutter/foundation.dart';

/// FFmpeg-based RTSP stream capture
/// Unified solution for Android and Linux
class FFmpegCaptureService {
  static Future<Stream<Uint8List>> captureStream(String url) async {
    final controller = StreamController<Uint8List>();

    // FFmpeg command to extract frames from RTSP
    // Output as RGBA raw video to pipe
    final command =
        '-rtsp_transport tcp -i "$url" -f rawvideo -pix_fmt rgba -s 1920x1080 -r 15 pipe:1';

    debugPrint('[FFmpeg] Starting capture: $url');

    FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('[FFmpeg] Stream ended successfully');
      } else {
        debugPrint(
          '[FFmpeg] Stream failed: ${await session.getFailStackTrace()}',
        );
      }
      await controller.close();
    });

    return controller.stream;
  }
}
