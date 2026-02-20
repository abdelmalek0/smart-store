import 'package:json_annotation/json_annotation.dart';
import 'stream_config.dart';
import 'plugin_config.dart';
import 'model_config.dart';

part 'app_config.g.dart';

@JsonSerializable(explicitToJson: true)
class AppConfig {
  final List<StreamConfig> streams;
  final List<PluginConfig> plugins;
  final List<ModelConfig> models;

  const AppConfig({
    this.streams = const [],
    this.plugins = const [],
    this.models = const [],
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigToJson(this);

  AppConfig copyWith({
    List<StreamConfig>? streams,
    List<PluginConfig>? plugins,
    List<ModelConfig>? models,
  }) {
    return AppConfig(
      streams: streams ?? this.streams,
      plugins: plugins ?? this.plugins,
      models: models ?? this.models,
    );
  }
}
