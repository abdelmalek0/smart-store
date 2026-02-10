import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/constants.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/models/rtsp_stream.dart';
import 'package:smart_store_linux/ai/inference/service/inference_service.dart';
import 'package:smart_store_linux/backend/services/video/ffmpeg_video_service.dart';
import 'package:smart_store_linux/plugins/manager/plugin_manager.dart';
import 'package:smart_store_linux/backend/services/config_service.dart';
import 'package:smart_store_linux/core/registry/plugin_registry.dart';

import 'logic/stream_capture_manager.dart';
import 'logic/stream_display_controller.dart';

/// Headless stream processor that orchestrates Video Capture, Plugin Processing, and Display.
///
/// Architecture:
/// - [StreamCaptureManager]: Handles Isolate spawning and raw frame parsing.
/// - [PluginManager]: Handles inference and event logic.
/// - [StreamDisplayController]: Handles display queue, backpressure, and broadcasting.
class StreamProcessor {
  final RTSPStream stream;

  // Managers
  late final StreamCaptureManager _captureManager;
  late final StreamDisplayController _displayController;
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
  StreamSubscription? _pluginEventSubscription;

  // Events
  final StreamController<Map<String, dynamic>> _eventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public Getters
  Stream<ProcessedFrame> get frameStream => _displayController.frameStream;
  Stream<Map<String, dynamic>> get eventStream => _eventStreamController.stream;

  int get nativeVideoId => _captureManager.nativeVideoId;
  int? get textureId => _captureManager.textureId;
  bool get isInitialized => _captureManager.nativeVideoId > 0;

  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  Map<int, String> get modelLabels => _modelLabels;
  bool get isFrozen => _displayController.isFrozen;

  bool _isPluginActive = false;

  StreamProcessor({required this.stream}) {
    _captureManager = StreamCaptureManager(
      streamUrl: stream.url,
      streamId: stream.id,
      onFrameReceived: _handleRawFrame,
      onProcessedFrameReceived: _handleProcessedFrame,
      onLabelsReceived: (labels) => _modelLabels = labels,
      onInitComplete: (vid, tex) {
        // UI will pull these from getters
      },
    );
    _displayController = StreamDisplayController(stream.id);
  }

  /// Initialize the processor and start all loops
  Future<void> initialize() async {
    try {
      debugPrint("Starting Stream Processor for stream: ${stream.id}");

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
        await _captureManager.start(null);
        _displayController.startLoop();
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
        _displayController.enqueue(processedFrame);
      });

      // Listen for Events
      _pluginEventSubscription = _pluginManager!.eventStream.listen((event) {
        _eventStreamController.add(event);
      });

      // Start Capture and Display
      await _captureManager.start(modelPath);
      _displayController.startLoop();
    } catch (e) {
      debugPrint("Error initializing processor for ${stream.id}: $e");
    }
  }

  /// Handle Raw Frame from Capture Manager (Standard Path)
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
      if (_displayController.queueLength < Constants.displayQueueMaxSize) {
        _displayController.enqueue(processed);
      }
    }
  }

  /// Handle Processed Frame from Capture Manager (Optimized Linux Path: Frame + Inference)
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
      _displayController.enqueue(processed);
    }
  }

  void freeze() {
    debugPrint("Freezing processor for ${stream.id}");
    _displayController.setFrozen(true);
  }

  void unfreeze() {
    debugPrint("Unfreezing processor for ${stream.id}");
    _displayController.setFrozen(false);
  }

  Future<bool> showFrame(int timestamp) async {
    if (_captureManager.nativeVideoId > 0) {
      return await FFmpegVideoService.showFrame(
        _captureManager.nativeVideoId,
        timestamp,
      );
    }
    return false;
  }

  Future<void> dispose() async {
    debugPrint("Disposing processor for ${stream.id}");

    await _captureManager.dispose();
    _displayController.dispose();

    _pluginFrameSubscription?.cancel();
    _pluginEventSubscription?.cancel();
    _pluginManager?.dispose();
    _eventStreamController.close();

    debugPrint("Processor disposed for ${stream.id}");
  }
}
