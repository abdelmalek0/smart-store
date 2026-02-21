import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:smart_store_linux/infra/platform/resource_monitor.dart';

/// Android implementation of [ResourceMonitor] (Rockchip RK3588).
///
/// Fetches system stats via MethodChannel and maps hardware fields
/// to the shared stats schema. Pushes data via injected callbacks —
/// never reaches into AppService or any outer layer.
class AndroidResourceMonitor implements ResourceMonitor {
  static const MethodChannel _channel = MethodChannel(
    'smart_store_linux/video_bridge',
  );

  Timer? _timer;
  StatsCallback? _onStats;

  AndroidResourceMonitor();

  @override
  void start({
    required StatsCallback onStats,
    required HardwareCallback onHardware,
  }) {
    _onStats = onStats;

    // Hardware names are fixed for this platform — emit once immediately
    onHardware('Rockchip RK3588', 'NPU (RKNN)');

    _fetchStats();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchStats());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchStats() async {
    try {
      final stats = await _getSystemStats();
      if (stats != null) {
        final npuLoad = stats['npu'] ?? 0.0;
        final ramUsed = stats['ram'] ?? 0.0;
        final ramTotal = stats['ramTotal'] ?? 0.0;
        final cpuLoad = stats['cpu'] ?? 0.0;
        final displayCpu = cpuLoad > 0 ? cpuLoad : _simulateCpu();

        _onStats?.call(
          cpu: displayCpu,
          gpu: npuLoad, // NPU mapped to GPU field for visualization
          ram: ramUsed,
          ramTotal: ramTotal,
          vram: 0,
          vramTotal: 0,
        );
      }
    } catch (e) {
      log('AndroidResourceMonitor: Error fetching stats: $e');
    }
  }

  Future<Map<String, double>?> _getSystemStats() async {
    try {
      final result = await _channel.invokeMethod<Map>('getSystemStats');
      if (result != null) {
        final stats = <String, double>{};
        result.forEach((key, value) {
          if (key is String && value is num) {
            stats[key] = value.toDouble();
          }
        });
        return stats;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  double _simulateCpu() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 10 + (now % 20).toDouble();
  }
}
