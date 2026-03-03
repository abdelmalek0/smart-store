import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';

/// Updates a plugin's configuration (e.g. assigned model, parameters).
class UpdatePlugin {
  final IConfigRepository _repo;
  UpdatePlugin(this._repo);
  Future<void> call(PluginConfig plugin) => _repo.updatePlugin(plugin);
}
