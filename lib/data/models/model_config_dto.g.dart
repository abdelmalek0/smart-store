// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_config_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelConfigDto _$ModelConfigDtoFromJson(Map<String, dynamic> json) =>
    ModelConfigDto(
      id: json['id'] as String,
      path: json['path'] as String,
      name: json['name'] as String,
      labels:
          (json['labels'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(int.parse(k), e as String),
          ) ??
          const {},
    );

Map<String, dynamic> _$ModelConfigDtoToJson(ModelConfigDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'path': instance.path,
      'name': instance.name,
      'labels': instance.labels.map((k, e) => MapEntry(k.toString(), e)),
    };
