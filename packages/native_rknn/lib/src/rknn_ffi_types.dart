import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ==========================================
// C++ Bridge Native Types
// ==========================================

// int64_t rknn_init_dart(const char* model_path, int32_t width, int32_t height, int32_t channels)
typedef RknnInitDartFunc = Int64 Function(
  Pointer<Utf8> modelPath,
  Int32 width,
  Int32 height,
  Int32 channels,
);
typedef RknnInitDart = int Function(
  Pointer<Utf8> modelPath,
  int width,
  int height,
  int channels,
);

// int32_t rknn_run_dart(int64_t handle, uint8_t* in_data, int32_t* out_ids, float* out_scores, float* out_boxes)
typedef RknnRunDartFunc = Int32 Function(
  Int64 handle,
  Pointer<Uint8> inData,
  Pointer<Int32> outIds,
  Pointer<Float> outScores,
  Pointer<Float> outBoxes, // [N * 4]
);
typedef RknnRunDart = int Function(
  int handle,
  Pointer<Uint8> inData,
  Pointer<Int32> outIds,
  Pointer<Float> outScores,
  Pointer<Float> outBoxes,
);

// void rknn_destroy_dart(int64_t handle)
typedef RknnDestroyDartFunc = Void Function(Int64 handle);
typedef RknnDestroyDart = void Function(int handle);

// Constants
const int objNumbMaxSize = 64;
