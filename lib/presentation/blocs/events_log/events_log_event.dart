import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/features/events/events.dart';

abstract class EventsLogEvent extends Equatable {
  const EventsLogEvent();

  @override
  List<Object?> get props => [];
}

class EventsLogStarted extends EventsLogEvent {
  const EventsLogStarted();
}

class EventsLogEventReceived extends EventsLogEvent {
  final AppEvent event;

  const EventsLogEventReceived(this.event);

  @override
  List<Object?> get props => [event];
}

class EventsLogCleared extends EventsLogEvent {
  const EventsLogCleared();
}

class EventsLogMockAdded extends EventsLogEvent {
  final Map<String, dynamic> eventData;

  const EventsLogMockAdded(this.eventData);

  @override
  List<Object?> get props => [eventData];
}
