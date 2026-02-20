import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/engine/pipeline_manager.dart';
import 'package:smart_store_linux/core/rendering/manager/rendering_manager.dart';

/// Service responsible for managing the engine state and pipeline operations.
class EngineService extends ChangeNotifier {
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  RenderingManager get rendering => RenderingManager.instance;

  /// Toggles the engine state and triggers PipelineManager.
  Future<void> toggle() async {
    _isRunning = !_isRunning;
    notifyListeners();

    if (_isRunning) {
      PipelineManager.instance.startAll();
    } else {
      await PipelineManager.instance.stopAll();
    }
  }
}
