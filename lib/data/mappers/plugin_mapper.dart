import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

/// Maps between plugin data representations and [PluginEntity] (domain layer).
///
/// Since [PluginEntity] definitions are currently hardcoded in [ConfigService],
/// this mapper is intentionally simple. It will grow if plugin definitions are
/// ever loaded from a data source.
class PluginMapper {
  const PluginMapper._();

  /// Convert a raw map to a [PluginEntity] (e.g. from JSON or DB).
  static PluginEntity fromMap(Map<String, dynamic> map) {
    return PluginEntity(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      iconName: map['iconName'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
      defaultConfig: map['defaultConfig'] as Map<String, dynamic>? ?? const {},
    );
  }
}
