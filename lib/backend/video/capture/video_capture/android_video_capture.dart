/// Android Video Capture Implementation
///
/// Uses FFmpeg via MethodChannel to capture video frames on Android.
/// Supports hardware-accelerated decoding on devices with MediaCodec support.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/backend/services/ffmpeg_video_service.dart';

import 'video_capture.dart';

/// Android-specific video capture implementation
///
/// Architecture:
/// - Dart (this class) ← MethodChannel → Kotlin (FFmpegVideoPlugin)
/// - Kotlin uses JavaCPP FFmpeg bindings for video decoding
/// - Frames are rendered to native Android TextureView
class AndroidVideoCapture implements VideoCapture {
  @override
  Future<VideoCaptureResult> open(String url) async {
    debugPrint("📱 Android: Opening video stream");
    debugPrint("   URL: $url");

    // Socket diagnostic check (helps debug network issues)
    await _diagnosticSocketCheck(url);

    try {
      final result = await FFmpegVideoService.openVideo(url);
      if (result != null) {
        final streamId = result['videoId'] as int;
        final textureId = result['textureId'] as int;
        debugPrint(
          "✓ Android: Video opened (stream=$streamId, texture=$textureId)",
        );
        return VideoCaptureResult(streamId, textureId: textureId);
      } else {
        throw Exception("FFmpeg failed to open video");
      }
    } catch (e) {
      debugPrint("❌ Android: Failed to open video - $e");
      rethrow;
    }
  }

  @override
  Future<VideoCaptureFrame?> getFrame(int streamId) async {
    try {
      final frameData = await FFmpegVideoService.getFrame(streamId);

      if (frameData == null) {
        return null; // No frame available
      }

      final width = frameData['width'] as int;
      final height = frameData['height'] as int;
      final data = frameData['data'] as Uint8List;
      final timestamp = frameData['timestamp'] as int;

      return VideoCaptureFrame(data, width, height, timestamp);
    } catch (e) {
      debugPrint("❌ Android: Error getting frame - $e");
      return null;
    }
  }

  @override
  Future<void> release(int streamId) async {
    try {
      await FFmpegVideoService.releaseVideo(streamId);
      debugPrint("✓ Android: Video stream $streamId released");
    } catch (e) {
      debugPrint("❌ Android: Error releasing stream - $e");
    }
  }

  /// Diagnostic socket connectivity check
  ///
  /// Helps debug RTSP/network stream issues by testing TCP connectivity
  /// before attempting FFmpeg decoding.
  Future<void> _diagnosticSocketCheck(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty && uri.hasPort) {
        debugPrint(
          "DIAGNOSTIC: Testing socket connection to ${uri.host}:${uri.port}...",
        );
        final socket = await Socket.connect(
          uri.host,
          uri.port,
          timeout: const Duration(seconds: 3),
        );
        debugPrint("DIAGNOSTIC: ✓ Socket connected successfully");
        socket.destroy();
      }
    } catch (e) {
      debugPrint("DIAGNOSTIC: ⚠ Socket connection failed - $e");
      // Non-fatal - FFmpeg may still work
    }
  }
}
