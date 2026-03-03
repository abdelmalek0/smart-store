import 'package:equatable/equatable.dart';

/// Domain entity representing an available plugin definition.
///
/// This replaces [PluginInfo] from the old core layer. It describes a plugin
/// that is available in the system catalog — not a user-specific configuration.
class PluginEntity extends Equatable {
  final String id;
  final String name;
  final String description;

  /// Icon name key for UI icon lookup.
  final String iconName;
  final bool isActive;

  /// Default config values for this plugin type (e.g. classId thresholds).
  final Map<String, dynamic> defaultConfig;

  const PluginEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    this.isActive = true,
    this.defaultConfig = const {},
  });

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    iconName,
    isActive,
    defaultConfig,
  ];
}

/// Static catalogue of all built-in plugins available in the system.
///
/// This is domain knowledge — it never changes at runtime and has no external
/// dependencies. Move here from ConfigService.availablePlugins.
const List<PluginEntity> kAvailablePlugins = [
  PluginEntity(
    id: 'people_counting',
    name: 'People Counting',
    description: 'Initializes YOLO model to count people.',
    iconName: 'people_counting',
    isActive: true,
    defaultConfig: {'personClassId': 0, 'confidenceThreshold': 0.5},
  ),
  PluginEntity(
    id: 'kitchen_supervision',
    name: 'Kitchen Supervision',
    description: 'Detects bare hands (no gloves) for 5 seconds.',
    iconName: 'kitchen_supervision',
    isActive: true,
    defaultConfig: {
      'handClassId': 4,
      'gloveClassId': 0,
      'confidenceThreshold': 0.5,
    },
  ),
];
