/// Linux Video Capture Implementation
///
/// Uses NVDEC (NVIDIA hardware decoder) + OpenCV via FFI for GPU-accelerated
/// video decoding on Linux. Supports optimized path that combines frame
/// capture and inference in a single native call.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/ai/utils/yolo_processor.dart';

import '../video_capture.dart';

/// Linux-specific video capture implementation
///
/// Architecture:
/// - Dart (this class) ← FFI → C++ (inference_bridge.cpp)
/// - C++ uses FFmpeg with NVDEC for GPU-accelerated decoding
/// - Frames decoded directly to GPU memory (cv::cuda::GpuMat)
/// - Zero-copy path: GPU decode → GPU inference → GL texture
class LinuxVideoCapture implements VideoCapture {
  final NativeInferenceService _native = NativeInferenceService();
  bool _initialized = false;

  /// FFI Pointers for frame data (reused across calls)
  final Pointer<Pointer<Uint8>> _bufferPtrPtr = calloc<Pointer<Uint8>>();
  final Pointer<Int32> _widthPtr = calloc<Int32>();
  final Pointer<Int32> _heightPtr = calloc<Int32>();
  final Pointer<Float> _inferenceTimePtr = calloc<Float>();
  final Pointer<Int64> _timestampPtr = calloc<Int64>();

  /// Optimized inference session (optional)
  int? _sessionId;
  String? _modelPath;

  LinuxVideoCapture();

  /// Initialize native ONNX service
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    try {
      await _native.init();
      _initialized = true;
      debugPrint("✓ Linux: Native service initialized");
    } catch (e) {
      debugPrint("❌ Linux: Failed to initialize native service - $e");
      rethrow;
    }
  }

  /// Enable optimized inference path
  ///
  /// When enabled, [getFrame] can return frames with pre-computed detections,
  /// combining video decode + inference in a single native call for better
  /// performance.
  Future<void> enableOptimizedInference(String modelPath) async {
    await _ensureInitialized();

    try {
      debugPrint("🚀 Linux: Enabling optimized inference with $modelPath");
      _sessionId = _native.createSession(modelPath);
      _modelPath = modelPath;

      if (_sessionId != 0) {
        debugPrint("✓ Linux: Optimized session created (ID: $_sessionId)");

        // Extract and register model labels from ONNX metadata
        final labels = _native.getLabels(_sessionId!);
        if (labels.isNotEmpty) {
          debugPrint(
            "✓ Linux: Found ${labels.length} labels in model metadata",
          );
          // Import and register labels
          _registerLabels(modelPath, labels);
        }
      } else {
        debugPrint("⚠ Linux: Session creation returned 0");
        _sessionId = null;
      }
    } catch (e) {
      debugPrint("❌ Linux: Failed to create optimized session - $e");
      _sessionId = null;
    }
  }

  /// Register labels with the global registry for UI access
  void _registerLabels(String modelPath, Map<int, String> labels) {
    // Store labels in a static map for UI access
    // We use a simple approach - store in the class and expose via getter
    _modelLabels = labels;
    debugPrint("✓ Linux: Registered labels for $modelPath");
  }

  /// Labels from the current model
  static Map<int, String> _modelLabels = {};

  /// Get labels for the currently loaded model
  static Map<int, String> get modelLabels => _modelLabels;

  @override
  Future<VideoCaptureResult> open(String url) async {
    debugPrint("🐧 Linux: Opening video stream");
    debugPrint("   URL: $url");

    await _ensureInitialized();

    try {
      final streamId = _native.videoOpen(url);
      if (streamId != 0) {
        debugPrint(
          "✓ Linux: Video opened (stream=$streamId, NVDEC accelerated)",
        );
        return VideoCaptureResult(streamId);
      } else {
        throw Exception("Failed to open video stream");
      }
    } catch (e) {
      debugPrint("❌ Linux: Failed to open video - $e");
      rethrow;
    }
  }

  @override
  Future<VideoCaptureFrame?> getFrame(int streamId) async {
    try {
      int result;

      // Use optimized path if available
      if (_sessionId != null && _modelPath != null) {
        result = await _getFrameWithInference(streamId);
      } else {
        result = await _getFrameOnly(streamId);
      }

      if (result != 0) {
        return null; // Error or no frame available
      }

      // Extract frame data from FFI pointers
      final width = _widthPtr.value;
      final height = _heightPtr.value;
      final dataPtr = _bufferPtrPtr.value;

      if (width <= 0 || height <= 0 || dataPtr == nullptr) {
        return null;
      }

      final length = width * height * 4; // RGBA
      final data = Uint8List.fromList(dataPtr.asTypedList(length));
      final timestamp = _timestampPtr.value;

      // Check if this is an optimized frame with detections
      if (_sessionId != null && result == 0) {
        return LinuxOptimizedFrame.fromNative(
          data: data,
          width: width,
          height: height,
          timestamp: timestamp,
          sessionId: _sessionId!,
          native: _native,
          outputNames: ['output0'],
          inferenceTimeMs: _inferenceTimePtr.value,
        );
      }

      return VideoCaptureFrame(data, width, height, timestamp);
    } catch (e) {
      debugPrint("❌ Linux: Error getting frame - $e");
      return null;
    }
  }

  /// Get frame without inference
  Future<int> _getFrameOnly(int streamId) async {
    return _native.videoGetFrame(
      streamId,
      _bufferPtrPtr,
      _widthPtr,
      _heightPtr,
      _timestampPtr,
    );
  }

  /// Get frame WITH inference (optimized path)
  Future<int> _getFrameWithInference(int streamId) async {
    return _native.videoGetFrameAndInfer(
      streamId,
      _sessionId!,
      'images', // Input name
      ['output0'], // Output names
      _bufferPtrPtr,
      _widthPtr,
      _heightPtr,
      _inferenceTimePtr,
      _timestampPtr,
    );
  }

  @override
  Future<void> release(int streamId) async {
    try {
      _native.videoRelease(streamId);
      debugPrint("✓ Linux: Video stream $streamId released");
    } catch (e) {
      debugPrint("❌ Linux: Error releasing stream - $e");
    }

    // Release optimized session if exists
    if (_sessionId != null) {
      try {
        _native.releaseSession(_sessionId!);
        debugPrint("✓ Linux: Optimized session $_sessionId released");
      } catch (e) {
        debugPrint("❌ Linux: Error releasing session - $e");
      }
      _sessionId = null;
    }
  }

  /// Clean up FFI resources
  void dispose() {
    calloc.free(_bufferPtrPtr);
    calloc.free(_widthPtr);
    calloc.free(_heightPtr);
    calloc.free(_inferenceTimePtr);
    calloc.free(_timestampPtr);
  }
}

/// Linux optimized frame with pre-computed inference results
///
/// This frame type is returned when using the optimized inference path,
/// where video decode + inference happen in a single native call.
class LinuxOptimizedFrame extends VideoCaptureFrame {
  /// Detected objects in legacy format [x1, y1, x2, y2, score, class]
  final List<List<double>> detections;

  /// Inference time in milliseconds
  final double inferenceTime;

  LinuxOptimizedFrame({
    required Uint8List data,
    required int width,
    required int height,
    required int timestamp,
    required this.detections,
    required this.inferenceTime,
  }) : super(data, width, height, timestamp);

  /// Create from native inference results
  factory LinuxOptimizedFrame.fromNative({
    required Uint8List data,
    required int width,
    required int height,
    required int timestamp,
    required int sessionId,
    required NativeInferenceService native,
    required List<String> outputNames,
    double inferenceTimeMs = 0.0,
  }) {
    // Get inference outputs
    final Map<String, List<dynamic>> outputs = {};
    native.getSessionOutputs(sessionId, outputNames, outputs);

    // Post-process YOLO output using shared module
    List<List<double>> detections = [];
    if (outputs.containsKey(outputNames[0])) {
      final outData = outputs[outputNames[0]]!;
      final floatList = outData[0] as List<double>;

      // Use shared YoloProcessor
      final yoloDetections = YoloPostProcessor.postProcessYoloFloat(
        data: floatList,
        originalWidth: width,
        originalHeight: height,
      );

      // Convert to legacy format for backward compatibility
      detections = yoloDetections.map((det) {
        return [
          det.x - det.width / 2, // x1
          det.y - det.height / 2, // y1
          det.x + det.width / 2, // x2
          det.y + det.height / 2, // y2
          det.confidence,
          det.classId.toDouble(),
        ];
      }).toList();
    }

    return LinuxOptimizedFrame(
      data: data,
      width: width,
      height: height,
      timestamp: timestamp,
      detections: detections,
      inferenceTime: inferenceTimeMs,
    );
  }
}
