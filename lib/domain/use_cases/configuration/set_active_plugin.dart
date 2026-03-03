import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';

/// Assigns an active plugin to a stream (or clears it by passing null).
class SetActivePlugin {
  final IConfigRepository _repo;
  SetActivePlugin(this._repo);

  Future<void> call(String streamId, String? pluginId) async {
    final stream = _repo.getStream(streamId);
    if (stream != null) {
      await _repo.updateStream(stream.copyWith(activePluginId: pluginId));
    }
  }
}
