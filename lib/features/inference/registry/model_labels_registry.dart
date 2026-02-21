/// Global registry for model labels extracted from ONNX metadata
///
/// This singleton holds labels for each loaded model, allowing the UI
/// to display proper class names without needing direct access to session IDs.
class ModelLabelsRegistry {
  static final ModelLabelsRegistry _instance = ModelLabelsRegistry._internal();
  factory ModelLabelsRegistry() => _instance;
  static ModelLabelsRegistry get instance => _instance;
  ModelLabelsRegistry._internal();

  /// Labels indexed by model path
  /// Each entry maps classId -> className
  final Map<String, Map<int, String>> _labelsByModel = {};

  /// Global labels to use when model-specific labels aren't available
  /// This is populated from the currently active model
  Map<int, String> _activeLabels = {};

  /// Register labels for a specific model
  void registerLabels(String modelPath, Map<int, String> labels) {
    _labelsByModel[modelPath] = labels;
    // Also set as active labels
    _activeLabels = labels;
  }

  /// Get labels for a specific model
  Map<int, String>? getLabels(String modelPath) {
    return _labelsByModel[modelPath];
  }

  /// Get currently active labels (from the most recently loaded model)
  Map<int, String> get activeLabels => _activeLabels;

  /// Set the active labels directly
  void setActiveLabels(Map<int, String> labels) {
    _activeLabels = labels;
  }

  /// Get a specific label by class ID from the active labels
  String? getLabel(int classId) {
    return _activeLabels[classId];
  }

  /// Clear all registered labels
  void clear() {
    _labelsByModel.clear();
    _activeLabels = {};
  }
}
