import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';

/// Removes an AI model from the configuration.
class RemoveModel {
  final IConfigRepository _repo;
  RemoveModel(this._repo);
  Future<void> call(String modelId) => _repo.removeModel(modelId);
}
