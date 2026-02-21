import 'package:equatable/equatable.dart';

abstract class StreamsEvent extends Equatable {
  const StreamsEvent();

  @override
  List<Object?> get props => [];
}

class StreamsLoaded extends StreamsEvent {
  const StreamsLoaded();
}

class StreamAdded extends StreamsEvent {
  final String name;
  final String url;

  const StreamAdded({required this.name, required this.url});

  @override
  List<Object?> get props => [name, url];
}

class StreamRemoved extends StreamsEvent {
  final String streamId;

  const StreamRemoved(this.streamId);

  @override
  List<Object?> get props => [streamId];
}
