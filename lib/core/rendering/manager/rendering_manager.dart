import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/rendering/queue/display_queue.dart';
import 'package:smart_store_linux/core/streaming/bridge/video_bridge.dart';

/// Manages rendering resources and display queues for all streams.
///
/// Responsibilities:
/// - Owns [DisplayQueue] instances.
/// - Controls display flow (freeze/unfreeze).
/// - Provides frame streams to UI.
class RenderingManager {
  static final RenderingManager _instance = RenderingManager._internal();
  factory RenderingManager() => _instance;
  static RenderingManager get instance => _instance;

  // Platform-specific video bridge (created once via factory)
  final VideoBridge _bridge = VideoBridge();

  RenderingManager._internal();

  // Active Display Queues: Map<StreamId, DisplayQueue>
  final Map<String, DisplayQueue> _queues = {};

  // Persistent Frame Controllers: Map<StreamId, StreamController<int>>
  final Map<String, StreamController<int>> _frameControllers = {};

  /// Initialize rendering resources for a stream
  void initialize(String streamId) {
    // 1. Cleanup old queue if any, but keep stream controller alive for UI subscriptions
    _queues[streamId]?.dispose();
    _queues.remove(streamId);

    debugPrint("RenderingManager: Initializing display queue for $streamId");
    final queue = DisplayQueue(streamId);
    _queues[streamId] = queue;

    // 2. Get or reuse existing controller (don't close it during re-initialization!)
    final controller = _getOrCreateFrameController(streamId);

    // Pipe queue events to controller
    // DisplayQueue emits ProcessedFrame. We map to timestamp.
    queue.frameStream.listen((frame) {
      if (!controller.isClosed) {
        controller.add(frame.decodeStartMs);
      }
    });

    queue.startLoop();
  }

  /// Helper to get or create persistent controller
  StreamController<int> _getOrCreateFrameController(String streamId) {
    if (!_frameControllers.containsKey(streamId) ||
        _frameControllers[streamId]!.isClosed) {
      // Broadcast controller so multiple listeners (UI, etc) can attach
      _frameControllers[streamId] = StreamController<int>.broadcast();
    }
    return _frameControllers[streamId]!;
  }

  /// Enqueue a processed frame for display
  void enqueueFrame(String streamId, ProcessedFrame frame) {
    _queues[streamId]?.enqueue(frame);
  }

  /// Get the frame stream (timestamps) for a given stream ID (used by UI)
  /// Now returns a persistent stream that survives pipeline restarts/delays
  Stream<int> getFrameStream(String streamId) {
    return _getOrCreateFrameController(streamId).stream;
  }

  /// Get the detection stream for a given stream ID
  Stream<ProcessedFrame> getDetectionStream(String streamId) {
    final stream = _queues[streamId]?.frameStream;
    if (stream != null) {
      return stream;
    }
    return Stream.empty();
  }

  /// Freeze display for a stream
  void freeze(String streamId) {
    _queues[streamId]?.setFrozen(true);
  }

  /// Unfreeze display for a stream
  void unfreeze(String streamId) {
    _queues[streamId]?.setFrozen(false);
  }

  /// Check if stream is frozen
  bool isFrozen(String streamId) {
    return _queues[streamId]?.isFrozen ?? false;
  }

  /// Dispose rendering resources for a stream
  void dispose(String streamId) {
    // 1. Dispose Queue
    _queues[streamId]?.dispose();
    _queues.remove(streamId);

    // 2. Dispose Frame Controller
    if (_frameControllers.containsKey(streamId)) {
      _frameControllers[streamId]?.close();
      _frameControllers.remove(streamId);
    }

    debugPrint("RenderingManager: Disposed resources for $streamId");
  }

  /// Dispose all resources
  void disposeAll() {
    for (final key in _queues.keys.toList()) {
      dispose(key);
    }
  }

  /// Show a frame on the native display (proxy to platform bridge)
  Future<bool> showFrame(int nativeVideoId, int timestamp) async {
    if (nativeVideoId > 0) {
      return await _bridge.showFrame(nativeVideoId, timestamp);
    }
    return false;
  }
}
