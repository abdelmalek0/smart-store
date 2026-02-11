import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/events/events.dart';
import 'package:smart_store_linux/core/events/event_service.dart';

/// ViewModel for the Events tab.
///
/// Owns event subscription management and event list state.
class EventsViewModel extends ChangeNotifier {
  final List<AppEvent> _events = [];
  StreamSubscription? _subscription;

  List<AppEvent> get events => List.unmodifiable(_events);
  int get eventCount => _events.length;

  EventsViewModel() {
    _init();
  }

  void _init() {
    _subscription = EventService.instance.eventStream.listen((event) {
      _events.insert(0, event);
      if (_events.length > 100) _events.removeLast();
      notifyListeners();
    });
  }

  /// Add a single event (used for mock/debug events).
  void addEvent(Map<String, dynamic> eventData) {
    // Convert mock map to AppEvent (SystemEvent for simplicity)
    final event = SystemEvent(
      eventId: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp:
          eventData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      streamId: eventData['streamId'] ?? 'unknown',
      message: eventData['data']?['msg'] ?? 'Mock Event',
      severity: EventSeverity.fromString(eventData['eventType']?.toString()),
      type: eventData['eventType'] ?? 'system',
    );

    _events.insert(0, event);
    if (_events.length > 100) _events.removeLast();
    notifyListeners();
  }

  /// Clear all events.
  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
