import 'dart:async';
import 'dart:io';
import 'dart:developer';

import 'package:smart_store_linux/infra/platform/resource_monitor.dart';

/// Linux implementation of [ResourceMonitor].
///
/// Reads CPU usage from /proc/stat, RAM via `free -m`,
/// and GPU via `nvidia-smi`. Pushes data via injected callbacks —
/// never reaches into AppService or any outer layer.
class LinuxResourceMonitor implements ResourceMonitor {
  Timer? _timer;
  StatsCallback? _onStats;
  HardwareCallback? _onHardware;

  // CPU delta state
  int _prevTotal = 0;
  int _prevIdle = 0;

  LinuxResourceMonitor();

  @override
  void start({
    required StatsCallback onStats,
    required HardwareCallback onHardware,
  }) {
    _onStats = onStats;
    _onHardware = onHardware;

    _fetchHardwareNames();
    _fetchStats(); // Initial fetch
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchStats());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchHardwareNames() async {
    String cpu = 'Unknown CPU';
    String gpu = 'Unknown GPU';

    // Detect CPU from /proc/cpuinfo
    try {
      final result = await Process.run('grep', [
        '-m',
        '1',
        'model name',
        '/proc/cpuinfo',
      ]);
      if (result.exitCode == 0) {
        final parts = result.stdout.toString().split(':');
        if (parts.length > 1) cpu = parts[1].trim();
      }
    } catch (e) {
      log('LinuxResourceMonitor: Error detecting CPU: $e');
    }

    // Detect GPU — try nvidia-smi, fall back to lspci
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=name',
        '--format=csv,noheader',
      ]);
      if (result.exitCode == 0) {
        gpu = result.stdout.toString().trim();
      } else {
        final lspci = await Process.run('lspci', []);
        if (lspci.exitCode == 0) {
          final vga = lspci.stdout
              .toString()
              .split('\n')
              .firstWhere((l) => l.contains('VGA'), orElse: () => '');
          if (vga.isNotEmpty) {
            final idx = vga.indexOf(': ');
            if (idx != -1) gpu = vga.substring(idx + 2).trim();
          }
        }
      }
    } catch (e) {
      log('LinuxResourceMonitor: Error detecting GPU: $e');
    }

    _onHardware?.call(cpu, gpu);
  }

  Future<void> _fetchStats() async {
    double cpuUsage = 0.0;
    double ramUsage = 0.0;
    double ramTotal = 0.0;
    double gpuUsage = 0.0;
    double vramUsage = 0.0;
    double vramTotal = 0.0;

    // CPU via /proc/stat
    try {
      final file = File('/proc/stat');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        if (lines.isNotEmpty) {
          final parts = lines[0].trim().split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            final user = int.tryParse(parts[1]) ?? 0;
            final nice = int.tryParse(parts[2]) ?? 0;
            final system = int.tryParse(parts[3]) ?? 0;
            final idle = int.tryParse(parts[4]) ?? 0;
            final total = user + nice + system + idle;

            if (_prevTotal != 0) {
              final totalDelta = total - _prevTotal;
              final idleDelta = idle - _prevIdle;
              if (totalDelta > 0) {
                cpuUsage = 100.0 * (1.0 - (idleDelta / totalDelta));
              }
            }
            _prevTotal = total;
            _prevIdle = idle;
          }
        }
      }
    } catch (e) {
      log('LinuxResourceMonitor: Error reading CPU: $e');
    }

    // RAM via free -m
    try {
      final result = await Process.run('free', ['-m']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        if (lines.length > 1) {
          final parts = lines[1].trim().split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final total = double.tryParse(parts[1]) ?? 1;
            final used = double.tryParse(parts[2]) ?? 0;
            ramUsage = used / 1024.0;
            ramTotal = total / 1024.0;
          }
        }
      }
    } catch (e) {
      log('LinuxResourceMonitor: Error reading RAM: $e');
    }

    // GPU via nvidia-smi
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=utilization.gpu,memory.used,memory.total',
        '--format=csv,noheader,nounits',
      ]);
      if (result.exitCode == 0) {
        final parts = result.stdout.toString().trim().split(',');
        if (parts.length >= 3) {
          gpuUsage = double.tryParse(parts[0].trim()) ?? 0.0;
          final usedMb = double.tryParse(parts[1].trim()) ?? 0.0;
          final totalMb = double.tryParse(parts[2].trim()) ?? 0.0;
          vramUsage = usedMb / 1024.0;
          vramTotal = totalMb / 1024.0;
        }
      }
    } catch (_) {
      // nvidia-smi may not be present — silently skip
    }

    _onStats?.call(
      cpu: cpuUsage,
      gpu: gpuUsage,
      ram: ramUsage,
      ramTotal: ramTotal,
      vram: vramUsage,
      vramTotal: vramTotal,
    );
  }
}
