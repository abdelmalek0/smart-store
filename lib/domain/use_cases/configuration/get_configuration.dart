import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

/// Returns streams list and available plugins for the Configuration screen.
class GetConfiguration {
  final ConfigService _configService;

  GetConfiguration(this._configService);

  ({List<StreamConfig> streams, List<PluginEntity> plugins}) call() => (
    streams: _configService.streams,
    plugins: _configService.availablePlugins,
  );
}
