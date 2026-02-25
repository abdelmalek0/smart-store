import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

/// Returns the list of all available plugin definitions.
class GetPlugins {
  final ConfigService _configService;

  GetPlugins(this._configService);

  List<PluginEntity> call() => _configService.availablePlugins;
}
