import 'package:smart_store_linux/infrastructure/plugins/plugin_runtime.dart';

/// Registry for active [PluginRuntime] instances.
///
/// Keeps track of all active plugin runtimes.
/// Does NOT manage lifecycle or frame routing (that's PluginManager).
class PluginRegistry {
  static final PluginRegistry _instance = PluginRegistry._internal();
  factory PluginRegistry() => _instance;
  static PluginRegistry get instance => _instance;
  PluginRegistry._internal();

  // Active Plugin Instances: Map<StreamId, List<PluginRuntime>>
  final Map<String, List<PluginRuntime>> _activeInstances = {};

  /// Register a runtime for a stream
  void register(String streamId, PluginRuntime runtime) {
    if (!_activeInstances.containsKey(streamId)) {
      _activeInstances[streamId] = [];
    }
    _activeInstances[streamId]!.add(runtime);
  }

  /// Unregister a specific runtime
  void unregister(String streamId, PluginRuntime runtime) {
    if (_activeInstances.containsKey(streamId)) {
      _activeInstances[streamId]!.remove(runtime);
      if (_activeInstances[streamId]!.isEmpty) {
        _activeInstances.remove(streamId);
      }
    }
  }

  /// Unregister all runtimes for a stream
  void unregisterAll(String streamId) {
    _activeInstances.remove(streamId);
  }

  /// Get active runtimes for a stream
  List<PluginRuntime> get(String streamId) {
    return _activeInstances[streamId] ?? [];
  }

  /// Get all active runtimes across all streams
  List<PluginRuntime> getAll() {
    return _activeInstances.values.expand((element) => element).toList();
  }
}
