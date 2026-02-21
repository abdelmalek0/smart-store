import 'package:json_annotation/json_annotation.dart';

part 'plugin_config_dto.g.dart';

/// Data Transfer Object for plugin configuration.
///
/// JSON-serializable. Maps to/from domain types via [PluginMapper].
@JsonSerializable()
class PluginConfigDto {
  final String id;
  final bool enabled;
  final String? assignedModelId;
  final Map<String, dynamic> parameters;

  const PluginConfigDto({
    required this.id,
    this.enabled = true,
    this.assignedModelId,
    this.parameters = const {},
  });

  factory PluginConfigDto.fromJson(Map<String, dynamic> json) =>
      _$PluginConfigDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PluginConfigDtoToJson(this);

  PluginConfigDto copyWith({
    String? id,
    bool? enabled,
    String? assignedModelId,
    Map<String, dynamic>? parameters,
    bool clearAssignedModel = false,
  }) {
    return PluginConfigDto(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      assignedModelId: clearAssignedModel
          ? null
          : (assignedModelId ?? this.assignedModelId),
      parameters: parameters ?? this.parameters,
    );
  }
}
