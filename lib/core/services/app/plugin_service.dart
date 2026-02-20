import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/plugins/models/plugin_info.dart';
import 'package:smart_store_linux/core/config/models/plugin_config.dart';

/// Service responsible for managing plugins.
class PluginService extends ChangeNotifier {
  PluginService() {
    ConfigService.instance.addListener(notifyListeners);
  }

  List<PluginInfo> get all => ConfigService.instance.availablePlugins;

  PluginConfig? get(String pluginId) =>
      ConfigService.instance.getPlugin(pluginId);

  Future<void> update(PluginConfig plugin) async {
    await ConfigService.instance.updatePlugin(plugin);
  }

  @override
  void dispose() {
    ConfigService.instance.removeListener(notifyListeners);
    super.dispose();
  }
}
