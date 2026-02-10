import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smart_store_linux/backend/streaming/isolates/isolate_params.dart';
import 'package:smart_store_linux/core/models/frames.dart';

import 'package:smart_store_linux/backend/streaming/isolates/capture_isolate.dart';
import 'package:native_onnx/native_onnx.dart';

/// Manages the Capture Isolate lifecycle and raw message parsing.
class StreamCaptureManager {
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

  StreamCaptureManager({
    required this.streamUrl,
    required this.streamId,
    this.onFrameReceived,
    this.onProcessedFrameReceived,
    this.onLabelsReceived,
    this.onInitComplete,
  });

  /// Spawn the capture isolate
  Future<void> start(String? modelPath) async {
    _captureReceivePort = ReceivePort();
    try {
      debugPrint(
        'SCM: Spawning capture isolate for $streamId with modelPath=$modelPath',
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
      debugPrint("SCM: Failed to spawn capture isolate: $e");
    }
  }

  void _handleMessage(dynamic message) {
    if (message is Map &&
        message.containsKey('type') &&
        message['type'] == 'init') {
      if (message.containsKey('commandPort')) {
        _captureCommandPort = message['commandPort'] as SendPort;
        debugPrint("✓ SCM: Received command port");
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

        final bytes = transferable.materialize().asUint8List();
        final frame = RawFrame(bytes, width, height, timestamp);
        onFrameReceived?.call(frame);
      } else if (msgType == 'processed_frame') {
        // Optimized Linux Path (Frame + Inference)
        final transferable = message[1] as TransferableTypedData;
        final width = message[2] as int;
        final height = message[3] as int;
        final timestamp = message[4] as int;
        final detections = message[5] as List<dynamic>;
        final inferenceTime = (message.length > 6) ? message[6] as double : 0.0;

        final bytes = transferable.materialize().asUint8List();
        final now = DateTime.now().millisecondsSinceEpoch;

        final processed = ProcessedFrame(
          imageBytes: bytes,
          width: width,
          height: height,
          detections: detections,
          decodeStartMs: timestamp,
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
      debugPrint("SCM: Video Init. ID=$_nativeVideoId, Texture=$_textureId");
      onInitComplete?.call(_nativeVideoId, _textureId);
    } else if (message is int) {
      // Legacy Linux ID only
      _nativeVideoId = message;
      onInitComplete?.call(_nativeVideoId, null);
    }
  }

  Future<void> dispose() async {
    debugPrint("SCM: Disposing capture manager for $streamId");

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
        debugPrint("SCM: Error releasing video: $e");
      }
      _nativeVideoId = 0;
    }
  }
}
