import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_rknn/src/rknn_ffi_types.dart';

class RknnInferenceService {
  late DynamicLibrary _dylib;

  late RknnInitDart _rknnInit;
  late RknnRunDart _rknnRun;
  late RknnDestroyDart _rknnDestroy;

  /// Initialize the native library
  Future<void> init() async {
    try {
      if (Platform.isAndroid) {
        _dylib = DynamicLibrary.open("libnative_rknn.so");
      } else {
        throw UnsupportedError("Only Android is supported for RKNN");
      }

      _rknnInit = _dylib
          .lookup<NativeFunction<RknnInitDartFunc>>('rknn_init_dart')
          .asFunction();
      _rknnRun = _dylib
          .lookup<NativeFunction<RknnRunDartFunc>>('rknn_run_dart')
          .asFunction();
      _rknnDestroy = _dylib
          .lookup<NativeFunction<RknnDestroyDartFunc>>('rknn_destroy_dart')
          .asFunction();

      debugPrint("[RKNN Service] Native library loaded successfully.");
    } catch (e) {
      debugPrint("[RKNN Service] Failed to load native library: $e");
      rethrow;
    }
  }

  /// Initialize RKNN Model (Calls create in C++)
  /// Returns handle (address) on success, 0 on failure.
  int initModel(String modelPath, int width, int height, int channels) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      debugPrint(
          "[RKNN Service] Initializing model: $modelPath ($width x $height)");

      // rknn_init_dart now returns int64 handle (address)
      final handle = _rknnInit(pathPtr, width, height, channels);

      if (handle != 0) {
        debugPrint("[RKNN Service] Model initialized with handle: $handle");
        return handle;
      } else {
        debugPrint("[RKNN Service] Model initialization failed.");
        return 0;
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Run Inference
  /// [handle]: Model handle returned by initModel
  /// [inData]: Pointer to RGBA bytes
  /// [outIds]: Pointer to Int32 buffer (Size 64)
  /// [outScores]: Pointer to Float buffer (Size 64)
  /// [outBoxes]: Pointer to Float buffer (Size 64*4)
  /// Returns detection count
  int run(
    int handle,
    Pointer<Uint8> inData,
    Pointer<Int32> outIds,
    Pointer<Float> outScores,
    Pointer<Float> outBoxes,
  ) {
    if (handle == 0) return -1;
    return _rknnRun(handle, inData, outIds, outScores, outBoxes);
  }

  void destroy(int handle) {
    if (handle != 0) {
      _rknnDestroy(handle);
    }
  }
}
