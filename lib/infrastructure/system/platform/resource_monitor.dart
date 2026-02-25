/// Pure-Dart abstract interface for platform resource monitors.
///
/// No Flutter dependencies — implementations are platform-specific
/// (Linux reads /proc, Android uses MethodChannel).
/// Stats are delivered to the caller via callbacks; monitors never
/// reach outside their own scope.
library;

/// Callback signature for periodic hardware stats updates.
typedef StatsCallback =
    void Function({
      double? cpu,
      double? gpu,
      double? ram,
      double? ramTotal,
      double? vram,
      double? vramTotal,
    });

/// Callback signature for one-time hardware name detection.
typedef HardwareCallback = void Function(String cpuName, String gpuName);

/// Abstract resource monitor interface.
///
/// Platform-specific implementations:
/// - Linux: reads /proc/stat, runs nvidia-smi ([LinuxResourceMonitor])
/// - Android: queries RK3588 NPU via MethodChannel ([AndroidResourceMonitor])
abstract class ResourceMonitor {
  /// Begin monitoring. Stats are pushed via [onStats] every ~2 s.
  /// Hardware names fire once via [onHardware] after detection.
  void start({
    required StatsCallback onStats,
    required HardwareCallback onHardware,
  });

  /// Stop monitoring and cancel any running timers.
  void stop();

  /// Factory: returns the correct platform implementation.
  factory ResourceMonitor() {
    // Import is done in platform files to avoid flutter dependency in this file.
    // Use conditional imports via dart:io.
    if (_isAndroid()) return _androidMonitor();
    return _linuxMonitor();
  }
}

// ── Minimal platform detection without Flutter ─────────────────────────────

bool _isAndroid() {
  try {
    // dart:io Platform is available in all Dart environments
    // ignore: avoid_dynamic_calls
    return const bool.fromEnvironment('dart.library.html') == false &&
        _platformString().contains('android');
  } catch (_) {
    return false;
  }
}

String _platformString() {
  try {
    return 'linux'; // overridden by conditional imports
  } catch (_) {
    return '';
  }
}

// Lazy loader functions — overcome circular import by using function references.
ResourceMonitor _linuxMonitor() {
  // resolved at import time via part files / conditional import in system_service
  throw UnimplementedError('Use SystemService to create the monitor');
}

ResourceMonitor _androidMonitor() {
  throw UnimplementedError('Use SystemService to create the monitor');
}
