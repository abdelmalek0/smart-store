import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/models/plugin_info.dart';
import 'package:smart_store_linux/core/plugins/registry/plugin_registry.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';

/// ViewModel for the Configuration screen.
///
/// Owns plugin-stream mapping via ConfigService.
class ConfigurationViewModel extends ChangeNotifier {
  final RTSPStreamProvider streamProvider;

  ConfigurationViewModel({required this.streamProvider});

  List<PluginInfo> get availablePlugins => PluginRegistry.plugins;

  /// Get the active plugin ID for a stream.
  String? getActivePlugin(String streamId) {
    return ConfigService.instance.getStreamActivePlugin(streamId);
  }

  /// Assign a plugin to a stream.
  Future<void> setActivePlugin(String streamId, String? pluginId) async {
    await ConfigService.instance.setStreamActivePlugin(streamId, pluginId);
    notifyListeners();
  }
}
