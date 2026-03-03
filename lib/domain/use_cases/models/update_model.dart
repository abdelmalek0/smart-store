import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';

/// Updates an existing AI model in the configuration.
class UpdateModel {
  final IConfigRepository _repo;
  UpdateModel(this._repo);
  Future<void> call(ModelConfig model) => _repo.updateModel(model);
}
