import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/plugins/models/plugin_info.dart';
import 'package:smart_store_linux/core/config/models/plugin_config.dart';

/// ViewModel for the Plugins tab.
///
/// Owns plugin config load/save via ConfigService,
/// model selection per plugin, and plugin enable/disable state.
class PluginsViewModel extends ChangeNotifier {
  final AppService _appService;

  PluginsViewModel(this._appService) {
    _appService.plugins.addListener(notifyListeners);
    _appService.models.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _appService.plugins.removeListener(notifyListeners);
    _appService.models.removeListener(notifyListeners);
    super.dispose();
  }

  List<PluginInfo> get plugins => _appService.plugins.all;

  /// Get the currently assigned model path for a plugin
  String? getModelPathForPlugin(String pluginId) {
    final PluginConfig? plugin = _appService.plugins.get(pluginId);
    if (plugin?.assignedModelId != null) {
      return _appService.models.get(plugin!.assignedModelId!)?.path;
    }
    return null;
  }

  /// Assign a model to a plugin
  /// Assign a model to a plugin and set default parameters if needed
  Future<void> setModelForPlugin(String pluginId, String? modelPath) async {
    debugPrint("PluginsViewModel: Setting model for $pluginId to $modelPath");
    PluginConfig? plugin = _appService.plugins.get(pluginId);
    if (plugin == null) {
      debugPrint(
        "PluginsViewModel: Plugin $pluginId not found in config, creating new.",
      );
      plugin = PluginConfig(id: pluginId, enabled: true);
    }

    if (modelPath != null) {
      // Find model by path
      try {
        final model = _appService.models.all.firstWhere(
          (m) => m.path == modelPath,
        );
        debugPrint("PluginsViewModel: Found model ${model.name} (${model.id})");

        var updatedPlugin = plugin.copyWith(assignedModelId: model.id);

        // Set default parameters based on plugin type
        // This logic was previously in the UI (PluginCard)
        final newParams = Map<String, dynamic>.from(updatedPlugin.parameters);
        bool paramsChanged = false;

        if (pluginId == 'people_counting') {
          newParams['personClassId'] = 0;
          newParams['confidenceThreshold'] = 0.5;
          paramsChanged = true;
        } else if (pluginId == 'kitchen_supervision') {
          newParams['handClassId'] = 4; // 'no-gloves'
          newParams['confidenceThreshold'] = 0.5;
          paramsChanged = true;
        }

        if (paramsChanged) {
          updatedPlugin = updatedPlugin.copyWith(parameters: newParams);
          debugPrint(
            "PluginsViewModel: Applied default parameters for $pluginId",
          );
        }

        await _appService.plugins.update(updatedPlugin);
        debugPrint("PluginsViewModel: Plugin updated successfully");
      } catch (e) {
        debugPrint(
          "PluginsViewModel: Could not find model for path $modelPath - $e",
        );
      }
    } else {
      // Clear assignment
      debugPrint("PluginsViewModel: Clearing model assignment for $pluginId");
      await _appService.plugins.update(
        plugin.copyWith(clearAssignedModel: true),
      );
    }
    notifyListeners();
  }
}
