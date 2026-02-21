import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

/// Returns the current list of configured AI models.
class GetModels {
  final ConfigService _configService;

  GetModels(this._configService);

  List<ModelConfig> call() => _configService.models;
}
