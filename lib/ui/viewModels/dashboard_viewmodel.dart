import 'package:flutter/foundation.dart';

import 'package:smart_store_linux/core/services/app/app_service.dart';

/// ViewModel for the Dashboard screen.
///
/// Owns engine start/stop orchestration and stat counting,
/// keeping the view thin and declarative.
class DashboardViewModel extends ChangeNotifier {
  final AppService _appService;

  DashboardViewModel(this._appService) {
    // Listen to AppService to propagate updates
    _appService.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _appService.removeListener(notifyListeners);
    super.dispose();
  }

  // Derived stats
  int get cameraCount => _appService.streams.all.length;
  int get modelCount => _appService.models.all.length;
  int get pluginCount => _appService.plugins.all.length;

  // Engine State (Delegated to AppService)
  bool get isEngineRunning => _appService.engine.isRunning;

  // System stats (Delegated to AppService)
  Map<String, double> get stats => _appService.system.stats;
  String get cpuName => _appService.system.cpuName;
  String get gpuName => _appService.system.gpuName;
  double get vramUsage => _appService.system.vramUsage;
  double get vramTotal => _appService.system.vramTotal;
  double get ramTotal => _appService.system.ramTotal;
  bool get supportsVRAM => _appService.system.supportsVRAM;

  /// Toggle engine on/off via AppService.
  Future<void> toggleEngine() async {
    await _appService.engine.toggle();
  }
}
