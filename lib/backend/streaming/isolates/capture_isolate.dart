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
import 'package:smart_store_linux/backend/video/capture/video_capture/video_capture.dart';
import 'package:smart_store_linux/backend/video/capture/video_capture/linux/linux_video_capture.dart';
import 'package:smart_store_linux/backend/streaming/isolates/isolate_params.dart';

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

  // Linux: Enable optimized inference path if model provided
  if (Platform.isLinux &&
      params.modelPath != null &&
      capture is LinuxVideoCapture) {
    await capture.enableOptimizedInference(params.modelPath!);

    // Send labels to parent isolate for UI access
    final labels = LinuxVideoCapture.modelLabels;
    if (labels.isNotEmpty) {
      params.sendPort.send(['labels', labels]);
      debugPrint("📋 Sent ${labels.length} labels to main isolate");
    }
  }

  VideoCaptureResult? videoStream;
  int lastFrameTime = DateTime.now().millisecondsSinceEpoch;

  // Frame rate limiting (removed)

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

      try {
        if (!isRunning) break;

        // Get next frame
        final frame = await capture.getFrame(videoStream.streamId);

        if (frame != null) {
          lastFrameTime = DateTime.now().millisecondsSinceEpoch;

          // Check if this is an optimized frame with inference results
          if (frame is LinuxOptimizedFrame) {
            // Send processed frame message
            final transferable = TransferableTypedData.fromList([frame.data]);
            params.sendPort.send([
              'processed_frame',
              transferable,
              frame.width,
              frame.height,
              frame.timestamp,
              frame.detections,
              frame.inferenceTime,
            ]);
          } else {
            // Standard frame
            final transferable = TransferableTypedData.fromList([frame.data]);
            params.sendPort.send([
              'frame',
              transferable,
              frame.width,
              frame.height,
              frame.timestamp,
            ]);
          }
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

      // Minimal delay for high frame rate (check running status)
      if (isRunning) {
        await Future.delayed(const Duration(milliseconds: 1));
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
