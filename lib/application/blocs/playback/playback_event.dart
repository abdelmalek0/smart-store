import 'package:equatable/equatable.dart';

abstract class PlaybackEvent extends Equatable {
  const PlaybackEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched on bloc creation to load streams and keep them in sync.
class PlaybackStreamsLoaded extends PlaybackEvent {
  const PlaybackStreamsLoaded();
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

/// Fired after the engine finishes starting all pipelines.
class PlaybackEngineStarted extends PlaybackEvent {
  /// IDs of streams that now have an active pipeline.
  final Set<String> activePipelineIds;

  const PlaybackEngineStarted(this.activePipelineIds);

  @override
  List<Object?> get props => [activePipelineIds];
}

/// Fired after the engine stops / clears all pipelines.
class PlaybackEngineCleared extends PlaybackEvent {
  const PlaybackEngineCleared();
}
