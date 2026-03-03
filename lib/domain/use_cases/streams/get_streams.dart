import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

/// Returns all configured streams.
class GetStreams {
  final IConfigRepository _repo;
  GetStreams(this._repo);
  List<StreamConfig> call() => _repo.currentConfig.streams;
}
