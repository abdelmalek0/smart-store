import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/use_cases/streams/add_stream.dart' as uc;
import 'package:smart_store_linux/domain/use_cases/streams/remove_stream.dart' as uc2;
import 'package:uuid/uuid.dart';
import 'streams_event.dart';
import 'streams_state.dart';

class StreamsBloc extends Bloc<StreamsEvent, StreamsState> {
  final uc.AddStream _addStream;
  final uc2.RemoveStream _removeStream;
  final IConfigRepository _repo;

  StreamsBloc({
    required uc.AddStream addStream,
    required uc2.RemoveStream removeStream,
    required IConfigRepository repo,
  }) : _addStream = addStream,
       _removeStream = removeStream,
       _repo = repo,
       super(const StreamsState()) {
    on<StreamsLoaded>(_onLoaded);
    on<StreamAdded>(_onStreamAdded);
    on<StreamRemoved>(_onStreamRemoved);
  }

  Future<void> _onLoaded(
    StreamsLoaded event,
    Emitter<StreamsState> emit,
  ) async {
    emit(state.copyWith(status: StreamsStatus.success, streams: _repo.currentConfig.streams));

    // Stay in sync with config changes
    await emit.forEach<AppConfig>(
      _repo.configStream,
      onData: (cfg) => state.copyWith(
        status: StreamsStatus.success,
        streams: cfg.streams,
      ),
      onError: (_, _) => state,
    );
  }

  Future<void> _onStreamAdded(
    StreamAdded event,
    Emitter<StreamsState> emit,
  ) async {
    if (event.name.trim().isEmpty || event.url.trim().isEmpty) return;

    final newStream = StreamConfig(
      id: const Uuid().v4(),
      url: event.url.trim(),
      name: event.name.trim(),
    );

    await _addStream(newStream);
    // configStream will fire and update state automatically via _onLoaded listener
  }

  Future<void> _onStreamRemoved(
    StreamRemoved event,
    Emitter<StreamsState> emit,
  ) async {
    await _removeStream(event.streamId);
    // configStream will fire and update state automatically via _onLoaded listener
  }
}
