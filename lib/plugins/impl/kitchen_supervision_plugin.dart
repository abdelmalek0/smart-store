import 'dart:async';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/plugins/base/plugin_base.dart';

/// Kitchen Supervision Plugin
/// Detects 'Hand' class (index 3) and emits an event if detected for 5 seconds consecutively.
class KitchenSupervisionPlugin extends SmartStorePlugin {
  DateTime? _handDetectionStartTime;
  int _handClassId = 3; // 'Hand' is index 3
  double _confidenceThreshold = 0.5;
  String _modelPath = ''; // Default, can be overridden in config
  bool _eventFiredForThisSession = false;

  @override
  Future<void> onInit(Map<String, dynamic> config) async {
    _handClassId = config['handClassId'] ?? 3;
    _confidenceThreshold = config['confidenceThreshold'] ?? 0.5;
    if (config.containsKey('modelPath')) {
      _modelPath = config['modelPath'];
    }
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

        // Classes: ['Hat', 'Mask', 'Glove', 'Hand']
        // We are interested in 'Hand' (index 3) for events.
        // We are interested in 'Hand' (index 3) and 'Glove' (index 2) for display.

        if (score >= _confidenceThreshold) {
          if (classId == _handClassId) {
            handDetected = true;
            handDetections.add(det);
          } else if (classId == 2) {
            // Glove
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
        print(
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
