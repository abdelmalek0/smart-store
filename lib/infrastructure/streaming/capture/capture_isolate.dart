/// Video Capture Isolate
///
/// Long-lived isolate for capturing video frames in the background.
/// Platform-specific video capture is handled by VideoCapture implementations.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smart_store_linux/infrastructure/streaming/capture/video_capture/video_capture.dart';
import 'package:smart_store_linux/infrastructure/streaming/capture/video_capture/linux/linux_video_capture.dart';
import 'package:smart_store_linux/infrastructure/streaming/capture/isolate_params.dart';

/// Isolate entry point for video capture
void captureLoop(IsolateInitParams params) {
  _captureLoopAsync(params);
}

/// Unified capture loop for all platforms
///
/// Uses platform-specific VideoCapture implementations to handle:
/// - Android: FFmpeg via MethodChannel
/// - Linux: NVDEC + OpenCV via FFI
Future<void> _captureLoopAsync(IsolateInitParams params) async {
  // Initialize platform messenger for MethodChannel calls (required on Android)
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.rootIsolateToken);

  debugPrint("📹 Starting video capture isolate");
  debugPrint("   Platform: ${Platform.operatingSystem}");
  debugPrint("   URL: ${params.videoUrl}");

  // Create platform-specific video capture implementation
  final capture = VideoCapture();

  // Linux: Registry labels (removed in this path)

  VideoCaptureResult? videoStream;
  int lastFrameTime = DateTime.now().millisecondsSinceEpoch;
  int frameCount = 0;
  int lastFrameProcessedTime = DateTime.now().millisecondsSinceEpoch;

  // Per-frame target interval derived from the video's native FPS.
  // 0 = live/RTSP stream: the blocking FFI call self-paces; no extra delay needed.
  int targetFrameMs = 0;

  Future<VideoCaptureResult?> openVideo() async {
    try {
      final result = await capture.open(params.videoUrl);

      // Send initialization message to parent isolate
      if (result.textureId != null) {
        // Android: send both stream ID and texture ID
        params.sendPort.send({
          'videoId': result.streamId,
          'textureId': result.textureId,
        });
      } else {
        // Linux: send stream ID only
        params.sendPort.send(result.streamId);
      }

      // Derive per-frame target delay from native FPS.
      // 0.0 = live stream → no artificial pacing.
      if (result.nativeFps > 0) {
        targetFrameMs = (1000 / result.nativeFps).round();
        debugPrint('✓ Video FPS: ${result.nativeFps.toStringAsFixed(2)} → target frame interval: ${targetFrameMs}ms');
      } else {
        targetFrameMs = 0; // RTSP: self-pacing
        debugPrint('✓ Video: live/RTSP stream — no frame-rate pacing applied');
      }

      debugPrint("✓ Video stream opened (ID: ${result.streamId})");
      return result;
    } catch (e) {
      debugPrint("❌ Failed to open video: $e");
      return null;
    }
  }

  // Open video stream
  videoStream = await openVideo();

  try {
    // Create command port for graceful shutdown
    final commandPort = ReceivePort();
    bool isRunning = true;

    // Send initialization message to parent isolate
    // We send a Map first to provide the command port
    params.sendPort.send({'type': 'init', 'commandPort': commandPort.sendPort});

    // Listen for commands
    commandPort.listen((message) {
      if (message == 'STOP') {
        debugPrint("🛑 Capture Isolate received STOP command");
        isRunning = false;
        commandPort.close();
      }
    });

    // Main capture loop
    while (isRunning) {
      // Reconnect if stream is not open
      if (videoStream == null) {
        if (!isRunning) break;
        videoStream = await openVideo();
        if (videoStream == null) {
          // Wait but check running status frequently
          for (int i = 0; i < 20 && isRunning; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
          continue;
        }
      }

      // Record iteration start time for accurate frame-rate pacing.
      // Must be captured BEFORE the blocking FFI call so the Dart sleep
      // correctly accounts for the time spent inside the C++ decoder.
      final iterStartMs = DateTime.now().millisecondsSinceEpoch;

      try {
        if (!isRunning) break;

        // Get next frame
        final frame = await capture.getFrame(videoStream.streamId);

        if (frame != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          lastFrameTime = now;
          frameCount++;

          final timeSinceLastFrame = now - lastFrameProcessedTime;
          lastFrameProcessedTime = now;

          // Standard frame (no inference)
          final transferable = frame.data.isEmpty ? null : TransferableTypedData.fromList([frame.data]);
          params.sendPort.send([
            'frame',
            transferable,
            frame.width,
            frame.height,
            frame.timestamp,
            DateTime.now().millisecondsSinceEpoch, // generationTime
          ]);
        } else {
          // No frame available - check watchdog
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastFrameTime > 5000) {
            debugPrint("⚠️  No frames for 5s, reconnecting...");
            await capture.release(videoStream.streamId);
            videoStream = null;
            lastFrameTime = now;
          }
        }
      } catch (e) {
        debugPrint("❌ Frame capture error: $e");
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Frame-rate pacing:
      // - File sources (targetFrameMs > 0): sleep for the remaining time in the
      //   frame interval so we decode at the video's native FPS, not as fast as
      //   the GPU can decode.
      // - RTSP/live (targetFrameMs == 0): tiny yield only; the blocking FFI call
      //   already self-paces at the stream's live rate.
      if (isRunning) {
        if (targetFrameMs > 0) {
          // Sleep only the time remaining in this frame's interval.
          // iterStartMs accounts for the FFI decode time so we don't
          // double-count: C++ no longer sleeps (WAIT branch removed),
          // so all pacing is done here.
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsed = now - iterStartMs;
          // Subtract 1ms to compensate for Dart's Future.delayed overshoot.
          // On Linux the event loop typically delivers ~1-2ms late, which
          // accumulates to ~5fps loss at 60fps. Waking up 1ms early keeps us
          // close to the native frame rate without busy-waiting.
          const int timerCorrectionMs = 1;
          final remaining = targetFrameMs - elapsed - timerCorrectionMs;
          if (remaining > 0) {
            await Future.delayed(Duration(milliseconds: remaining));
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
    }
  } finally {
    // Cleanup
    if (videoStream != null) {
      await capture.release(videoStream.streamId);
    }

    // Dispose Linux-specific resources
    if (capture is LinuxVideoCapture) {
      capture.dispose();
    }

    debugPrint("✓ Video capture isolate terminated");
  }
}
