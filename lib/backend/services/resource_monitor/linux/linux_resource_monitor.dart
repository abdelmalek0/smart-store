import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/ui/providers/app_provider.dart';

class LinuxResourceMonitor {
  final AppProvider _provider;
  Timer? _timer;

  // Cache for CPU calculation
  int _prevTotal = 0;
  int _prevIdle = 0;

  LinuxResourceMonitor(this._provider);

  void start() {
    _fetchHardwareNames();
    _fetchStats(); // Initial fetch
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchStats());
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _fetchHardwareNames() async {
    String cpu = "Unknown CPU";
    String gpu = "Unknown GPU";

    // Detect CPU
    try {
      final result = await Process.run('grep', [
        '-m',
        '1',
        'model name',
        '/proc/cpuinfo',
      ]);
      if (result.exitCode == 0) {
        // Output: model name : Intel(R) Core(TM) ...
        final parts = result.stdout.toString().split(':');
        if (parts.length > 1) {
          cpu = parts[1].trim();
        }
      }
    } catch (e) {
      debugPrint("Error detecting CPU: $e");
    }

    // Detect GPU (Nvidia)
    try {
      // Try nvidia-smi first
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=name',
        '--format=csv,noheader',
      ]);
      if (result.exitCode == 0) {
        gpu = result.stdout.toString().trim();
      } else {
        // Fallback to lspci
        final lspci = await Process.run('lspci', []);
        if (lspci.exitCode == 0) {
          final lines = lspci.stdout.toString().split('\n');
          final vga = lines.firstWhere(
            (l) => l.contains('VGA'),
            orElse: () => "",
          );
          if (vga.isNotEmpty) {
            // 01:00.0 VGA compatible controller: NVIDIA Corporation ...
            final index = vga.indexOf(': ');
            if (index != -1) {
              gpu = vga.substring(index + 2).trim();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error detecting GPU: $e");
    }

    _provider.updateHardwareInfo(cpu, gpu);
  }

  Future<void> _fetchStats() async {
    double cpuUsage = 0.0;
    double ramUsage = 0.0;
    double ramTotal = 0.0;
    double gpuUsage = 0.0;
    double vramUsage = 0.0;
    double vramTotal = 0.0;

    // CPU Usage via /proc/stat
    try {
      final file = File('/proc/stat');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        if (lines.isNotEmpty) {
          // cpu  2255 34 2290 22625563 ...
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
      debugPrint("Error reading CPU stats: $e");
    }

    // RAM Usage via free -m
    try {
      final result = await Process.run('free', ['-m']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        // Mem: Total Used Free ...
        if (lines.length > 1) {
          final parts = lines[1].trim().split(RegExp(r'\s+'));
          // parts[0]="Mem:", parts[1]=Total, parts[2]=Used
          if (parts.length >= 3) {
            final total = double.tryParse(parts[1]) ?? 1;
            final used = double.tryParse(parts[2]) ?? 0;
            ramUsage = used / 1024.0; // Convert MB to GB
            ramTotal = total / 1024.0;
          }
        }
      }
    } catch (e) {
      debugPrint("Error reading RAM stats: $e");
    }

    // GPU Stats via nvidia-smi
    try {
      // utilization.gpu, memory.used, memory.total
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
    } catch (e) {
      // GPU monitor might fail if nvidia-smi not present
    }

    _provider.updateStats(
      cpu: cpuUsage,
      ram: ramUsage,
      ramTotal: ramTotal,
      gpu: gpuUsage,
      vram: vramUsage,
      vramTotal: vramTotal,
    );
  }
}
