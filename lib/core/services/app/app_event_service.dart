import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/events/event_service.dart';
import 'package:smart_store_linux/core/events/events.dart';

/// Service responsible for exposing application events to the UI.
class AppEventService extends ChangeNotifier {
  // Expose the underlying stream for ViewModels that want to listen directly
  Stream<AppEvent> get stream => EventService.instance.eventStream;

  // Add an event (e.g. from UI testing or manual trigger)
  void add(AppEvent event) {
    EventService.instance.emit(event);
  }
}
