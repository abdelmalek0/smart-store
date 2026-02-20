import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/ai/registry/model_registry.dart';
import 'package:smart_store_linux/ai/model_runtime.dart';
import 'package:smart_store_linux/ai/models/inference_result.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

/// Active Orchestrator for Models.
///
/// Acts as the gateway for inference requests.
class ModelManager {
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  static ModelManager get instance => _instance;
  ModelManager._internal();

  final StreamController<InferenceResult> _globalResultController =
      StreamController<InferenceResult>.broadcast();

  /// Global stream of inference results from all models
  Stream<InferenceResult> get resultsStream => _globalResultController.stream;

  Map<String, ModelConfig> _models = {};

  void initialize(List<ModelConfig> configs) {
    _models = {for (var m in configs) m.id: m};
  }

  ModelConfig? getModel(String id) => _models[id];

  /// Request inference for a specific frame from a specific stream.
  Future<void> requestInference({
    required String streamId,
    required int requestId,
    required String modelPath,
    required Uint8List imageBytes,
    required int width,
    required int height,
  }) async {
    // 1. Get or Create Runtime
    ModelRuntime? runtime = ModelRegistry.instance.getRuntime(modelPath);

    if (runtime == null) {
      try {
        debugPrint("[ModelManager] Initializing runtime for $modelPath");
        runtime = ModelRuntime(modelPath);

        // Pipe results to global stream
        runtime.resultsStream.listen((result) {
          _globalResultController.add(result);
        });

        await runtime.init();
        ModelRegistry.instance.registerRuntime(modelPath, runtime);
      } catch (e) {
        debugPrint(
          "❌ [ModelManager] Failed to initialize runtime for $modelPath: $e",
        );
        return;
      }
    }

    // 2. Enqueue Frame
    runtime.enqueueFrame(streamId, requestId, imageBytes, width, height);
  }

  /// Release all resources
  Future<void> release() async {
    debugPrint("[ModelManager] Releasing all runtimes...");
    final runtimes = ModelRegistry.instance.runtimes;
    for (var runtime in runtimes) {
      if (runtime is ModelRuntime) {
        await runtime.dispose();
      }
    }
    ModelRegistry.instance.clear();
  }
}
