import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/features/events/event_bus_impl.dart';
import 'package:smart_store_linux/features/events/events.dart';
import 'events_log_event.dart';
import 'events_log_state.dart';

/// Manages the application event log by subscribing to [EventBusImpl].
class EventsLogBloc extends Bloc<EventsLogEvent, EventsLogState> {
  final EventBusImpl _eventService;
  StreamSubscription<AppEvent>? _subscription;

  static const int _maxEvents = 100;

  EventsLogBloc({required EventBusImpl eventService})
    : _eventService = eventService,
      super(const EventsLogState()) {
    on<EventsLogStarted>(_onStarted);
    on<EventsLogEventReceived>(_onEventReceived);
    on<EventsLogCleared>(_onCleared);
    on<EventsLogMockAdded>(_onMockAdded);
  }

  Future<void> _onStarted(
    EventsLogStarted event,
    Emitter<EventsLogState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = _eventService.eventStream.listen((appEvent) {
      add(EventsLogEventReceived(appEvent));
    });
  }

  void _onEventReceived(
    EventsLogEventReceived event,
    Emitter<EventsLogState> emit,
  ) {
    final updated = [event.event, ...state.events];
    if (updated.length > _maxEvents) updated.removeLast();
    emit(state.copyWith(events: updated));
  }

  void _onCleared(EventsLogCleared event, Emitter<EventsLogState> emit) {
    emit(const EventsLogState());
  }

  void _onMockAdded(EventsLogMockAdded event, Emitter<EventsLogState> emit) {
    final data = event.eventData;
    final appEvent = SystemEvent(
      eventId: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      streamId: data['streamId'] ?? 'unknown',
      message: data['data']?['msg'] ?? 'Mock Event',
      severity: EventSeverity.fromString(data['eventType']?.toString()),
      type: data['eventType'] ?? 'system',
    );
    final updated = [appEvent, ...state.events];
    if (updated.length > _maxEvents) updated.removeLast();
    emit(state.copyWith(events: updated));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
