import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

class PlaybackState extends Equatable {
  final String? selectedStreamId;
  final bool isSidebarOpen;

  /// IDs of streams that have an active pipeline (engine is running).
  final Set<String> activePipelineIds;

  /// Live list of configured streams, kept in sync with [configStream].
  final List<StreamConfig> streams;

  const PlaybackState({
    this.selectedStreamId,
    this.isSidebarOpen = true,
    this.activePipelineIds = const {},
    this.streams = const [],
  });

  PlaybackState copyWith({
    String? selectedStreamId,
    bool? isSidebarOpen,
    bool clearSelectedStream = false,
    Set<String>? activePipelineIds,
    List<StreamConfig>? streams,
  }) {
    return PlaybackState(
      selectedStreamId: clearSelectedStream
          ? null
          : (selectedStreamId ?? this.selectedStreamId),
      isSidebarOpen: isSidebarOpen ?? this.isSidebarOpen,
      activePipelineIds: activePipelineIds ?? this.activePipelineIds,
      streams: streams ?? this.streams,
    );
  }

  bool isPipelineActive(String streamId) => activePipelineIds.contains(streamId);

  @override
  List<Object?> get props => [selectedStreamId, isSidebarOpen, activePipelineIds, streams];
}
