import 'package:json_annotation/json_annotation.dart';

part 'model_config.g.dart';

@JsonSerializable()
class ModelConfig {
  final String id;
  final String path;
  final String name;
  final Map<int, String> labels;

  const ModelConfig({
    required this.id,
    required this.path,
    required this.name,
    this.labels = const {},
  });

  factory ModelConfig.fromJson(Map<String, dynamic> json) =>
      _$ModelConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ModelConfigToJson(this);

  ModelConfig copyWith({
    String? id,
    String? path,
    String? name,
    Map<int, String>? labels,
  }) {
    return ModelConfig(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      labels: labels ?? this.labels,
    );
  }
}
