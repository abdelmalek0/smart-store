import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PersistenceService {
  static const String keyAppConfig = 'app_config';

  Future<void> saveConfig(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyAppConfig, jsonEncode(data));
  }

  Future<Map<String, dynamic>> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(keyAppConfig);
    if (jsonString != null) {
      return jsonDecode(jsonString);
    }
    return {};
  }
  
  Future<void> saveKey(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<dynamic> loadKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(key);
    if (jsonString != null) {
      return jsonDecode(jsonString);
    }
    return null;
  }
}
