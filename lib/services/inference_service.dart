import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/inference/inference_result.dart';
import 'package:smart_store_linux/inference/inference_worker.dart';
import 'package:smart_store_linux/inference/messages.dart';

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

  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _receivePort;
  bool _isServiceInitialized = false;
  Future<void>? _initFuture;

  /// Initialize the inference service and spawn worker isolate
  Future<void> init() async {
    if (_isServiceInitialized) return;
    if (_initFuture != null) return _initFuture;

    _initFuture = _doInit();
    return _initFuture;
  }

  /// Internal initialization implementation
  Future<void> _doInit() async {
    debugPrint("InferenceService: Initializing Worker Isolate...");

    _receivePort = ReceivePort();
    try {
      _workerIsolate = await Isolate.spawn(
        inferenceWorkerEntry,
        WorkerInit(_receivePort!.sendPort),
      );
    } catch (e) {
      debugPrint("Failed to spawn inference isolate: $e");
      _initFuture = null;
      return;
    }

    final completer = Completer<void>();
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message;
        debugPrint("InferenceService (Main): Received Worker SendPort");
      } else if (message is WorkerReady) {
        if (message.success) {
          debugPrint("InferenceService (Main): Worker signal READY SUCCESS");
          if (!completer.isCompleted) completer.complete();
        } else {
          debugPrint(
            "InferenceService (Main): Worker signal READY FAILED: ${message.error}",
          );
          if (!completer.isCompleted)
            completer.completeError(message.error ?? "Unknown Error");
        }
      } else if (message is WorkerResponse) {
        // Only log errors or actual detections
        if (message.error != null) {
          debugPrint(
            "⚠️ InferenceService: Error for ${message.streamId}: ${message.error}",
          );
        } else if (message.detections.isNotEmpty) {
          debugPrint(
            "✓ InferenceService: ${message.streamId} -> ${message.detections.length} detections",
          );
        }
        _resultStreamController.add(
          InferenceResult(
            streamId: message.streamId,
            requestId: message.requestId,
            detections: message.detections,
            modelPath: message.modelPath,
          ),
        );
      } else {
        debugPrint(
          "InferenceService (Main): Received unknown message type: ${message.runtimeType}",
        );
      }
    });

    try {
      // Increased timeout to 30 seconds for slow hardware/TensorRT compilation
      await completer.future.timeout(const Duration(seconds: 30));
      _isServiceInitialized = true;
      debugPrint(
        "Inference Service (Main): Worker Initialized and Fully Ready",
      );
    } catch (e) {
      debugPrint("Inference Service: Initialization Failed or Timed out: $e");
      _isServiceInitialized = false;
      _initFuture = null; // Allow retry if it failed/timed out
      _workerIsolate?.kill();
      _workerIsolate = null;
      _receivePort?.close();
      _receivePort = null;
    }
  }

  /// Enqueue a frame for inference
  void enqueueFrame(
    String streamId,
    int requestId,
    String modelPath,
    Uint8List bytes,
    int w,
    int h,
  ) {
    if (!_isServiceInitialized || _workerSendPort == null) {
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

  /// Load a model (currently a no-op as models are loaded on-demand)
  Future<void> loadModel(String modelPath) async {}

  /// Release the inference service and kill worker isolate
  Future<void> release() async {
    debugPrint("InferenceService: Releasing worker isolate...");

    // Kill the worker isolate to stop all inference threads
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;

    // Close the receive port
    _receivePort?.close();
    _receivePort = null;

    // Reset state
    _workerSendPort = null;
    _isServiceInitialized = false;
    _initFuture = null;

    debugPrint(
      "InferenceService: Worker isolate killed and resources released",
    );
  }
}
