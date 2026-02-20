import 'package:smart_store_linux/ai/models/model_info.dart';

/// Central registry for AI Models.
///
/// Serves as the single source of truth for available models.
class ModelRegistry {
  static final ModelRegistry _instance = ModelRegistry._internal();
  factory ModelRegistry() => _instance;
  static ModelRegistry get instance => _instance;
  ModelRegistry._internal();

  final Map<String, ModelInfo> _models = {};
  // Map modelPath -> ModelRuntime
  final Map<String, dynamic> _runtimes = {};

  /// Get all registered models
  List<ModelInfo> get models => _models.values.toList();

  /// Register a model
  void register(ModelInfo model) {
    _models[model.id] = model;
  }

  /// Unregister a model
  void unregister(String modelId) {
    _models.remove(modelId);
  }

  /// Get a model by ID
  ModelInfo? get(String modelId) {
    return _models[modelId];
  }

  /// Register a runtime instance
  void registerRuntime(String modelPath, dynamic runtime) {
    _runtimes[modelPath] = runtime;
  }

  /// Get a runtime instance
  dynamic getRuntime(String modelPath) {
    return _runtimes[modelPath];
  }

  /// Unregister a runtime instance
  void unregisterRuntime(String modelPath) {
    _runtimes.remove(modelPath);
  }

  /// Get all active runtimes
  List<dynamic> get runtimes => _runtimes.values.toList();

  /// Clear all models and runtimes
  void clear() {
    _models.clear();
    _runtimes.clear();
  }
}
