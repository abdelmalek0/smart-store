import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';

/// Returns all AI models from the configuration.
class GetModels {
  final IConfigRepository _repo;
  GetModels(this._repo);
  List<ModelConfig> call() => _repo.currentConfig.models;
}
