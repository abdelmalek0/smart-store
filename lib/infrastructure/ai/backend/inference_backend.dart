import 'dart:typed_data';

/// Type of model to load
enum ModelType { classifier, yolo }

/// Standardized output for inference
/// Wraps the raw results which might differ by platform/model
class InferenceResult {
  /// Raw output buffers (e.g. `List<float>` or `List<int>`)
  final List<List<dynamic>> outputs;

  /// Metadata helpful for post-processing (e.g. quantization params for RKNN)
  final Map<String, dynamic> metadata;

  InferenceResult(this.outputs, {this.metadata = const {}});
}

/// Input for inference
class InferenceInput {
  final Uint8List imageBytes;
  final int width;
  final int height;
  // Unique ID for the stream/request to help with debugging or matching
  final String streamId;

  InferenceInput({
    required this.imageBytes,
    required this.width,
    required this.height,
    this.streamId = '',
  });
}

/// Abstract interface for Inference Backends
abstract class InferenceBackend {
  /// Initialize the backend service (if needed)
  Future<void> init();

  /// Load a model and return a handle/ID
  /// [modelPath] is the absolute path to the model file
  /// [type] hints at the model architecture
  Future<int> loadModel(String modelPath, ModelType type);

  /// Run inference on a batch of inputs
  /// [modelId] is the handle returned by loadModel
  /// [inputs] is a list of inputs (batch size 1 or more)
  /// Returns a list of results corresponding to inputs
  Future<List<InferenceResult>> run(int modelId, List<InferenceInput> inputs);

  /// Unload a model
  void unloadModel(int modelId);
}
