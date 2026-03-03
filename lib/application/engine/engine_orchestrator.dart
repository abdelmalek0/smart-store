import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/application/engine/pipeline.dart';
import 'package:smart_store_linux/infrastructure/plugins/plugin_orchestrator.dart';
import 'package:smart_store_linux/infrastructure/rendering/rendering_orchestrator.dart';
import 'package:smart_store_linux/infrastructure/streaming/stream_orchestrator.dart';
import 'package:smart_store_linux/infrastructure/ai/inference_orchestrator.dart';
import 'package:smart_store_linux/application/engine/pipeline_registry.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';

// ===========================================================================
// SMART STORE STREAM PROCESSING ARCHITECTURE
// ===========================================================================

/// The main manager that orchestrates all stream pipelines.
///
/// Responsibilities:
/// - Creating and managing [Pipeline] instances.
/// - Starting/stopping pipelines.
/// - Coordinating with [InferenceOrchestrator], [StreamOrchestrator],
///   and [IConfigRepository].
class EngineOrchestrator {
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
  Future<void> startAll(IConfigRepository repo) async {
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

    // 1. Load config (already in cache after AppService.init)
    final config = repo.currentConfig;

    // 2. Init Model Manager
    InferenceOrchestrator.instance.initialize(config.models);

    // 3. Init Stream Manager (Starts Captures)
    await StreamOrchestrator.instance.initialize(config.streams);

    // 4. Create Pipelines for enabled streams
    for (var streamConfig in config.streams) {
      if (!streamConfig.enabled) continue;

      if (PipelineRegistry.instance.isRegistered(streamConfig.id)) {
        debugPrint('[SKIP] Pipeline for ${streamConfig.id} already exists');
        continue;
      }

      final pipeline = Pipeline(
        streamId: streamConfig.id,
        streamManager: StreamOrchestrator.instance,
        pluginManager: PluginOrchestrator.instance,
        renderingManager: RenderingOrchestrator.instance,
        repo: repo,
      );

      debugPrint('[INIT] Pipeline for stream: ${streamConfig.id}');
      await pipeline.initialize();

      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Update the model assigned to a stream
  Future<void> updateStreamModel(
    IConfigRepository repo,
    String streamId,
    String? modelPath,
  ) async {
    final stream = repo.getStream(streamId);
    if (stream != null) {
      if (modelPath == null) {
        await repo.updateStream(stream.copyWith(clearAssignedModel: true));
      } else {
        try {
          final modelConfig = repo.currentConfig.models.firstWhere(
            (m) => m.path == modelPath,
          );
          await repo.updateStream(
            stream.copyWith(assignedModelId: modelConfig.id),
          );
        } catch (e) {
          debugPrint(
            'EngineOrchestrator: Could not find model for path $modelPath',
          );
        }
      }
    }
  }

  /// Stop all pipelines and release resources
  Future<void> stopAll() async {
    debugPrint('EngineOrchestrator: Stopping (full shutdown)...');
    await clearAll();
    debugPrint('EngineOrchestrator: Stopped.');
  }

  /// Clear all pipelines
  Future<void> clearAll() async {
    debugPrint('EngineOrchestrator: Clearing all pipelines...');

    for (var p in PipelineRegistry.instance.pipelines) {
      await p.dispose();
    }
    final ids = PipelineRegistry.instance.pipelines
        .map((p) => p.streamId)
        .toList();
    for (var id in ids) {
      PipelineRegistry.instance.unregister(id);
    }

    await StreamOrchestrator.instance.disposeAll();
    await InferenceOrchestrator.instance.release();

    debugPrint('EngineOrchestrator: All resources cleared');
  }

  /// Get a specific pipeline by stream ID
  Pipeline? getPipeline(String streamId) {
    return PipelineRegistry.instance.get(streamId);
  }
}
