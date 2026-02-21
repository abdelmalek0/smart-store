import 'dart:async';
import 'dart:developer';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/streaming/capture_runtime.dart';
import 'package:smart_store_linux/core/streaming/stream_registry.dart';

import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:smart_store_linux/core/config/config_service.dart';

/// Active Orchestrator for Stream Capture and Routing.
///
/// Responsibilities:
/// - Manages lifecycle of [CaptureRuntime] instances.
/// - Acts as the frame bus, routing frames to [PluginManager].
/// - Provides frame stream for Pipelines.
class StreamManager {
  static final StreamManager _instance = StreamManager._internal();
  factory StreamManager() => _instance;
  static StreamManager get instance => _instance;
  StreamManager._internal();

  // Frame Streams: Map<StreamId, StreamController<RawFrame>>
  // Kept here as per user request
  final Map<String, StreamController<RawFrame>> _frameControllers = {};
  final Map<String, StreamController<ProcessedFrame>>
  _processedFrameControllers = {};
  final Map<String, Map<int, String>> _streamLabels = {};
  final Map<String, StreamController<Map<int, String>>> _labelControllers = {};

  /// Initialize all streams from configuration
  Future<void> initialize(List<StreamConfig> configs) async {
    for (final config in configs) {
      if (config.enabled) {
        await initializeStream(config);
      }
    }
  }

  /// Initialize and start a single stream
  Future<void> initializeStream(StreamConfig config) async {
    if (StreamRegistry.instance.isRegistered(config.id)) {
      log('StreamManager: Stream ${config.id} already initialized.');
      return;
    }

    log('StreamManager: Initializing stream ${config.id}...');

    final frameController = StreamController<RawFrame>.broadcast();
    _frameControllers[config.id] = frameController;

    final labelController = StreamController<Map<int, String>>.broadcast();
    _labelControllers[config.id] = labelController;

    final processedFrameController =
        StreamController<ProcessedFrame>.broadcast();
    _processedFrameControllers[config.id] = processedFrameController;

    final runtime = CaptureRuntime(
      streamUrl: config.url,
      streamId: config.id,
      onFrameReceived: (frame) {
        // 1. Route to Stream Pipeline (via Controller)
        if (!frameController.isClosed) {
          frameController.add(frame);
        }
      },
      onProcessedFrameReceived: (processed) {
        // Feed the processed frame controller - Pipeline will subscribe to this
        if (!processedFrameController.isClosed) {
          processedFrameController.add(processed);
        }
      },
      onLabelsReceived: (labels) {
        // Store labels for this stream so Pipeline can access them
        _streamLabels[config.id] = labels;
        _labelControllers[config.id]?.add(labels);
        log('StreamManager: Received ${labels.length} labels for ${config.id}');
      },
      onInitComplete: (vid, tex) {
        log('StreamManager: Stream ${config.id} initialized (VideoID: $vid)');
      },
    );

    // Register with StreamRegistry
    StreamRegistry.instance.register(runtime);

    // Resolve Model Path for Optimized Inference
    final modelPath = ConfigService.instance.getEffectiveModelPathForStream(
      config.id,
    );
    log(
      'StreamManager: Starting capture for ${config.id} with model: $modelPath',
    );

    await runtime.start(modelPath);
  }

  /// Get the frame stream for a given stream ID
  Stream<RawFrame>? getFrameStream(String streamId) {
    return _frameControllers[streamId]?.stream;
  }

  /// Get the label stream for a given stream ID
  Stream<Map<int, String>>? getLabelStream(String streamId) {
    return _labelControllers[streamId]?.stream;
  }

  /// Get the processed frame stream (Optimized Path) for a given stream ID
  Stream<ProcessedFrame>? getProcessedFrameStream(String streamId) {
    return _processedFrameControllers[streamId]?.stream;
  }

  /// Get current labels for a given stream ID
  Map<int, String>? getCurrentLabels(String streamId) {
    return _streamLabels[streamId];
  }

  /// Get the native video ID for a stream (if active)
  int getNativeVideoId(String streamId) {
    return StreamRegistry.instance.get(streamId)?.nativeVideoId ?? 0;
  }

  /// Get the texture ID for a stream (if available)
  int? getTextureId(String streamId) {
    return StreamRegistry.instance.get(streamId)?.textureId;
  }

  /// Dispose a specific stream
  Future<void> disposeStream(String streamId) async {
    final runtime = StreamRegistry.instance.get(streamId);
    if (runtime != null) {
      await runtime.dispose();
      StreamRegistry.instance.unregister(streamId);
    }
    await _frameControllers[streamId]?.close();
    _frameControllers.remove(streamId);

    await _labelControllers[streamId]?.close();
    _labelControllers.remove(streamId);

    await _processedFrameControllers[streamId]?.close();
    _processedFrameControllers.remove(streamId);

    _streamLabels.remove(streamId);
  }

  /// Dispose all streams
  Future<void> disposeAll() async {
    final runtimes = StreamRegistry.instance.runtimes;
    for (final runtime in runtimes) {
      await disposeStream(runtime.streamId);
    }
  }
}
