import 'package:json_annotation/json_annotation.dart';
import 'package:smart_store_linux/data/dto/stream_config_dto.dart';
import 'package:smart_store_linux/data/dto/model_config_dto.dart';
import 'package:smart_store_linux/data/dto/plugin_config_dto.dart';

part 'app_config_dto.g.dart';

/// Root Data Transfer Object for the entire application configuration.
@JsonSerializable()
class AppConfigDto {
  final List<StreamConfigDto> streams;
  final List<PluginConfigDto> plugins;
  final List<ModelConfigDto> models;

  const AppConfigDto({
    this.streams = const [],
    this.plugins = const [],
    this.models = const [],
  });

  factory AppConfigDto.fromJson(Map<String, dynamic> json) =>
      _$AppConfigDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigDtoToJson(this);

  AppConfigDto copyWith({
    List<StreamConfigDto>? streams,
    List<PluginConfigDto>? plugins,
    List<ModelConfigDto>? models,
  }) {
    return AppConfigDto(
      streams: streams ?? this.streams,
      plugins: plugins ?? this.plugins,
      models: models ?? this.models,
    );
  }
}
