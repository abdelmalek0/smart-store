import 'package:json_annotation/json_annotation.dart';

part 'stream_config_dto.g.dart';

/// Data Transfer Object for stream configuration.
///
/// JSON-serializable. Maps to/from [StreamEntity] via [StreamMapper].
@JsonSerializable()
class StreamConfigDto {
  final String id;
  final String url;
  final String name;
  final bool enabled;
  final String? activePluginId;
  final String? assignedModelId;

  const StreamConfigDto({
    required this.id,
    required this.url,
    this.name = '',
    this.enabled = true,
    this.activePluginId,
    this.assignedModelId,
  });

  factory StreamConfigDto.fromJson(Map<String, dynamic> json) =>
      _$StreamConfigDtoFromJson(json);

  Map<String, dynamic> toJson() => _$StreamConfigDtoToJson(this);

  StreamConfigDto copyWith({
    String? id,
    String? url,
    String? name,
    bool? enabled,
    String? activePluginId,
    String? assignedModelId,
    bool clearAssignedModel = false,
  }) {
    return StreamConfigDto(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      activePluginId: activePluginId ?? this.activePluginId,
      assignedModelId: clearAssignedModel
          ? null
          : (assignedModelId ?? this.assignedModelId),
    );
  }
}
