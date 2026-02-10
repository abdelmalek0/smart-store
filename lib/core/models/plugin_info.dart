import 'package:flutter/material.dart';

/// Metadata for an available plugin
class PluginInfo {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool isActive;

  /// Default config values for this plugin type (e.g. classId thresholds)
  final Map<String, dynamic> defaultConfig;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.isActive = true,
    this.defaultConfig = const {},
  });
}
