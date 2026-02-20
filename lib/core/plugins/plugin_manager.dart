import 'dart:async';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/plugins/plugin_runtime.dart';
import 'package:smart_store_linux/core/plugins/plugin_registry.dart';

/// Active Orchestrator for Plugins.
///
/// Manages the creation and lifecycle of [PluginRuntime] instances.
/// Routes frames, but delegates runtime storage to [PluginRegistry].
class PluginManager {
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;
  static PluginManager get instance => _instance;
  PluginManager._internal();

  // Output Streams: Map<StreamId, StreamController<ProcessedFrame>>
  // Kept here as per user request: "Controllers should stay in managers"
  final Map<String, StreamController<ProcessedFrame>> _outputControllers = {};

  /// Route a frame to all active plugins for the given stream
  void routeFrame(String streamId, RawFrame frame) {
    // Retrieve runtimes from Registry
    final runtimes = PluginRegistry.instance.get(streamId);
    for (final runtime in runtimes) {
      runtime.processFrame(frame);
    }
  }

  /// Inject an already processed frame (e.g. from Linux Native Optimization)
  void injectProcessedFrame(String streamId, ProcessedFrame frame) {
    if (!_outputControllers.containsKey(streamId)) {
      _outputControllers[streamId] =
          StreamController<ProcessedFrame>.broadcast();
    }
    // Forward directly to output stream (Pipeline listens to this)
    if (!_outputControllers[streamId]!.isClosed) {
      _outputControllers[streamId]!.add(frame);
    }
  }

  /// Get the aggregated output stream for a stream ID
  Stream<ProcessedFrame> getOutputStream(String streamId) {
    if (!_outputControllers.containsKey(streamId)) {
      _outputControllers[streamId] =
          StreamController<ProcessedFrame>.broadcast();
    }
    return _outputControllers[streamId]!.stream;
  }

  /// Activate a plugin for a stream using configuration
  Future<void> activatePlugin(String streamId, String pluginId) async {
    // 1. Get Config from ConfigService
    final pluginConfig = ConfigService.instance.getPlugin(pluginId);
    if (pluginConfig == null || !pluginConfig.enabled) {
      debugPrint("PluginManager: Plugin $pluginId not found or disabled");
      return;
    }

    // 2. Create Runtime
    final runtime = PluginRuntime(streamId);

    // 3. Initialize
    final configMap = Map<String, dynamic>.from(pluginConfig.parameters);
    configMap['pluginId'] = pluginId;
    configMap['pluginType'] = pluginId;

    // Resolve model path if assigned
    if (pluginConfig.assignedModelId != null) {
      final model = ConfigService.instance.getModel(
        pluginConfig.assignedModelId!,
      );
      if (model != null) {
        configMap['modelPath'] = model.path;
      }
    }

    await runtime.init(configMap);

    // 3.5 Setup Output Routing
    // Ensure output controller exists
    if (!_outputControllers.containsKey(streamId)) {
      _outputControllers[streamId] =
          StreamController<ProcessedFrame>.broadcast();
    }

    // Forward runtime events to output controller
    runtime.processedFrameStream.listen((frame) {
      if (_outputControllers.containsKey(streamId) &&
          !_outputControllers[streamId]!.isClosed) {
        _outputControllers[streamId]!.add(frame);
      }
    });

    // 4. Register Runtime in Registry
    PluginRegistry.instance.register(streamId, runtime);
  }

  /// Deactivate a specific plugin for a stream
  Future<void> deactivatePlugin(String streamId, String pluginId) async {
    final runtimes = PluginRegistry.instance.get(streamId);

    final toRemove = runtimes
        .where((runtime) => runtime.pluginId == pluginId)
        .toList();

    for (final runtime in toRemove) {
      runtime.dispose();
      PluginRegistry.instance.unregister(streamId, runtime);
    }
  }

  /// Deactivate ALL plugins for a stream
  Future<void> deactivateAll(String streamId) async {
    final runtimes = PluginRegistry.instance.get(streamId);

    for (final runtime in runtimes) {
      runtime.dispose();
    }
    PluginRegistry.instance.unregisterAll(streamId);

    // Close output controller
    if (_outputControllers.containsKey(streamId)) {
      await _outputControllers[streamId]?.close();
      _outputControllers.remove(streamId);
    }
  }
}
