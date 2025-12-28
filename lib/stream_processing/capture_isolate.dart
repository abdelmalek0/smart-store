import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/models/frames.dart';
import 'package:smart_store_linux/stream_processing/isolate_params.dart';

/// Long-lived isolate entry point for video capture (must be synchronous)
void captureLoop(IsolateInitParams params) {
  // Capture loop entry - no log needed
  _captureLoopAsync(params);
}

/// Async implementation of the video capture loop
Future<void> _captureLoopAsync(IsolateInitParams params) async {
  // Init Native Service ONCE
  try {
    await NativeInferenceService().init();
  } catch (e) {
    debugPrint("❌ Capture Isolate Init Failed: $e");
    return;
  }

  // 2. Open Video INSIDE Isolate
  int videoId = 0;
  int consecutiveErrors = 0;

  int openVideo() {
    final id = NativeInferenceService().videoOpen(params.videoUrl);
    if (id != 0) {
      params.sendPort.send(id);
    } else {
      debugPrint("❌ Failed to open: ${params.videoUrl}");
    }
    return id;
  }

  videoId = openVideo();

  final bufferPtrPtr = calloc<Pointer<Uint8>>();
  final widthPtr = calloc<Int32>();
  final heightPtr = calloc<Int32>();

  try {
    // Main capture loop - no verbose logging
    while (true) {
      // Reconnection Logic
      if (videoId == 0) {
        videoId = openVideo();
        if (videoId == 0) {
          // Wait before retry
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        consecutiveErrors = 0;
      }

      try {
        final resultArray = NativeInferenceService().videoGetFrame(
          videoId,
          bufferPtrPtr,
          widthPtr,
          heightPtr,
        );

        // 0 = Success
        if (resultArray == 0) {
          consecutiveErrors = 0;
          final w = widthPtr.value;
          final h = heightPtr.value;
          final dataPtr = bufferPtrPtr.value;

          if (w > 0 && h > 0 && dataPtr != nullptr) {
            final length = w * h * 4;
            final list = Uint8List.fromList(dataPtr.asTypedList(length));
            final decodeTimestamp = DateTime.now().millisecondsSinceEpoch;
            params.sendPort.send(RawFrame(list, w, h, decodeTimestamp));
          }
        } else {
          // Handle Error
          consecutiveErrors++;

          if (consecutiveErrors > 30) {
            debugPrint(
              "Capture Isolate: Too many errors ($consecutiveErrors). Reconnecting video...",
            );
            NativeInferenceService().videoRelease(videoId);
            videoId = 0; // Trigger re-open next loop
            consecutiveErrors = 0;
          } else {
            // Only log occasionally to avoid spam
            if (consecutiveErrors % 10 == 0) {
              debugPrint(
                "Native Video Error for ID $videoId: Code $resultArray (Count: $consecutiveErrors)",
              );
            }
            // No delay for transient errors - fail fast for low latency
          }
        }
      } catch (e) {
        debugPrint("Capture Isolate inner Error: $e");
        consecutiveErrors++;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // No artificial delay - let NVDEC naturally throttle based on stream FPS
      // This eliminates decode time jitter caused by forced 1ms waits
      await Future.delayed(Duration.zero);
    }
  } catch (e) {
    debugPrint("Capture Isolate Error: $e");
  } finally {
    calloc.free(bufferPtrPtr);
    calloc.free(widthPtr);
    calloc.free(heightPtr);
    if (videoId != 0) {
      NativeInferenceService().videoRelease(videoId);
    }
  }
}
