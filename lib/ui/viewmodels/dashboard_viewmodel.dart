import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';
import 'package:smart_store_linux/core/registry/plugin_registry.dart';
import 'package:smart_store_linux/ui/providers/app_provider.dart';
import 'package:smart_store_linux/ui/providers/inference_provider.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';

/// ViewModel for the Dashboard screen.
///
/// Owns engine start/stop orchestration and stat counting,
/// keeping the view thin and declarative.
class DashboardViewModel extends ChangeNotifier {
  final AppProvider appProvider;
  final RTSPStreamProvider streamProvider;
  final InferenceProvider inferenceProvider;
  final ModelProvider modelProvider;

  DashboardViewModel({
    required this.appProvider,
    required this.streamProvider,
    required this.inferenceProvider,
    required this.modelProvider,
  });

  // Derived stats
  int get cameraCount => streamProvider.streams.length;
  int get modelCount => modelProvider.models.length;
  int get pluginCount => PluginRegistry.plugins.length;
  bool get isEngineRunning => appProvider.isEngineRunning;

  // System stats (delegated to AppProvider)
  Map<String, double> get stats => appProvider.stats;
  String get cpuName => appProvider.cpuName;
  String get gpuName => appProvider.gpuName;
  double get vramUsage => appProvider.vramUsage;
  double get vramTotal => appProvider.vramTotal;
  double get ramTotal => appProvider.ramTotal;
  bool get supportsVRAM => appProvider.supportsVRAM;

  /// Toggle engine on/off, coordinating StreamProcessManager.
  Future<void> toggleEngine() async {
    final shouldRun = !appProvider.isEngineRunning;
    appProvider.toggleEngine();

    if (shouldRun) {
      StreamProcessManager.instance.startAll(
        streamProvider.streams,
        inferenceProvider.streamModelMap,
        modelProvider.models,
      );
    } else {
      await StreamProcessManager.instance.stopAll();
    }
    notifyListeners();
  }
}
