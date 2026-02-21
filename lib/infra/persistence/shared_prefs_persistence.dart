import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_store_linux/core/config/models/app_config.dart';
import 'package:smart_store_linux/data/repositories/persistence_repository.dart';

/// Persistence implementation using SharedPreferences (Android/iOS).
class SharedPrefsPersistence implements PersistenceRepository {
  static const String _keyAppConfig = 'app_config';

  @override
  Future<void> saveConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppConfig, jsonEncode(config.toJson()));
  }

  @override
  Future<AppConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyAppConfig);
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString);
        return AppConfig.fromJson(json);
      } catch (e) {
        // Fallback or log error
        return null;
      }
    }
    return null;
  }
}
