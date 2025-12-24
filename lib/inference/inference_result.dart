/// Public inference result returned to stream processors
class InferenceResult {
  final String streamId;
  final int requestId;
  final List<dynamic> detections;
  final String modelPath;

  InferenceResult({
    required this.streamId,
    required this.requestId,
    required this.detections,
    required this.modelPath,
  });
}
