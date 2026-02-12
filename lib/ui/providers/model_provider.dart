import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:smart_store_linux/core/models/model_info.dart';

class ModelProvider extends ChangeNotifier {
  final List<ModelInfo> _models = [];
  static const String _storageKey = 'saved_models';
  bool _isInitialized = false;

  List<ModelInfo> get models => _models;
  bool get isInitialized => _isInitialized;

  // Load persisted models on initialization
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? modelsJson = prefs.getString(_storageKey);

      if (modelsJson != null) {
        final List<dynamic> modelsList = jsonDecode(modelsJson);
        _models.clear();
        for (var modelMap in modelsList) {
          // Parse customLabels if present
          Map<int, String>? labels;
          if (modelMap['customLabels'] != null) {
            final labelsMap = modelMap['customLabels'] as Map<String, dynamic>;
            labels = labelsMap.map(
              (k, v) => MapEntry(int.parse(k), v as String),
            );
          }

          _models.add(
            ModelInfo(
              id: modelMap['id'],
              path: modelMap['path'],
              name: modelMap['name'],
              customLabels: labels,
            ),
          );
        }
      }
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading saved models: $e');
      _isInitialized = true;
    }
  }

  Future<void> addModel(String path) async {
    final id = const Uuid().v4();
    final name = p.basename(path);
    _models.add(ModelInfo(id: id, path: path, name: name));
    await _saveModels();
    notifyListeners();
  }

  Future<void> removeModel(String id) async {
    _models.removeWhere((m) => m.id == id);
    await _saveModels();
    notifyListeners();
  }

  /// Update custom labels for a model
  Future<void> updateModelLabels(String id, Map<int, String>? labels) async {
    final index = _models.indexWhere((m) => m.id == id);
    if (index != -1) {
      _models[index] = _models[index].copyWithLabels(labels);
      await _saveModels();
      notifyListeners();
    }
  }

  /// Get labels for a model by its path (used by StreamPipeline)
  Map<int, String>? getLabelsForModelPath(String modelPath) {
    // debugPrint("[LABELS LOOKUP] Searching for path: $modelPath");
    // debugPrint(
    //   "[LABELS LOOKUP] Available models: ${_models.map((m) => '${m.path} (${m.customLabels?.length ?? 0} labels)').toList()}",
    // );
    final model = _models.where((m) => m.path == modelPath).firstOrNull;
    // debugPrint(
    //   "[LABELS LOOKUP] Found model: ${model?.name}, labels: ${model?.customLabels?.length ?? 0}",
    // );
    return model?.customLabels;
  }

  // Persist models to shared preferences
  Future<void> _saveModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelsList = _models
          .map(
            (model) => {
              'id': model.id,
              'path': model.path,
              'name': model.name,
              // Serialize labels with string keys for JSON compatibility
              if (model.customLabels != null)
                'customLabels': model.customLabels!.map(
                  (k, v) => MapEntry(k.toString(), v),
                ),
            },
          )
          .toList();
      await prefs.setString(_storageKey, jsonEncode(modelsList));
    } catch (e) {
      debugPrint('Error saving models: $e');
    }
  }
}
