import 'dart:async';
import 'package:smart_store_linux/core/events/events.dart';

/// Central service for application-wide event broadcasting.
///
/// Decouples event producers (Plugins, System) from consumers (UI).
class EventService {
  static final EventService _instance = EventService._internal();
  static EventService get instance => _instance;

  EventService._internal();

  final StreamController<AppEvent> _eventController =
      StreamController.broadcast();

  /// Stream of all application events
  Stream<AppEvent> get eventStream => _eventController.stream;

  /// Emit a new event to all listeners
  void emit(AppEvent event) {
    _eventController.add(event);
  }

  /// Dispose resources
  void dispose() {
    _eventController.close();
  }
}
