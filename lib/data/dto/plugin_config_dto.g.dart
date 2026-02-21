// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plugin_config_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PluginConfigDto _$PluginConfigDtoFromJson(Map<String, dynamic> json) =>
    PluginConfigDto(
      id: json['id'] as String,
      enabled: json['enabled'] as bool? ?? true,
      assignedModelId: json['assignedModelId'] as String?,
      parameters: json['parameters'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$PluginConfigDtoToJson(PluginConfigDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'enabled': instance.enabled,
      'assignedModelId': instance.assignedModelId,
      'parameters': instance.parameters,
    };
