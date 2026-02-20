import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/services/app/system_service.dart';
import 'package:smart_store_linux/core/services/app/engine_service.dart';
import 'package:smart_store_linux/core/services/app/stream_service.dart';
import 'package:smart_store_linux/core/services/app/app_event_service.dart';
import 'package:smart_store_linux/core/services/app/plugin_service.dart';
import 'package:smart_store_linux/core/services/app/model_service.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/core/engine/pipeline_manager.dart';
export 'system_service.dart';
export 'engine_service.dart';
export 'stream_service.dart';
export 'app_event_service.dart';
export 'plugin_service.dart';
export 'model_service.dart';

/// The main application service facade that acts as a mediator
/// between the UI (ViewModels) and the Core Logic.
///
/// It exposes specialized sub-services for different domains.
class AppService extends ChangeNotifier {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  static AppService get instance => _instance;

  final SystemService _system;
  final EngineService _engine;
  final StreamService _streams;
  final AppEventService _events;
  final PluginService _plugins;
  final ModelService _models;

  AppService._internal()
    : _system = SystemService(),
      _engine = EngineService(),
      _streams = StreamService(),
      _events = AppEventService(),
      _plugins = PluginService(),
      _models = ModelService() {
    // Propagate notifications from sub-services to AppService listeners
    // This allows UI to listen to AppService for ANY change, or specific services for specific changes.
    _system.addListener(notifyListeners);
    _engine.addListener(notifyListeners);
    _streams.addListener(notifyListeners);
    _events.addListener(notifyListeners);
    _plugins.addListener(notifyListeners);
    _models.addListener(notifyListeners);
  }

  SystemService get system => _system;
  EngineService get engine => _engine;
  StreamService get streams => _streams;
  AppEventService get events => _events;
  PluginService get plugins => _plugins;
  ModelService get models => _models;

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
    debugPrint("[AppService] Shutting down services...");

    // 1. Stop high-level stream processing logic
    await PipelineManager.instance.clearAll();

    // 2. Stop system monitoring
    _system.shutdown();

    // 3. Shutdown low-level native resources
    NativeInferenceService().shutdown();

    debugPrint("[AppService] Services shutdown complete");
  }

  /// Force exit the application using native C++ exit to bypass any hanging threads.
  void forceExit() {
    NativeInferenceService().forceExit();
  }
}
