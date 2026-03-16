import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:smart_store_linux/infrastructure/ai/backend/android/android_device.dart';
import 'package:smart_store_linux/infrastructure/ai/registry/model_registry.dart';
import 'package:smart_store_linux/infrastructure/ai/inference_runtime.dart';
import 'package:smart_store_linux/domain/entities/inference_result.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';

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

  /// Fallback Android inference device used when the model format cannot be
  /// determined from the file extension. Defaults to [InferenceDevice.rknn].
  InferenceDevice androidDevice = InferenceDevice.rknn;

  /// Infer the appropriate [InferenceDevice] from the model file extension.
  ///
  /// - `.tflite` → [InferenceDevice.gpu]
  ///   The TFLite backend will try: GPU delegate → XNNPack → bare CPU
  ///   automatically, so requesting `gpu` is safe on all devices including
  ///   emulators (delegates that are unavailable are caught and skipped).
  /// - anything else (`.rknn`, `.onnx`, …) → [InferenceDevice.rknn]
  ///   (RKNN NPU with automatic TFLite CPU fallback on non-Rockchip devices)
  InferenceDevice _deviceForPath(String path) {
    if (path.toLowerCase().endsWith('.tflite')) return InferenceDevice.gpu;
    return InferenceDevice.rknn;
  }

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
    InferenceDevice? device,
  }) async {
    // 1. Get or Create Runtime
    InferenceRuntime? runtime = InferenceRegistry.instance.getRuntime(modelPath);

    if (runtime == null) {
      final selectedDevice = device ?? _deviceForPath(modelPath);
      try {
        log('[ModelManager] Initializing runtime for $modelPath (device=$selectedDevice)');
        runtime = InferenceRuntime(modelPath, androidDevice: selectedDevice);

        // Pipe results to global stream
        runtime.resultsStream.listen((result) {
          _globalResultController.add(result);
        });

        await runtime.init();
        InferenceRegistry.instance.registerRuntime(modelPath, runtime);
      } catch (e) {
        log('❌ [ModelManager] Failed to initialize runtime for $modelPath: $e');
        return;
      }
    }

    // 2. Enqueue Frame
    runtime.enqueueFrame(streamId, requestId, imageBytes, width, height);
  }

  /// Release all resources
  Future<void> release() async {
    log('[ModelManager] Releasing all runtimes...');
    final runtimes = InferenceRegistry.instance.runtimes;
    for (var runtime in runtimes) {
      if (runtime is InferenceRuntime) {
        await runtime.dispose();
      }
    }
    InferenceRegistry.instance.clear();
  }
}
