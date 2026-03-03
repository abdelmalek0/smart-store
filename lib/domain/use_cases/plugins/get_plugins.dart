import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

/// Returns the list of available (static) plugins.
class GetPlugins {
  const GetPlugins();
  List<PluginEntity> call() => kAvailablePlugins;
}
