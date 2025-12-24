/// Native ONNX Runtime Plugin for Flutter
/// 
/// This package provides a native bridge to ONNX Runtime with GPU acceleration.
/// 
/// Main classes:
/// - [NativeInferenceService] - Singleton service for native inference
/// - [NativeOrtSession] - ONNX runtime session
/// - [NativeOrtValueTensor] - Tensor value wrapper
/// - [NativeOrtRunOptions] - Runtime options
library native_onnx;

// Export public API
export 'src/native_inference_service.dart';
export 'src/ort_session.dart';
export 'src/ort_tensor.dart';
