import 'dart:io';

import 'package:smart_store_linux/core/config/models/app_config.dart';
import 'package:smart_store_linux/data/repositories/persistence_repository.dart';
import 'package:smart_store_linux/data/repositories/file_persistence.dart';
import 'package:smart_store_linux/data/repositories/shared_prefs_persistence.dart';

/// Repository for persisting application configuration.
class ConfigRepository {
  late final PersistenceRepository _persistence;

  ConfigRepository() {
    if (Platform.isAndroid || Platform.isIOS) {
      _persistence = SharedPrefsPersistence();
    } else {
      _persistence = FilePersistence();
    }
  }

  /// Load configuration from disk.
  Future<AppConfig> loadConfig() async {
    final config = await _persistence.loadConfig();
    return config ?? const AppConfig();
  }

  /// Save configuration to disk.
  Future<void> saveConfig(AppConfig config) async {
    await _persistence.saveConfig(config);
  }
}
