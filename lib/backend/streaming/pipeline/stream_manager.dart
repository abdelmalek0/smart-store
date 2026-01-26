import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/models/rtsp_stream.dart';
import 'package:smart_store_linux/backend/services/config_service.dart';
import 'package:smart_store_linux/ai/inference/service/inference_service.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_processor.dart';

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
/// - Creating and managing StreamProcessor instances
/// - Starting/stopping inference for all streams
/// - Coordinating with InferenceService and ConfigService
class StreamProcessManager extends ChangeNotifier {
  static final StreamProcessManager _instance =
      StreamProcessManager._internal();
  factory StreamProcessManager() => _instance;
  static StreamProcessManager get instance => _instance;

  StreamProcessManager._internal();

  final Map<String, StreamProcessor> _processors = {};

  Map<String, StreamProcessor> get processors =>
      UnmodifiableMapView(_processors);

  bool get isRunning => _processors.values.any((p) => !p.isFrozen);

  /// Start all streams with their assigned models
  void startAll(
    List<RTSPStream> streams,
    Map<String, String>
    streamModelMap, // Keep for backward compat or initial overrides
    List<dynamic> models,
  ) async {
    debugPrint("StreamManager: Starting all streams...");

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
      // Skip if already exists
      if (_processors.containsKey(stream.id)) {
        debugPrint("[SKIP] Processor for ${stream.id} already exists");
        continue;
      }

      // StreamProcessor will load its own config and model
      final processor = StreamProcessor(stream: stream);
      _processors[stream.id] = processor;

      // CRITICAL: Log stream initialization
      debugPrint("[INIT] Stream: ${stream.id}");

      // Await initialization to prevent race conditions/crashes
      await processor.initialize();
      notifyListeners();

      // Stagger startup
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Update the model assigned to a stream
  Future<void> updateStreamModel(String streamId, String? modelPath) async {
    await ConfigService.instance.setModelForStream(streamId, modelPath);
    // Logic to restart specific stream processor?
    // For now, user has to Stop/Start engine.
    // But we can support hot-swap if we wanted.
  }

  /// Stop all inference and release all resources
  Future<void> stopAll() async {
    debugPrint("StreamManager: Stopping engine (full shutdown)...");

    // Full destruction of all processors and resources
    await clearAll();

    debugPrint("StreamManager: Engine stopped and resources released");
    notifyListeners();
  }

  /// Clear all streams and stop all processing
  Future<void> clearAll() async {
    debugPrint("StreamManager: Clearing all streams and inference...");

    // Dispose all processors
    for (var p in _processors.values) {
      await p.dispose();
    }
    _processors.clear();

    // Release inference service
    InferenceService.instance.release();

    debugPrint("StreamManager: All resources cleared");
    notifyListeners();
  }

  /// Get a specific processor by stream ID
  StreamProcessor? getProcessor(String streamId) {
    return _processors[streamId];
  }
}
