import 'package:equatable/equatable.dart';

abstract class PlaybackEvent extends Equatable {
  const PlaybackEvent();

  @override
  List<Object?> get props => [];
}

class PlaybackStreamSelected extends PlaybackEvent {
  final String streamId;

  const PlaybackStreamSelected(this.streamId);

  @override
  List<Object?> get props => [streamId];
}

class PlaybackFirstAutoSelected extends PlaybackEvent {
  final String streamId;

  const PlaybackFirstAutoSelected(this.streamId);

  @override
  List<Object?> get props => [streamId];
}

class PlaybackSidebarToggled extends PlaybackEvent {
  const PlaybackSidebarToggled();
}
