import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/application/services/system_service.dart';
import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';
import 'package:smart_store_linux/application/engine/engine_orchestrator.dart';
import 'package:smart_store_linux/application/events/event_bus_impl.dart';
import 'package:smart_store_linux/application/events/events.dart';
import 'package:native_onnx/native_onnx.dart';

export 'system_service.dart';

/// The main application service facade that acts as a mediator
/// between the UI (BLoCs) and the Core Logic.
///
/// BLoCs subscribe to use-case results rather than listening to this object
/// directly. AppService is a pure service: no ChangeNotifier.
class AppService {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  static AppService get instance => _instance;

  final SystemService _system = SystemService();

  bool _isEngineRunning = false;

  AppService._internal();

  // ── System ──────────────────────────────────────────────────────────────

  SystemService get system => _system;

  // ── Engine ──────────────────────────────────────────────────────────────

  bool get isEngineRunning => _isEngineRunning;

  /// Toggle the inference engine on or off.
  Future<void> toggleEngine() async {
    _isEngineRunning = !_isEngineRunning;

    if (_isEngineRunning) {
      await EngineOrchestrator.instance.startAll();
    } else {
      await EngineOrchestrator.instance.stopAll();
    }
  }

  // ── Streams ─────────────────────────────────────────────────────────────

  List<StreamConfig> get streams => ConfigService.instance.streams;

  Future<void> addStream(StreamConfig stream) =>
      ConfigService.instance.addStream(stream);

  Future<void> removeStream(String streamId) =>
      ConfigService.instance.removeStream(streamId);

  // ── Models ───────────────────────────────────────────────────────────────

  List<ModelConfig> get models => ConfigService.instance.models;

  ModelConfig? getModel(String modelId) =>
      ConfigService.instance.getModel(modelId);

  Future<void> addModel(ModelConfig model) =>
      ConfigService.instance.addModel(model);

  Future<void> removeModel(String modelId) =>
      ConfigService.instance.removeModel(modelId);

  Future<void> updateModel(ModelConfig model) =>
      ConfigService.instance.updateModel(model);

  // ── Plugins ──────────────────────────────────────────────────────────────

  List<PluginEntity> get availablePlugins =>
      ConfigService.instance.availablePlugins;

  PluginConfig? getPlugin(String pluginId) =>
      ConfigService.instance.getPlugin(pluginId);

  Future<void> updatePlugin(PluginConfig plugin) =>
      ConfigService.instance.updatePlugin(plugin);

  // ── Events ───────────────────────────────────────────────────────────────

  /// Stream of all application events for BLoCs to subscribe to.
  Stream<AppEvent> get eventStream => EventBusImpl.instance.eventStream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    // 1. Initialize Config Service
    await ConfigService.instance.init();

    // 2. Initialize System Service (Resource Monitor)
    await _system.init();

    // 3. Initialize Native Inference (Desktop only)
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await NativeInferenceService().init();
    }
  }

  Future<void> shutdown() async {
    debugPrint('[AppService] Shutting down services...');

    // 1. Stop stream processing
    await EngineOrchestrator.instance.clearAll();

    // 2. Stop system monitoring
    _system.shutdown();

    // 3. Shutdown native resources
    NativeInferenceService().shutdown();

    debugPrint('[AppService] Services shutdown complete');
  }

  /// Force exit via native C++ to bypass hanging threads.
  void forceExit() {
    NativeInferenceService().forceExit();
  }
}
