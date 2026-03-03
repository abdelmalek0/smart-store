import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/application/services/app_service.dart';
import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final AppService _appService;
  final SystemService _systemService;
  final IConfigRepository _repo;

  DashboardBloc({
    required AppService appService,
    required SystemService systemService,
    required IConfigRepository repo,
  }) : _appService = appService,
       _systemService = systemService,
       _repo = repo,
       super(
         DashboardState(
           supportsVRAM:
               defaultTargetPlatform == TargetPlatform.linux ||
               defaultTargetPlatform == TargetPlatform.windows,
         ),
       ) {
    on<DashboardStarted>(_onStarted);
    on<DashboardEngineToggleRequested>(_onToggleEngine);
    on<DashboardSystemStatsUpdated>(_onSystemStatsUpdated);
    on<DashboardConfigUpdated>(_onConfigUpdated);
  }

  Future<void> _onStarted(
    DashboardStarted event,
    Emitter<DashboardState> emit,
  ) async {
    final config = _repo.currentConfig;
    emit(
      state.copyWith(
        isEngineRunning: _appService.isEngineRunning,
        cameraCount: config.streams.length,
        modelCount: config.models.length,
        pluginCount: config.plugins.length,
        stats: Map<String, double>.from(_systemService.stats),
        cpuName: _systemService.cpuName,
        gpuName: _systemService.gpuName,
        vramUsage: _systemService.vramUsage,
        vramTotal: _systemService.vramTotal,
        ramTotal: _systemService.ramTotal,
      ),
    );

    // Listen to system service changes
    void onSystemUpdate() {
      add(
        DashboardSystemStatsUpdated(
          stats: Map<String, double>.from(_systemService.stats),
          cpuName: _systemService.cpuName,
          gpuName: _systemService.gpuName,
          vramUsage: _systemService.vramUsage,
          vramTotal: _systemService.vramTotal,
          ramTotal: _systemService.ramTotal,
        ),
      );
    }

    _systemService.addListener(onSystemUpdate);

    // React to config changes via configStream
    await emit.forEach<AppConfig>(
      _repo.configStream,
      onData: (cfg) => state.copyWith(
        cameraCount: cfg.streams.length,
        modelCount: cfg.models.length,
        pluginCount: cfg.plugins.length,
      ),
      onError: (_, _) => state,
    );

    _systemService.removeListener(onSystemUpdate);
  }

  Future<void> _onToggleEngine(
    DashboardEngineToggleRequested event,
    Emitter<DashboardState> emit,
  ) async {
    await _appService.toggleEngine();
    emit(state.copyWith(isEngineRunning: _appService.isEngineRunning));
  }

  void _onSystemStatsUpdated(
    DashboardSystemStatsUpdated event,
    Emitter<DashboardState> emit,
  ) {
    emit(
      state.copyWith(
        stats: event.stats,
        cpuName: event.cpuName,
        gpuName: event.gpuName,
        vramUsage: event.vramUsage,
        vramTotal: event.vramTotal,
        ramTotal: event.ramTotal,
      ),
    );
  }

  void _onConfigUpdated(
    DashboardConfigUpdated event,
    Emitter<DashboardState> emit,
  ) {
    emit(
      state.copyWith(
        cameraCount: event.cameraCount,
        modelCount: event.modelCount,
        pluginCount: event.pluginCount,
      ),
    );
  }
}
