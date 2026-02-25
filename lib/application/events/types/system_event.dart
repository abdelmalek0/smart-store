import '../base/app_event.dart';
import '../base/event_severity.dart';

/// Event representing a system status update
class SystemEvent extends AppEvent {
  final String message;

  SystemEvent({
    required super.eventId,
    required super.timestamp,
    required super.streamId,
    required this.message,
    super.severity = EventSeverity.info, // Mapped from old 'level'
    super.type = 'system',
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'timestamp': timestamp,
      'streamId': streamId,
      'eventType': type,
      'message': message,
      'severity': severity.name,
    };
  }
}
