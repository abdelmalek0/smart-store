import 'package:flutter_bloc/flutter_bloc.dart';
import 'playback_event.dart';
import 'playback_state.dart';

class PlaybackBloc extends Bloc<PlaybackEvent, PlaybackState> {
  PlaybackBloc() : super(const PlaybackState()) {
    on<PlaybackStreamSelected>(_onStreamSelected);
    on<PlaybackFirstAutoSelected>(_onFirstAutoSelected);
    on<PlaybackSidebarToggled>(_onSidebarToggled);
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
}
