import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/infrastructure/ai/backend/inference_backend.dart';

/// Linux implementation using ONNX Runtime
class OnnxInferenceBackend implements InferenceBackend {
  NativeInferenceService? _service;
  final Map<int, NativeOrtSession> _sessions = {};
  // Track IDs manually since we are wrapping the session key
  int _nextModelId = 1;

  @override
  Future<void> init() async {
    _service = NativeInferenceService();
    await _service!.init();
    debugPrint("OnnxBackend: Service initialized");
  }

  @override
  Future<int> loadModel(String modelPath, ModelType type) async {
    if (_service == null) await init();

    final file = File(modelPath);
    if (!file.existsSync()) {
      throw Exception("Model file not found: $modelPath");
    }

    final session = await NativeOrtSession.fromFile(file);
    final id = _nextModelId++;
    _sessions[id] = session;
    return id;
  }

  @override
  Future<List<BackendResult>> run(
    int modelId,
    List<InferenceInput> inputs,
  ) async {
    final session = _sessions[modelId];
    if (session == null) {
      throw Exception("Model ID $modelId not found");
    }

    // ONNX Preprocessing and Batch Construction
    // Mimics the logic from InferenceWorker, but encapsulated here
    final batchSize = inputs.length;
    // Expected size for YoloV5/V8 640x640 input (3 * 640 * 640 floats)
    const singleImageFloats = 3 * 640 * 640;
    final totalFloats = batchSize * singleImageFloats;

    final batchBuffer = calloc<Float>(totalFloats);
    final inputTensor = NativeOrtValueTensor.createTensorFromPointer(
      batchBuffer,
      [batchSize, 3, 640, 640], // NCHW
    );
    final runOptions = NativeOrtRunOptions();

    try {
      // Check if we can use zero-copy optimized path (Batch size 1 only for zero-copy)
      if (batchSize == 1 &&
          inputs[0].videoId != null &&
          inputs[0].videoId! > 0 &&
          inputs[0].imageBytes.isEmpty) {
        final req = inputs[0];
        final inferenceTimePtr = calloc<Float>();

        try {
          // Use Zero-Copy 2.0: Inference ONLY on the last captured GPU frame
          final ret = _service!.videoInferenceOnly(
            req.videoId!,
            session.sessionId,
            'images',
            ['output0'],
            inferenceTimePtr,
          );

          if (ret == 0) {
            // Retrieve outputs from session
            final Map<String, List<dynamic>> outputs = {};
            _service!.getSessionOutputs(session.sessionId, ['output0'], outputs);

            if (outputs.containsKey('output0')) {
              final flatData = (outputs['output0']![0] as List).cast<double>();
              return [BackendResult([flatData])];
            }
          }
        } finally {
          calloc.free(inferenceTimePtr);
        }
      }

      // 1. Preprocess each image into the batch buffer
      for (int i = 0; i < batchSize; i++) {
        final req = inputs[i];
        if (req.imageBytes.isEmpty) continue;

        final Pointer<Uint8> inPtr = calloc<Uint8>(req.imageBytes.length);
        try {
          final inList = inPtr.asTypedList(req.imageBytes.length);
          inList.setAll(0, req.imageBytes);

          // Calculate offset for this image in the batch buffer
          final Pointer<Float> outPtr = Pointer.fromAddress(
            batchBuffer.address + (i * singleImageFloats * sizeOf<Float>()),
          );

          // Use native preprocessing
          _service!.preprocessImage(inPtr, req.width, req.height, outPtr);
        } finally {
          calloc.free(inPtr);
        }
      }

      // 2. Run Inference
      final inputsMap = {'images': inputTensor};
      final results = session.run(runOptions, inputsMap);

      if (results.isEmpty) {
        return List.generate(batchSize, (_) => BackendResult([]));
      }

      // 3. Parse Results
      final dynamic firstOutput = results[0]; // [data, shape]
      final List<double> flatData = (firstOutput[0] as List).cast<double>();

      final outputResults = <BackendResult>[];
      final perImageSize = flatData.length ~/ batchSize;

      for (int i = 0; i < batchSize; i++) {
        final start = i * perImageSize;
        final end = start + perImageSize;
        final sublist = flatData.sublist(start, end);

        outputResults.add(BackendResult([sublist]));
      }

      return outputResults;
    } finally {
      inputTensor.release();
      runOptions.release();
      calloc.free(batchBuffer);
    }
  }

  @override
  void unloadModel(int modelId) {
    final session = _sessions.remove(modelId);
    session?.release();
  }

  @override
  Map<int, String> getLabels(int modelId) {
    if (_service == null) return {};
    final session = _sessions[modelId];
    if (session == null) return {};
    return _service!.getLabels(session.sessionId);
  }
}
