import 'package:equatable/equatable.dart';

class PlaybackState extends Equatable {
  final String? selectedStreamId;
  final bool isSidebarOpen;

  const PlaybackState({this.selectedStreamId, this.isSidebarOpen = true});

  PlaybackState copyWith({
    String? selectedStreamId,
    bool? isSidebarOpen,
    bool clearSelectedStream = false,
  }) {
    return PlaybackState(
      selectedStreamId: clearSelectedStream
          ? null
          : (selectedStreamId ?? this.selectedStreamId),
      isSidebarOpen: isSidebarOpen ?? this.isSidebarOpen,
    );
  }

  @override
  List<Object?> get props => [selectedStreamId, isSidebarOpen];
}
