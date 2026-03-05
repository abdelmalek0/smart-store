import 'dart:async';
import 'dart:io';

import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/infrastructure/repositories/persistence_repository.dart';
import 'package:smart_store_linux/infrastructure/repositories/file_persistence.dart';
import 'package:smart_store_linux/infrastructure/repositories/shared_prefs_persistence.dart';

/// Concrete repository for application configuration.
///
/// Owns the in-memory config cache and broadcasts changes via [configStream],
/// making it the single reactive source of truth (replaces ConfigService).
class ConfigRepository implements IConfigRepository {
  static final ConfigRepository _instance = ConfigRepository._internal();
  factory ConfigRepository() => _instance;
  static ConfigRepository get instance => _instance;

  ConfigRepository._internal() {
    if (Platform.isAndroid || Platform.isIOS) {
      _persistence = SharedPrefsPersistence();
    } else {
      _persistence = FilePersistence();
    }
  }

  late final PersistenceRepository _persistence;

  AppConfig _cache = const AppConfig();
  final StreamController<AppConfig> _controller =
      StreamController<AppConfig>.broadcast();

  // ── IConfigRepository ────────────────────────────────────────────────────

  @override
  Stream<AppConfig> get configStream => _controller.stream;

  @override
  AppConfig get currentConfig => _cache;

  @override
  Future<AppConfig> loadConfig() async {
    _cache = (await _persistence.loadConfig()) ?? const AppConfig();
    _controller.add(_cache);
    return _cache;
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    _cache = config;
    await _persistence.saveConfig(_cache);
    _controller.add(_cache);
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Future<void> addStream(StreamConfig stream) {
    final updated = List<StreamConfig>.from(_cache.streams)..add(stream);
    return saveConfig(_cache.copyWith(streams: updated));
  }

  @override
  Future<void> removeStream(String id) {
    final updated = _cache.streams.where((s) => s.id != id).toList();
    return saveConfig(_cache.copyWith(streams: updated));
  }

  @override
  Future<void> updateStream(StreamConfig stream) {
    final updated = List<StreamConfig>.from(_cache.streams);
    final index = updated.indexWhere((s) => s.id == stream.id);
    if (index != -1) updated[index] = stream;
    return saveConfig(_cache.copyWith(streams: updated));
  }

  @override
  StreamConfig? getStream(String id) {
    try {
      return _cache.streams.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Models ────────────────────────────────────────────────────────────────

  @override
  Future<void> addModel(ModelConfig model) {
    final updated = List<ModelConfig>.from(_cache.models)..add(model);
    return saveConfig(_cache.copyWith(models: updated));
  }

  @override
  Future<void> removeModel(String id) {
    final updated = _cache.models.where((m) => m.id != id).toList();
    return saveConfig(_cache.copyWith(models: updated));
  }

  @override
  Future<void> updateModel(ModelConfig model) {
    final updated = List<ModelConfig>.from(_cache.models);
    final index = updated.indexWhere((m) => m.id == model.id);
    if (index != -1) updated[index] = model;
    return saveConfig(_cache.copyWith(models: updated));
  }

  @override
  ModelConfig? getModel(String id) {
    try {
      return _cache.models.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Plugins ───────────────────────────────────────────────────────────────

  @override
  Future<void> updatePlugin(PluginConfig plugin) {
    final updated = List<PluginConfig>.from(_cache.plugins);
    final index = updated.indexWhere((p) => p.id == plugin.id);
    if (index != -1) {
      updated[index] = plugin;
    } else {
      updated.add(plugin);
    }
    return saveConfig(_cache.copyWith(plugins: updated));
  }

  @override
  PluginConfig? getPlugin(String id) {
    try {
      return _cache.plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  @override
  String? getModelPathForPlugin(String pluginId) {
    final plugin = getPlugin(pluginId);
    if (plugin?.assignedModelId != null) {
      return getModel(plugin!.assignedModelId!)?.path;
    }
    return null;
  }



  /// Dispose the broadcast controller. Call once on app shutdown.
  void dispose() => _controller.close();
}
