import 'package:json_annotation/json_annotation.dart';

part 'model_config_dto.g.dart';

/// Data Transfer Object for AI model configuration.
///
/// JSON-serializable. Maps to/from [ModelEntity] via [ModelMapper].
@JsonSerializable()
class ModelConfigDto {
  final String id;
  final String path;
  final String name;
  final Map<int, String> labels;

  const ModelConfigDto({
    required this.id,
    required this.path,
    required this.name,
    this.labels = const {},
  });

  factory ModelConfigDto.fromJson(Map<String, dynamic> json) =>
      _$ModelConfigDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ModelConfigDtoToJson(this);

  ModelConfigDto copyWith({
    String? id,
    String? path,
    String? name,
    Map<int, String>? labels,
  }) {
    return ModelConfigDto(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      labels: labels ?? this.labels,
    );
  }
}
