import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:smart_store_linux/infrastructure/ai/backend/inference_backend.dart';
import 'package:smart_store_linux/infrastructure/ai/backend/android/android_device.dart';
import 'package:smart_store_linux/infrastructure/ai/utils/constants.dart';

// ============================================================================
// TFLite Inference Backend – Android (CPU / GPU / NNAPI)
// ============================================================================

/// Holds per-model resources allocated once in [TfliteInferenceBackend.loadModel]
/// and reused every frame.
class _ModelResources {
  final Interpreter interpreter;

  /// Flat float32 input buffer: 1 × modelSize × modelSize × 3
  final Float32List inputBuf;

  /// Flat float32 output buffer: product of output shape
  final Float32List outputBuf;

  /// Output tensor shape, e.g. [1, 84, 8400] or [1, 8400, 84]
  final List<int> outputShape;

  /// Zero-copy Uint8List views of the buffers above.
  ///
  /// Passing a Uint8List (not Float32List) to [Interpreter.runForMultipleInputs]
  /// makes [Tensor.getInputShapeIfDifferent] return null immediately — so
  /// resizeInputTensor is never called and our pinned [1,640,640,3] shape is
  /// never clobbered to [1228800], preventing the "PAD: 4 != 1" crash.
  late final Uint8List inputBytes;
  late final Uint8List outputBytes;

  _ModelResources({
    required this.interpreter,
    required this.inputBuf,
    required this.outputBuf,
    required this.outputShape,
  }) {
    inputBytes  = inputBuf.buffer.asUint8List();
    outputBytes = outputBuf.buffer.asUint8List();
  }
}

class TfliteInferenceBackend implements InferenceBackend {
  final InferenceDevice device;

  // modelId -> per-model resources (allocated once at loadModel time)
  final Map<int, _ModelResources> _models = {};
  int _nextModelId = 1;

  bool _initialized = false;

  TfliteInferenceBackend({this.device = InferenceDevice.cpu});

  // --------------------------------------------------------------------------
  // InferenceBackend interface
  // --------------------------------------------------------------------------

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('TfliteBackend: Initialized (device=$device)');
  }

  @override
  Future<int> loadModel(String modelPath, ModelType type) async {
    if (!_initialized) await init();

    final options = _buildInterpreterOptions();

    late final Interpreter interpreter;
    if (modelPath.startsWith('assets/')) {
      final assetRelPath = modelPath.substring('assets/'.length);
      interpreter = await Interpreter.fromAsset(assetRelPath, options: options);
    } else {
      interpreter = Interpreter.fromFile(File(modelPath), options: options);
    }

    // Pin the input shape once – prevents the PAD op from seeing a 1-D tensor
    // on models with dynamic batch dims (e.g. [-1, 640, 640, 3]).
    const int modelSize = AiConstants.modelInputSize;
    interpreter.resizeInputTensor(0, [1, modelSize, modelSize, 3]);
    interpreter.allocateTensors();

    final outShape = interpreter.getOutputTensor(0).shape;
    final outLen = outShape.fold<int>(1, (a, b) => a * b);

    // Pre-allocate both I/O buffers once – reused every frame (mirrors RKNN)
    final inputBuf  = Float32List(1 * modelSize * modelSize * 3);
    final outputBuf = Float32List(outLen);

    final id = _nextModelId++;
    _models[id] = _ModelResources(
      interpreter: interpreter,
      inputBuf: inputBuf,
      outputBuf: outputBuf,
      outputShape: outShape,
    );

    debugPrint(
      'TfliteBackend: Loaded model (id=$id device=$device) '
      'in=[1,$modelSize,$modelSize,3] out=$outShape',
    );

    return id;
  }

  @override
  Future<List<BackendResult>> run(
    int modelId,
    List<InferenceInput> inputs,
  ) async {
    final res = _models[modelId];
    if (res == null) throw StateError('TfliteBackend: model $modelId not loaded');

    final results = <BackendResult>[];
    for (final input in inputs) {
      try {
        results.add(_runSingle(res, input));
      } catch (e, st) {
        debugPrint('TfliteBackend: run error [${input.streamId}]: $e\n$st');
        results.add(BackendResult([], metadata: {'error': e.toString()}));
      }
    }
    return results;
  }

  @override
  void unloadModel(int modelId) {
    _models.remove(modelId)?.interpreter.close();
  }

  @override
  Map<int, String> getLabels(int modelId) => const {};

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------

  InterpreterOptions _buildInterpreterOptions() {
    final options = InterpreterOptions()..threads = 4;

    switch (device) {
      case InferenceDevice.gpu:
        // Try GPU → XNNPack → bare CPU (in that order).
        bool gpuAttached = false;
        try {
          options.addDelegate(GpuDelegateV2());
          debugPrint('TfliteBackend: GPU delegate attached');
          gpuAttached = true;
        } catch (e) {
          debugPrint('TfliteBackend: GPU delegate unavailable – $e');
        }
        if (!gpuAttached) {
          try {
            options.addDelegate(XNNPackDelegate());
            debugPrint('TfliteBackend: XNNPack delegate attached (GPU fallback)');
          } catch (e) {
            debugPrint('TfliteBackend: XNNPack unavailable – using bare CPU – $e');
          }
        }
        break;

      case InferenceDevice.nnapi:
        // tflite_flutter 0.10.x does not ship an NnApiDelegate wrapper.
        // Fall back to multi-threaded XNNPack, which uses available SIMD
        // acceleration on ARM64 and is typically faster than unaccelerated NNAPI.
        debugPrint(
          'TfliteBackend: NNAPI requested – using XNNPack (no NnApiDelegate in tflite_flutter 0.10.x)',
        );
        try {
          options.addDelegate(XNNPackDelegate());
          debugPrint('TfliteBackend: XNNPack delegate attached');
        } catch (e) {
          debugPrint('TfliteBackend: XNNPack delegate unavailable – $e');
        }
        break;

      case InferenceDevice.rknn:
        // Should not happen – worker uses RknnInferenceBackend for this case.
        // Treat as CPU fallback if TfliteInferenceBackend is somehow called with rknn.
        debugPrint('TfliteBackend: device=rknn unexpected here, using CPU');
        break;

      case InferenceDevice.cpu:
        // No extra delegate – tflite_flutter enables XNNPack by default
        break;
    }

    return options;
  }

  // --------------------------------------------------------------------------
  // Per-frame inference (synchronous – runs inside the worker isolate)
  // --------------------------------------------------------------------------

  BackendResult _runSingle(_ModelResources res, InferenceInput input) {
    const int modelSize = AiConstants.modelInputSize;

    // 1. Preprocess directly into the cached input buffer (zero extra alloc)
    _preprocessImage(
      input.imageBytes,
      input.width,
      input.height,
      modelSize,
      res.inputBuf,
    );

    // 2. Run: pass Uint8List byte-views.
    //    tflite_flutter's getInputShapeIfDifferent short-circuits for
    //    Uint8List/ByteBuffer → returns null → resizeInputTensor is never
    //    called → our pinned [1,640,640,3] stays intact → no PAD crash.
    res.interpreter.runForMultipleInputs(
      [res.inputBytes],
      {0: res.outputBytes},
    );

    // 3. Convert to List<double> for the worker post-processor
    final outShape = res.outputShape;
    final flat = res.outputBuf.map((v) => v.toDouble()).toList(growable: false);

    // Detect transposed layout [1, 8400, 84] vs standard [1, 84, 8400]
    final isTransposed =
        outShape.length == 3 && outShape[1] == AiConstants.yolov8NumAnchors;

    if (isTransposed) {
      final rows = outShape[1]; // 8400
      final cols = outShape[2]; // 84
      final transposed = List<double>.filled(flat.length, 0.0, growable: false);
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          transposed[c * rows + r] = flat[r * cols + c];
        }
      }
      return BackendResult([transposed]);
    }

    return BackendResult([flat]);
  }

  // --------------------------------------------------------------------------
  // Image preprocessing – letterbox resize + normalize to [0,1]
  // --------------------------------------------------------------------------

  /// Writes a stretch-resized, normalised NHWC float32 image into [out].
  /// [out] must be the pre-allocated input buffer: 1 × dstSize × dstSize × 3.
  ///
  /// Uses simple nearest-neighbour stretch (no letterbox padding) so that
  /// the post-processor's naive coordinate scaling
  ///   `cx * (originalWidth / dstSize)`
  /// is correct without needing a letterbox offset correction.
  ///
  /// Mirrors the RKNN backend's pattern of writing into a pre-allocated buffer
  /// instead of allocating a new one every frame.
  void _preprocessImage(
    Uint8List bytes,
    int srcW,
    int srcH,
    int dstSize,
    Float32List out,
  ) {
    final int channels = bytes.length ~/ (srcW * srcH); // 3 (RGB) or 4 (RGBA)

    for (int dy = 0; dy < dstSize; dy++) {
      // Nearest-neighbour Y mapping: stretch srcH → dstSize
      final sy = (dy * srcH ~/ dstSize).clamp(0, srcH - 1);

      for (int dx = 0; dx < dstSize; dx++) {
        // Nearest-neighbour X mapping: stretch srcW → dstSize
        final sx     = (dx * srcW ~/ dstSize).clamp(0, srcW - 1);
        final srcIdx = (sy * srcW + sx) * channels;
        final dstBase = (dy * dstSize + dx) * 3;

        out[dstBase + 0] = bytes[srcIdx]     / 255.0; // R
        out[dstBase + 1] = bytes[srcIdx + 1] / 255.0; // G
        out[dstBase + 2] = bytes[srcIdx + 2] / 255.0; // B
      }
    }
  }

  // --------------------------------------------------------------------------
  // Misc
  // --------------------------------------------------------------------------

}
