import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/models/rtsp_stream.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/services/inference_service.dart';
import 'package:smart_store_linux/stream_processing/headless_stream_processor.dart';

// ===========================================================================
// SMART STORE STREAM PROCESSING ARCHITECTURE
// ===========================================================================
//
// This file implements the core stream processing pipeline with proper queue
// management to ensure real-time performance and minimal latency.
//
// ARCHITECTURE OVERVIEW:
//
// 1. STREAM HANDLING (per stream):
//    - Each video stream is decoded using GPU (NVIDIA CUDA preferred)
//    - InferenceQueue (max size 2) buffers raw frames from capture
//    - Maintains smooth playback even if inference is slower than capture
//
// 2. INFERENCE PROCESSING:
//    - Latest frame selection: Always processes most recent frame from InferenceQueue
//    - Batchable models: Single inference instance handles all streams (batching)
//    - Non-batchable models: Dedicated instance per stream
//    - Results placed in DisplayQueue (max size 10)
//
// 3. REALTIME PLAYBACK:
//    - Frames displayed sequentially from DisplayQueue
//    - If DisplayQueue exceeds max, oldest frames are dropped
//    - Streams without models display directly from InferenceQueue
//
// QUEUE FLOW:
//   Capture -> InferenceQueue(2) -> Inference -> DisplayQueue(10) -> Display
//
// ===========================================================================

/// Manager for all stream processors
///
/// Responsibilities:
/// - Creating and managing HeadlessStreamProcessor instances
/// - Starting/stopping inference for all streams
/// - Coordinating with InferenceService and ConfigService
class StreamProcessManager extends ChangeNotifier {
  static final StreamProcessManager _instance =
      StreamProcessManager._internal();
  factory StreamProcessManager() => _instance;
  static StreamProcessManager get instance => _instance;

  StreamProcessManager._internal();

  final Map<String, HeadlessStreamProcessor> _processors = {};

  Map<String, HeadlessStreamProcessor> get processors =>
      UnmodifiableMapView(_processors);

  bool get isRunning => _processors.values.any((p) => !p.isFrozen);

  /// Start all streams with their assigned models
  void startAll(
    List<RTSPStream> streams,
    Map<String, String>
    streamModelMap, // Keep for backward compat or initial overrides
    List<dynamic> models,
  ) async {
    debugPrint("StreamProcessManager: Starting all streams...");

    // Clean up any frozen processors first for clean restart
    if (_processors.isNotEmpty) {
      final hasFrozen = _processors.values.any((p) => p.isFrozen);
      if (hasFrozen) {
        debugPrint("Clearing frozen processors before restart...");
        clearAll();
        // Wait a bit for cleanup to complete
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // Init Config Service
    await ConfigService.instance.init();

    // Ensure inference service is init ONCE for all streams
    await InferenceService.instance.init();

    for (var stream in streams) {
      // Find model for this stream
      String? modelPath;

      // 1. Check override map (runtime args)
      if (streamModelMap.containsKey(stream.id)) {
        final modelId = streamModelMap[stream.id];
        try {
          final model = models.firstWhere((m) => m.id == modelId);
          modelPath = model.path;
          // Also save this preference
          ConfigService.instance.setModelForStream(stream.id, modelPath);
        } catch (_) {}
      }
      // 2. Check Persistent Config
      else {
        final savedId = ConfigService.instance.getModelForStream(stream.id);
        if (savedId != null) {
          try {
            final model = models.firstWhere((m) => m.id == savedId);
            modelPath = model.path;
          } catch (_) {
            // If lookup fails, check if it looks like a legacy path
            if (savedId.contains("/") || savedId.contains("\\")) {
              modelPath = savedId;
            }
          }
        }

        // 3. Fallback to stream object default
        if (modelPath == null && stream.modelPath != null) {
          modelPath = stream.modelPath;
        }
      }

      if (modelPath != null) {
        // Skip if already exists
        if (_processors.containsKey(stream.id)) {
          debugPrint("[SKIP] Processor for ${stream.id} already exists");
          continue;
        }

        await InferenceService.instance.loadModel(modelPath);

        final processor = HeadlessStreamProcessor(
          stream: stream,
          modelPath: modelPath,
        );
        _processors[stream.id] = processor;

        // CRITICAL: Log stream initialization
        debugPrint(
          "[INIT] Stream: ${stream.id} | Model: ${modelPath.split('/').last}",
        );

        // Await initialization to prevent race conditions/crashes
        await processor.initialize();
        notifyListeners();

        // Stagger startup
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Update the model assigned to a stream
  Future<void> updateStreamModel(String streamId, String? modelPath) async {
    await ConfigService.instance.setModelForStream(streamId, modelPath);
    // Logic to restart specific stream processor?
    // For now, user has to Stop/Start engine.
    // But we can support hot-swap if we wanted.
  }

  /// Stop all inference (but keep video playback)
  void stopAll() {
    debugPrint(
      "StreamProcessManager: Stopping inference (keeping video playback)...",
    );

    // Freeze all stream processors to stop inference (capture continues)
    for (var p in _processors.values) {
      p.freeze(); // Stops inference, keeps showing raw video
    }

    // Release the inference service to stop worker isolate
    InferenceService.instance.release();

    debugPrint(
      "StreamProcessManager: Inference stopped - showing raw video feeds",
    );

    // Don't clear _processors - keep them frozen
    notifyListeners();
  }

  /// Clear all streams and stop all processing
  void clearAll() {
    debugPrint("StreamProcessManager: Clearing all streams and inference...");

    // Dispose all processors
    for (var p in _processors.values) {
      p.dispose();
    }
    _processors.clear();

    // Release inference service
    InferenceService.instance.release();

    debugPrint("StreamProcessManager: All resources cleared");
    notifyListeners();
  }

  /// Get a specific processor by stream ID
  HeadlessStreamProcessor? getProcessor(String streamId) {
    return _processors[streamId];
  }
}
