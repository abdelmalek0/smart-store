import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_rknn/native_rknn.dart';
import 'package:smart_store_linux/infrastructure/ai/backend/inference_backend.dart';

class RknnInferenceBackend extends InferenceBackend {
  final RknnInferenceService _service = RknnInferenceService();

  // Cache buffers to avoid allocation every frame
  Pointer<Uint8>? _inputBuf;
  int _inputBufSize = 0;

  Pointer<Int32>? _outIds;
  Pointer<Float>? _outScores;
  Pointer<Float>? _outBoxes;

  String? _modelPath;

  // Map streamId -> handle
  final Map<String, int> _handles = {};
  // Map streamId -> resolution hash (w << 16 | h)
  final Map<String, int> _resolutions = {};

  // Track initialization
  bool _serviceInited = false;

  @override
  Future<void> init() async {
    if (!_serviceInited) {
      await _service.init();
      _serviceInited = true;
    }
  }

  @override
  Future<int> loadModel(String modelPath, ModelType type) async {
    debugPrint("RknnBackend: loadModel $modelPath");
    _modelPath = modelPath;

    if (!_serviceInited) {
      await init();
    }

    // Allocate output buffers once (Max objects = OBJ_NUMB_MAX_SIZE)
    if (_outIds == null) {
      _outIds = calloc<Int32>(objNumbMaxSize);
      _outScores = calloc<Float>(objNumbMaxSize);
      _outBoxes = calloc<Float>(objNumbMaxSize * 4);
    }

    return 1; // Return dummy ID
  }

  @override
  Future<List<InferenceResult>> run(
    int modelId,
    List<InferenceInput> inputs,
  ) async {
    if (inputs.isEmpty || _modelPath == null) return [];

    final input = inputs.first;
    final w = input.width;
    final h = input.height;
    final streamId = input.streamId;

    // Check if we have a handle for this stream at this resolution
    int? handle = _handles[streamId];
    final currentRes = _resolutions[streamId];
    final targetRes = (w << 16) | h;

    if (handle == null || currentRes != targetRes) {
      debugPrint(
        "RknnBackend: Initializing model for stream $streamId (${w}x$h)",
      );

      if (handle != null) {
        _service.destroy(handle);
      }

      handle = _service.initModel(_modelPath!, w, h, 3);
      if (handle == 0) {
        debugPrint("RknnBackend: Init failed for stream $streamId");
        return [
          InferenceResult([], metadata: {'error': 'Init failed'}),
        ];
      }

      _handles[streamId] = handle;
      _resolutions[streamId] = targetRes;
    }

    // Prepare Input Buffer
    final requiredSize = input.imageBytes.length;
    if (_inputBuf == null || _inputBufSize < requiredSize) {
      if (_inputBuf != null) calloc.free(_inputBuf!);
      _inputBuf = calloc<Uint8>(requiredSize);
      _inputBufSize = requiredSize;
    }

    // Copy Data: Dart (Heap) -> Native (Heap)
    final bufList = _inputBuf!.asTypedList(requiredSize);
    bufList.setAll(0, input.imageBytes);

    // Run Inference in C++
    final count = _service.run(
      handle,
      _inputBuf!,
      _outIds!,
      _outScores!,
      _outBoxes!,
    );

    if (count < 0) {
      return [
        InferenceResult([], metadata: {'error': 'Run failed'}),
      ];
    }

    // Parse Results (Class, Score, X1, Y1, X2, Y2)
    // Flattened Float32List
    final resultFloats = Float32List(count * 6);
    for (int i = 0; i < count; i++) {
      resultFloats[i * 6 + 0] = _outIds![i].toDouble(); // Class
      resultFloats[i * 6 + 1] = _outScores![i]; // Score
      resultFloats[i * 6 + 2] = _outBoxes![i * 4 + 0]; // Left
      resultFloats[i * 6 + 3] = _outBoxes![i * 4 + 1]; // Top
      resultFloats[i * 6 + 4] = _outBoxes![i * 4 + 2]; // Right
      resultFloats[i * 6 + 5] = _outBoxes![i * 4 + 3]; // Bottom
    }

    // Convert to Bytes for InferenceResult
    final resultBytes = resultFloats.buffer.asUint8List().toList();

    return [
      InferenceResult([resultBytes], metadata: {'format': 'detections_f32_6'}),
    ];
  }

  @override
  void unloadModel(int modelId) {
    // Destroy all handles
    for (var handle in _handles.values) {
      _service.destroy(handle);
    }
    _handles.clear();
    _resolutions.clear();
  }
}
