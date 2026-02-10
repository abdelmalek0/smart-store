import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smart_store_linux/core/models/model_info.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';

/// ViewModel for the Models screen.
///
/// Owns file picking, model CRUD, label file parsing,
/// and dialog form state.
class ModelsViewModel extends ChangeNotifier {
  final ModelProvider modelProvider;

  ModelsViewModel({required this.modelProvider});

  List<ModelInfo> get models => modelProvider.models;

  /// Pick an ONNX/RKNN model file from disk.
  /// Returns the selected path, or null if cancelled.
  Future<String?> pickModelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      return result.files.single.path;
    }
    return null;
  }

  /// Add a model by path. Name is auto-derived from filename by ModelProvider.
  void addModel(String path) {
    modelProvider.addModel(path);
    notifyListeners();
  }

  /// Remove a model by its ID.
  void removeModel(String modelId) {
    modelProvider.removeModel(modelId);
    notifyListeners();
  }

  /// Pick and parse a label .txt file.
  /// Returns a map of classId → label, or null if cancelled/error.
  Future<Map<int, String>?> pickAndParseLabels() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      allowMultiple: false,
    );

    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return null;
    }

    return parseLabelFile(result.files.single.path!);
  }

  /// Parse a label .txt file into classId → label map.
  Map<int, String>? parseLabelFile(String filePath) {
    try {
      final file = File(filePath);
      final lines = file.readAsLinesSync();
      final labels = <int, String>{};
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) {
          labels[i] = line;
        }
      }
      return labels.isEmpty ? null : labels;
    } catch (e) {
      debugPrint('Error parsing label file: $e');
      return null;
    }
  }

  /// Upload parsed labels to a model.
  void uploadLabels(String modelId, Map<int, String> labels) {
    modelProvider.updateModelLabels(modelId, labels);
    notifyListeners();
  }
}
