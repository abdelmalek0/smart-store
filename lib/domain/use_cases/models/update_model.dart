import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

/// Updates an existing AI model entry in the configuration.
class UpdateModel {
  final ConfigService _configService;

  UpdateModel(this._configService);

  Future<void> call(ModelConfig model) => _configService.updateModel(model);
}
