import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/domain/entities/inference_result.dart';
import 'package:smart_store_linux/infrastructure/ai/backend/android/android_device.dart';
import 'package:smart_store_linux/infrastructure/ai/worker/inference_worker.dart';
import 'package:smart_store_linux/infrastructure/ai/worker/messages.dart';
import 'package:smart_store_linux/infrastructure/streaming/stream_orchestrator.dart';

/// Single Runtime Instance for a specific Model
///
/// Responsibilities:
/// - Spawning and managing ONE inference worker isolate for THIS model
/// - Queuing inference requests
/// - Broadcasting inference results
class InferenceRuntime {
  final String modelPath;

  /// Hardware device to use for Android inference.
  /// Ignored on non-Android platforms.
  final InferenceDevice androidDevice;

  // Output stream for this specific model
  final StreamController<InferenceResult> _resultStreamController =
      StreamController<InferenceResult>.broadcast();
  Stream<InferenceResult> get resultsStream => _resultStreamController.stream;

  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;

  bool _isInitialized = false;
  bool _isDisposed = false;

  InferenceRuntime(this.modelPath,
      {this.androidDevice = InferenceDevice.rknn});

  /// Initialize the worker for this model
  Future<void> init() async {
    if (_isInitialized) return;
    if (_isDisposed) {
      throw Exception("Cannot re-initialize disposed InferenceRuntime");
    }

    debugPrint(
      "InferenceRuntime: Spawning worker for ${modelPath.split('/').last}",
    );

    final receivePort = ReceivePort();
    _workerReceivePort = receivePort;
    final completer = Completer<void>();

    try {
      _workerIsolate = await Isolate.spawn(
        inferenceWorkerEntry,
        WorkerInit(receivePort.sendPort, androidDevice: androidDevice),
      );
    } catch (e) {
      debugPrint("Failed to spawn inference isolate for $modelPath: $e");
      receivePort.close();
      rethrow;
    }

    receivePort.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message;
        debugPrint(
          "InferenceRuntime: Received SendPort for ${modelPath.split('/').last}",
        );
      } else if (message is WorkerReady) {
        if (message.success) {
          debugPrint(
            "InferenceRuntime: Worker ready for ${modelPath.split('/').last}",
          );
          if (!completer.isCompleted) completer.complete();
        } else {
          debugPrint(
            "InferenceRuntime: Worker failed for ${modelPath.split('/').last}: ${message.error}",
          );
          if (!completer.isCompleted) {
            completer.completeError(message.error ?? "Unknown Error");
          }
        }
      } else if (message is WorkerLabels) {
        // Forward labels to StreamOrchestrator for the associated stream(s)
        try {
          _labels = message.labels;
          for (final sid in _knownStreams) {
            StreamOrchestrator.instance.updateLabels(sid, message.labels);
          }
        } catch (e) {
          debugPrint("Failed to update labels: $e");
        }
      } else if (message is WorkerResponse) {
        // Forward to stream
        if (message.error != null) {
          debugPrint(
            "⚠️ InferenceRuntime: Error for ${message.streamId}: ${message.error}",
          );
        }

        if (!_resultStreamController.isClosed) {
          _resultStreamController.add(
            InferenceResult(
              streamId: message.streamId,
              requestId: message.requestId,
              detections: message.detections,
              modelPath: message.modelPath,
              processingStartMs: message.processingStartMs,
            ),
          );
        }
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 30));
      _isInitialized = true;
      debugPrint(
        "InferenceRuntime: Worker for ${modelPath.split('/').last} fully initialized",
      );
    } catch (e) {
      debugPrint(
        "InferenceRuntime: Worker initialization failed/timed out for $modelPath: $e",
      );
      dispose();
      rethrow;
    }
  }

  final Set<String> _knownStreams = {};
  Map<int, String> _labels = {};

  /// Enqueue a frame for inference
  void enqueueFrame(
    String streamId,
    int requestId,
    Uint8List bytes,
    int w,
    int h, {
    int? videoId,
  }) {
    if (!_isInitialized || _workerSendPort == null) {
      debugPrint("⚠️ InferenceRuntime not initialized for $modelPath");
      return;
    }

    if (!_knownStreams.contains(streamId)) {
      _knownStreams.add(streamId);
      if (_labels.isNotEmpty) {
        try {
          StreamOrchestrator.instance.updateLabels(streamId, _labels);
        } catch (_) {}
      }
    }

    _workerSendPort!.send(
      WorkerRequest(
        streamId: streamId,
        requestId: requestId,
        modelPath: modelPath,
        imageBytes: bytes,
        width: w,
        height: h,
        videoId: videoId,
      ),
    );
  }

  /// Release resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isInitialized = false;

    debugPrint(
      "InferenceRuntime: Disposing worker for ${modelPath.split('/').last}...",
    );

    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;

    _workerReceivePort?.close();
    _workerReceivePort = null;

    _workerSendPort = null;

    await _resultStreamController.close();
  }
}
