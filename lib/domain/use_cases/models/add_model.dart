import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

/// Adds a new AI model to the configuration.
class AddModel {
  final ConfigService _configService;

  AddModel(this._configService);

  Future<void> call(ModelConfig model) => _configService.addModel(model);
}
