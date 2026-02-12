import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/models/plugin_info.dart';
import 'package:smart_store_linux/core/plugins/plugin_registry.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';

/// ViewModel for the Plugins tab.
///
/// Owns plugin config load/save via ConfigService,
/// model selection per plugin, and plugin enable/disable state.
class PluginsViewModel extends ChangeNotifier {
  final ModelProvider modelProvider;

  PluginsViewModel({required this.modelProvider});

  List<PluginInfo> get plugins => PluginRegistry.plugins;

  /// Get the currently assigned model path for a plugin (global config).
  String? getModelPathForPlugin(String pluginId) {
    final config = ConfigService.instance.getGlobalPluginConfig(pluginId);
    if (config != null && config.containsKey('modelPath')) {
      return config['modelPath'] as String?;
    }
    return null;
  }

  /// Assign a model to a plugin globally.
  Future<void> setModelForPlugin(String pluginId, String? modelPath) async {
    if (modelPath != null) {
      final newConfig = <String, dynamic>{'modelPath': modelPath};
      // Preserve existing config entries
      final existing = ConfigService.instance.getGlobalPluginConfig(pluginId);
      if (existing != null) {
        existing['modelPath'] = modelPath;
        await ConfigService.instance.setGlobalPluginConfig(pluginId, existing);
      } else {
        await ConfigService.instance.setGlobalPluginConfig(pluginId, newConfig);
      }
    } else {
      // Clear model
      final existing =
          ConfigService.instance.getGlobalPluginConfig(pluginId) ?? {};
      existing.remove('modelPath');
      await ConfigService.instance.setGlobalPluginConfig(pluginId, existing);
    }
    notifyListeners();
  }
}
