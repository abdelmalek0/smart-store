import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';

import 'package:smart_store_linux/core/engine/pipeline.dart';
import 'package:smart_store_linux/core/streaming/stream_manager.dart';
import 'package:smart_store_linux/ai/model_manager.dart';
import 'package:smart_store_linux/core/engine/pipeline_registry.dart';

// ===========================================================================
// SMART STORE STREAM PROCESSING ARCHITECTURE
// ===========================================================================

/// The main manager that orchestrates all stream pipelines.
///
/// Responsibilities:
/// - Creating and managing [Pipeline] instances.
/// - Starting/stopping pipelines.
/// - Coordinating with [ModelRuntime], [StreamManager], and [ConfigService].
class PipelineManager extends ChangeNotifier {
  static final PipelineManager _instance = PipelineManager._internal();
  factory PipelineManager() => _instance;
  static PipelineManager get instance => _instance;

  PipelineManager._internal();

  Map<String, Pipeline> get pipelines => UnmodifiableMapView({
    for (var p in PipelineRegistry.instance.pipelines) p.streamId: p,
  });

  bool get isRunning =>
      PipelineRegistry.instance.pipelines.any((p) => !p.isFrozen);

  /// Start all pipelines based on current configuration.
  void startAll() async {
    debugPrint("PipelineManager: Starting all pipelines...");

    // Clean up any frozen pipelines first
    if (PipelineRegistry.instance.pipelines.isNotEmpty) {
      final hasFrozen = PipelineRegistry.instance.pipelines.any(
        (p) => p.isFrozen,
      );
      if (hasFrozen) {
        debugPrint("Clearing frozen pipelines before restart...");
        await clearAll();
      }
    }

    // 1. Init Config Service
    await ConfigService.instance.init();
    final config = ConfigService.instance.config;

    // 2. Init Model Manager
    ModelManager.instance.initialize(config.models);

    // 3. Init Stream Manager (Starts Captures)
    await StreamManager.instance.initialize(config.streams);

    // 4. Create Pipelines for enabled streams
    for (var streamConfig in config.streams) {
      if (!streamConfig.enabled) continue;

      // Skip if already exists
      if (PipelineRegistry.instance.isRegistered(streamConfig.id)) {
        debugPrint("[SKIP] Pipeline for ${streamConfig.id} already exists");
        continue;
      }

      // Create new Pipeline
      final pipeline = Pipeline(streamId: streamConfig.id);

      // Register
      PipelineRegistry.instance.register(pipeline);

      debugPrint("[INIT] Pipeline for stream: ${streamConfig.id}");

      // Await initialization (Connects to StreamManager, activates Plugins)
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
            "PipelineManager: Could not find model for path $modelPath",
          );
        }
      }
    }
  }

  /// Stop all pipelines and release resources
  Future<void> stopAll() async {
    debugPrint("PipelineManager: Stopping (full shutdown)...");
    await clearAll();
    debugPrint("PipelineManager: Stopped.");
    notifyListeners();
  }

  /// Clear all pipelines
  Future<void> clearAll() async {
    debugPrint("PipelineManager: Clearing all pipelines...");

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
    await StreamManager.instance.disposeAll();

    // Release inference service
    await ModelManager.instance.release();

    debugPrint("PipelineManager: All resources cleared");
    notifyListeners();
  }

  /// Get a specific pipeline by stream ID
  Pipeline? getPipeline(String streamId) {
    return PipelineRegistry.instance.get(streamId);
  }
}
