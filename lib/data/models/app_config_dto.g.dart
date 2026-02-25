// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfigDto _$AppConfigDtoFromJson(Map<String, dynamic> json) => AppConfigDto(
  streams:
      (json['streams'] as List<dynamic>?)
          ?.map((e) => StreamConfigDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  plugins:
      (json['plugins'] as List<dynamic>?)
          ?.map((e) => PluginConfigDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  models:
      (json['models'] as List<dynamic>?)
          ?.map((e) => ModelConfigDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$AppConfigDtoToJson(AppConfigDto instance) =>
    <String, dynamic>{
      'streams': instance.streams,
      'plugins': instance.plugins,
      'models': instance.models,
    };
