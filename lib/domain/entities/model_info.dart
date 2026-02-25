class ModelInfo {
  final String id;
  final String path;
  final String name;

  /// Custom labels uploaded by user from .txt file
  /// Key: class index (line number in file), Value: class name
  final Map<int, String>? customLabels;

  ModelInfo({
    required this.id,
    required this.path,
    required this.name,
    this.customLabels,
  });

  /// Create a copy with updated labels
  ModelInfo copyWithLabels(Map<int, String>? labels) {
    return ModelInfo(id: id, path: path, name: name, customLabels: labels);
  }

  /// Check if model has custom labels loaded
  bool get hasCustomLabels => customLabels != null && customLabels!.isNotEmpty;
}
