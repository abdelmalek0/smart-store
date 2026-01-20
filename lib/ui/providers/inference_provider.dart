import 'package:flutter/material.dart';

import 'package:smart_store_linux/backend/services/config_service.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';

class InferenceProvider extends ChangeNotifier {
  // Map<StreamId, ModelId> - stores model IDs for UI display
  final Map<String, String> _streamModelMap = {};
  // Reference to ModelProvider for path<->ID conversion
  ModelProvider? _modelProvider;
  // Track if we've already initialized
  bool _isInitialized = false;

  Map<String, String> get streamModelMap => _streamModelMap;
  bool get isInitialized => _isInitialized;

  /// Set ModelProvider reference for path<->ID conversion
  void setModelProvider(ModelProvider modelProvider) {
    _modelProvider = modelProvider;
  }

  Future<void> initialize() async {
    // Ensure ConfigService is initialized
    await ConfigService.instance.init();

    // Load all persisted stream-to-model mappings (these are paths)
    final persistedPaths = ConfigService.instance.getAllStreamMappings();
    _streamModelMap.clear();

    // Convert paths to model IDs for UI
    if (_modelProvider != null) {
      persistedPaths.forEach((streamId, modelPath) {
        try {
          final model = _modelProvider!.models.firstWhere(
            (m) => m.path == modelPath,
          );
          _streamModelMap[streamId] = model.id;
        } catch (e) {
          debugPrint('Could not find model for path $modelPath, skipping');
        }
      });
    }

    debugPrint(
      'InferenceProvider: Loaded ${_streamModelMap.length} stream-model mappings from config',
    );

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setModelForStream(
    String streamId,
    String? modelId,
    String? modelPath,
  ) async {
    if (modelId == null || modelPath == null) {
      _streamModelMap.remove(streamId);
      await ConfigService.instance.setModelForStream(streamId, null);
    } else {
      // Store modelId in memory for UI (dropdown selection)
      _streamModelMap[streamId] = modelId;
      // Store modelPath in config for persistence (actual file path needed by StreamManager)
      await ConfigService.instance.setModelForStream(streamId, modelPath);
    }
    notifyListeners();
  }

  String? getModelForStream(String streamId) {
    if (_streamModelMap.containsKey(streamId)) {
      return _streamModelMap[streamId];
    }
    // Fallback/Lazy Load from Config
    final persistedPath = ConfigService.instance.getModelForStream(streamId);
    if (persistedPath != null && _modelProvider != null) {
      try {
        final model = _modelProvider!.models.firstWhere(
          (m) => m.path == persistedPath,
        );
        _streamModelMap[streamId] = model.id;
        return model.id;
      } catch (e) {
        debugPrint('Could not find model for path $persistedPath');
      }
    }
    return null;
  }
}
