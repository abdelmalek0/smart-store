import 'package:json_annotation/json_annotation.dart';

part 'plugin_config.g.dart';

@JsonSerializable()
class PluginConfig {
  final String id;
  final bool enabled;

  /// ID of the model assigned to this plugin (if applicable)
  final String? assignedModelId;

  /// Additional plugin-specific parameters
  final Map<String, dynamic> parameters;

  const PluginConfig({
    required this.id,
    this.enabled = true,
    this.assignedModelId,
    this.parameters = const {},
  });

  factory PluginConfig.fromJson(Map<String, dynamic> json) =>
      _$PluginConfigFromJson(json);

  Map<String, dynamic> toJson() => _$PluginConfigToJson(this);

  PluginConfig copyWith({
    String? id,
    bool? enabled,
    String? assignedModelId,
    Map<String, dynamic>? parameters,
    bool clearAssignedModel = false,
  }) {
    return PluginConfig(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      assignedModelId: clearAssignedModel
          ? null
          : (assignedModelId ?? this.assignedModelId),
      parameters: parameters ?? this.parameters,
    );
  }
}
