import 'dart:async';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/plugins/base/plugin_base.dart';
import 'package:flutter/foundation.dart';

/// Kitchen Supervision Plugin
/// Detects 'no-gloves' class (index 4) for violations and 'gloves' class (index 0) for display.
/// Emits an event if 'no-gloves' is detected for 5 seconds consecutively.
class KitchenSupervisionPlugin extends SmartStorePlugin {
  DateTime? _handDetectionStartTime;
  int _handClassId = 4; // 'no-gloves' is index 4
  double _confidenceThreshold = 0.5;
  String _modelPath = ''; // Default, can be overridden in config
  bool _eventFiredForThisSession = false;

  @override
  Future<void> onInit(Map<String, dynamic> config) async {
    _handClassId = config['handClassId'] ?? 4;
    _confidenceThreshold = config['confidenceThreshold'] ?? 0.5;
    if (config.containsKey('modelPath')) {
      _modelPath = config['modelPath'];
    }

    // DEBUG: Log initialization
    debugPrint(
      "KitchenSupervisionPlugin [$streamId]: Initialized. Model Path: $_modelPath, Hand Class ID: $_handClassId",
    );
  }

  @override
  Future<void> processFrame(RawFrame frame) async {
    // NOTE: This method is NOT called when using the optimized Linux video pipeline.
    // Inference results are passed directly via handleInferenceResult.
    // Logs here will not appear in production on Linux.
    requestInference(frame, _modelPath);
  }

  @override
  Future<void> handleInferenceResult(Map<String, dynamic> result) async {
    final detections = result['detections'] as List<dynamic>;
    // Format: [x1, y1, x2, y2, prob, classId]

    bool handDetected = false;
    final List<dynamic> handDetections = [];

    for (var det in detections) {
      if (det is List && det.length >= 6) {
        final classId = (det[5] as num).toInt();
        final score = (det[4] as num).toDouble();

        // Classes:
        // 0: gloves
        // 1: hat
        // 2: head
        // 3: mask
        // 4: no-gloves (Hand) - Violation
        // 5: no-mask

        if (score >= _confidenceThreshold) {
          if (classId == _handClassId) {
            // 4: no-gloves
            handDetected = true;
            handDetections.add(det);
          } else if (classId == 0) {
            // 0: gloves (Display only)
            handDetections.add(det);
          }
        }
      }
    }

    final now = DateTime.now();

    if (handDetected) {
      if (_handDetectionStartTime == null) {
        _handDetectionStartTime = now;
        _eventFiredForThisSession = false;
      } else {
        final duration = now.difference(_handDetectionStartTime!);
        if (duration.inSeconds >= 5 && !_eventFiredForThisSession) {
          debugPrint("Kitchen Violation: Bare hands detected!");
          emitEvent('Kitchen Violation', {
            'msg': 'Bare hands detected for ${duration.inSeconds} seconds!',
            'duration': duration.inSeconds,
            'timestamp': now.millisecondsSinceEpoch,
          });
          _eventFiredForThisSession =
              true; // Prevent spamming every frame after 5s
        }
      }
    } else {
      // Reset if hand is lost
      // Optional: Add a small grace period (e.g. 0.5s) to avoid resetting on flickering detections
      // For now, strict reset.
      _handDetectionStartTime = null;
      _eventFiredForThisSession = false;
    }

    // Emit processed frame for display
    final requestId = result['requestId'] as int;
    final frame = getPendingFrame(requestId);

    if (frame != null) {
      final processingStartMs = result['processingStartMs'] as int? ?? 0;
      final inferenceEndMs = DateTime.now().millisecondsSinceEpoch;

      // DEBUG: Log detections similar to PeopleCountingPlugin
      if (detections.isNotEmpty) {
        debugPrint(
          "KitchenSupervisionPlugin [$streamId]: Frame processed. Total Detections: ${detections.length}, Hands: ${handDetections.length}, Hand Detected: $handDetected",
        );
      }

      emitDisplayFrame(frame, handDetections, {
        'decode': 0,
        'inference': (processingStartMs > 0)
            ? (inferenceEndMs - processingStartMs)
            : 0,
        'postprocess': 0,
      });
    }
  }
}
