import 'package:flutter/material.dart';
import 'package:smart_store_linux/services/inference_service.dart';

class InferenceProvider extends ChangeNotifier {
  // Map<StreamId, ModelId>
  final Map<String, String> _streamModelMap = {};

  Map<String, String> get streamModelMap => _streamModelMap;

  Future<void> setModelForStream(String streamId, String? modelId, String? modelPath) async {
    if (modelId == null) {
      _streamModelMap.remove(streamId);
    } else {
      _streamModelMap[streamId] = modelId;
      if (modelPath != null) {
        // Trigger model loading in background
        // In a real app we might want to await this or handle errors
        InferenceService().loadModel(modelPath);
      }
    }
    notifyListeners();
  }
  
  String? getModelForStream(String streamId) {
    return _streamModelMap[streamId];
  }
}
