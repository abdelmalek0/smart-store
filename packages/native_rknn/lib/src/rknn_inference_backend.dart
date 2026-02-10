import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_rknn/src/rknn_ffi_types.dart';
import 'package:native_rknn/src/rknn_inference_service.dart';

/// RKNN inference backend for Rockchip NPU
///
/// Provides inference functionality using RKNN Runtime.
/// Supports multiple models via sessions.
class RknnInferenceBackend {
  final RknnInferenceService _rknnService = RknnInferenceService();
  final Map<int, int> _sessionToHandle = {};

  // Cache output buffers (shared across sessions for now, or per-cal)
  // To be safe for multi-threading/concurrency, we should allocate per run or use a pool.
  // But Dart is single threaded in one Isolate.
  Pointer<Int32>? _outIds;
  Pointer<Float>? _outScores;
  Pointer<Float>? _outBoxes;

  int _nextSessionId = 1;
  bool _isInitialized = false;

  String get name => 'RKNN Runtime (NPU)';

  Future<void> init() async {
    if (!_isInitialized) {
      await _rknnService.init();
      _isInitialized = true;
      debugPrint('[$name] Backend initialized');
    }
  }

  /// Create a session for a model
  /// Returns session ID
  int createSession(String modelPath, {int width = 640, int height = 640}) {
    debugPrint('[$name] Creating session for: $modelPath');

    final handle = _rknnService.initModel(modelPath, width, height, 3);
    if (handle == 0) {
      throw Exception('Failed to initialize model: $modelPath');
    }

    final sessionId = _nextSessionId++;
    _sessionToHandle[sessionId] = handle;

    debugPrint('[$name] Session created with ID: $sessionId, handle: $handle');
    return sessionId;
  }

  void releaseSession(int sessionId) {
    final handle = _sessionToHandle.remove(sessionId);
    if (handle != null) {
      _rknnService.destroy(handle);
      debugPrint('[$name] Released session: $sessionId');
    }
  }

  /// Run inference
  /// Returns List of detections [class, score, x1, y1, x2, y2, ...]
  List<double> runInference(
    int sessionId,
    Uint8List imageBytes,
  ) {
    final handle = _sessionToHandle[sessionId];
    if (handle == null) {
      throw Exception('[$name] Invalid session ID: $sessionId');
    }

    // Allocate temp input buffer
    // Note: In a real high-perf scenario, we should cache this or use an Allocator that reuses memory.
    final inputPtr = calloc<Uint8>(imageBytes.length);
    try {
      inputPtr.asTypedList(imageBytes.length).setAll(0, imageBytes);

      // Ensure output buffers exist
      if (_outIds == null) {
        _outIds = calloc<Int32>(objNumbMaxSize);
        _outScores = calloc<Float>(objNumbMaxSize);
        _outBoxes = calloc<Float>(objNumbMaxSize * 4);
      }

      // Run inference
      final count =
          _rknnService.run(handle, inputPtr, _outIds!, _outScores!, _outBoxes!);

      if (count < 0) {
        throw Exception('Inference failed');
      }

      // Collect results
      final results = <double>[];
      for (int i = 0; i < count; i++) {
        results.add(_outIds![i].toDouble()); // Class
        results.add(_outScores![i]); // Score
        results.add(_outBoxes![i * 4 + 0]); // x1
        results.add(_outBoxes![i * 4 + 1]); // y1
        results.add(_outBoxes![i * 4 + 2]); // x2
        results.add(_outBoxes![i * 4 + 3]); // y2
      }

      return results;
    } finally {
      calloc.free(inputPtr);
    }
  }

  void dispose() {
    // Release all sessions
    for (var sessionId in _sessionToHandle.keys.toList()) {
      releaseSession(sessionId);
    }

    // Free buffers
    if (_outIds != null) {
      calloc.free(_outIds!);
      calloc.free(_outScores!);
      calloc.free(_outBoxes!);
      _outIds = null;
    }

    debugPrint('[$name] Backend disposed');
  }
}
