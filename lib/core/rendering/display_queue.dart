import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/constants.dart';
import 'package:smart_store_linux/core/models/frames.dart';

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

          if (_isFrozen) {
            // Remove detections if frozen
            frameToDisplay = ProcessedFrame(
              imageBytes: frameToDisplay.imageBytes,
              width: frameToDisplay.width,
              height: frameToDisplay.height,
              detections: [], // Clean detections
              decodeStartMs: frameToDisplay.decodeStartMs,
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
            // debugPrint("DisplayQueue: Display loop emitting frame #${_displayCount}. Q: $_displayQueue.length");
          }
        }
      } catch (e) {
        debugPrint("DisplayQueue: Error in display loop: $e");
      }

      // Adaptive timing
      if (frameToDisplay != null) {
        await Future.delayed(Duration.zero);
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
