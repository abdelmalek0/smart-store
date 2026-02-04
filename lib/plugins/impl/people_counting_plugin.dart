import 'dart:async';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/plugins/base/plugin_base.dart';

/// People Counting Plugin
/// Detects people in the frame and emits a count event every 10 seconds.
class PeopleCountingPlugin extends SmartStorePlugin {
  DateTime? _lastEventTime;
  int _personClassId = 0; // COCO 'person' class ID
  double _confidenceThreshold = 0.5;

  // Smoothing
  final List<int> _recentCounts = [];
  static const int MAX_HISTORY = 5;

  String _modelPath = '';

  @override
  Future<void> onInit(Map<String, dynamic> config) async {
    _personClassId = config['personClassId'] ?? 0;
    _confidenceThreshold = config['confidenceThreshold'] ?? 0.5;
    if (config.containsKey('modelPath')) {
      _modelPath = config['modelPath'];
    }
    _lastEventTime = DateTime.now();
  }

  @override
  Future<void> processFrame(RawFrame frame) async {
    // Run inference on every frame for smooth visualization
    // TODO: optimization - skip inference if busy, but always pass frame?
    print("###########################################");
    print("People counting model path: $_modelPath");
    print("###########################################");
    requestInference(frame, _modelPath);
  }

  @override
  Future<void> handleInferenceResult(Map<String, dynamic> result) async {
    final detections = result['detections'] as List<dynamic>;
    // Format: [x1, y1, x2, y2, prob, classId]

    int personCount = 0;
    final List<dynamic> personDetections = [];

    for (var det in detections) {
      if (det is List && det.length >= 6) {
        final classId = (det[5] as num).toInt();
        final score = (det[4] as num).toDouble();
        if (classId == _personClassId && score >= _confidenceThreshold) {
          personCount++;
          personDetections.add(det);
        }
      }
    }

    // DEBUG: Log detections to verify inference
    if (detections.isNotEmpty) {
      print(
        "PeopleCountingPlugin: Frame processed. Total Detections: ${detections.length}, Persons: $personCount",
      );
    }

    // Smoothing logic (simple moving average)
    _recentCounts.add(personCount);
    if (_recentCounts.length > MAX_HISTORY) {
      _recentCounts.removeAt(0);
    }

    // Check if we should emit an event (every 30 seconds)
    final now = DateTime.now();
    if (_lastEventTime == null ||
        now.difference(_lastEventTime!).inSeconds >= 30) {
      final avgCount = _recentCounts.isEmpty
          ? 0
          : (_recentCounts.reduce((a, b) => a + b) / _recentCounts.length)
                .round();

      // DEBUG: Log event triggering
      print(
        "PeopleCountingPlugin: Check. Count: $avgCount (Recent: $_recentCounts)",
      );

      // Requirement: Only emit if people are detected (> 0)
      if (avgCount > 0) {
        emitEvent('People Count', {
          'count': avgCount,
          'msg': 'Detected $avgCount people',
        });
      }
      _lastEventTime = now;
    }

    // Emit processed frame for display
    final requestId = result['requestId'] as int;
    final frame = getPendingFrame(requestId);

    if (frame != null) {
      // Determine processing time
      final processingStartMs = result['processingStartMs'] as int? ?? 0;
      final inferenceEndMs = DateTime.now().millisecondsSinceEpoch;

      emitDisplayFrame(frame, personDetections, {
        'decode':
            0, // lost this info unless we passed it through requestInference->result meta
        'inference': (processingStartMs > 0)
            ? (inferenceEndMs - processingStartMs)
            : 0,
        'postprocess': 0,
      });
    }
  }
}
