// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => AppConfig(
  streams:
      (json['streams'] as List<dynamic>?)
          ?.map((e) => StreamConfig.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  plugins:
      (json['plugins'] as List<dynamic>?)
          ?.map((e) => PluginConfig.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  models:
      (json['models'] as List<dynamic>?)
          ?.map((e) => ModelConfig.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$AppConfigToJson(AppConfig instance) => <String, dynamic>{
  'streams': instance.streams.map((e) => e.toJson()).toList(),
  'plugins': instance.plugins.map((e) => e.toJson()).toList(),
  'models': instance.models.map((e) => e.toJson()).toList(),
};
