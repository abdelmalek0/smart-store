import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';

/// Returns the current list of configured streams.
class GetStreams {
  final ConfigService _configService;

  GetStreams(this._configService);

  List<StreamConfig> call() => _configService.streams;
}
