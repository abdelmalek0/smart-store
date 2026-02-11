import 'package:flutter/material.dart';
import 'package:smart_store_linux/core/models/plugin_info.dart';

/// Central registry of all available plugins.
///
/// Single source of truth — replaces hardcoded lists in
/// [PluginsTab], [ConfigurationScreen], and [StreamProcessor].
class PluginRegistry {
  PluginRegistry._();

  static const List<PluginInfo> plugins = [
    PluginInfo(
      id: 'people_counting',
      name: 'People Counting',
      description: 'Initializes YOLO model to count people.',
      icon: Icons.people_alt_rounded,
      isActive: true,
      defaultConfig: {'personClassId': 0, 'confidenceThreshold': 0.5},
    ),
    PluginInfo(
      id: 'kitchen_supervision',
      name: 'Kitchen Supervision',
      description: 'Detects bare hands (no gloves) for 5 seconds.',
      icon: Icons.restaurant_rounded,
      isActive: true,
      defaultConfig: {
        'handClassId': 4,
        'gloveClassId': 0,
        'confidenceThreshold': 0.5,
      },
    ),
  ];

  /// Find a plugin by its ID, or null if not registered.
  static PluginInfo? findById(String id) {
    try {
      return plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Plugin IDs as a simple list (useful for dropdowns).
  static List<String> get pluginIds => plugins.map((p) => p.id).toList();
}
