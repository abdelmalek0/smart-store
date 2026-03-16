import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/application/services/app_service.dart';
import 'playback_event.dart';
import 'playback_state.dart';

class PlaybackBloc extends Bloc<PlaybackEvent, PlaybackState> {
  final IConfigRepository _repo;
  StreamSubscription<Set<String>>? _engineStateSub;

  PlaybackBloc({required IConfigRepository repo, AppService? appService})
      : _repo = repo,
        super(const PlaybackState()) {
    on<PlaybackStreamsLoaded>(_onStreamsLoaded);
    on<PlaybackStreamSelected>(_onStreamSelected);
    on<PlaybackFirstAutoSelected>(_onFirstAutoSelected);
    on<PlaybackSidebarToggled>(_onSidebarToggled);
    on<PlaybackEngineStarted>(_onEngineStarted);
    on<PlaybackEngineCleared>(_onEngineCleared);

    // Kick off stream subscription immediately.
    add(const PlaybackStreamsLoaded());

    // Subscribe to engine state changes from AppService.
    // This decouples PlaybackBloc from DashboardBloc (which triggers the engine).
    _engineStateSub = (appService ?? AppService.instance)
        .engineStateStream
        .listen((activeIds) {
      if (activeIds.isEmpty) {
        add(const PlaybackEngineCleared());
      } else {
        add(PlaybackEngineStarted(activeIds));
      }
    });
  }

  Future<void> _onStreamsLoaded(
    PlaybackStreamsLoaded event,
    Emitter<PlaybackState> emit,
  ) async {
    emit(state.copyWith(streams: _repo.currentConfig.streams));

    // Stay in sync with every future config save.
    await emit.forEach<AppConfig>(
      _repo.configStream,
      onData: (cfg) => state.copyWith(streams: cfg.streams),
      onError: (_, _) => state,
    );
  }

  void _onStreamSelected(
    PlaybackStreamSelected event,
    Emitter<PlaybackState> emit,
  ) {
    if (state.selectedStreamId != event.streamId) {
      emit(state.copyWith(selectedStreamId: event.streamId));
    }
  }

  void _onFirstAutoSelected(
    PlaybackFirstAutoSelected event,
    Emitter<PlaybackState> emit,
  ) {
    if (state.selectedStreamId == null) {
      emit(state.copyWith(selectedStreamId: event.streamId));
    }
  }

  void _onSidebarToggled(
    PlaybackSidebarToggled event,
    Emitter<PlaybackState> emit,
  ) {
    emit(state.copyWith(isSidebarOpen: !state.isSidebarOpen));
  }

  void _onEngineStarted(
    PlaybackEngineStarted event,
    Emitter<PlaybackState> emit,
  ) {
    emit(state.copyWith(activePipelineIds: event.activePipelineIds));
  }

  void _onEngineCleared(
    PlaybackEngineCleared event,
    Emitter<PlaybackState> emit,
  ) {
    emit(state.copyWith(activePipelineIds: const {}));
  }

  @override
  Future<void> close() {
    _engineStateSub?.cancel();
    return super.close();
  }
}
