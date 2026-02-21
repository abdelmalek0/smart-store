import 'package:smart_store_linux/features/streaming/capture_runtime.dart';

/// Registry for active [CaptureRuntime] instances.
///
/// Keeps track of all active streaming runtimes.
/// Used by StreamOrchestrator and potentially UI for introspection.
class StreamRegistry {
  static final StreamRegistry _instance = StreamRegistry._internal();
  factory StreamRegistry() => _instance;
  static StreamRegistry get instance => _instance;
  StreamRegistry._internal();

  final Map<String, CaptureRuntime> _runtimes = {};

  /// Get all active runtimes
  List<CaptureRuntime> get runtimes => _runtimes.values.toList();

  /// Register a runtime
  void register(CaptureRuntime runtime) {
    _runtimes[runtime.streamId] = runtime;
  }

  /// Unregister a runtime
  void unregister(String streamId) {
    _runtimes.remove(streamId);
  }

  /// Get a runtime by Stream ID
  CaptureRuntime? get(String streamId) {
    return _runtimes[streamId];
  }

  /// Check if a stream runtime is registered
  bool isRegistered(String streamId) => _runtimes.containsKey(streamId);
}
