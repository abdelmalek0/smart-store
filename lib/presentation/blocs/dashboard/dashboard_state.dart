import 'package:equatable/equatable.dart';

class DashboardState extends Equatable {
  final bool isEngineRunning;
  final Map<String, double> stats;
  final String cpuName;
  final String gpuName;
  final double vramUsage;
  final double vramTotal;
  final double ramTotal;
  final bool supportsVRAM;
  final int cameraCount;
  final int modelCount;
  final int pluginCount;

  const DashboardState({
    this.isEngineRunning = false,
    this.stats = const {'cpu': 0.0, 'gpu': 0.0, 'ram': 0.0},
    this.cpuName = 'Detecting...',
    this.gpuName = 'Detecting...',
    this.vramUsage = 0.0,
    this.vramTotal = 0.0,
    this.ramTotal = 0.0,
    this.supportsVRAM = false,
    this.cameraCount = 0,
    this.modelCount = 0,
    this.pluginCount = 0,
  });

  DashboardState copyWith({
    bool? isEngineRunning,
    Map<String, double>? stats,
    String? cpuName,
    String? gpuName,
    double? vramUsage,
    double? vramTotal,
    double? ramTotal,
    bool? supportsVRAM,
    int? cameraCount,
    int? modelCount,
    int? pluginCount,
  }) {
    return DashboardState(
      isEngineRunning: isEngineRunning ?? this.isEngineRunning,
      stats: stats ?? this.stats,
      cpuName: cpuName ?? this.cpuName,
      gpuName: gpuName ?? this.gpuName,
      vramUsage: vramUsage ?? this.vramUsage,
      vramTotal: vramTotal ?? this.vramTotal,
      ramTotal: ramTotal ?? this.ramTotal,
      supportsVRAM: supportsVRAM ?? this.supportsVRAM,
      cameraCount: cameraCount ?? this.cameraCount,
      modelCount: modelCount ?? this.modelCount,
      pluginCount: pluginCount ?? this.pluginCount,
    );
  }

  @override
  List<Object?> get props => [
    isEngineRunning,
    stats,
    cpuName,
    gpuName,
    vramUsage,
    vramTotal,
    ramTotal,
    supportsVRAM,
    cameraCount,
    modelCount,
    pluginCount,
  ];
}
