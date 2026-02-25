import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

/// Adds a new stream to the configuration.
class AddStream {
  final ConfigService _configService;

  AddStream(this._configService);

  Future<void> call(StreamConfig stream) => _configService.addStream(stream);
}
