import 'package:smart_store_linux/data/dto/model_config_dto.dart';
import 'package:smart_store_linux/domain/entities/model_entity.dart';

/// Maps between [ModelConfigDto] (data layer) and [ModelEntity] (domain layer).
class ModelMapper {
  const ModelMapper._();

  static ModelEntity toEntity(ModelConfigDto dto) {
    return ModelEntity(
      id: dto.id,
      path: dto.path,
      name: dto.name,
      labels: dto.labels,
    );
  }

  static ModelConfigDto toDto(ModelEntity entity) {
    return ModelConfigDto(
      id: entity.id,
      path: entity.path,
      name: entity.name,
      labels: entity.labels,
    );
  }

  static List<ModelEntity> toEntityList(List<ModelConfigDto> dtos) {
    return dtos.map(toEntity).toList();
  }

  static List<ModelConfigDto> toDtoList(List<ModelEntity> entities) {
    return entities.map(toDto).toList();
  }
}
