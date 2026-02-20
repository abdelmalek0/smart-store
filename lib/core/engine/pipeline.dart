import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/models/frames.dart';
// import 'package:smart_store_linux/core/rendering/display_queue.dart'; // Removed
import 'package:smart_store_linux/core/rendering/manager/rendering_manager.dart'; // Added
import 'package:smart_store_linux/core/config/config_service.dart';

import 'package:smart_store_linux/core/plugins/plugin_manager.dart';
import 'package:smart_store_linux/core/streaming/stream_manager.dart';
import 'package:smart_store_linux/core/engine/pipeline_registry.dart';

/// Headless stream pipeline that orchestrates Plugin Processing and Display.
///
/// Connects a Stream (from [StreamManager]) to Plugins and Display.
class Pipeline {
  final String streamId;

  // Managers
  // late final DisplayQueue _displayQueue; // Removed

  // Subscriptions
  StreamSubscription<RawFrame>? _frameSubscription;
  StreamSubscription<ProcessedFrame>? _pluginOutputSubscription;
  StreamSubscription<ProcessedFrame>? _optimizedFrameSubscription;
  StreamSubscription<Map<int, String>>? _labelSubscription;

  // State
  int _frameWidth = 0;
  int _frameHeight = 0;
  Map<int, String> _modelLabels = {};

  // Public Getters
  Stream<int> get frameStream =>
      RenderingManager.instance.getFrameStream(streamId);

  Stream<ProcessedFrame> get detectionStream =>
      RenderingManager.instance.getDetectionStream(streamId);

  // Native Video ID is now managed by StreamManager/Runtime.
  // We might need to ask StreamManager for it if UI needs it directly,
  // or UI interacts with StreamManager directly for video display.
  // For now, let's keep the getter by querying StreamManager if possible,
  // or rely on UI using StreamManager.showFrame().

  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  bool get isFrozen => RenderingManager.instance.isFrozen(streamId);
  Map<int, String> get modelLabels => _modelLabels;

  // Proxy getters for Runtime state managed by StreamManager
  int get nativeVideoId => StreamManager.instance.getNativeVideoId(streamId);
  int? get textureId => StreamManager.instance.getTextureId(streamId);

  Pipeline({required this.streamId});

  /// Initialize the pipeline
  Future<void> initialize() async {
    try {
      debugPrint("Starting Pipeline for stream: $streamId");

      // 1. Initialize Rendering Manager
      RenderingManager.instance.initialize(streamId);

      // 2. Subscribe to Frame Stream
      final streamSource = StreamManager.instance.getFrameStream(streamId);
      if (streamSource != null) {
        _frameSubscription = streamSource.listen(_handleRawFrame);
      } else {
        debugPrint("Error: No frame stream available for $streamId");
      }

      // 2.1 Subscribe to Optimized Frame Stream (Linux Native Path)
      final optimizedStream = StreamManager.instance.getProcessedFrameStream(
        streamId,
      );
      if (optimizedStream != null) {
        _optimizedFrameSubscription = optimizedStream.listen((frame) {
          if (!isFrozen) {
            // Forward directly to PluginManager's output logic
            PluginManager.instance.injectProcessedFrame(streamId, frame);
          }
        });
      }

      // 2.5 Subscribe to Label Stream (Dynamic Labels from C++)
      final labelStream = StreamManager.instance.getLabelStream(streamId);
      final currentLabels = StreamManager.instance.getCurrentLabels(streamId);

      // Load current immediately if available
      if (currentLabels != null && currentLabels.isNotEmpty) {
        _modelLabels = currentLabels;
        debugPrint(
          "Pipeline: Loaded ${currentLabels.length} existing dynamic labels",
        );
      }

      if (labelStream != null) {
        _labelSubscription = labelStream.listen((lbs) {
          _modelLabels = lbs;
          debugPrint("Pipeline: Received ${lbs.length} dynamic labels update");
        });
      }

      // 3. Activate Plugins & Load Labels
      final activePluginId = ConfigService.instance
          .getStream(streamId)
          ?.activePluginId;
      if (activePluginId != null) {
        await PluginManager.instance.activatePlugin(streamId, activePluginId);

        // 4. Load Labels from ModelConfig (Static)
        final pluginConfig = ConfigService.instance.getPlugin(activePluginId);
        if (pluginConfig?.assignedModelId != null) {
          final modelConfig = ConfigService.instance.getModel(
            pluginConfig!.assignedModelId!,
          );
          if (modelConfig != null && modelConfig.labels.isNotEmpty) {
            _modelLabels = modelConfig.labels;
            debugPrint(
              "Pipeline: Loaded ${_modelLabels.length} labels from ${modelConfig.name} (Static Config)",
            );
          } else {
            debugPrint(
              "Pipeline: Static labels empty for ${modelConfig?.name ?? 'unknown model'}, keeping existing labels (${_modelLabels.length})",
            );
          }
        }

        // 5. Subscribe to Plugin Output (Merged Stream)
        // Correct Logic: Pipeline listens to PluginManager output and routes to RenderingManager
        _pluginOutputSubscription = PluginManager.instance
            .getOutputStream(streamId)
            .listen((processedFrame) {
              if (!isFrozen) {
                RenderingManager.instance.enqueueFrame(
                  streamId,
                  processedFrame,
                );
              }
            });
      } else {
        // No debugPrint here as per instruction
      }

      // Register self in PipelineRegistry (Data Store)
      PipelineRegistry.instance.register(this);
    } catch (e) {
      debugPrint("Error initializing pipeline for $streamId: $e");
    }
  }

  /// Handle Raw Frame from StreamManager
  void _handleRawFrame(RawFrame frame) {
    if (frame.width > 0) {
      _frameWidth = frame.width;
      _frameHeight = frame.height;
    }

    if (!isFrozen) {
      // Logic Check: Is there an active plugin?
      // For now, we assume if we subscribed to plugin output, a plugin is processing.
      // But activePluginId might change or be null.
      // Ideally we check if we have an active plugin subscription.

      if (_pluginOutputSubscription != null &&
          !_pluginOutputSubscription!.isPaused) {
        // 1. Route to Active Plugins
        // The PluginManager will emit the result via getOutputStream, which we are listening to.
        PluginManager.instance.routeFrame(streamId, frame);
      } else {
        // 2. No Plugin Active -> Pass directly to RenderingManager
        final now = DateTime.now().millisecondsSinceEpoch;
        final processed = ProcessedFrame(
          imageBytes: frame.bytes,
          width: frame.width,
          height: frame.height,
          detections: [], // No detections in passthrough mode
          decodeStartMs: frame.decodeTimestamp,
          preprocessEndMs: now,
          inferenceEndMs: now,
          postprocessEndMs: now,
        );

        RenderingManager.instance.enqueueFrame(streamId, processed);
      }
    }
  }

  void freeze() {
    debugPrint("Freezing pipeline for $streamId");
    RenderingManager.instance.freeze(streamId);
  }

  void unfreeze() {
    debugPrint("Unfreezing pipeline for $streamId");
    RenderingManager.instance.unfreeze(streamId);
  }

  /// Show Frame: Proxy to RenderingManager
  Future<bool> showFrame(int timestamp) async {
    final nativeId = StreamManager.instance.getNativeVideoId(streamId);
    return await RenderingManager.instance.showFrame(nativeId, timestamp);
  }

  Future<void> dispose() async {
    debugPrint("Disposing pipeline for $streamId");

    PipelineRegistry.instance.unregister(streamId);

    // Stop subscription
    await _frameSubscription?.cancel();
    await _labelSubscription?.cancel();
    await _pluginOutputSubscription?.cancel();
    await _optimizedFrameSubscription?.cancel();

    // Deactivate plugins
    await PluginManager.instance.deactivateAll(streamId);

    // Dispose Rendering Resources
    RenderingManager.instance.dispose(streamId);

    // Dispose Stream (if we own it / it's the right place)
    await StreamManager.instance.disposeStream(streamId);

    debugPrint("Pipeline disposed for $streamId");
  }
}
