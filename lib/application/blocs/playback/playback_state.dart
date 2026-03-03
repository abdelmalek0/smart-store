import 'package:equatable/equatable.dart';

class PlaybackState extends Equatable {
  final String? selectedStreamId;
  final bool isSidebarOpen;

  /// IDs of streams that have an active pipeline (engine is running).
  final Set<String> activePipelineIds;

  const PlaybackState({
    this.selectedStreamId,
    this.isSidebarOpen = true,
    this.activePipelineIds = const {},
  });

  PlaybackState copyWith({
    String? selectedStreamId,
    bool? isSidebarOpen,
    bool clearSelectedStream = false,
    Set<String>? activePipelineIds,
  }) {
    return PlaybackState(
      selectedStreamId: clearSelectedStream
          ? null
          : (selectedStreamId ?? this.selectedStreamId),
      isSidebarOpen: isSidebarOpen ?? this.isSidebarOpen,
      activePipelineIds: activePipelineIds ?? this.activePipelineIds,
    );
  }

  bool isPipelineActive(String streamId) => activePipelineIds.contains(streamId);

  @override
  List<Object?> get props => [selectedStreamId, isSidebarOpen, activePipelineIds];
}
