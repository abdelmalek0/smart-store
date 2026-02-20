import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_store_linux/core/config/models/app_config.dart';
import 'package:smart_store_linux/data/repositories/persistence_repository.dart';

/// Persistence implementation using local JSON file (Linux/Desktop).
class FilePersistence implements PersistenceRepository {
  static const String _fileName = 'smart_store_config.json';

  Future<File> get _file async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    try {
      final file = await _file;
      final json = jsonEncode(config.toJson());
      debugPrint("FilePersistence: Saving config to ${file.path}");
      debugPrint("FilePersistence: Content length: ${json.length}");
      await file.writeAsString(json);
      debugPrint("FilePersistence: Config saved successfully.");
    } catch (e) {
      debugPrint("FilePersistence: Error saving config: $e");
    }
  }

  @override
  Future<AppConfig?> loadConfig() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content);

        // Usage of Map<String, dynamic> here avoids the "type cast" error
        // occurring inside AppConfig.fromJson
        if (json is Map<String, dynamic>) {
          _migrateConfig(json);
          return AppConfig.fromJson(json);
        }
      }
    } catch (e) {
      debugPrint("FilePersistence: Error loading config: $e");
    }
    return null;
  }

  /// Migrates legacy config format (Maps) to new format (Lists).
  /// Injects the map key as the 'id' field if missing.
  /// Also extracts embedded 'modelPath' from streams/plugins into 'models'.
  void _migrateConfig(Map<String, dynamic> json) {
    // 1. Convert Maps to Lists (Filtering Invalid Items)
    _migrateCollection(json, 'streams', (item) {
      // StreamConfig requirements
      // We only accept streams with a valid URL
      if (item['url'] == null || (item['url'] as String).isEmpty) {
        return false; // Reject
      }
      item.putIfAbsent('name', () => 'Stream ${item['id']}');
      return true; // Accept
    });

    _migrateCollection(json, 'plugins');

    _migrateCollection(json, 'models', (item) {
      // ModelConfig requirements
      // We only accept models with a valid Path
      if (item['path'] == null || (item['path'] as String).isEmpty) {
        return false; // Reject
      }
      item.putIfAbsent('name', () => 'Model ${item['id']}');
      return true; // Accept
    });

    // 2. Ensure models list exists
    if (!json.containsKey('models') || json['models'] == null) {
      json['models'] = [];
    }
    // Use 'as List' to handle List<dynamic> (from jsonDecode) or List<Map>
    final modelsList = json['models'] as List;

    // Helper to find or create model
    String? getOrCreateModel(String path, String? nameHint) {
      if (path.isEmpty) return null;

      // Check if model already exists
      try {
        final existing = modelsList.firstWhere((m) => m['path'] == path);
        return existing['id'] as String;
      } catch (_) {
        // Create new model
        final newId =
            'model_${modelsList.length + 1}_${DateTime.now().millisecondsSinceEpoch}';
        final newName = nameHint ?? 'Imported Model ${modelsList.length + 1}';
        modelsList.add({
          'id': newId,
          'path': path,
          'name': newName,
          'labels': <String, dynamic>{}, // Empty labels map
        });
        debugPrint("FilePersistence: Extracted legacy model '$path' -> $newId");
        return newId;
      }
    }

    // 3. Extract models from Streams
    if (json['streams'] is List) {
      final streams = json['streams'] as List;
      for (var item in streams) {
        if (item is Map<String, dynamic> && item.containsKey('modelPath')) {
          final path = item['modelPath'] as String;
          if (path.isNotEmpty) {
            final modelId = getOrCreateModel(path, 'Model for ${item['name']}');
            if (modelId != null) {
              item['assignedModelId'] = modelId;
            }
          }
          // Remove legacy field
          item.remove('modelPath');
        }
      }
    }

    // 4. Extract models from Plugins
    if (json['plugins'] is List) {
      final plugins = json['plugins'] as List;
      for (var item in plugins) {
        if (item is Map<String, dynamic> && item.containsKey('modelPath')) {
          final path = item['modelPath'] as String;
          if (path.isNotEmpty) {
            final modelId = getOrCreateModel(path, 'Model for ${item['id']}');
            if (modelId != null) {
              item['assignedModelId'] = modelId;
            }
          }
          // Remove legacy field
          item.remove('modelPath');
        }
      }
    }
  }

  void _migrateCollection(
    Map<String, dynamic> json,
    String key, [
    bool Function(Map<String, dynamic>)? validateAndEnrich,
  ]) {
    if (json[key] is Map) {
      final map = json[key] as Map;
      final list = <Map<String, dynamic>>[];

      map.forEach((id, value) {
        if (value is Map<String, dynamic>) {
          // Inject ID if it's missing or if we are converting from Map
          // We prioritize the key as the ID.
          final item = Map<String, dynamic>.from(value);
          item['id'] = id.toString();

          // Apply validation/enrichment
          bool isValid = true;
          if (validateAndEnrich != null) {
            isValid = validateAndEnrich(item);
          }

          if (isValid) {
            list.add(item);
          } else {
            debugPrint(
              "FilePersistence: Skipped invalid item in '$key' (ID: $id)",
            );
          }
        }
      });

      json[key] = list;
      debugPrint(
        "FilePersistence: Migrated '$key' from Map to List (Count: ${list.length}).",
      );
    }
  }
}
