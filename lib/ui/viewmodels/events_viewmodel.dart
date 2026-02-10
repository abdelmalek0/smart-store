import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';

/// ViewModel for the Events tab.
///
/// Owns event subscription management and event list state.
class EventsViewModel extends ChangeNotifier {
  final List<Map<String, dynamic>> _events = [];
  final Map<String, StreamSubscription> _subscriptions = {};

  List<Map<String, dynamic>> get events => List.unmodifiable(_events);
  int get eventCount => _events.length;

  EventsViewModel() {
    _updateSubscriptions();
    StreamProcessManager.instance.addListener(_updateSubscriptions);
  }

  void _updateSubscriptions() {
    final processors = StreamProcessManager.instance.processors;

    // Subscribe to new processors
    processors.forEach((streamId, processor) {
      if (!_subscriptions.containsKey(streamId)) {
        _subscriptions[streamId] = processor.eventStream.listen((event) {
          _events.insert(0, event);
          if (_events.length > 100) _events.removeLast();
          notifyListeners();
        });
      }
    });

    // Cleanup removed processors
    final currentIds = processors.keys.toSet();
    final subscribedIds = _subscriptions.keys.toSet();
    final removedIds = subscribedIds.difference(currentIds);

    for (var id in removedIds) {
      _subscriptions[id]?.cancel();
      _subscriptions.remove(id);
    }
  }

  /// Add a single event (used for mock/debug events).
  void addEvent(Map<String, dynamic> event) {
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
    StreamProcessManager.instance.removeListener(_updateSubscriptions);
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
