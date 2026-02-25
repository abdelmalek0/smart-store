import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/infrastructure/repositories/config_repository.dart';

/// Service for managing application configuration.
///
/// Acts as a central source of truth for Streams, Plugins, and Models.
/// State reactivity is delegated to BLoCs — this class does NOT extend
/// ChangeNotifier. BLoCs call use cases which in turn call these methods.
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  static ConfigService get instance => _instance;

  ConfigService._internal();

  final ConfigRepository _repository = ConfigRepository();
  AppConfig _config = const AppConfig();

  bool _isInitialized = false;

  // Internal listeners list for components that still need simple callbacks
  // (e.g., BLoCs that need to be notified when config changes in order to
  // re-emit their own state). This is a lightweight alternative to ChangeNotifier.
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Get the current application configuration.
  AppConfig get config => _config;

  Future<void> init() async {
    if (_isInitialized) return;
    _config = await _repository.loadConfig();
    _isInitialized = true;
    _notifyListeners();
  }

  // --- Main Config Updates ---

  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await _repository.saveConfig(_config);
    _notifyListeners();
  }

  // --- Stream Management ---

  List<StreamConfig> get streams => _config.streams;

  Future<void> addStream(StreamConfig stream) async {
    final newStreams = List<StreamConfig>.from(_config.streams)..add(stream);
    await updateConfig(_config.copyWith(streams: newStreams));
  }

  Future<void> removeStream(String streamId) async {
    final newStreams = _config.streams.where((s) => s.id != streamId).toList();
    await updateConfig(_config.copyWith(streams: newStreams));
  }

  Future<void> updateStream(StreamConfig stream) async {
    final index = _config.streams.indexWhere((s) => s.id == stream.id);
    if (index != -1) {
      final newStreams = List<StreamConfig>.from(_config.streams);
      newStreams[index] = stream;
      await updateConfig(_config.copyWith(streams: newStreams));
    }
  }

  StreamConfig? getStream(String streamId) {
    try {
      return _config.streams.firstWhere((s) => s.id == streamId);
    } catch (_) {
      return null;
    }
  }

  // --- Plugin Management ---

  List<PluginConfig> get plugins => _config.plugins;

  Future<void> updatePlugin(PluginConfig plugin) async {
    final index = _config.plugins.indexWhere((p) => p.id == plugin.id);
    List<PluginConfig> newPlugins;
    if (index != -1) {
      newPlugins = List<PluginConfig>.from(_config.plugins);
      newPlugins[index] = plugin;
    } else {
      newPlugins = List<PluginConfig>.from(_config.plugins)..add(plugin);
    }
    await updateConfig(_config.copyWith(plugins: newPlugins));
  }

  PluginConfig? getPlugin(String pluginId) {
    try {
      return _config.plugins.firstWhere((p) => p.id == pluginId);
    } catch (_) {
      return null;
    }
  }

  // --- Model Management ---

  List<ModelConfig> get models => _config.models;

  Future<void> addModel(ModelConfig model) async {
    final newModels = List<ModelConfig>.from(_config.models)..add(model);
    await updateConfig(_config.copyWith(models: newModels));
  }

  Future<void> removeModel(String modelId) async {
    final newModels = _config.models.where((m) => m.id != modelId).toList();
    await updateConfig(_config.copyWith(models: newModels));
  }

  Future<void> updateModel(ModelConfig model) async {
    final index = _config.models.indexWhere((m) => m.id == model.id);
    if (index != -1) {
      final newModels = List<ModelConfig>.from(_config.models);
      newModels[index] = model;
      await updateConfig(_config.copyWith(models: newModels));
    }
  }

  ModelConfig? getModel(String modelId) {
    try {
      return _config.models.firstWhere((m) => m.id == modelId);
    } catch (_) {
      return null;
    }
  }

  // --- Helper for backwards compatibility / ease of use ---

  /// Resolve the model path for a given plugin assignment.
  String? getModelPathForPlugin(String pluginId) {
    final pluginConfig = getPlugin(pluginId);
    if (pluginConfig?.assignedModelId != null) {
      final model = getModel(pluginConfig!.assignedModelId!);
      return model?.path;
    }
    return null;
  }

  /// Resolve effective model path for a stream (based on override or active plugin)
  String? getEffectiveModelPathForStream(String streamId) {
    final stream = getStream(streamId);
    if (stream == null) return null;

    // 1. Check Stream Override
    if (stream.assignedModelId != null) {
      return getModel(stream.assignedModelId!)?.path;
    }

    // 2. Check Plugin Default
    if (stream.activePluginId != null) {
      return getModelPathForPlugin(stream.activePluginId!);
    }
    return null;
  }

  // --- Static Plugin Definitions ---

  List<PluginEntity> get availablePlugins => const [
    PluginEntity(
      id: 'people_counting',
      name: 'People Counting',
      description: 'Initializes YOLO model to count people.',
      iconName: 'people_counting',
      isActive: true,
      defaultConfig: {'personClassId': 0, 'confidenceThreshold': 0.5},
    ),
    PluginEntity(
      id: 'kitchen_supervision',
      name: 'Kitchen Supervision',
      description: 'Detects bare hands (no gloves) for 5 seconds.',
      iconName: 'kitchen_supervision',
      isActive: true,
      defaultConfig: {
        'handClassId': 4,
        'gloveClassId': 0,
        'confidenceThreshold': 0.5,
      },
    ),
  ];
}
