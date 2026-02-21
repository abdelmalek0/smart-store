import 'package:smart_store_linux/services/config_service.dart';

/// Removes a stream by its [streamId] from the configuration.
class RemoveStream {
  final ConfigService _configService;

  RemoveStream(this._configService);

  Future<void> call(String streamId) => _configService.removeStream(streamId);
}
