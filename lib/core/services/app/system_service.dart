import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/resources/resource_monitor.dart';
import 'package:smart_store_linux/core/resources/linux/linux_resource_monitor.dart';
import 'package:smart_store_linux/core/resources/android/android_resource_monitor.dart';

/// Service responsible for managing system statistics and hardware information.
///
/// Owns the [ResourceMonitor] lifecycle and wires its callbacks to local state.
/// State reactivity is delegated to BLoCs — this class does NOT extend
/// ChangeNotifier. BLoCs subscribe via [addListener].
class SystemService {
  final Map<String, double> _stats = {'cpu': 0.0, 'gpu': 0.0, 'ram': 0.0};

  String _cpuName = 'Detecting...';
  String _gpuName = 'Detecting...';
  double _vramUsage = 0.0;
  double _vramTotal = 0.0;
  double _ramTotal = 0.0;

  Map<String, double> get stats => Map.unmodifiable(_stats);
  String get cpuName => _cpuName;
  String get gpuName => _gpuName;
  double get vramUsage => _vramUsage;
  double get vramTotal => _vramTotal;
  double get ramTotal => _ramTotal;

  bool get supportsVRAM =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  ResourceMonitor? _monitor;

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

  Future<void> init() async {
    // Select the correct platform implementation
    if (Platform.isAndroid) {
      _monitor = AndroidResourceMonitor();
    } else {
      _monitor = LinuxResourceMonitor();
    }

    // Wire callbacks — monitor pushes, SystemService stores & notifies
    _monitor!.start(
      onStats:
          ({
            double? cpu,
            double? gpu,
            double? ram,
            double? ramTotal,
            double? vram,
            double? vramTotal,
          }) {
            updateStats(
              cpu: cpu,
              gpu: gpu,
              ram: ram,
              ramTotal: ramTotal,
              vram: vram,
              vramTotal: vramTotal,
            );
          },
      onHardware: (cpuName, gpuName) {
        updateHardwareInfo(cpuName, gpuName);
      },
    );
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
    _notifyListeners();
  }

  void updateHardwareInfo(String cpu, String gpu) {
    _cpuName = cpu;
    _gpuName = gpu;
    _notifyListeners();
  }
}
