import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/domain/entities/raw_frame.dart';
import 'package:smart_store_linux/domain/entities/processed_frame.dart';
import 'package:smart_store_linux/infrastructure/rendering/rendering_orchestrator.dart';
import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/infrastructure/plugins/plugin_orchestrator.dart';
import 'package:smart_store_linux/infrastructure/streaming/stream_orchestrator.dart';
import 'package:smart_store_linux/application/engine/pipeline_registry.dart';

/// Headless stream pipeline that orchestrates Plugin Processing and Display.
///
/// All manager dependencies are injected by [PipelineManager] at construction
/// time. Pipeline never reaches for global singletons directly.
class Pipeline {
  final String streamId;

  // Injected dependencies (set by PipelineManager)
  final StreamOrchestrator _streamManager;
  final PluginOrchestrator _pluginManager;
  final RenderingOrchestrator _renderingManager;
  final ConfigService _config;

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
  Stream<int> get frameStream => _renderingManager.getFrameStream(streamId);
  Stream<ProcessedFrame> get detectionStream =>
      _renderingManager.getDetectionStream(streamId);

  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  bool get isFrozen => _renderingManager.isFrozen(streamId);
  Map<int, String> get modelLabels => _modelLabels;

  // Proxy getters for Runtime state managed by StreamManager
  int get nativeVideoId => _streamManager.getNativeVideoId(streamId);
  int? get textureId => _streamManager.getTextureId(streamId);

  Pipeline({
    required this.streamId,
    required StreamOrchestrator streamManager,
    required PluginOrchestrator pluginManager,
    required RenderingOrchestrator renderingManager,
    required ConfigService config,
  }) : _streamManager = streamManager,
       _pluginManager = pluginManager,
       _renderingManager = renderingManager,
       _config = config;

  /// Initialize the pipeline
  Future<void> initialize() async {
    try {
      debugPrint('Starting Pipeline for stream: $streamId');

      // 1. Initialize Rendering Manager
      _renderingManager.initialize(streamId);

      // 2. Subscribe to Frame Stream
      final streamSource = _streamManager.getFrameStream(streamId);
      if (streamSource != null) {
        _frameSubscription = streamSource.listen(_handleRawFrame);
      } else {
        debugPrint('Error: No frame stream available for $streamId');
      }

      // 2.1 Subscribe to Optimized Frame Stream (Linux Native Path)
      final optimizedStream = _streamManager.getProcessedFrameStream(streamId);
      if (optimizedStream != null) {
        _optimizedFrameSubscription = optimizedStream.listen((frame) {
          if (!isFrozen) {
            _pluginManager.injectProcessedFrame(streamId, frame);
          }
        });
      }

      // 2.5 Subscribe to Label Stream (Dynamic Labels from C++)
      final labelStream = _streamManager.getLabelStream(streamId);
      final currentLabels = _streamManager.getCurrentLabels(streamId);

      if (currentLabels != null && currentLabels.isNotEmpty) {
        _modelLabels = currentLabels;
        debugPrint(
          'Pipeline: Loaded ${currentLabels.length} existing dynamic labels',
        );
      }

      if (labelStream != null) {
        _labelSubscription = labelStream.listen((lbs) {
          _modelLabels = lbs;
          debugPrint('Pipeline: Received ${lbs.length} dynamic labels update');
        });
      }

      // 3. Activate Plugins & Load Labels
      final activePluginId = _config.getStream(streamId)?.activePluginId;
      if (activePluginId != null) {
        await _pluginManager.activatePlugin(streamId, activePluginId);

        // 4. Load Labels from ModelConfig (Static)
        final pluginConfig = _config.getPlugin(activePluginId);
        if (pluginConfig?.assignedModelId != null) {
          final modelConfig = _config.getModel(pluginConfig!.assignedModelId!);
          if (modelConfig != null && modelConfig.labels.isNotEmpty) {
            _modelLabels = modelConfig.labels;
            debugPrint(
              'Pipeline: Loaded ${_modelLabels.length} labels from ${modelConfig.name} (Static Config)',
            );
          } else {
            debugPrint(
              'Pipeline: Static labels empty for ${modelConfig?.name ?? "unknown model"}, '
              'keeping existing labels (${_modelLabels.length})',
            );
          }
        }

        // 5. Subscribe to Plugin Output (Merged Stream)
        _pluginOutputSubscription = _pluginManager
            .getOutputStream(streamId)
            .listen((processedFrame) {
              if (!isFrozen) {
                _renderingManager.enqueueFrame(streamId, processedFrame);
              }
            });
      }

      // Register self in PipelineRegistry (Data Store)
      PipelineRegistry.instance.register(this);
    } catch (e) {
      debugPrint('Error initializing pipeline for $streamId: $e');
    }
  }

  /// Handle Raw Frame from StreamManager
  void _handleRawFrame(RawFrame frame) {
    if (frame.width > 0) {
      _frameWidth = frame.width;
      _frameHeight = frame.height;
    }

    if (!isFrozen) {
      if (_pluginOutputSubscription != null &&
          !_pluginOutputSubscription!.isPaused) {
        // Route to Active Plugins
        _pluginManager.routeFrame(streamId, frame);
      } else {
        // No Plugin Active → Pass directly to RenderingManager
        final now = DateTime.now().millisecondsSinceEpoch;
        final processed = ProcessedFrame(
          imageBytes: frame.bytes,
          width: frame.width,
          height: frame.height,
          detections: [],
          decodeStartMs: frame.decodeTimestamp,
          preprocessEndMs: now,
          inferenceEndMs: now,
          postprocessEndMs: now,
        );
        _renderingManager.enqueueFrame(streamId, processed);
      }
    }
  }

  void freeze() {
    debugPrint('Freezing pipeline for $streamId');
    _renderingManager.freeze(streamId);
  }

  void unfreeze() {
    debugPrint('Unfreezing pipeline for $streamId');
    _renderingManager.unfreeze(streamId);
  }

  /// Show Frame: Proxy to RenderingManager
  Future<bool> showFrame(int timestamp) async {
    final nativeId = _streamManager.getNativeVideoId(streamId);
    return await _renderingManager.showFrame(nativeId, timestamp);
  }

  Future<void> dispose() async {
    debugPrint('Disposing pipeline for $streamId');

    PipelineRegistry.instance.unregister(streamId);

    await _frameSubscription?.cancel();
    await _labelSubscription?.cancel();
    await _pluginOutputSubscription?.cancel();
    await _optimizedFrameSubscription?.cancel();

    await _pluginManager.deactivateAll(streamId);

    _renderingManager.dispose(streamId);

    await _streamManager.disposeStream(streamId);

    debugPrint('Pipeline disposed for $streamId');
  }
}
