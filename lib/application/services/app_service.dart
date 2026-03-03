import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/infrastructure/system/system_service.dart';
import 'package:smart_store_linux/application/engine/engine_orchestrator.dart';
import 'package:smart_store_linux/application/engine/pipeline_registry.dart';
import 'package:smart_store_linux/application/events/event_bus_impl.dart';
import 'package:smart_store_linux/application/events/events.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:native_onnx/native_onnx.dart';

export 'package:smart_store_linux/infrastructure/system/system_service.dart';

/// Application lifecycle facade.
///
/// Responsible for initialisation order, engine toggling, and shutdown.
/// Config/model/plugin CRUD is handled directly by BLoCs via IConfigRepository.
class AppService {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  static AppService get instance => _instance;

  final SystemService _system = SystemService();
  late final IConfigRepository _repo;

  bool _isEngineRunning = false;

  /// Broadcasts the set of active pipeline IDs after each engine state change.
  /// Empty set means the engine has stopped.
  final StreamController<Set<String>> _engineStateController =
      StreamController<Set<String>>.broadcast();

  Stream<Set<String>> get engineStateStream => _engineStateController.stream;

  AppService._internal();

  // ── System ──────────────────────────────────────────────────────────────

  SystemService get system => _system;

  // ── Engine ──────────────────────────────────────────────────────────────

  bool get isEngineRunning => _isEngineRunning;

  /// Toggle the inference engine on or off.
  Future<void> toggleEngine() async {
    _isEngineRunning = !_isEngineRunning;

    if (_isEngineRunning) {
      await EngineOrchestrator.instance.startAll(_repo);
      final ids = PipelineRegistry.instance.pipelines
          .map((p) => p.streamId)
          .toSet();
      _engineStateController.add(ids);
    } else {
      await EngineOrchestrator.instance.stopAll();
      _engineStateController.add(const {});
    }
  }

  // ── Events ───────────────────────────────────────────────────────────────

  /// Stream of all application events for BLoCs to subscribe to.
  Stream<AppEvent> get eventStream => EventBusImpl.instance.eventStream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init(IConfigRepository repo) async {
    _repo = repo;

    // 1. Load config into repository cache
    await repo.loadConfig();

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

    await EngineOrchestrator.instance.clearAll();
    _engineStateController.add(const {});
    _system.shutdown();
    NativeInferenceService().shutdown();

    debugPrint('[AppService] Services shutdown complete');
  }

  /// Force exit via native C++ to bypass hanging threads.
  void forceExit() {
    NativeInferenceService().forceExit();
  }
}
