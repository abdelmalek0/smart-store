import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

/// Adds a new stream to the configuration.
class AddStream {
  final IConfigRepository _repo;
  AddStream(this._repo);
  Future<void> call(StreamConfig stream) => _repo.addStream(stream);
}
