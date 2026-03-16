/// Android-specific device selector for inference backends.
///
/// This enum is only meaningful on Android; on Linux the ONNX backend is
/// always used and this value is ignored.
enum InferenceDevice {
  /// Try Rockchip RKNN NPU first (arm64 physical devices).
  /// Automatically falls back to TFLite CPU when RKNN is unavailable
  /// (e.g. x86_64 emulator or non-Rockchip hardware).
  rknn,

  /// TFLite CPU inference – XNNPack multi-threaded, works everywhere.
  cpu,

  /// TFLite GPU inference via the OpenGL ES delegate (Android).
  gpu,

  /// TFLite XNNPack delegate (same as [cpu] + explicit SIMD acceleration).
  nnapi,
}
