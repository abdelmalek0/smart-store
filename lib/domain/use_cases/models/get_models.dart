import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';

/// Returns the current list of configured AI models.
class GetModels {
  final ConfigService _configService;

  GetModels(this._configService);

  List<ModelConfig> call() => _configService.models;
}
