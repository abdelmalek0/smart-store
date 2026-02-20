import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:smart_store_linux/core/plugins/models/plugin_info.dart';

/// ViewModel for the Configuration screen.
///
/// Owns plugin-stream mapping via ConfigService.
class ConfigurationViewModel extends ChangeNotifier {
  final AppService _appService;

  ConfigurationViewModel(this._appService) {
    _appService.streams.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _appService.streams.removeListener(notifyListeners);
    super.dispose();
  }

  List<StreamConfig> get streams => ConfigService.instance.streams;

  List<PluginInfo> get availablePlugins =>
      ConfigService.instance.availablePlugins;

  /// Get the active plugin ID for a stream.
  String? getActivePlugin(String streamId) {
    return ConfigService.instance.getStream(streamId)?.activePluginId;
  }

  /// Assign a plugin to a stream.
  Future<void> setActivePlugin(String streamId, String? pluginId) async {
    final stream = ConfigService.instance.getStream(streamId);
    if (stream != null) {
      await ConfigService.instance.updateStream(
        stream.copyWith(activePluginId: pluginId),
      );
      // notifyListeners(); // Not strictly needed as AppService will notify us
    }
  }
}
