import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

enum StreamsStatus { initial, loading, success, failure }

class StreamsState extends Equatable {
  final StreamsStatus status;
  final List<StreamConfig> streams;
  final String? errorMessage;

  const StreamsState({
    this.status = StreamsStatus.initial,
    this.streams = const [],
    this.errorMessage,
  });

  StreamsState copyWith({
    StreamsStatus? status,
    List<StreamConfig>? streams,
    String? errorMessage,
  }) {
    return StreamsState(
      status: status ?? this.status,
      streams: streams ?? this.streams,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, streams, errorMessage];
}
