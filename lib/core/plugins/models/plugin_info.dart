/// Metadata for an available plugin.
///
/// Pure Dart — no Flutter dependencies.
class PluginInfo {
  final String id;
  final String name;
  final String description;

  /// Icon name key for UI icon lookup (see `PluginCatalog.iconFor`).
  final String iconName;
  final bool isActive;

  /// Default config values for this plugin type (e.g. classId thresholds)
  final Map<String, dynamic> defaultConfig;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    this.isActive = true,
    this.defaultConfig = const {},
  });
}
