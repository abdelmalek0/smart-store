import 'package:flutter/material.dart';

/// Widget that displays FPS counter and pipeline timing stats
/// as an overlay on top of a video stream.
///
/// Extracted from `detached_stream_player.dart` for single-responsibility.
class StatsOverlay extends StatelessWidget {
  final double fps;
  final int decodeMs;
  final int inferenceMs;
  final int postprocessMs;

  const StatsOverlay({
    super.key,
    required this.fps,
    required this.decodeMs,
    required this.inferenceMs,
    required this.postprocessMs,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display FPS (Big)
          Text(
            "FPS: ${fps.toStringAsFixed(1)}",
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  offset: Offset(2, 2),
                  blurRadius: 4,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          // Pipeline Stats (Smaller)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (decodeMs > 0 || inferenceMs > 0)
                  Text(
                    "D:${decodeMs}ms I:${inferenceMs}ms P:${postprocessMs}ms",
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
