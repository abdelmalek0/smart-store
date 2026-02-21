import 'package:flutter/material.dart';

/// UI-only icon lookup for plugin types.
///
/// Maps plugin IDs to Flutter [IconData].
/// This is the only place in the codebase that maps plugin metadata to icons.
abstract final class PluginCatalog {
  static const Map<String, IconData> _icons = {
    'people_counting': Icons.people_alt_rounded,
    'kitchen_supervision': Icons.restaurant_rounded,
  };

  /// Returns the [IconData] for the given plugin [iconName], or a fallback.
  static IconData iconFor(String iconName) {
    return _icons[iconName] ?? Icons.extension_rounded;
  }
}
