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
  // MODEL CONFIGURATION
  // ============================================================================

  /// Input size for YOLO models (width and height in pixels)
  ///
  /// Most YOLO models (v5, v7, v8) use 640x640 input. Frames are resized
  /// to this dimension before inference.
  static const int modelInputSize = 640;

  /// Number of channels in model input (RGB)
  static const int modelInputChannels = 3;

  /// Total size of flattened model input tensor
  static const int modelInputTensorSize =
      modelInputSize * modelInputSize * modelInputChannels;

  // ============================================================================
  // DETECTION THRESHOLDS
  // ============================================================================

  /// Minimum confidence score for a detection to be considered valid
  ///
  /// Detections with confidence below this threshold are filtered out.
  ///
  /// Range: 0.0 - 1.0
  /// Tuning:
  /// - Higher values: Fewer false positives, may miss some objects
  /// - Lower values: More detections, may include false positives
  static const double confidenceThreshold = 0.25;

  /// IoU (Intersection over Union) threshold for Non-Maximum Suppression
  ///
  /// During NMS, boxes with IoU > this threshold are considered duplicates
  /// and suppressed.
  ///
  /// Range: 0.0 - 1.0
  /// Tuning:
  /// - Higher values: Keep more overlapping boxes (less suppression)
  /// - Lower values: Aggressive suppression, may merge nearby objects
  static const double nmsIouThreshold = 0.45;

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

  /// Inference batch processing interval in milliseconds
  ///
  /// The inference worker waits this long to accumulate a batch before
  /// processing. Lower values reduce latency but may reduce throughput.
  static const int inferenceBatchIntervalMs = 10;

  /// Maximum batch size for inference
  ///
  /// Number of frames to process together in one inference call.
  /// Note: Current implementation processes frames individually.
  static const int maxBatchSize = 1;

  // ============================================================================
  // YOLO POST-PROCESSING
  // ============================================================================

  /// YOLOv8 output tensor shape (flattened)
  ///
  /// YOLOv8 outputs [1, 84, 8400] which is flattened to 705600 elements:
  /// - 84 rows: 4 bbox coords (x, y, w, h) + 80 class probabilities
  /// - 8400 columns: anchor points
  static const int yolov8OutputSize = 705600;

  /// Number of anchor points in YOLOv8 output
  static const int yolov8NumAnchors = 8400;

  /// Number of elements per anchor (4 bbox + 80 classes)
  static const int yolov8ElementsPerAnchor = 84;

  /// Number of YOLO classes (COCO dataset)
  static const int numClasses = 80;
}
