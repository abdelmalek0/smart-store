import 'package:flutter/material.dart';
import 'package:smart_store_linux/application/events/events.dart';

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
