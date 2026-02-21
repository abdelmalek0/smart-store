import 'package:smart_store_linux/features/engine/pipeline.dart';

/// Registry for active [Pipeline] instances.
///
/// Stores active pipelines enabling access from UI components and other managers.
class PipelineRegistry {
  static final PipelineRegistry _instance = PipelineRegistry._internal();
  factory PipelineRegistry() => _instance;
  static PipelineRegistry get instance => _instance;
  PipelineRegistry._internal();

  final Map<String, Pipeline> _pipelines = {};

  /// Get all active pipelines
  List<Pipeline> get pipelines => _pipelines.values.toList();

  /// Register a pipeline
  void register(Pipeline pipeline) {
    _pipelines[pipeline.streamId] = pipeline;
  }

  /// Unregister a pipeline
  void unregister(String streamId) {
    _pipelines.remove(streamId);
  }

  /// Get a pipeline by Stream ID
  Pipeline? get(String streamId) {
    return _pipelines[streamId];
  }

  /// Check if a stream is registered
  bool isRegistered(String streamId) => _pipelines.containsKey(streamId);
}
