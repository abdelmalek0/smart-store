import 'package:smart_store_linux/services/config_service.dart';

/// Removes an AI model by its [modelId].
class RemoveModel {
  final ConfigService _configService;

  RemoveModel(this._configService);

  Future<void> call(String modelId) => _configService.removeModel(modelId);
}
