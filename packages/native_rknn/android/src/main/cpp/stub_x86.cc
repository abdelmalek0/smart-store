// Stub implementation for non-arm64 platforms (e.g. x86_64 emulator).
// The RKNN NPU hardware does not exist on these platforms; Android inference
// is handled by the Dart TfliteInferenceBackend instead.
// This file exists solely so the native_rknn plugin CMake target builds
// successfully and the Flutter plugin can register without errors.
