import 'package:smart_store_linux/application/config/config_service.dart';

/// Assigns an active plugin to a stream (or clears it by passing null).
class SetActivePlugin {
  final ConfigService _configService;

  SetActivePlugin(this._configService);

  Future<void> call(String streamId, String? pluginId) async {
    final stream = _configService.getStream(streamId);
    if (stream != null) {
      await _configService.updateStream(
        stream.copyWith(activePluginId: pluginId),
      );
    }
  }
}
