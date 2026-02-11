import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service for persisting configuration across app restarts
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  static ConfigService get instance => _instance;

  ConfigService._internal();

  Map<String, dynamic> _config = {};
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _loadConfig();
    _isInitialized = true;
  }

  Future<File> get _file async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/smart_store_config.json');
  }

  Future<void> _loadConfig() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        final content = await file.readAsString();
        _config = jsonDecode(content);
      }
    } catch (e) {
      debugPrint("Error loading config: $e");
      _config = {};
    }
  }

  Future<void> _saveConfig() async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(_config));
    } catch (e) {
      debugPrint("Error saving config: $e");
    }
  }

  // --- Specialized Methods ---

  /// Get all stream-to-model mappings
  Map<String, String> getAllStreamMappings() {
    final Map<String, String> mappings = {};
    if (!_config.containsKey('streams')) return mappings;

    final streams = _config['streams'] as Map<String, dynamic>;
    streams.forEach((streamId, data) {
      if (data is Map) {
        // 1. Check Active Plugin config
        final activePluginId = data['activePluginId'] ?? 'people_counting';
        if (data.containsKey('plugins')) {
          final plugins = data['plugins'] as Map<String, dynamic>;
          if (plugins.containsKey(activePluginId)) {
            final pluginConfig =
                plugins[activePluginId] as Map<String, dynamic>;
            if (pluginConfig.containsKey('modelPath')) {
              final path = pluginConfig['modelPath'];
              if (path is String && path.isNotEmpty) {
                mappings[streamId] = path;
                return;
              }
            }
          }
        }

        // 2. Fallback: Legacy stream-level modelPath
        if (data.containsKey('modelPath')) {
          final modelPath = data['modelPath'];
          if (modelPath != null && modelPath is String) {
            mappings[streamId] = modelPath;
          }
        }
      }
    });

    return mappings;
  }

  String? getModelForStream(String streamId) {
    if (!_config.containsKey('streams')) return null;
    final streams = _config['streams'] as Map<String, dynamic>;
    if (!streams.containsKey(streamId)) return null;

    final streamData = streams[streamId] as Map<String, dynamic>;
    final activePluginId = streamData['activePluginId'] ?? 'people_counting';

    // 1. Try Active Plugin Config
    if (streamData.containsKey('plugins')) {
      final plugins = streamData['plugins'] as Map<String, dynamic>;
      if (plugins.containsKey(activePluginId)) {
        final pluginConfig = plugins[activePluginId] as Map<String, dynamic>;
        return pluginConfig['modelPath'] as String?;
      }
    }

    // 2. Fallback: Legacy
    return streamData['modelPath'] as String?;
  }

  Future<void> setModelForStream(String streamId, String? modelPath) async {
    // 1. Get Active Plugin (default to people_counting if not set)
    final currentPlugin = getStreamActivePlugin(streamId) ?? 'people_counting';

    // 2. Get existing config to preserve other settings
    final existingConfig = getPluginConfig(streamId, currentPlugin) ?? {};

    // 3. Update model path
    if (modelPath == null) {
      existingConfig.remove('modelPath');
    } else {
      existingConfig['modelPath'] = modelPath;
    }

    // 4. Save back to plugin config
    await setPluginConfig(streamId, currentPlugin, existingConfig);
  }

  /// Get Global configuration for a plugin
  Map<String, dynamic>? getGlobalPluginConfig(String pluginId) {
    if (!_config.containsKey('plugins')) return null;
    final plugins = _config['plugins'] as Map<String, dynamic>;
    return plugins[pluginId] as Map<String, dynamic>?;
  }

  /// Set Global configuration for a plugin
  Future<void> setGlobalPluginConfig(
    String pluginId,
    Map<String, dynamic> config,
  ) async {
    if (!_config.containsKey('plugins')) {
      _config['plugins'] = <String, dynamic>{};
    }
    final plugins = _config['plugins'] as Map<String, dynamic>;
    plugins[pluginId] = config;
    await _saveConfig();
  }

  /// Set Active Plugin for a stream
  Future<void> setStreamActivePlugin(String streamId, String? pluginId) async {
    if (!_config.containsKey('streams')) {
      _config['streams'] = <String, dynamic>{};
    }
    final streams = _config['streams'] as Map<String, dynamic>;

    // Initialize stream data if needed
    if (!streams.containsKey(streamId)) {
      if (pluginId == null) return; // Nothing to set
      streams[streamId] = <String, dynamic>{};
    }

    final streamData = streams[streamId] as Map<String, dynamic>;

    if (pluginId == null) {
      streamData.remove('activePluginId');
    } else {
      streamData['activePluginId'] = pluginId;
    }

    await _saveConfig();
  }

  /// Get Active Plugin ID for a stream
  String? getStreamActivePlugin(String streamId) {
    if (!_config.containsKey('streams')) return null;
    final streams = _config['streams'] as Map<String, dynamic>;
    if (!streams.containsKey(streamId)) return null;

    final streamData = streams[streamId] as Map<String, dynamic>;
    return streamData['activePluginId'] as String?;
  }

  /// Get configuration for a specific plugin on a stream
  Map<String, dynamic>? getPluginConfig(String streamId, String pluginId) {
    if (!_config.containsKey('streams')) return null;
    final streams = _config['streams'] as Map<String, dynamic>;
    if (!streams.containsKey(streamId)) return null;

    final streamData = streams[streamId] as Map<String, dynamic>;
    if (!streamData.containsKey('plugins')) return null;

    final plugins = streamData['plugins'] as Map<String, dynamic>;
    return plugins[pluginId] as Map<String, dynamic>?;
  }

  /// Set configuration for a plugin
  Future<void> setPluginConfig(
    String streamId,
    String pluginId,
    Map<String, dynamic> config,
  ) async {
    if (!_config.containsKey('streams')) {
      _config['streams'] = <String, dynamic>{};
    }
    final streams = _config['streams'] as Map<String, dynamic>;

    if (!streams.containsKey(streamId)) {
      streams[streamId] = <String, dynamic>{'plugins': <String, dynamic>{}};
    }

    final streamData = streams[streamId] as Map<String, dynamic>;
    if (!streamData.containsKey('plugins')) {
      streamData['plugins'] = <String, dynamic>{};
    }

    final plugins = streamData['plugins'] as Map<String, dynamic>;

    // Merge or overwrite? Overwrite for now.
    plugins[pluginId] = config;

    await _saveConfig();
  }
}
