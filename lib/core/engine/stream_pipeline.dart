import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/constants.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/streaming/models/rtsp_stream.dart';
import 'package:smart_store_linux/ai/service/inference_service.dart';
import 'package:smart_store_linux/core/streaming/video_bridge/video_bridge.dart';
import 'package:smart_store_linux/core/plugins/plugin_manager.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/plugins/plugin_registry.dart';

import 'package:smart_store_linux/core/streaming/capture/capture_isolate_controller.dart';
import 'package:smart_store_linux/core/rendering/display_queue.dart';

/// Headless stream pipeline that orchestrates Video Capture, Plugin Processing, and Display.
///
/// Architecture:
/// - [CaptureIsolateController]: Handles Isolate spawning and raw frame parsing.
/// - [PluginManager]: Handles inference and event logic.
/// - [DisplayQueue]: Handles display queue, backpressure, and broadcasting.
class StreamPipeline {
  final RTSPStream stream;

  // Managers
  late final CaptureIsolateController _captureController;
  late final DisplayQueue _displayQueue;
  PluginManager? _pluginManager;

  // State
  int _frameWidth = 0;
  int _frameHeight = 0;

  // Model labels
  Map<int, String> _modelLabels = {};

  // Backpressure tracking for Plugin
  int _pendingPluginFrames = 0;

  // Subscriptions
  StreamSubscription? _pluginFrameSubscription;

  // Public Getters
  Stream<ProcessedFrame> get frameStream => _displayQueue.frameStream;

  int get nativeVideoId => _captureController.nativeVideoId;
  int? get textureId => _captureController.textureId;
  bool get isInitialized => _captureController.nativeVideoId > 0;

  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  Map<int, String> get modelLabels => _modelLabels;
  bool get isFrozen => _displayQueue.isFrozen;

  bool _isPluginActive = false;

  StreamPipeline({required this.stream}) {
    _captureController = CaptureIsolateController(
      streamUrl: stream.url,
      streamId: stream.id,
      onFrameReceived: _handleRawFrame,
      onProcessedFrameReceived: _handleProcessedFrame,
      onLabelsReceived: (labels) => _modelLabels = labels,
      onInitComplete: (vid, tex) {
        // UI will pull these from getters
      },
    );
    _displayQueue = DisplayQueue(stream.id);
  }

  /// Initialize the pipeline and start all loops
  Future<void> initialize() async {
    try {
      debugPrint("Starting Stream Pipeline for stream: ${stream.id}");

      // Initialize Plugin Manager
      _pluginManager = PluginManager(stream.id);

      // 1. Resolve Active Plugin
      var pluginId =
          ConfigService.instance.getStreamActivePlugin(stream.id) ??
          'people_counting';

      // 2. Get Plugin Configuration
      var config = ConfigService.instance.getGlobalPluginConfig(pluginId) ?? {};
      final streamConfig = ConfigService.instance.getPluginConfig(
        stream.id,
        pluginId,
      );
      if (streamConfig != null) {
        config.addAll(streamConfig);
      }

      // Check for valid model path
      final modelPath = config['modelPath'] as String?;

      if (modelPath == null || modelPath.isEmpty) {
        debugPrint(
          "⚠️ No model assigned for stream ${stream.id}. Plugin will NOT start.",
        );
        _isPluginActive = false;
        await _captureController.start(null);
        _displayQueue.startLoop();
        return;
      }

      _isPluginActive = true;
      debugPrint("✓ Model assigned: $modelPath. Starting Plugin.");

      // Apply default config from registry
      final registeredPlugin = PluginRegistry.findById(pluginId);
      if (registeredPlugin != null) {
        for (final entry in registeredPlugin.defaultConfig.entries) {
          config.putIfAbsent(entry.key, () => entry.value);
        }
      }

      config['pluginId'] = pluginId;
      config['pluginType'] = pluginId;

      await InferenceService.instance.loadModel(modelPath);
      await _pluginManager!.init(config);

      // Listen for processed frames from Plugin
      _pluginFrameSubscription = _pluginManager!.processedFrameStream.listen((
        processedFrame,
      ) {
        if (_pendingPluginFrames > 0) _pendingPluginFrames--;
        _displayQueue.enqueue(processedFrame);
      });

      // Events are emitted directly by PluginManager to EventService

      // Start Capture and Display
      await _captureController.start(modelPath);
      _displayQueue.startLoop();
    } catch (e) {
      debugPrint("Error initializing pipeline for ${stream.id}: $e");
    }
  }

  /// Handle Raw Frame from Capture Controller (Standard Path)
  void _handleRawFrame(RawFrame frame) {
    if (frame.width > 0) {
      _frameWidth = frame.width;
      _frameHeight = frame.height;
    }

    if (_isPluginActive && !isFrozen && _pendingPluginFrames < 2) {
      _pendingPluginFrames++;
      _pluginManager?.processFrame(frame);
    } else if (!_isPluginActive) {
      // Pass-through
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
      if (_displayQueue.queueLength < Constants.displayQueueMaxSize) {
        _displayQueue.enqueue(processed);
      }
    }
  }

  /// Handle Processed Frame from Capture Controller (Optimized Linux Path: Frame + Inference)
  void _handleProcessedFrame(ProcessedFrame processed) {
    if (processed.width > 0) {
      _frameWidth = processed.width;
      _frameHeight = processed.height;
    }

    // If Plugin Active, route detections through plugin for logic (counting etc)
    if (_isPluginActive && !isFrozen && _pluginManager != null) {
      // Re-construct RawFrame from ProcessedFrame to pass strict typing if needed
      // But PluginManager.processDirectDetections expects RawFrame and Detections
      final frame = RawFrame(
        processed.imageBytes,
        processed.width,
        processed.height,
        processed.decodeStartMs,
      );

      if (_pendingPluginFrames < 2) {
        _pendingPluginFrames++;
        _pluginManager!.processDirectDetections(frame, processed.detections);
      }
    } else {
      // Pass-through display
      _displayQueue.enqueue(processed);
    }
  }

  void freeze() {
    debugPrint("Freezing pipeline for ${stream.id}");
    _displayQueue.setFrozen(true);
  }

  void unfreeze() {
    debugPrint("Unfreezing pipeline for ${stream.id}");
    _displayQueue.setFrozen(false);
  }

  Future<bool> showFrame(int timestamp) async {
    if (_captureController.nativeVideoId > 0) {
      return await VideoBridge.showFrame(
        _captureController.nativeVideoId,
        timestamp,
      );
    }
    return false;
  }

  Future<void> dispose() async {
    debugPrint("Disposing pipeline for ${stream.id}");

    await _captureController.dispose();
    _displayQueue.dispose();

    _pluginFrameSubscription?.cancel();
    _pluginManager?.dispose();

    debugPrint("Pipeline disposed for ${stream.id}");
  }
}
