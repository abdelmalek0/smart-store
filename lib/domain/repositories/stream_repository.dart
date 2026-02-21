import 'package:smart_store_linux/domain/entities/stream_entity.dart';

/// Abstract contract for stream configuration management.
abstract class StreamRepository {
  /// Get all configured streams.
  List<StreamEntity> getAll();

  /// Get a stream by its ID, or null if not found.
  StreamEntity? getById(String streamId);

  /// Add a new stream configuration.
  Future<void> add(StreamEntity stream);

  /// Remove a stream configuration by ID.
  Future<void> remove(String streamId);

  /// Update an existing stream configuration.
  Future<void> update(StreamEntity stream);
}
