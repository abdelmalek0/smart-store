import 'package:smart_store_linux/domain/entities/raw_frame.dart';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:smart_store_linux/domain/entities/processed_frame.dart';

import 'package:smart_store_linux/infrastructure/streaming/capture/capture_isolate.dart';
import 'package:smart_store_linux/infrastructure/streaming/capture/isolate_params.dart';
import 'package:smart_store_linux/infrastructure/streaming/bridge/video_bridge.dart';
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
  int? _textureManagerId;

  // Getters
  int get nativeVideoId => _nativeVideoId;
  int? get textureId => _textureId;
  int? get textureManagerId => _textureManagerId;

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
  Future<void> start() async {
    _captureReceivePort = ReceivePort();
    try {
      debugPrint(
        'CaptureIsolateController: Spawning capture isolate for $streamId',
      );

      _captureIsolate = await Isolate.spawn(
        captureLoop,
        IsolateInitParams(
          _captureReceivePort!.sendPort,
          streamUrl,
          RootIsolateToken.instance!,
          modelPath: null, // Force null - no inference in capture loop
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
        final transferable = message[1] as TransferableTypedData?;
        final width = message[2] as int;
        final height = message[3] as int;
        final timestamp = message[4] as int;

        // Robust Latency Check using Generation Time
        final now = DateTime.now().millisecondsSinceEpoch;
        final generationTime = message[5] as int;
        final lag = now - generationTime;

        if (lag > 1000) {
          debugPrint(
            "CaptureRuntime: Dropping frame $timestamp (Queue Lag: ${lag}ms)",
          );

          // CRITICAL FIX: Flush the frame from Native Buffer!
          if (_textureManagerId != null) {
            try {
              _bridge.showFrame(_textureManagerId!, timestamp);
            } catch (e) {
              // Ignore errors during flush
            }
          }

          // Do NOT materialize bytes to save CPU
          return;
        }

        final bytes = transferable?.materialize().asUint8List() ?? Uint8List(0);
        final frame = RawFrame(
          bytes,
          width,
          height,
          timestamp,
          generationTimeMs: generationTime,
          nativeVideoId: _nativeVideoId, // Pass native ID for downstream inference
        );
        onFrameReceived?.call(frame);
      } else if (msgType == 'labels') {
        final labelsMap = message[1] as Map<int, String>;
        onLabelsReceived?.call(labelsMap);
      }
    } else if (message is Map && message.containsKey('videoId')) {
      _nativeVideoId = message['videoId'] as int;
      _textureId = message['textureId'] as int?;
      _textureManagerId = message['textureManagerId'] as int?;
      debugPrint(
        "CaptureIsolateController: Video Init. ID=$_nativeVideoId, Texture=$_textureId, Mgr=$_textureManagerId",
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
