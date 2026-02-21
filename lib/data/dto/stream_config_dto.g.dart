// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_config_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StreamConfigDto _$StreamConfigDtoFromJson(Map<String, dynamic> json) =>
    StreamConfigDto(
      id: json['id'] as String,
      url: json['url'] as String,
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      activePluginId: json['activePluginId'] as String?,
      assignedModelId: json['assignedModelId'] as String?,
    );

Map<String, dynamic> _$StreamConfigDtoToJson(StreamConfigDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'url': instance.url,
      'name': instance.name,
      'enabled': instance.enabled,
      'activePluginId': instance.activePluginId,
      'assignedModelId': instance.assignedModelId,
    };
