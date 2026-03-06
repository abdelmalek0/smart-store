import 'package:json_annotation/json_annotation.dart';

part 'stream_config.g.dart';

@JsonSerializable()
class StreamConfig {
  final String id;
  final String url;
  final String name;
  final bool enabled;

  /// ID of the plugin actively processing this stream
  final String? activePluginId;

  const StreamConfig({
    required this.id,
    required this.url,
    this.name = '',
    this.enabled = true,
    this.activePluginId,
  });

  factory StreamConfig.fromJson(Map<String, dynamic> json) =>
      _$StreamConfigFromJson(json);

  Map<String, dynamic> toJson() => _$StreamConfigToJson(this);

  StreamConfig copyWith({
    String? id,
    String? url,
    String? name,
    bool? enabled,
    String? activePluginId,
  }) {
    return StreamConfig(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      activePluginId: activePluginId ?? this.activePluginId,
    );
  }
}
