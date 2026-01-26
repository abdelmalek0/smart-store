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
      color: const Color(0xFF111722), // Updated dark background
      child: Column(
        children: [
          // Optional Header or just padding
          const SizedBox(height: 16),

          Expanded(
            child: _events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 48,
                          color: Colors.grey[700],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No recent alerts",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        TextButton(
                          onPressed: () {
                            // Mock Event Generation for Testing
                            _addMockEvent();
                          },
                          child: const Text("Add Test Event (Debug)"),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      // Resolve Camera Name from StreamManager
                      final streamId = event['streamId']?.toString() ?? '';
                      final processor = StreamProcessManager.instance
                          .getProcessor(streamId);
                      final streamName = processor?.stream.name ?? streamId;

                      return EventCard(event: event, streamName: streamName);
                    },
                  ),
          ),

          // clear button (temporary or persistence needed?)
          if (_events.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _events.clear()),
                    child: const Text(
                      "Clear All",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),

          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: TextButton(
              onPressed: () {
                // View history logic
              },
              child: const Text(
                "View Alert History",
                style: TextStyle(
                  color: Color(0xFF94A3B8), // Slate-400
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addMockEvent() {
    setState(() {
      final now = DateTime.now().millisecondsSinceEpoch;
      final types = ['CRITICAL', 'WARNING', 'INFO'];
      final type = types[now % 3];

      String msg = "Something happened";
      if (type == 'CRITICAL')
        msg = "Queue limit exceeded\nCheckout 3 queue time > 5 mins.";
      if (type == 'WARNING')
        msg = "Low Staff Presence\nElectronics zone staff ratio below 1:5.";
      if (type == 'INFO')
        msg = "Restock Required\nEmpty shelf detected in Aisle 4.";

      _events.insert(0, {
        'eventType': type,
        'streamId':
            'Camera ${now % 4 + 1}', // Mock ID that might act as name if not found
        'timestamp': now,
        'data': {'msg': msg},
      });
    });
  }
}

class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final String streamName;

  const EventCard({
    super.key,
    required this.event,
    this.streamName = 'Unknown Camera',
  });

  @override
  Widget build(BuildContext context) {
    final type = (event['eventType'] ?? 'INFO').toString().toUpperCase();
    final timestamp = event['timestamp'] as int? ?? 0;

    // msg might be complex or simple string
    final rawMsg = event['data']?['msg']?.toString() ?? 'No details';

    // Split title and description if newline exists
    String title = rawMsg;
    String description = "";

    if (rawMsg.contains('\n')) {
      final parts = rawMsg.split('\n');
      title = parts[0];
      description = parts.sublist(1).join('\n');
    }

    final severityColor = _getSeverityColor(type);
    final iconData = _getSeverityIcon(type);
    final dateTimeString = _formatDateTime(timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate-800
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: severityColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Icon + Severity + Separator + Stream Name + Time
            Row(
              children: [
                Icon(iconData, color: severityColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  type,
                  style: TextStyle(
                    color: severityColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                // Separator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFF64748B), // Slate-500
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Stream Name
                Expanded(
                  child: Text(
                    streamName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1), // Slate-300
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Time
                Text(
                  dateTimeString,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8), // Slate-400
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),

            // Description
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8), // Slate-400
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getSeverityColor(String type) {
    if (type.contains('CRITICAL')) return const Color(0xFFEF4444); // Red-500
    if (type.contains('WARNING')) return const Color(0xFFEAB308); // Yellow-500
    return const Color(0xFF3B82F6); // Blue-500 (Info)
  }

  IconData _getSeverityIcon(String type) {
    if (type.contains('CRITICAL')) return Icons.warning_amber_rounded;
    if (type.contains('WARNING')) return Icons.info_outline;
    return Icons.notifications_active_outlined;
  }

  String _formatDateTime(int timestamp) {
    final now = DateTime.now();
    final eventTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    // Simple manual format: yyyy-MM-dd HH:mm
    final year = eventTime.year;
    final month = eventTime.month.toString().padLeft(2, '0');
    final day = eventTime.day.toString().padLeft(2, '0');
    final hour = eventTime.hour.toString().padLeft(2, '0');
    final minute = eventTime.minute.toString().padLeft(2, '0');

    // If today, show "Today, HH:mm"
    if (year == now.year &&
        month == now.month.toString().padLeft(2, '0') &&
        day == now.day.toString().padLeft(2, '0')) {
      return "Today, $hour:$minute";
    }

    return "$year-$month-$day $hour:$minute";
  }
}
