// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelConfig _$ModelConfigFromJson(Map<String, dynamic> json) => ModelConfig(
  id: json['id'] as String,
  path: json['path'] as String,
  name: json['name'] as String,
  labels:
      (json['labels'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(int.parse(k), e as String),
      ) ??
      const {},
);

Map<String, dynamic> _$ModelConfigToJson(ModelConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'path': instance.path,
      'name': instance.name,
      'labels': instance.labels.map((k, e) => MapEntry(k.toString(), e)),
    };
