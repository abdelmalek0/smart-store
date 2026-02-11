/// YOLO Post-Processing Utilities
///
/// Shared utilities for processing YOLO model outputs, including:
/// - Converting raw model outputs to bounding boxes
/// - Non-Maximum Suppression (NMS)
/// - Coordinate scaling from model space to image space
///
/// This module eliminates duplication between inference_worker.dart and
/// capture_isolate.dart by providing a single, well-tested implementation.
library;

import 'dart:math' as math;
import 'package:smart_store_linux/ai/utils/constants.dart';

/// Represents a single object detection result
class Detection {
  final double x; // Center X coordinate (in original image space)
  final double y; // Center Y coordinate (in original image space)
  final double width; // Box width (in original image space)
  final double height; // Box height (in original image space)
  final int classId; // Class ID (0-79 for COCO)
  final double confidence; // Detection confidence (0.0 - 1.0)

  Detection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.classId,
    required this.confidence,
  });

  /// Convert to list format [x, y, w, h, confidence, classId]
  List<double> toList() {
    return [x, y, width, height, confidence, classId.toDouble()];
  }

  @override
  String toString() {
    return 'Detection(class=$classId, conf=${confidence.toStringAsFixed(2)}, '
        'box=[${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
        '${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)}])';
  }
}

/// YOLO Post-Processing Utilities
class YoloPostProcessor {
  // Prevent instantiation
  YoloPostProcessor._();

  /// Post-process YOLOv8 float output
  ///
  /// Expected input shape: [1, 84, 8400] flattened to [705600]
  /// Layout:
  /// - Row 0: x (center)
  /// - Row 1: y (center)
  /// - Row 2: w
  /// - Row 3: h
  /// - Rows 4..83: Class probabilities (80 classes)
  ///
  /// Returns: List of detections in original image coordinates
  static List<Detection> postProcessYoloFloat({
    required List<double> data,
    required int originalWidth,
    required int originalHeight,
    double confidenceThreshold = AiConstants.confidenceThreshold,
    double nmsThreshold = AiConstants.nmsIouThreshold,
  }) {
    final int numAnchors = AiConstants.yolov8NumAnchors; // 8400
    // Dynamic calculation: data.length = (4 + numClasses) * numAnchors
    // (4 + numClasses) = data.length / numAnchors
    // numClasses = (data.length / numAnchors) - 4
    if (data.length % numAnchors != 0) {
      throw ArgumentError(
        'Invalid YOLOv8 output size: ${data.length} is not divisible by $numAnchors anchors.',
      );
    }

    final int numClasses = (data.length ~/ numAnchors) - 4;

    // Safety check
    if (numClasses <= 0) {
      throw ArgumentError(
        'Invalid YOLOv8 output size: ${data.length} implies $numClasses classes (must be > 0).',
      );
    }

    final int inputSize = AiConstants.modelInputSize;

    final List<Detection> candidates = [];

    // Process each anchor point
    for (int i = 0; i < numAnchors; i++) {
      // Extract bbox coordinates (model space: 0-640)
      final double cx = data[i]; // x center
      final double cy = data[numAnchors + i]; // y center
      final double w = data[2 * numAnchors + i]; // width
      final double h = data[3 * numAnchors + i]; // height

      // Find the class with maximum probability
      double maxProb = 0.0;
      int maxClass = 0;
      for (int c = 0; c < numClasses; c++) {
        final double prob = data[(4 + c) * numAnchors + i];
        if (prob > maxProb) {
          maxProb = prob;
          maxClass = c;
        }
      }

      // Filter by confidence threshold
      if (maxProb < confidenceThreshold) continue;

      // Scale coordinates from model space (640x640) to original image space
      final scaleX = originalWidth / inputSize;
      final scaleY = originalHeight / inputSize;

      candidates.add(
        Detection(
          x: cx * scaleX,
          y: cy * scaleY,
          width: w * scaleX,
          height: h * scaleY,
          classId: maxClass,
          confidence: maxProb,
        ),
      );
    }

    // Apply Non-Maximum Suppression
    return performNMS(candidates, iouThreshold: nmsThreshold);
  }

  /// Perform Non-Maximum Suppression (NMS)
  ///
  /// Filters out overlapping detections, keeping only the most confident ones.
  ///
  /// Algorithm:
  /// 1. Sort detections by confidence (descending)
  /// 2. For each detection:
  ///    - Keep it if it doesn't overlap significantly with any already-kept detection
  ///    - "Significant overlap" means IoU > iouThreshold
  ///
  /// Returns: Filtered list of detections
  static List<Detection> performNMS(
    List<Detection> detections, {
    double iouThreshold = AiConstants.nmsIouThreshold,
  }) {
    if (detections.isEmpty) return [];

    // Sort by confidence descending
    final sorted = List<Detection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<Detection> kept = [];

    for (final candidate in sorted) {
      bool shouldKeep = true;

      // Check if candidate overlaps significantly with any kept detection
      for (final keptDetection in kept) {
        // Only compare detections of the same class
        if (candidate.classId != keptDetection.classId) continue;

        final iou = _calculateIoU(candidate, keptDetection);
        if (iou > iouThreshold) {
          shouldKeep = false;
          break;
        }
      }

      if (shouldKeep) {
        kept.add(candidate);
      }
    }

    return kept;
  }

  /// Calculate Intersection over Union (IoU) between two detections
  ///
  /// IoU = Area of Overlap / Area of Union
  ///
  /// Returns: IoU value in range [0.0, 1.0]
  static double _calculateIoU(Detection a, Detection b) {
    // Convert center coordinates to corner coordinates
    final double aX1 = a.x - a.width / 2;
    final double aY1 = a.y - a.height / 2;
    final double aX2 = a.x + a.width / 2;
    final double aY2 = a.y + a.height / 2;

    final double bX1 = b.x - b.width / 2;
    final double bY1 = b.y - b.height / 2;
    final double bX2 = b.x + b.width / 2;
    final double bY2 = b.y + b.height / 2;

    // Calculate intersection rectangle
    final double interX1 = math.max(aX1, bX1);
    final double interY1 = math.max(aY1, bY1);
    final double interX2 = math.min(aX2, bX2);
    final double interY2 = math.min(aY2, bY2);

    // Calculate intersection area
    final double interWidth = math.max(0.0, interX2 - interX1);
    final double interHeight = math.max(0.0, interY2 - interY1);
    final double interArea = interWidth * interHeight;

    // Calculate union area
    final double aArea = a.width * a.height;
    final double bArea = b.width * b.height;
    final double unionArea = aArea + bArea - interArea;

    // Avoid division by zero
    if (unionArea == 0.0) return 0.0;

    return interArea / unionArea;
  }

  /// Scale coordinates from model space to original image space
  ///
  /// Utility function for manual coordinate scaling if needed.
  static Map<String, double> scaleCoordinates({
    required double modelX,
    required double modelY,
    required double modelWidth,
    required double modelHeight,
    required int originalWidth,
    required int originalHeight,
    int modelInputSize = AiConstants.modelInputSize,
  }) {
    final scaleX = originalWidth / modelInputSize;
    final scaleY = originalHeight / modelInputSize;

    return {
      'x': modelX * scaleX,
      'y': modelY * scaleY,
      'width': modelWidth * scaleX,
      'height': modelHeight * scaleY,
    };
  }
}
