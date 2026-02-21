import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/features/inference/models/inference_result.dart';
import 'package:smart_store_linux/features/inference/worker/inference_worker.dart';
import 'package:smart_store_linux/features/inference/worker/messages.dart';

/// Single Runtime Instance for a specific Model
///
/// Responsibilities:
/// - Spawning and managing ONE inference worker isolate for THIS model
/// - Queuing inference requests
/// - Broadcasting inference results
class InferenceRuntime {
  final String modelPath;

  // Output stream for this specific model
  final StreamController<InferenceResult> _resultStreamController =
      StreamController<InferenceResult>.broadcast();
  Stream<InferenceResult> get resultsStream => _resultStreamController.stream;

  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;

  bool _isInitialized = false;
  bool _isDisposed = false;

  InferenceRuntime(this.modelPath);

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
        WorkerInit(receivePort.sendPort),
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

  /// Enqueue a frame for inference
  void enqueueFrame(
    String streamId,
    int requestId,
    Uint8List bytes,
    int w,
    int h,
  ) {
    if (!_isInitialized || _workerSendPort == null) {
      debugPrint("⚠️ InferenceRuntime not initialized for $modelPath");
      return;
    }

    _workerSendPort!.send(
      WorkerRequest(
        streamId: streamId,
        requestId: requestId,
        modelPath: modelPath,
        imageBytes: bytes,
        width: w,
        height: h,
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
