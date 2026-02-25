import 'package:equatable/equatable.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Fired once when the Dashboard screen is opened.
class DashboardStarted extends DashboardEvent {
  const DashboardStarted();
}

/// Fired when the user taps the engine toggle button.
class DashboardEngineToggleRequested extends DashboardEvent {
  const DashboardEngineToggleRequested();
}

/// Fired internally when the SystemBloc pushes updated resource stats.
class DashboardSystemStatsUpdated extends DashboardEvent {
  final Map<String, double> stats;
  final String cpuName;
  final String gpuName;
  final double vramUsage;
  final double vramTotal;
  final double ramTotal;

  const DashboardSystemStatsUpdated({
    required this.stats,
    required this.cpuName,
    required this.gpuName,
    required this.vramUsage,
    required this.vramTotal,
    required this.ramTotal,
  });

  @override
  List<Object?> get props => [
    stats,
    cpuName,
    gpuName,
    vramUsage,
    vramTotal,
    ramTotal,
  ];
}

/// Fired when the counts of streams/models/plugins change.
class DashboardConfigUpdated extends DashboardEvent {
  final int cameraCount;
  final int modelCount;
  final int pluginCount;

  const DashboardConfigUpdated({
    required this.cameraCount,
    required this.modelCount,
    required this.pluginCount,
  });

  @override
  List<Object?> get props => [cameraCount, modelCount, pluginCount];
}
