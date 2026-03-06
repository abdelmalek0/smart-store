import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/domain/utils/constants.dart';
import 'package:smart_store_linux/domain/entities/processed_frame.dart';
import 'package:smart_store_linux/infrastructure/streaming/stream_orchestrator.dart';
import 'package:smart_store_linux/infrastructure/streaming/bridge/video_bridge.dart';

/// Manages the display queue, backpressure, and frame broadcasting.
class DisplayQueue {
  final String streamId;

  // Platform-specific bridge for native frame flushing
  final VideoBridge _bridge = VideoBridge();

  // Configuration
  static const int displayQueueMaxSize = Constants.displayQueueMaxSize;

  // State
  final Queue<ProcessedFrame> _displayQueue = Queue<ProcessedFrame>();
  final StreamController<ProcessedFrame> _frameStreamController =
      StreamController<ProcessedFrame>.broadcast();

  bool _isActive = true;
  bool _isFrozen = false;
  int _displayCount = 0;

  // Live display FPS tracking (5-second window)
  int _fpsWindowStart = DateTime.now().millisecondsSinceEpoch;
  int _fpsWindowFrames = 0;
  static const int _fpsLogIntervalMs = 5000;

  // Getters
  Stream<ProcessedFrame> get frameStream => _frameStreamController.stream;
  bool get isClosed => _frameStreamController.isClosed;
  bool get isFrozen => _isFrozen;
  int get queueLength => _displayQueue.length;

  DisplayQueue(this.streamId);

  /// Add a frame to the queue, managing backpressure
  void enqueue(ProcessedFrame frame) {
    if (_displayQueue.length >= displayQueueMaxSize) {
      _displayQueue.removeFirst(); // Drop oldest to make room
    }
    _displayQueue.add(frame);
  }

  /// Start the display loop
  void startLoop() async {
    debugPrint("DisplayQueue: Starting display loop for $streamId");

    while (_isActive) {
      ProcessedFrame? frameToDisplay;

      try {
        if (_displayQueue.isNotEmpty) {
          // Drain stale frames so only the latest is shown.
          while (_displayQueue.length > 1) {
            final stale = _displayQueue.removeFirst();
            try {
              final tid = StreamOrchestrator.instance.getTextureManagerId(streamId);
              if (tid != null) {
                _bridge.showFrame(tid, stale.decodeStartMs);
              }
            } catch (_) {}
          }

          frameToDisplay = _displayQueue.removeFirst();

          // STALENESS CHECK: Drop frame if it's too old (> 500ms = real-time threshold)
          final now = DateTime.now().millisecondsSinceEpoch;
          final lag = now - frameToDisplay.generationTimeMs;

          if (frameToDisplay.generationTimeMs > 0 && lag > Constants.maxDisplayLatencyMs) {
            debugPrint(
              "DisplayQueue: Dropping stale frame TS=${frameToDisplay.decodeStartMs} Lag=${lag}ms",
            );

            // Flush from native buffer before discarding.
            try {
              final tid = StreamOrchestrator.instance.getTextureManagerId(streamId);
              if (tid != null) {
                _bridge.showFrame(tid, frameToDisplay.decodeStartMs);
              }
            } catch (_) {}

            frameToDisplay = null;
            continue;
          }

          if (_isFrozen) {
            frameToDisplay = ProcessedFrame(
              imageBytes: frameToDisplay.imageBytes,
              width: frameToDisplay.width,
              height: frameToDisplay.height,
              detections: [],
              decodeStartMs: frameToDisplay.decodeStartMs,
              generationTimeMs: frameToDisplay.generationTimeMs,
              preprocessEndMs: frameToDisplay.preprocessEndMs,
              inferenceEndMs: frameToDisplay.inferenceEndMs,
              postprocessEndMs: frameToDisplay.postprocessEndMs,
            );
          }
        }

        if (frameToDisplay != null && !_frameStreamController.isClosed) {
          // STRICT SYNC: Force-update the native GPU texture to match THIS frame's timestamp
          // before we broadcast it to the UI.
          try {
             final tid = StreamOrchestrator.instance.getTextureManagerId(streamId);
             if (tid != null) {
               _bridge.showFrame(tid, frameToDisplay.decodeStartMs);
             }
          } catch (_) {
            // Ignore temporary sync failures
          }

          _frameStreamController.add(frameToDisplay);
          _displayCount++;
          _fpsWindowFrames++;

          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsed = now - _fpsWindowStart;
          if (elapsed >= _fpsLogIntervalMs) {
            final displayFps = (_fpsWindowFrames / (elapsed / 1000.0)).toStringAsFixed(1);
            debugPrint('[Display] $streamId | live: $displayFps fps | total emitted: $_displayCount');
            _fpsWindowFrames = 0;
            _fpsWindowStart  = now;
          }
        }
      } catch (e) {
        debugPrint("DisplayQueue: Error in display loop: $e");
      }

      // Vsync-aligned timing (~60fps cap).
      // Do not spin faster than the display can render — 1ms was burning CPU.
      if (frameToDisplay != null) {
        await Future.delayed(const Duration(milliseconds: 16));
      } else {
        await Future.delayed(const Duration(milliseconds: 8));
      }
    }
  }

  void setFrozen(bool frozen) {
    _isFrozen = frozen;
    debugPrint("DisplayQueue: Frozen state set to $_isFrozen for $streamId");
  }

  void dispose() {
    _isActive = false;
    _displayQueue.clear();
    if (!_frameStreamController.isClosed) {
      _frameStreamController.close();
    }
    debugPrint("DisplayQueue: Disposed for $streamId");
  }
}
