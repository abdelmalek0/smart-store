import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class AppProvider extends ChangeNotifier {
  bool _isEngineRunning = false;
  bool _isSidebarExpanded = false;
  Map<String, double> _stats = {'cpu': 0.0, 'gpu': 0.0, 'ram': 0.0};

  String _cpuName = "Detecting...";
  String _gpuName = "Detecting...";
  double _vramUsage = 0.0; // GB
  double _vramTotal = 0.0; // GB
  double _ramTotal = 0.0; // GB

  bool get isEngineRunning => _isEngineRunning;
  bool get isSidebarExpanded => _isSidebarExpanded;
  Map<String, double> get stats => _stats;
  String get cpuName => _cpuName;
  String get gpuName => _gpuName;
  double get vramUsage => _vramUsage;
  double get vramTotal => _vramTotal;
  double get ramTotal => _ramTotal;

  bool get supportsVRAM =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  void toggleEngine() {
    _isEngineRunning = !_isEngineRunning;
    notifyListeners();
  }

  void toggleSidebar() {
    _isSidebarExpanded = !_isSidebarExpanded;
    notifyListeners();
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
