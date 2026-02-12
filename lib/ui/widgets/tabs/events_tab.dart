import 'package:flutter/material.dart';
import 'package:smart_store_linux/core/engine/stream_engine.dart';
import 'package:smart_store_linux/ui/viewModels/events_viewmodel.dart';
import 'package:smart_store_linux/core/events/events.dart';

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  late final EventsViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = EventsViewModel();
    _vm.addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _vm.dispose();
    super.dispose();
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
            child: _vm.events.isEmpty
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
                    itemCount: _vm.events.length,
                    itemBuilder: (context, index) {
                      final event = _vm.events[index];
                      // Resolve Camera Name from StreamManager
                      final streamId = event.streamId;
                      final pipeline = StreamEngine.instance.getPipeline(
                        streamId,
                      );
                      final streamName = pipeline?.stream.name ?? streamId;

                      return EventCard(event: event, streamName: streamName);
                    },
                  ),
          ),

          // clear button (temporary or persistence needed?)
          if (_vm.events.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _vm.clearEvents(),
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final types = ['CRITICAL', 'WARNING', 'INFO'];
    final type = types[now % 3];

    String msg = "Something happened";
    if (type == 'CRITICAL') {
      msg = "Queue limit exceeded\nCheckout 3 queue time > 5 mins.";
    }
    if (type == 'WARNING') {
      msg = "Low Staff Presence\nElectronics zone staff ratio below 1:5.";
    }
    if (type == 'INFO') {
      msg = "Restock Required\nEmpty shelf detected in Aisle 4.";
    }

    _vm.addEvent({
      'eventType': type, // This will be parsed as severity by ViewModel
      'streamId': 'Camera ${now % 4 + 1}',
      'timestamp': now,
      'data': {'msg': msg},
    });
  }
}

class EventCard extends StatelessWidget {
  final AppEvent event;
  final String streamName;

  const EventCard({
    super.key,
    required this.event,
    this.streamName = 'Unknown Camera',
  });

  @override
  Widget build(BuildContext context) {
    final type = event.type.toUpperCase();
    final severity = event.severity;
    final timestamp = event.timestamp;

    String rawMsg = 'No details';
    if (event is SystemEvent) {
      rawMsg = (event as SystemEvent).message;
    } else if (event is DetectionEvent) {
      final e = event as DetectionEvent;
      rawMsg = "${e.label} caused alert";
      if (e.metadata.containsKey('msg')) {
        rawMsg = e.metadata['msg'].toString();
      }
    }

    // Split title and description if newline exists
    String title = rawMsg;
    String description = "";

    if (rawMsg.contains('\n')) {
      final parts = rawMsg.split('\n');
      title = parts[0];
      description = parts.sublist(1).join('\n');
    }

    final severityColor = _getSeverityColor(severity);
    final iconData = _getSeverityIcon(severity);
    final dateTimeString = _formatDateTime(timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate-800
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: severityColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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

  Color _getSeverityColor(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.critical:
        return const Color(0xFFEF4444); // Red-500
      case EventSeverity.warning:
        return const Color(0xFFEAB308); // Yellow-500
      case EventSeverity.info:
        return const Color(0xFF3B82F6); // Blue-500 (Info)
    }
  }

  IconData _getSeverityIcon(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.critical:
        return Icons.warning_amber_rounded;
      case EventSeverity.warning:
        return Icons.info_outline;
      case EventSeverity.info:
        return Icons.notifications_active_outlined;
    }
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
