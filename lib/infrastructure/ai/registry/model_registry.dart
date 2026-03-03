/// Central registry for AI runtimes.
///
/// Maps model paths to their active [InferenceRuntime] instances.
class InferenceRegistry {
  static final InferenceRegistry _instance = InferenceRegistry._internal();
  factory InferenceRegistry() => _instance;
  static InferenceRegistry get instance => _instance;
  InferenceRegistry._internal();

  // Map modelPath -> InferenceRuntime
  final Map<String, dynamic> _runtimes = {};

  /// Register a runtime instance.
  void registerRuntime(String modelPath, dynamic runtime) {
    _runtimes[modelPath] = runtime;
  }

  /// Get a runtime instance by model path.
  dynamic getRuntime(String modelPath) {
    return _runtimes[modelPath];
  }

  /// Unregister a runtime instance.
  void unregisterRuntime(String modelPath) {
    _runtimes.remove(modelPath);
  }

  /// All active runtimes.
  List<dynamic> get runtimes => _runtimes.values.toList();

  /// Clear all runtimes.
  void clear() {
    _runtimes.clear();
  }
}
