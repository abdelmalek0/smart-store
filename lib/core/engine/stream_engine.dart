import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/streaming/models/rtsp_stream.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/ai/service/inference_service.dart';
import 'package:smart_store_linux/core/engine/stream_pipeline.dart';

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

/// The main engine that manages all stream pipelines.
///
/// Responsibilities:
/// - Creating and managing StreamPipeline instances
/// - Starting/stopping inference for all streams
/// - Coordinating with InferenceService and ConfigService
class StreamEngine extends ChangeNotifier {
  static final StreamEngine _instance = StreamEngine._internal();
  factory StreamEngine() => _instance;
  static StreamEngine get instance => _instance;

  StreamEngine._internal();

  final Map<String, StreamPipeline> _pipelines = {};

  Map<String, StreamPipeline> get pipelines => UnmodifiableMapView(_pipelines);

  bool get isRunning => _pipelines.values.any((p) => !p.isFrozen);

  /// Start all streams with their assigned models
  void startAll(
    List<RTSPStream> streams,
    Map<String, String>
    streamModelMap, // Keep for backward compat or initial overrides
    List<dynamic> models,
  ) async {
    debugPrint("StreamEngine: Starting all streams...");

    // Clean up any frozen pipelines first for clean restart
    if (_pipelines.isNotEmpty) {
      final hasFrozen = _pipelines.values.any((p) => p.isFrozen);
      if (hasFrozen) {
        debugPrint("Clearing frozen pipelines before restart...");
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
      // Skip if already exists
      if (_pipelines.containsKey(stream.id)) {
        debugPrint("[SKIP] Pipeline for ${stream.id} already exists");
        continue;
      }

      // StreamPipeline will load its own config and model
      final pipeline = StreamPipeline(stream: stream);
      _pipelines[stream.id] = pipeline;

      // CRITICAL: Log stream initialization
      debugPrint("[INIT] Stream: ${stream.id}");

      // Await initialization to prevent race conditions/crashes
      await pipeline.initialize();
      notifyListeners();

      // Stagger startup
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Update the model assigned to a stream
  Future<void> updateStreamModel(String streamId, String? modelPath) async {
    await ConfigService.instance.setModelForStream(streamId, modelPath);
    // Logic to restart specific stream pipeline?
    // For now, user has to Stop/Start engine.
    // But we can support hot-swap if we wanted.
  }

  /// Stop all inference and release all resources
  Future<void> stopAll() async {
    debugPrint("StreamEngine: Stopping engine (full shutdown)...");

    // Full destruction of all pipelines and resources
    await clearAll();

    debugPrint("StreamEngine: Engine stopped and resources released");
    notifyListeners();
  }

  /// Clear all streams and stop all processing
  Future<void> clearAll() async {
    debugPrint("StreamEngine: Clearing all streams and inference...");

    // Dispose all pipelines
    for (var p in _pipelines.values) {
      await p.dispose();
    }
    _pipelines.clear();

    // Release inference service
    InferenceService.instance.release();

    debugPrint("StreamEngine: All resources cleared");
    notifyListeners();
  }

  /// Get a specific pipeline by stream ID
  StreamPipeline? getPipeline(String streamId) {
    return _pipelines[streamId];
  }
}
