import 'package:flutter/material.dart';

/// Paints bounding boxes and labels for object detections on top of a video frame.
///
/// Extracted from `detached_stream_player.dart` for single-responsibility.
/// Handles coordinate transformation from model/original image space to
/// screen space using BoxFit.contain logic.
class DetectionOverlayPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size originalSize;

  /// Optional custom labels map from ONNX model metadata
  /// Key: classId, Value: class name
  final Map<int, String>? customLabels;

  /// Get label for a class ID
  /// Uses customLabels from model metadata if available, otherwise falls back to 'class_N' format
  String getLabel(int classId) {
    if (customLabels != null && customLabels!.containsKey(classId)) {
      return customLabels![classId]!;
    }
    return 'class_$classId';
  }

  DetectionOverlayPainter({
    required this.detections,
    required this.originalSize,
    this.customLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final Paint paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint textBgPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );

    // BoxFit.contain logic
    // The image is centered and scaled to fit within 'size' while maintaining aspect ratio.

    double scale = 0.0;
    double offsetX = 0.0;
    double offsetY = 0.0;

    double aspectRatio = originalSize.width / originalSize.height;
    double containerRatio = size.width / size.height;

    if (containerRatio > aspectRatio) {
      // Container is wider than image. Image is height-constrained.
      scale = size.height / originalSize.height;
      offsetX = (size.width - (originalSize.width * scale)) / 2;
    } else {
      // Container is taller than image. Image is width-constrained.
      scale = size.width / originalSize.width;
      offsetY = (size.height - (originalSize.height * scale)) / 2;
    }

    for (var det in detections) {
      if (det is List && det.length >= 4) {
        // Coordinates from C++ are already in original image space (e.g., 1280x720)
        // NOT in model space (320x320) - the C++ post_process already converted them
        double x1 = (det[0] as num).toDouble();
        double y1 = (det[1] as num).toDouble();
        double x2 = (det[2] as num).toDouble();
        double y2 = (det[3] as num).toDouble();

        // Transform from original image coords to screen coords
        double screenX1 = (x1 * scale) + offsetX;
        double screenY1 = (y1 * scale) + offsetY;
        double screenX2 = (x2 * scale) + offsetX;
        double screenY2 = (y2 * scale) + offsetY;

        // Draw bounding box
        canvas.drawRect(
          Rect.fromLTRB(screenX1, screenY1, screenX2, screenY2),
          paint,
        );

        // Draw label with confidence
        if (det.length >= 5) {
          final double confidence = (det[4] as num).toDouble();
          // Use classId (index 5) to get actual label if available
          final int classId = det.length >= 6 ? (det[5] as num).toInt() : 0;
          final String label = getLabel(classId);
          final String text =
              '$label ${(confidence * 100).toStringAsFixed(1)}%';

          final textSpan = TextSpan(text: text, style: textStyle);
          final textPainter = TextPainter(
            text: textSpan,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();

          // Draw background for text
          final textOffset = Offset(
            screenX1,
            screenY1 - textPainter.height - 4,
          );
          final textBgRect = Rect.fromLTWH(
            textOffset.dx,
            textOffset.dy,
            textPainter.width + 8,
            textPainter.height + 4,
          );
          canvas.drawRect(textBgRect, textBgPaint);

          // Draw text
          textPainter.paint(canvas, textOffset.translate(4, 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.originalSize != originalSize;
  }
}
