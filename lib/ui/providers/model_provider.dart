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
          _models.add(ModelInfo(
            id: modelMap['id'],
            path: modelMap['path'],
            name: modelMap['name'],
          ));
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
    _models.add(ModelInfo(
      id: id,
      path: path,
      name: name,
    ));
    await _saveModels();
    notifyListeners();
  }

  Future<void> removeModel(String id) async {
    _models.removeWhere((m) => m.id == id);
    await _saveModels();
    notifyListeners();
  }

  // Persist models to shared preferences
  Future<void> _saveModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelsList = _models.map((model) => {
        'id': model.id,
        'path': model.path,
        'name': model.name,
      }).toList();
      await prefs.setString(_storageKey, jsonEncode(modelsList));
    } catch (e) {
      debugPrint('Error saving models: $e');
    }
  }
}

