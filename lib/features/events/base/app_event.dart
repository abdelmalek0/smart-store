import 'event_severity.dart';

/// Base class for all application events
abstract class AppEvent {
  final String eventId;
  final int timestamp;
  final String streamId;
  final String type;
  final EventSeverity severity;

  AppEvent({
    required this.eventId,
    required this.timestamp,
    required this.streamId,
    required this.type,
    this.severity = EventSeverity.info,
  });

  Map<String, dynamic> toMap();
}
