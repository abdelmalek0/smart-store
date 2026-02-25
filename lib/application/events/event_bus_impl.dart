import 'dart:async';
import 'package:smart_store_linux/application/events/events.dart';

/// Central service for application-wide event broadcasting.
///
/// Decouples event producers (Plugins, System) from consumers (UI).
class EventBusImpl {
  static final EventBusImpl _instance = EventBusImpl._internal();
  static EventBusImpl get instance => _instance;

  EventBusImpl._internal();

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
