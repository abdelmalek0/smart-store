import '../base/app_event.dart';
import '../base/event_severity.dart';

/// Event representing an AI detection (e.g., violation, count)
class DetectionEvent extends AppEvent {
  final String label;
  final double confidence;
  final Map<String, dynamic> metadata;

  DetectionEvent({
    required super.eventId,
    required super.timestamp,
    required super.streamId,
    required this.label,
    required this.confidence,
    this.metadata = const {},
    super.type = 'detection',
    super.severity = EventSeverity.info,
  });

  factory DetectionEvent.fromMap(Map<String, dynamic> map) {
    // Determine severity from map, defaulting to info
    final severityStr = map['severity'] as String?;

    return DetectionEvent(
      eventId:
          map['eventId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      streamId: map['streamId'] ?? 'unknown',
      label: map['data'] != null
          ? map['data']['label'] ?? 'unknown'
          : 'unknown',
      confidence: map['data'] != null
          ? (map['data']['confidence'] ?? 0.0)
          : 0.0,
      metadata: map['data'] ?? {},
      type: map['eventType'] ?? 'detection',
      severity: EventSeverity.fromString(severityStr),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'timestamp': timestamp,
      'streamId': streamId,
      'eventType': type,
      'severity': severity.name,
      'data': {'label': label, 'confidence': confidence, ...metadata},
    };
  }
}
