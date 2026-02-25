/// Pipeline Configuration Constants
///
/// Centralized location for all configuration values used throughout the
/// video processing pipeline. This ensures consistency and makes it easy
/// to tune performance characteristics.
library;

/// Global constants for the video processing pipeline
class Constants {
  // Prevent instantiation
  Constants._();

  // ============================================================================
  // QUEUE CONFIGURATION
  // ============================================================================

  /// Maximum size of the inference queue (per stream)
  ///
  /// This queue buffers raw frames waiting for inference. A small size (2)
  /// ensures we always process the most recent frame and prevents memory
  /// buildup when inference is slower than capture.
  ///
  /// Tuning:
  /// - Larger values: More buffering, higher latency, more memory
  /// - Smaller values: Lower latency, may drop more frames if inference is slow
  static const int inferenceQueueMaxSize = 2;

  /// Maximum size of the display queue (per stream)
  ///
  /// This queue buffers processed frames (with detections) ready for display.
  /// A moderate size (10) smooths out inference jitter while limiting memory.
  ///
  /// Tuning:
  /// - Larger values: Smoother playback, higher latency, more memory
  /// - Smaller values: Lower latency, may stutter if inference fluctuates
  static const int displayQueueMaxSize = 10;

  // ============================================================================
  // PERFORMANCE TUNING
  // ============================================================================

  /// Video capture timeout in milliseconds
  ///
  /// Maximum time to wait for a frame from video capture before timing out.
  static const int captureTimeoutMs = 100;

  /// Performance logging interval (in frames)
  ///
  /// Log performance metrics every N frames to avoid excessive logging.
  static const int perfLogIntervalFrames = 100;
}
