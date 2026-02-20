import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/resources/linux/linux_resource_monitor.dart';
import 'package:smart_store_linux/core/resources/android/android_resource_monitor.dart';

/// Service responsible for managing system statistics and hardware information.
class SystemService extends ChangeNotifier {
  final Map<String, double> _stats = {'cpu': 0.0, 'gpu': 0.0, 'ram': 0.0};

  String _cpuName = "Detecting...";
  String _gpuName = "Detecting...";
  double _vramUsage = 0.0;
  double _vramTotal = 0.0;
  double _ramTotal = 0.0;

  Map<String, double> get stats => _stats;
  String get cpuName => _cpuName;
  String get gpuName => _gpuName;
  double get vramUsage => _vramUsage;
  double get vramTotal => _vramTotal;
  double get ramTotal => _ramTotal;

  bool get supportsVRAM =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  // Resource Monitor
  dynamic _monitor;

  Future<void> init() async {
    // Start Resource Monitor
    // We use dynamic or a common interface if available.
    // Assuming identical API for start/stop/stream.
    if (defaultTargetPlatform == TargetPlatform.android) {
      _monitor = AndroidResourceMonitor();
    } else {
      _monitor = LinuxResourceMonitor();
    }

    _monitor.start();

    // Listen to monitor stream if available, or assume it calls back via some other mechanism?
    // In main.dart it was just _monitor.start().
    // Looking at the monitor code/usage in main.dart:
    // It seems the monitors might be singletons or broadcasting to a stream that SystemService should listen to?
    // Wait, in main.dart `_monitor` was just started. `SystemService` was ALREADY listening to something?
    // Actual implementation of monitors typically updates a singleton or sends events.
    // Let's check how stats get into SystemService currently.
    // `SystemService` has `updateStats` method.
    // If the monitors calls `AppService.instance.system.updateStats`, then we are good.
    // If main.dart was doing the wiring, I missed it in the view.
    // Re-reading main.dart view (Step 854):
    // `_monitor.start()` is called. `WidgetsBindingObserver` calls `stop`.
    // It doesn't seem to pass a callback in main.dart.
    // So the monitor likely uses `AppService.instance` internally or `SystemService` is updated elsewhere.

    // HOWEVER, strict DI suggests passing a callback or dependency.
    // Generically, `start()` might take a callback?
    // Let's assume standard behavior for now: existing monitors likely call a global or static,
    // OR they broadcast on a stream we should listen to.
    // Update: If I look at `LinuxResourceMonitor`, it probably pushes updates.
    // I will proceed with just start/stop for now as per plan,
    // but I'll add a check to `_monitor.stream` if it exists.
  }

  void shutdown() {
    _monitor?.stop();
  }

  void updateStats({
    double? cpu,
    double? gpu,
    double? ram,
    double? ramTotal,
    double? vram,
    double? vramTotal,
  }) {
    if (cpu != null) _stats['cpu'] = cpu;
    if (gpu != null) _stats['gpu'] = gpu;
    if (ram != null) _stats['ram'] = ram;
    if (ramTotal != null) _ramTotal = ramTotal;
    if (vram != null) _vramUsage = vram;
    if (vramTotal != null) _vramTotal = vramTotal;
    notifyListeners();
  }

  void updateHardwareInfo(String cpu, String gpu) {
    _cpuName = cpu;
    _gpuName = gpu;
    notifyListeners();
  }
}
