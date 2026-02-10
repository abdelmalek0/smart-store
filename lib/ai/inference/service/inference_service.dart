import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/ai/inference/inference_result.dart';
import 'package:smart_store_linux/ai/inference/worker/inference_worker.dart';
import 'package:smart_store_linux/ai/inference/messages.dart';

/// Service for managing inference in a background isolate
///
/// Responsibilities:
/// - Spawning and managing the inference worker isolate
/// - Queuing inference requests
/// - Broadcasting inference results
/// - Loading models
class InferenceService {
  // Singleton pattern
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  static InferenceService get instance => _instance;
  InferenceService._internal();

  final StreamController<InferenceResult> _resultStreamController =
      StreamController<InferenceResult>.broadcast();
  Stream<InferenceResult> get resultsStream => _resultStreamController.stream;

  // Multi-worker architecture: one worker per model
  final Map<String, Isolate> _workerIsolates = {};
  final Map<String, SendPort> _workerSendPorts = {};
  final Map<String, ReceivePort> _workerReceivePorts = {};
  final Map<String, Completer<void>> _workerInitCompleters = {};

  bool _isServiceInitialized = false;

  /// Initialize the inference service
  Future<void> init() async {
    if (_isServiceInitialized) return;
    _isServiceInitialized = true;
    debugPrint("InferenceService: Multi-worker architecture initialized");
  }

  /// Spawn a worker for a specific model (called on-demand)
  Future<void> _spawnWorkerForModel(String modelPath) async {
    if (_workerIsolates.containsKey(modelPath)) {
      return; // Already spawned
    }

    debugPrint(
      "InferenceService: Spawning worker for model: ${modelPath.split('/').last}",
    );

    final receivePort = ReceivePort();
    _workerReceivePorts[modelPath] = receivePort;

    final completer = Completer<void>();
    _workerInitCompleters[modelPath] = completer;

    try {
      final isolate = await Isolate.spawn(
        inferenceWorkerEntry,
        WorkerInit(receivePort.sendPort),
      );
      _workerIsolates[modelPath] = isolate;
    } catch (e) {
      debugPrint("Failed to spawn inference isolate for $modelPath: $e");
      receivePort.close();
      _workerReceivePorts.remove(modelPath);
      _workerInitCompleters.remove(modelPath);
      rethrow;
    }

    receivePort.listen((message) {
      if (message is SendPort) {
        _workerSendPorts[modelPath] = message;
        debugPrint(
          "InferenceService: Received SendPort for ${modelPath.split('/').last}",
        );
      } else if (message is WorkerReady) {
        if (message.success) {
          debugPrint(
            "InferenceService: Worker ready for ${modelPath.split('/').last}",
          );
          if (!completer.isCompleted) completer.complete();
        } else {
          debugPrint(
            "InferenceService: Worker failed for ${modelPath.split('/').last}: ${message.error}",
          );
          if (!completer.isCompleted) {
            completer.completeError(message.error ?? "Unknown Error");
          }
        }
      } else if (message is WorkerResponse) {
        // Only log errors or actual detections
        if (message.error != null) {
          debugPrint(
            "⚠️ InferenceService: Error for ${message.streamId}: ${message.error}",
          );
        } else if (message.detections.isNotEmpty) {
          debugPrint(
            "✓ InferenceService: ${message.streamId} → ${message.detections.length} detections",
          );
        }

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
    });

    try {
      await completer.future.timeout(const Duration(seconds: 30));
      debugPrint(
        "InferenceService: Worker for ${modelPath.split('/').last} fully initialized",
      );
    } catch (e) {
      debugPrint(
        "InferenceService: Worker initialization failed or timed out for $modelPath: $e",
      );
      _workerIsolates[modelPath]?.kill();
      _workerIsolates.remove(modelPath);
      _workerSendPorts.remove(modelPath);
      _workerReceivePorts[modelPath]?.close();
      _workerReceivePorts.remove(modelPath);
      _workerInitCompleters.remove(modelPath);
      rethrow;
    }
  }

  /// Enqueue a frame for inference (routes to correct worker based on model)
  void enqueueFrame(
    String streamId,
    int requestId,
    String modelPath,
    Uint8List bytes,
    int w,
    int h,
  ) async {
    if (!_isServiceInitialized) {
      debugPrint("⚠️ InferenceService not initialized");
      return;
    }

    // Spawn worker if it doesn't exist for this model
    if (!_workerSendPorts.containsKey(modelPath)) {
      try {
        await _spawnWorkerForModel(modelPath);
      } catch (e) {
        debugPrint("❌ Failed to spawn worker for $modelPath: $e");
        return;
      }
    }

    final sendPort = _workerSendPorts[modelPath];
    if (sendPort == null) {
      debugPrint("⚠️ No worker available for model: $modelPath");
      return;
    }

    sendPort.send(
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

  /// Load a model (currently a no-op as models are loaded on-demand)
  Future<void> loadModel(String modelPath) async {}

  /// Release the inference service and kill all worker isolates
  Future<void> release() async {
    debugPrint(
      "InferenceService: Releasing ${_workerIsolates.length} worker isolates...",
    );

    // Kill all worker isolates
    for (var entry in _workerIsolates.entries) {
      entry.value.kill(priority: Isolate.immediate);
      debugPrint(
        "InferenceService: Killed worker for ${entry.key.split('/').last}",
      );
    }

    _workerIsolates.clear();

    // Close all receive ports
    for (var receivePort in _workerReceivePorts.values) {
      receivePort.close();
    }
    _workerReceivePorts.clear();

    // Clear send ports
    _workerSendPorts.clear();

    // Clear completers
    _workerInitCompleters.clear();

    // Reset state
    _isServiceInitialized = false;

    debugPrint(
      "InferenceService: All worker isolates killed and resources released",
    );
  }
}
