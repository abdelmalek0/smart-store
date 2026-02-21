import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:smart_store_linux/domain/use_cases/streams/add_stream.dart'
    as uc;
import 'package:smart_store_linux/domain/use_cases/streams/remove_stream.dart'
    as uc2;
import 'package:uuid/uuid.dart';
import 'streams_event.dart';
import 'streams_state.dart';

class StreamsBloc extends Bloc<StreamsEvent, StreamsState> {
  final uc.AddStream _addStream;
  final uc2.RemoveStream _removeStream;
  final ConfigService _configService;

  StreamsBloc({
    required uc.AddStream addStream,
    required uc2.RemoveStream removeStream,
    required ConfigService configService,
  }) : _addStream = addStream,
       _removeStream = removeStream,
       _configService = configService,
       super(const StreamsState()) {
    on<StreamsLoaded>(_onLoaded);
    on<StreamAdded>(_onStreamAdded);
    on<StreamRemoved>(_onStreamRemoved);

    _configService.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    add(const StreamsLoaded());
  }

  void _onLoaded(StreamsLoaded event, Emitter<StreamsState> emit) {
    emit(
      state.copyWith(
        status: StreamsStatus.success,
        streams: _configService.streams,
      ),
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
    emit(
      state.copyWith(
        status: StreamsStatus.success,
        streams: _configService.streams,
      ),
    );
  }

  Future<void> _onStreamRemoved(
    StreamRemoved event,
    Emitter<StreamsState> emit,
  ) async {
    await _removeStream(event.streamId);
    emit(
      state.copyWith(
        status: StreamsStatus.success,
        streams: _configService.streams,
      ),
    );
  }

  @override
  Future<void> close() {
    _configService.removeListener(_onConfigChanged);
    return super.close();
  }
}
