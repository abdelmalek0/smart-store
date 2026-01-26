import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  final List<Map<String, dynamic>> _events = [];

  // Track subscriptions by streamID
  final Map<String, StreamSubscription> _subscriptions = {};

  @override
  void initState() {
    super.initState();
    // Initial load
    _updateSubscriptions();

    // Listen to StreamManager for new streams
    StreamProcessManager.instance.addListener(_updateSubscriptions);
  }

  @override
  void dispose() {
    StreamProcessManager.instance.removeListener(_updateSubscriptions);
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  void _updateSubscriptions() {
    final processors = StreamProcessManager.instance.processors;

    // Subscribe to new processors
    processors.forEach((streamId, processor) {
      if (!_subscriptions.containsKey(streamId)) {
        _subscriptions[streamId] = processor.eventStream.listen((event) {
          if (mounted) {
            setState(() {
              _events.insert(0, event); // Add to top
              if (_events.length > 100) _events.removeLast();
            });
          }
        });
      }
    });

    // Determine removed processors (Optional cleanup)
    final currentIds = processors.keys.toSet();
    final subscribedIds = _subscriptions.keys.toSet();
    final removedIds = subscribedIds.difference(currentIds);

    for (var id in removedIds) {
      _subscriptions[id]?.cancel();
      _subscriptions.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Latest Events",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _events.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _events.isEmpty
                ? Center(
                    child: Text(
                      "No events yet",
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final timestamp = DateTime.fromMillisecondsSinceEpoch(
                        event['timestamp'],
                      );
                      return Card(
                        color: Colors.grey[900],
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.notifications_active,
                            color: Colors.orangeAccent,
                          ),
                          title: Text(
                            event['eventType'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            "Camera: ${event['streamId'] ?? 'Unknown'}\n${event['data']['msg']}\nTime: ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}",
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
