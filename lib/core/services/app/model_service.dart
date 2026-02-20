import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

/// Service responsible for managing AI models.
class ModelService extends ChangeNotifier {
  ModelService() {
    ConfigService.instance.addListener(notifyListeners);
  }

  List<ModelConfig> get all => ConfigService.instance.models;

  ModelConfig? get(String modelId) => ConfigService.instance.getModel(modelId);

  Future<void> add(ModelConfig model) async {
    await ConfigService.instance.addModel(model);
  }

  Future<void> remove(String modelId) async {
    await ConfigService.instance.removeModel(modelId);
  }

  Future<void> update(ModelConfig model) async {
    await ConfigService.instance.updateModel(model);
  }

  @override
  void dispose() {
    ConfigService.instance.removeListener(notifyListeners);
    super.dispose();
  }
}
