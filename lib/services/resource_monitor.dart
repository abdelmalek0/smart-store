import 'dart:async';
import 'package:flutter/foundation.dart';

class SystemStats {
  final double cpuUsage;
  final double ramUsage;
  final double gpuUsage;

  SystemStats({this.cpuUsage = 0, this.ramUsage = 0, this.gpuUsage = 0});
}

class ResourceMonitor extends ChangeNotifier {
  SystemStats _stats = SystemStats();
  Timer? _timer;

  SystemStats get stats => _stats;

  void startMonitoring() {
    // In a real app, this would use MethodChannels to call native C++ code
    // to get actual CPU/GPU stats.
    // For this port, we will simulate values.
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Simulate fluctuation
      final now = DateTime.now().millisecondsSinceEpoch;
      _stats = SystemStats(
        cpuUsage: 10 + (now % 20).toDouble(), // 10-30%
        ramUsage: 45 + (now % 5).toDouble(),  // 45-50%
        gpuUsage: 5 + (now % 40).toDouble(),  // 5-45%
      );
      notifyListeners();
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
  }
}
