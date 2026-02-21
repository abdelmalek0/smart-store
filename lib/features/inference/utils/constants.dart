/// AI Configuration Constants
///
/// Centralized location for all AI-related configuration values.
library;

/// Global constants for AI inference and post-processing
class AiConstants {
  // Prevent instantiation
  AiConstants._();

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
  static const double confidenceThreshold = 0.25;

  /// IoU (Intersection over Union) threshold for Non-Maximum Suppression
  ///
  /// During NMS, boxes with IoU > this threshold are considered duplicates
  /// and suppressed.
  ///
  /// Range: 0.0 - 1.0
  static const double nmsIouThreshold = 0.45;

  // ============================================================================
  // PERFORMANCE TUNING (AI)
  // ============================================================================

  /// Inference batch processing interval in milliseconds
  ///
  /// The inference worker waits this long to accumulate a batch before
  /// processing. Lower values reduce latency but may reduce throughput.
  static const int inferenceBatchIntervalMs = 10;

  /// Maximum batch size for inference
  ///
  /// Number of frames to process together in one inference call.
  static const int maxBatchSize = 1;

  // ============================================================================
  // YOLO POST-PROCESSING
  // ============================================================================

  /// YOLOv8 output tensor shape (flattened)
  static const int yolov8OutputSize = 705600;

  /// Number of anchor points in YOLOv8 output
  static const int yolov8NumAnchors = 8400;

  /// Number of elements per anchor (4 bbox + 80 classes)
  static const int yolov8ElementsPerAnchor = 84;

  /// Number of YOLO classes (COCO dataset)
  static const int numClasses = 80;
}
