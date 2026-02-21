import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/services/app_service.dart';
import 'package:smart_store_linux/domain/use_cases/engine/toggle_engine.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final ToggleEngine _toggleEngine;
  final AppService _appService;
  final SystemService _systemService;
  StreamSubscription<void>? _configSub;

  DashboardBloc({
    required ToggleEngine toggleEngine,
    required AppService appService,
    required SystemService systemService,
  }) : _toggleEngine = toggleEngine,
       _appService = appService,
       _systemService = systemService,
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
    // Emit initial counts from config
    emit(
      state.copyWith(
        isEngineRunning: _appService.isEngineRunning,
        cameraCount: ConfigService.instance.streams.length,
        modelCount: ConfigService.instance.models.length,
        pluginCount: ConfigService.instance.availablePlugins.length,
        stats: Map<String, double>.from(_systemService.stats),
        cpuName: _systemService.cpuName,
        gpuName: _systemService.gpuName,
        vramUsage: _systemService.vramUsage,
        vramTotal: _systemService.vramTotal,
        ramTotal: _systemService.ramTotal,
      ),
    );

    // Listen to system service changes via stream
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

    void onConfigUpdate() {
      add(
        DashboardConfigUpdated(
          cameraCount: ConfigService.instance.streams.length,
          modelCount: ConfigService.instance.models.length,
          pluginCount: ConfigService.instance.availablePlugins.length,
        ),
      );
    }

    _systemService.addListener(onSystemUpdate);
    ConfigService.instance.addListener(onConfigUpdate);

    await emit.onEach(
      Stream<void>.periodic(
        const Duration(seconds: 1),
      ).take(0).asBroadcastStream(),
      onData: (_) {},
      onError: (_, _) {},
    );

    // Keep listeners alive — cleaned up in close()
    _configSub = Stream<void>.empty().listen((_) {});
  }

  Future<void> _onToggleEngine(
    DashboardEngineToggleRequested event,
    Emitter<DashboardState> emit,
  ) async {
    await _toggleEngine();
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

  @override
  Future<void> close() {
    _configSub?.cancel();
    return super.close();
  }
}
