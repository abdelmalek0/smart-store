import 'package:smart_store_linux/data/dto/stream_config_dto.dart';
import 'package:smart_store_linux/domain/entities/stream_entity.dart';

/// Maps between [StreamConfigDto] (data layer) and [StreamEntity] (domain layer).
class StreamMapper {
  const StreamMapper._();

  static StreamEntity toEntity(StreamConfigDto dto) {
    return StreamEntity(
      id: dto.id,
      url: dto.url,
      name: dto.name,
      enabled: dto.enabled,
      activePluginId: dto.activePluginId,
      assignedModelId: dto.assignedModelId,
    );
  }

  static StreamConfigDto toDto(StreamEntity entity) {
    return StreamConfigDto(
      id: entity.id,
      url: entity.url,
      name: entity.name,
      enabled: entity.enabled,
      activePluginId: entity.activePluginId,
      assignedModelId: entity.assignedModelId,
    );
  }

  static List<StreamEntity> toEntityList(List<StreamConfigDto> dtos) {
    return dtos.map(toEntity).toList();
  }

  static List<StreamConfigDto> toDtoList(List<StreamEntity> entities) {
    return entities.map(toDto).toList();
  }
}
