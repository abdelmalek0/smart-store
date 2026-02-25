import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/application/events/events.dart';

class EventsLogState extends Equatable {
  final List<AppEvent> events;

  const EventsLogState({this.events = const []});

  EventsLogState copyWith({List<AppEvent>? events}) {
    return EventsLogState(events: events ?? this.events);
  }

  @override
  List<Object?> get props => [events];
}
