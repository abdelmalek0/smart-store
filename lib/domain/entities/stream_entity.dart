import 'package:equatable/equatable.dart';

/// Domain entity representing a camera stream.
///
/// Pure value object — no JSON annotations, no Flutter dependencies.
class StreamEntity extends Equatable {
  final String id;
  final String url;
  final String name;
  final bool enabled;

  /// ID of the plugin actively processing this stream.
  final String? activePluginId;

  /// Optional override model ID (supersedes plugin default).
  final String? assignedModelId;

  const StreamEntity({
    required this.id,
    required this.url,
    this.name = '',
    this.enabled = true,
    this.activePluginId,
    this.assignedModelId,
  });

  StreamEntity copyWith({
    String? id,
    String? url,
    String? name,
    bool? enabled,
    String? activePluginId,
    String? assignedModelId,
    bool clearAssignedModel = false,
    bool clearActivePlugin = false,
  }) {
    return StreamEntity(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      activePluginId: clearActivePlugin
          ? null
          : (activePluginId ?? this.activePluginId),
      assignedModelId: clearAssignedModel
          ? null
          : (assignedModelId ?? this.assignedModelId),
    );
  }

  @override
  List<Object?> get props => [
    id,
    url,
    name,
    enabled,
    activePluginId,
    assignedModelId,
  ];
}
