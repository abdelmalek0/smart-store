import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/features/engine/pipeline.dart';
import 'package:smart_store_linux/features/plugins/plugin_orchestrator.dart';
import 'package:smart_store_linux/features/rendering/rendering_orchestrator.dart';
import 'package:smart_store_linux/features/streaming/stream_orchestrator.dart';
import 'package:smart_store_linux/features/inference/inference_orchestrator.dart';
import 'package:smart_store_linux/features/engine/pipeline_registry.dart';

// ===========================================================================
// SMART STORE STREAM PROCESSING ARCHITECTURE
// ===========================================================================

/// The main manager that orchestrates all stream pipelines.
///
/// Responsibilities:
/// - Creating and managing [Pipeline] instances.
/// - Starting/stopping pipelines.
/// - Coordinating with [ModelRuntime], [StreamManager], and [ConfigService].
class EngineOrchestrator extends ChangeNotifier {
  static final EngineOrchestrator _instance = EngineOrchestrator._internal();
  factory EngineOrchestrator() => _instance;
  static EngineOrchestrator get instance => _instance;

  EngineOrchestrator._internal();

  Map<String, Pipeline> get pipelines => UnmodifiableMapView({
    for (var p in PipelineRegistry.instance.pipelines) p.streamId: p,
  });

  bool get isRunning =>
      PipelineRegistry.instance.pipelines.any((p) => !p.isFrozen);

  /// Start all pipelines based on current configuration.
  Future<void> startAll() async {
    debugPrint('EngineOrchestrator: Starting all pipelines...');

    // Clean up any frozen pipelines first
    if (PipelineRegistry.instance.pipelines.isNotEmpty) {
      final hasFrozen = PipelineRegistry.instance.pipelines.any(
        (p) => p.isFrozen,
      );
      if (hasFrozen) {
        debugPrint('Clearing frozen pipelines before restart...');
        await clearAll();
      }
    }

    // 1. Init Config Service
    await ConfigService.instance.init();
    final config = ConfigService.instance.config;

    // 2. Init Model Manager
    InferenceOrchestrator.instance.initialize(config.models);

    // 3. Init Stream Manager (Starts Captures)
    await StreamOrchestrator.instance.initialize(config.streams);

    // 4. Create Pipelines for enabled streams
    for (var streamConfig in config.streams) {
      if (!streamConfig.enabled) continue;

      // Skip if already exists
      if (PipelineRegistry.instance.isRegistered(streamConfig.id)) {
        debugPrint('[SKIP] Pipeline for ${streamConfig.id} already exists');
        continue;
      }

      // Inject all manager dependencies — EngineOrchestrator is the wiring point.
      final pipeline = Pipeline(
        streamId: streamConfig.id,
        streamManager: StreamOrchestrator.instance,
        pluginManager: PluginOrchestrator.instance,
        renderingManager: RenderingOrchestrator.instance,
        config: ConfigService.instance,
      );

      debugPrint('[INIT] Pipeline for stream: ${streamConfig.id}');

      // Await initialization (subscribes to streams, activates plugins)
      // Note: Pipeline.initialize() registers itself in PipelineRegistry.
      await pipeline.initialize();
      notifyListeners();

      // Stagger startup to avoid resource spike
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Update the model assigned to a stream
  Future<void> updateStreamModel(String streamId, String? modelPath) async {
    final stream = ConfigService.instance.getStream(streamId);
    if (stream != null) {
      // If modelPath is null, clear assignment
      if (modelPath == null) {
        await ConfigService.instance.updateStream(
          stream.copyWith(clearAssignedModel: true),
        );
      } else {
        // Find model by path
        try {
          final modelConfig = ConfigService.instance.models.firstWhere(
            (m) => m.path == modelPath,
          );
          await ConfigService.instance.updateStream(
            stream.copyWith(assignedModelId: modelConfig.id),
          );
        } catch (e) {
          debugPrint(
            "EngineOrchestrator: Could not find model for path $modelPath",
          );
        }
      }
    }
  }

  /// Stop all pipelines and release resources
  Future<void> stopAll() async {
    debugPrint("EngineOrchestrator: Stopping (full shutdown)...");
    await clearAll();
    debugPrint("EngineOrchestrator: Stopped.");
    notifyListeners();
  }

  /// Clear all pipelines
  Future<void> clearAll() async {
    debugPrint("EngineOrchestrator: Clearing all pipelines...");

    // Dispose all pipelines
    for (var p in PipelineRegistry.instance.pipelines) {
      await p.dispose();
    }
    // Clear registry by iterating and unregistering? Or just assume dispose does it?
    // Pipeline.dispose doesn't unregister itself usually.
    // We should clear the registry here.
    // But iterating and removing is tricky.
    // Let's iterate keys.
    final ids = PipelineRegistry.instance.pipelines
        .map((p) => p.streamId)
        .toList();
    for (var id in ids) {
      PipelineRegistry.instance.unregister(id);
    }

    // Also dispose all streams in StreamManager
    await StreamOrchestrator.instance.disposeAll();

    // Release inference service
    await InferenceOrchestrator.instance.release();

    debugPrint("EngineOrchestrator: All resources cleared");
    notifyListeners();
  }

  /// Get a specific pipeline by stream ID
  Pipeline? getPipeline(String streamId) {
    return PipelineRegistry.instance.get(streamId);
  }
}
