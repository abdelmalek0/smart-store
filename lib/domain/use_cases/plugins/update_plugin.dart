import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/plugin_config.dart';

/// Persists an updated [PluginConfig] (model assignment, params, enabled state).
class UpdatePlugin {
  final ConfigService _configService;

  UpdatePlugin(this._configService);

  Future<void> call(PluginConfig plugin) => _configService.updatePlugin(plugin);
}
