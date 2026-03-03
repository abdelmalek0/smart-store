import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';

/// Adds a new AI model to the configuration.
class AddModel {
  final IConfigRepository _repo;
  AddModel(this._repo);
  Future<void> call(ModelConfig model) => _repo.addModel(model);
}
