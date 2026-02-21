import 'dart:typed_data';

/// Abstract contract for the inference gateway.
///
/// Decouples the features layer from the native ONNX implementation.
abstract class InferenceGateway {
  /// Initialize the inference backend.
  Future<void> init();

  /// Request inference on a frame.
  Future<void> requestInference({
    required String streamId,
    required int requestId,
    required String modelPath,
    required Uint8List imageBytes,
    required int width,
    required int height,
  });

  /// Release all inference resources.
  Future<void> release();

  /// Shutdown the inference backend.
  void shutdown();
}
