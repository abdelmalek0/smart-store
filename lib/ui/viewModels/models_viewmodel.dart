import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

/// ViewModel for the Models screen.
///
/// Owns file picking, model CRUD, label file parsing,
/// and dialog form state.
class ModelsViewModel extends ChangeNotifier {
  ModelsViewModel() {
    AppService.instance.models.addListener(notifyListeners);
  }

  @override
  void dispose() {
    AppService.instance.models.removeListener(notifyListeners);
    super.dispose();
  }

  List<ModelConfig> get models => AppService.instance.models.all;

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

  /// Add a model by path. Name is auto-derived from filename by ConfigService logic here.
  Future<void> addModel(String path) async {
    final id = const Uuid().v4();
    final name = p.basename(path);
    final model = ModelConfig(id: id, path: path, name: name);

    await AppService.instance.models.add(model);
    notifyListeners();
  }

  /// Remove a model by its ID.
  Future<void> removeModel(String modelId) async {
    await AppService.instance.models.remove(modelId);
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
  Future<void> updateModelLabels(
    String modelId,
    Map<int, String> labels,
  ) async {
    final model = AppService.instance.models.get(modelId);
    if (model != null) {
      await AppService.instance.models.update(model.copyWith(labels: labels));
      notifyListeners();
    }
  }
}
