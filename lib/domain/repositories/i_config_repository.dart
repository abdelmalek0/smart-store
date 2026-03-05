import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';

/// Abstract contract for application configuration.
///
/// Acts as the single source of truth for config state:
/// - Reactive via [configStream]
/// - Synchronous access via [currentConfig]
/// - Full CRUD for streams, models, and plugins
abstract class IConfigRepository {
  /// Emits the latest [AppConfig] whenever it changes.
  Stream<AppConfig> get configStream;

  /// The most recently loaded/saved config (synchronous).
  AppConfig get currentConfig;

  /// Load config from the underlying store and seed [configStream].
  Future<AppConfig> loadConfig();

  /// Persist [config] to the underlying store and update [configStream].
  Future<void> saveConfig(AppConfig config);

  // ── Streams ──────────────────────────────────────────────────────────────

  Future<void> addStream(StreamConfig stream);
  Future<void> removeStream(String id);
  Future<void> updateStream(StreamConfig stream);
  StreamConfig? getStream(String id);

  // ── Models ───────────────────────────────────────────────────────────────

  Future<void> addModel(ModelConfig model);
  Future<void> removeModel(String id);
  Future<void> updateModel(ModelConfig model);
  ModelConfig? getModel(String id);

  // ── Plugins ──────────────────────────────────────────────────────────────

  Future<void> updatePlugin(PluginConfig plugin);
  PluginConfig? getPlugin(String id);

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Resolve the model path for a given plugin assignment.
  String? getModelPathForPlugin(String pluginId);
}
