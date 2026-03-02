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

import '../video_capture.dart';

/// Linux-specific video capture implementation
///
/// Architecture:
/// - Dart (this class) ← FFI → C++ (inference_bridge.cpp)
/// - C++ uses FFmpeg with NVDEC for GPU-accelerated decoding
/// - Frames decoded directly to GPU memory (cv::cuda::GpuMat)
/// - Zero-copy path: GPU decode → GL texture
class LinuxVideoCapture implements VideoCapture {
  final NativeInferenceService _native = NativeInferenceService();
  bool _initialized = false;

  /// FFI Pointers for frame data (reused across calls)
  final Pointer<Pointer<Uint8>> _bufferPtrPtr = calloc<Pointer<Uint8>>();
  final Pointer<Int32> _widthPtr = calloc<Int32>();
  final Pointer<Int32> _heightPtr = calloc<Int32>();
  final Pointer<Int64> _timestampPtr = calloc<Int64>();

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

  @override
  Future<VideoCaptureResult> open(String url) async {
    debugPrint("🐧 Linux: Opening video stream");
    debugPrint("   URL: $url");

    await _ensureInitialized();

    try {
      final streamId = _native.videoOpen(url);
      if (streamId != 0) {
        // Query native FPS — > 0 for files, 0.0 for live RTSP (self-pacing).
        final fps = _native.videoGetFps(streamId);
        debugPrint(
          '✓ Linux: Video opened (stream=$streamId, fps=${fps > 0 ? fps.toStringAsFixed(2) : "live/RTSP"})',
        );
        return VideoCaptureResult(streamId, nativeFps: fps);
      } else {
        throw Exception('Failed to open video stream');
      }
    } catch (e) {
      debugPrint("❌ Linux: Failed to open video - $e");
      rethrow;
    }
  }

  @override
  Future<VideoCaptureFrame?> getFrame(int streamId) async {
    try {
      final result = await _native.videoGetFrame(
        streamId,
        _bufferPtrPtr,
        _widthPtr,
        _heightPtr,
        _timestampPtr,
      );

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
      
      // OPTIMIZATION: In Zero-Copy Path, we don't need the pixels on the Dart side.
      final data = Uint8List(0); 
          
      final timestamp = _timestampPtr.value;

      return VideoCaptureFrame(data, width, height, timestamp);
    } catch (e) {
      debugPrint("❌ Linux: Error getting frame - $e");
      return null;
    }
  }

  @override
  Future<void> release(int streamId) async {
    try {
      _native.videoRelease(streamId);
      debugPrint("✓ Linux: Video stream $streamId released");
    } catch (e) {
      debugPrint("❌ Linux: Error releasing stream - $e");
    }
  }

  /// Clean up FFI resources
  void dispose() {
    calloc.free(_bufferPtrPtr);
    calloc.free(_widthPtr);
    calloc.free(_heightPtr);
    calloc.free(_timestampPtr);
  }
}
