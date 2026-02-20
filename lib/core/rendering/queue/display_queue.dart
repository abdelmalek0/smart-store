import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/constants.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/streaming/stream_manager.dart';
import 'package:smart_store_linux/core/streaming/video_bridge.dart';

/// Manages the display queue, backpressure, and frame broadcasting.
class DisplayQueue {
  final String streamId;

  // Configuration
  static const int displayQueueMaxSize = Constants.displayQueueMaxSize;

  // State
  final Queue<ProcessedFrame> _displayQueue = Queue<ProcessedFrame>();
  final StreamController<ProcessedFrame> _frameStreamController =
      StreamController<ProcessedFrame>.broadcast();

  bool _isActive = true;
  bool _isFrozen = false;
  int _displayCount = 0;

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
          frameToDisplay = _displayQueue.removeFirst();

          // STALENESS CHECK: Drop frame if it's too old for the native buffer
          final now = DateTime.now().millisecondsSinceEpoch;
          final lag = now - frameToDisplay.generationTimeMs;

          // If frame is > 1s old and we have generation time, drop it
          if (frameToDisplay.generationTimeMs > 0 && lag > 1000) {
            debugPrint(
              "DisplayQueue: Dropping stale frame TS=${frameToDisplay.decodeStartMs} Lag=${lag}ms",
            );

            // CRITICAL: Flush from native buffer
            // We need to know the native Video ID or Texture ID to flush.
            // DisplayQueue doesn't natively know the TextureID.
            // However, we can use StreamManager to look it up, or pass it in.
            // But DisplayQueue is in `core/rendering/queue`.
            // Ideally we use VideoBridge directly if we knew the Texture ID.

            // Getting Texture ID from StreamManager:
            // We need to import StreamManager.
            try {
              // We need a way to get the TextureID.
              // DisplayQueue has `streamId`.
              // We can use StreamManager singleton.
              // Note: This adds a dependency on StreamManager.
              final tid = StreamManager.instance.getTextureId(streamId);
              if (tid != null) {
                VideoBridge.showFrame(tid, frameToDisplay.decodeStartMs);
              }
            } catch (e) {
              // Ignore
            }

            // Loop again to get next frame
            frameToDisplay = null;
            continue;
          }

          if (_isFrozen) {
            // Remove detections if frozen
            frameToDisplay = ProcessedFrame(
              imageBytes: frameToDisplay.imageBytes,
              width: frameToDisplay.width,
              height: frameToDisplay.height,
              detections: [], // Clean detections
              decodeStartMs: frameToDisplay.decodeStartMs,
              generationTimeMs: frameToDisplay.generationTimeMs,
              preprocessEndMs: frameToDisplay.preprocessEndMs,
              inferenceEndMs: frameToDisplay.inferenceEndMs,
              postprocessEndMs: frameToDisplay.postprocessEndMs,
            );
          }
        }

        if (frameToDisplay != null && !_frameStreamController.isClosed) {
          _frameStreamController.add(frameToDisplay);
          _displayCount++;

          if (_displayCount % 60 == 0) {
            debugPrint(
              "DisplayQueue: Emitting frame #$_displayCount. TS: ${frameToDisplay.decodeStartMs} Q: ${_displayQueue.length}",
            );
          }
        }
      } catch (e) {
        debugPrint("DisplayQueue: Error in display loop: $e");
      }

      // Adaptive timing
      if (frameToDisplay != null) {
        // Yield to allow UI updates and other isolates to run
        await Future.delayed(const Duration(milliseconds: 1));
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
