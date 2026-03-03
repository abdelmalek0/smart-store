import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/application/services/app_service.dart';
import 'playback_event.dart';
import 'playback_state.dart';

class PlaybackBloc extends Bloc<PlaybackEvent, PlaybackState> {
  StreamSubscription<Set<String>>? _engineStateSub;

  PlaybackBloc({AppService? appService})
      : super(const PlaybackState()) {
    on<PlaybackStreamSelected>(_onStreamSelected);
    on<PlaybackFirstAutoSelected>(_onFirstAutoSelected);
    on<PlaybackSidebarToggled>(_onSidebarToggled);
    on<PlaybackEngineStarted>(_onEngineStarted);
    on<PlaybackEngineCleared>(_onEngineCleared);

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
