import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

/// Abstract contract for plugin management.
abstract class PluginRepository {
  /// Get all available plugin definitions.
  List<PluginEntity> getAvailablePlugins();

  /// Get a plugin entity by its ID, or null if not found.
  PluginEntity? getById(String pluginId);
}
