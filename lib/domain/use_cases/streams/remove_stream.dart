import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';

/// Removes a stream from the configuration.
class RemoveStream {
  final IConfigRepository _repo;
  RemoveStream(this._repo);
  Future<void> call(String streamId) => _repo.removeStream(streamId);
}
