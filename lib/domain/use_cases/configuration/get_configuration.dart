import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

/// Returns streams list and available plugins for the Configuration screen.
class GetConfiguration {
  final IConfigRepository _repo;
  GetConfiguration(this._repo);

  ({List<StreamConfig> streams, List<PluginEntity> plugins}) call() => (
    streams: _repo.currentConfig.streams,
    plugins: kAvailablePlugins,
  );
}
