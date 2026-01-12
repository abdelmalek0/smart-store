import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/models/frames.dart';
import 'package:smart_store_linux/stream_processing/isolate_params.dart';
import 'package:smart_store_linux/services/ffmpeg_video_service.dart';

/// Long-lived isolate entry point for video capture
void captureLoop(IsolateInitParams params) {
  _captureLoopAsync(params);
}

/// Async implementation - platform specific
Future<void> _captureLoopAsync(IsolateInitParams params) async {
  if (Platform.isAndroid) {
    await _androidFFmpegCaptureLoop(params);
  } else {
    await _linuxOpenCVCaptureLoop(params);
  }
}

/// Android: FFmpeg via MethodChannel
Future<void> _androidFFmpegCaptureLoop(IsolateInitParams params) async {
  // Initialize BackgroundIsolateBinaryMessenger for MethodChannel calls
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.rootIsolateToken);

  debugPrint("📱 Android: Starting FFmpeg capture via JavaCPP");
  debugPrint("   URL: ${params.videoUrl}");

  int? videoId;
  int lastFrameTime =
      DateTime.now().millisecondsSinceEpoch; // Time-based watchdog

  Future<int?> openVideo() async {
    // --- DIAGNOSTIC START ---
    try {
      final uri = Uri.parse(params.videoUrl); // Basic parsing
      // If parsing fails or host is empty, likely RTSP syntax issues, but let's try
      if (uri.host.isNotEmpty && uri.hasPort) {
        debugPrint(
          "DART DIAGNOSTIC: Attempting Socket connect to ${uri.host}:${uri.port}...",
        );
        final socket = await Socket.connect(
          uri.host,
          uri.port,
          timeout: const Duration(seconds: 3),
        );
        debugPrint(
          "DART DIAGNOSTIC: ✓ Socket connected successfully to ${uri.host}:${uri.port}",
        );
        socket.destroy();
      } else {
        debugPrint(
          "DART DIAGNOSTIC: Could not parse host/port from URL: ${params.videoUrl}",
        );
      }
    } catch (e) {
      debugPrint("DART DIAGNOSTIC: ❌ Socket connection failed: $e");
    }
    // --- DIAGNOSTIC END ---

    try {
      final result = await FFmpegVideoService.openVideo(params.videoUrl);
      if (result != null) {
        final streamId = result['videoId'] as int;
        final textureId = result['textureId'] as int;
        debugPrint(
          "Capture: Opened video stream $streamId with texture $textureId",
        );

        // Send initialization success with texture ID
        // Protocol: Map { 'videoId': int, 'textureId': int }
        params.sendPort.send({'videoId': streamId, 'textureId': textureId});
        return streamId;
      } else {
        debugPrint("❌ FFmpeg: Failed to open video");
        return null;
      }
    } catch (e) {
      debugPrint("❌ FFmpeg open error: $e");
      return null;
    }
  }

  videoId = await openVideo();

  try {
    while (true) {
      if (videoId == null) {
        videoId = await openVideo();
        if (videoId == null) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
      }

      try {
        final frameData = await FFmpegVideoService.getFrame(videoId!);

        if (frameData != null) {
          final width = frameData['width'] as int;
          final height = frameData['height'] as int;
          final data = frameData['data'] as Uint8List;

          lastFrameTime =
              DateTime.now().millisecondsSinceEpoch; // Reset watchdog

          // Use native timestamp for sync
          final timestamp = frameData['timestamp'] as int;

          // OPTIMIZATION: Use TransferableTypedData to avoid copying data between isolates
          // Protocol: ['frame', TransferableTypedData, width, height, timestamp]
          final transferable = TransferableTypedData.fromList([data]);
          params.sendPort.send([
            'frame',
            transferable,
            width,
            height,
            timestamp,
          ]);
        } else {
          // No frame available (native buffer empty or not ready)
          final now = DateTime.now().millisecondsSinceEpoch;
          // Watchdog: If no frames for 5 seconds, reconnect
          if (now - lastFrameTime > 5000) {
            debugPrint("FFmpeg: No frames for 5s (Watchdog), reconnecting...");
            await FFmpegVideoService.releaseVideo(videoId!);
            videoId = null;
            lastFrameTime = now; // Prevent immediate double-trigger
          }
        }
      } catch (e) {
        debugPrint("FFmpeg capture error: $e");
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Poll frequently (1ms) to pick up frames immediately
      // Native side is now throttled to 30fps, so we want low-latency pickup
      await Future.delayed(const Duration(milliseconds: 1));
    }
  } finally {
    if (videoId != null) {
      await FFmpegVideoService.releaseVideo(videoId!);
    }
  }
}

/// Linux: OpenCV video capture via native_onnx
Future<void> _linuxOpenCVCaptureLoop(IsolateInitParams params) async {
  debugPrint("🐧 Linux: Starting OpenCV capture");

  try {
    await NativeInferenceService().init();
  } catch (e) {
    debugPrint("❌ Native Init Failed: $e");
    return;
  }

  int videoId = 0;
  int consecutiveErrors = 0;

  int openVideo() {
    final id = NativeInferenceService().videoOpen(params.videoUrl);
    if (id != 0) {
      params.sendPort.send(id);
      debugPrint("✓ OpenCV: Video opened (id=$id)");
    } else {
      debugPrint("❌ OpenCV: Failed to open");
    }
    return id;
  }

  videoId = openVideo();

  final bufferPtrPtr = calloc<Pointer<Uint8>>();
  final widthPtr = calloc<Int32>();
  final heightPtr = calloc<Int32>();

  try {
    while (true) {
      if (videoId == 0) {
        videoId = openVideo();
        if (videoId == 0) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        consecutiveErrors = 0;
      }

      try {
        final result = NativeInferenceService().videoGetFrame(
          videoId,
          bufferPtrPtr,
          widthPtr,
          heightPtr,
        );

        if (result == 0) {
          consecutiveErrors = 0;
          final w = widthPtr.value;
          final h = heightPtr.value;
          final dataPtr = bufferPtrPtr.value;

          if (w > 0 && h > 0 && dataPtr != nullptr) {
            final length = w * h * 4;
            final list = Uint8List.fromList(dataPtr.asTypedList(length));
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            params.sendPort.send(RawFrame(list, w, h, timestamp));
          }
        } else {
          consecutiveErrors++;
          if (consecutiveErrors > 30) {
            debugPrint("OpenCV: Too many errors, reconnecting...");
            NativeInferenceService().videoRelease(videoId);
            videoId = 0;
            consecutiveErrors = 0;
          }
        }
      } catch (e) {
        debugPrint("OpenCV error: $e");
        consecutiveErrors++;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await Future.delayed(Duration.zero);
    }
  } finally {
    calloc.free(bufferPtrPtr);
    calloc.free(widthPtr);
    calloc.free(heightPtr);
    if (videoId != 0) {
      NativeInferenceService().videoRelease(videoId);
    }
  }
}
