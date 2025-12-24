import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
      if (data is Map && data.containsKey('modelPath')) {
        final modelPath = data['modelPath'];
        if (modelPath != null && modelPath is String) {
          mappings[streamId] = modelPath;
        }
      }
    });

    return mappings;
  }

  String? getModelForStream(String streamId) {
    if (!_config.containsKey('streams')) return null;
    final streams = _config['streams'] as Map<String, dynamic>;
    if (!streams.containsKey(streamId)) return null;
    return streams[streamId]['modelPath'];
  }

  Future<void> setModelForStream(String streamId, String? modelPath) async {
    if (!_config.containsKey('streams')) {
      _config['streams'] = <String, dynamic>{};
    }
    final streams = _config['streams'] as Map<String, dynamic>;

    if (modelPath == null) {
      streams.remove(streamId);
    } else {
      streams[streamId] = {'modelPath': modelPath};
    }

    await _saveConfig();
  }
}
