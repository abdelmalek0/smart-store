import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/ai/inference/backends/inference_backend.dart';

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
  Future<List<InferenceResult>> run(
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
      // 1. Preprocess each image into the batch buffer
      for (int i = 0; i < batchSize; i++) {
        final req = inputs[i];
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
        return List.generate(batchSize, (_) => InferenceResult([]));
      }

      // 3. Parse Results
      // ONNX returns [ [data, shape], ... ]
      // We assume single output head for now as per current worker logic (though v8 might differ)
      // The current worker expects a flat list of floats and splits it
      final dynamic firstOutput = results[0]; // [data, shape]
      final List<double> flatData = (firstOutput[0] as List).cast<double>();
      // shape is firstOutput[1]

      final outputResults = <InferenceResult>[];
      final perImageSize = flatData.length ~/ batchSize;

      for (int i = 0; i < batchSize; i++) {
        final start = i * perImageSize;
        final end = start + perImageSize;
        final sublist = flatData.sublist(start, end);

        // Wrap in InferenceResult
        outputResults.add(InferenceResult([sublist]));
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
}
