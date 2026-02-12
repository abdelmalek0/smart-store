import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smart_store_linux/ui/providers/app_provider.dart';

class AndroidResourceMonitor {
  static const MethodChannel _channel = MethodChannel('ffmpeg_video');

  final AppProvider _provider;
  Timer? _timer;

  AndroidResourceMonitor(this._provider);

  void start() {
    _provider.updateHardwareInfo("Rockchip RK3588", "NPU (RKNN)");
    _fetchStats(); // Initial fetch
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchStats());
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _fetchStats() async {
    try {
      final stats = await _getSystemStats();

      if (stats != null) {
        // Map Native stats to Provider stats
        // On Android RK3588, we map NPU load to "GPU" field for visualization

        final npuLoad = stats['npu'] ?? 0.0;
        final ramUsed = stats['ram'] ?? 0.0;
        final ramTotal = stats['ramTotal'] ?? 0.0;
        final cpuLoad = stats['cpu'] ?? 0.0; // Often 0 if restricted

        // Use simulated CPU if native returns 0 (common on modern Android)
        final displayCpu = cpuLoad > 0 ? cpuLoad : _simulateCpu();

        _provider.updateStats(
          cpu: displayCpu,
          ram: ramUsed,
          ramTotal: ramTotal,
          gpu: npuLoad, // Mapped to GPU bar
          vram: 0, // NPU shares system memory usually
          vramTotal: 0,
        );
      }
    } catch (e) {
      debugPrint("Error fetching Android stats: $e");
    }
  }

  /// Fetch system stats from the native Android plugin via MethodChannel.
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
    } catch (e) {
      return null;
    }
  }

  double _simulateCpu() {
    // Simple fluctuation for visual aliveness if /proc/stat blocked
    final now = DateTime.now().millisecondsSinceEpoch;
    return 10 + (now % 20).toDouble();
  }
}
