import 'package:smart_store_linux/domain/entities/model_entity.dart';

/// Abstract contract for AI model configuration management.
abstract class ModelRepository {
  /// Get all configured models.
  List<ModelEntity> getAll();

  /// Get a model by its ID, or null if not found.
  ModelEntity? getById(String modelId);

  /// Add a new model configuration.
  Future<void> add(ModelEntity model);

  /// Remove a model configuration by ID.
  Future<void> remove(String modelId);

  /// Update an existing model configuration.
  Future<void> update(ModelEntity model);
}
