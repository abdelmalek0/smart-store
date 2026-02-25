import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

/// Returns the current list of configured streams.
class GetStreams {
  final ConfigService _configService;

  GetStreams(this._configService);

  List<StreamConfig> call() => _configService.streams;
}
