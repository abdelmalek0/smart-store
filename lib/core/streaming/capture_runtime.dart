import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:smart_store_linux/core/models/frames.dart';

import 'package:smart_store_linux/core/streaming/capture/capture_isolate.dart';
import 'package:smart_store_linux/core/streaming/capture/isolate_params.dart';
import 'package:smart_store_linux/core/streaming/bridge/video_bridge.dart';
import 'package:native_onnx/native_onnx.dart';

/// Controls the Capture Isolate lifecycle and raw message parsing.
class CaptureRuntime {
  final String streamUrl;
  final String streamId;

  // Isolate state
  Isolate? _captureIsolate;
  ReceivePort? _captureReceivePort;
  SendPort? _captureCommandPort;

  // Native IDs
  int _nativeVideoId = 0;
  int? _textureId;

  // Getters
  int get nativeVideoId => _nativeVideoId;
  int? get textureId => _textureId;

  // Callbacks
  Function(RawFrame frame)? onFrameReceived;
  Function(ProcessedFrame frame)? onProcessedFrameReceived; // Optimized path
  Function(Map<int, String> labels)? onLabelsReceived;
  Function(int videoId, int? textureId)? onInitComplete;

  CaptureRuntime({
    required this.streamUrl,
    required this.streamId,
    this.onFrameReceived,
    this.onProcessedFrameReceived,
    this.onLabelsReceived,
    this.onInitComplete,
  });

  // Platform bridge — used for frame flushing on lag drop
  final VideoBridge _bridge = VideoBridge();

  /// Spawn the capture isolate
  Future<void> start(String? modelPath) async {
    _captureReceivePort = ReceivePort();
    try {
      debugPrint(
        'CaptureIsolateController: Spawning capture isolate for $streamId with modelPath=$modelPath',
      );

      _captureIsolate = await Isolate.spawn(
        captureLoop,
        IsolateInitParams(
          _captureReceivePort!.sendPort,
          streamUrl,
          RootIsolateToken.instance!,
          modelPath: modelPath,
        ),
      );

      _captureReceivePort!.listen(_handleMessage);
    } catch (e) {
      debugPrint(
        "CaptureIsolateController: Failed to spawn capture isolate: $e",
      );
    }
  }

  // Latency management
  // int? _firstFrameTimestamp;
  // int? _firstFrameWallTime;

  void _handleMessage(dynamic message) {
    if (message is Map &&
        message.containsKey('type') &&
        message['type'] == 'init') {
      if (message.containsKey('commandPort')) {
        _captureCommandPort = message['commandPort'] as SendPort;
        debugPrint("✓ CaptureIsolateController: Received command port");
      }
      return;
    }

    if (message is RawFrame) {
      onFrameReceived?.call(message);
      return;
    }

    if (message is List && message.isNotEmpty) {
      final msgType = message[0];

      if (msgType == 'frame') {
        // Standard Frame with TransferableTypedData
        final transferable = message[1] as TransferableTypedData;
        final width = message[2] as int;
        final height = message[3] as int;
        final timestamp = message[4] as int;

        // Robust Latency Check using Generation Time
        final now = DateTime.now().millisecondsSinceEpoch;
        final generationTime = message[5] as int;
        final lag = now - generationTime;

        debugPrint(
          "CaptureRuntime: TS=$timestamp Gen=$generationTime Lag=${lag}ms",
        );

        if (lag > 1000) {
          debugPrint(
            "CaptureRuntime: Dropping frame $timestamp (Queue Lag: ${lag}ms)",
          );

          // CRITICAL FIX: Flush the frame from Native Buffer!
          // If we simply drop it here, the native buffer fills up with unconsumed frames.
          // We must tell Native to "consume" it (showFrame removes it from buffer).
          if (_textureId != null) {
            try {
              _bridge.showFrame(_textureId!, timestamp);
            } catch (e) {
              // Ignore errors during flush
            }
          }

          // Do NOT materialize bytes to save CPU
          return;
        }

        final bytes = transferable.materialize().asUint8List();
        final frame = RawFrame(
          bytes,
          width,
          height,
          timestamp,
          generationTimeMs: generationTime,
        );
        onFrameReceived?.call(frame);
      } else if (msgType == 'processed_frame') {
        // Optimized Linux Path (Frame + Inference)
        final transferable = message[1] as TransferableTypedData;
        final width = message[2] as int;
        final height = message[3] as int;
        final timestamp = message[4] as int;

        // Robust Latency Check using Generation Time
        final now = DateTime.now().millisecondsSinceEpoch;
        if (message.length > 7) {
          final generationTime = message[7] as int;
          final lag = now - generationTime;

          debugPrint(
            "CaptureRuntime: Frame Lag: ${lag}ms (Gen: $generationTime, Now: $now)",
          );

          if (lag > 1000) {
            debugPrint(
              "CaptureRuntime: Dropping processed frame $timestamp (Queue Lag: ${lag}ms)",
            );

            // CRITICAL FIX: Flush Native Buffer
            if (_textureId != null) {
              try {
                NativeInferenceService().showFrame(_textureId!, timestamp);
              } catch (e) {
                // Ignore errors during flush to avoid spamming logs
              }
            }

            // Do NOT materialize bytes
            return;
          }
        }

        final detections = (message[5] as List<dynamic>?) ?? [];
        final inferenceTime = (message.length > 6) ? message[6] as double : 0.0;
        final generationTime = (message.length > 7)
            ? message[7] as int
            : 0; // Capture generation time

        final bytes = transferable.materialize().asUint8List();

        final processed = ProcessedFrame(
          imageBytes: bytes,
          width: width,
          height: height,
          detections: detections,
          decodeStartMs: timestamp,
          generationTimeMs: generationTime,
          preprocessEndMs: now - inferenceTime.toInt(),
          inferenceEndMs: now,
          postprocessEndMs: now,
        );
        onProcessedFrameReceived?.call(processed);
      } else if (msgType == 'labels') {
        final labelsMap = message[1] as Map<int, String>;
        onLabelsReceived?.call(labelsMap);
      }
    } else if (message is Map && message.containsKey('videoId')) {
      _nativeVideoId = message['videoId'] as int;
      _textureId = message['textureId'] as int;
      debugPrint(
        "CaptureIsolateController: Video Init. ID=$_nativeVideoId, Texture=$_textureId",
      );
      onInitComplete?.call(_nativeVideoId, _textureId);
    } else if (message is int) {
      // Legacy Linux ID only
      _nativeVideoId = message;
      onInitComplete?.call(_nativeVideoId, null);
    }
  }

  Future<void> dispose() async {
    debugPrint("CaptureIsolateController: Disposing for $streamId");

    // Stop isolate
    if (_captureCommandPort != null) {
      _captureCommandPort?.send('STOP');
      await Future.delayed(const Duration(milliseconds: 200));
      _captureCommandPort = null;
    }

    _captureIsolate?.kill(priority: Isolate.immediate);
    _captureIsolate = null;

    _captureReceivePort?.close();
    _captureReceivePort = null;

    // Release native
    if (_nativeVideoId > 0) {
      try {
        NativeInferenceService().videoRelease(_nativeVideoId);
      } catch (e) {
        debugPrint("CaptureIsolateController: Error releasing video: $e");
      }
      _nativeVideoId = 0;
    }
  }
}
