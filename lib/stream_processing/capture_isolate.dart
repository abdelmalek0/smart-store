import 'dart:async';
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
  int consecutiveErrors = 0;

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
      final id = await FFmpegVideoService.openVideo(params.videoUrl);
      if (id != null) {
        params.sendPort.send(id);
        debugPrint("✓ FFmpeg: Video opened (id=$id)");
      } else {
        debugPrint("❌ FFmpeg: Failed to open video");
      }
      return id;
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
        consecutiveErrors = 0;
      }

      try {
        final frameData = await FFmpegVideoService.getFrame(videoId!);

        if (frameData != null) {
          final width = frameData['width'] as int;
          final height = frameData['height'] as int;
          final data = frameData['data'] as Uint8List;

          consecutiveErrors = 0;
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          params.sendPort.send(RawFrame(data, width, height, timestamp));
        } else {
          consecutiveErrors++;
          // Increased threshold: FFmpeg takes 3-5 seconds to initialize grabber
          if (consecutiveErrors > 200) {
            // ~6.6 seconds at 33ms polls
            debugPrint("FFmpeg: Too many errors, reconnecting...");
            await FFmpegVideoService.releaseVideo(videoId!);
            videoId = null;
            consecutiveErrors = 0;
          }
        }
      } catch (e) {
        debugPrint("FFmpeg capture error: $e");
        consecutiveErrors++;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Poll at ~30 FPS
      await Future.delayed(const Duration(milliseconds: 33));
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
