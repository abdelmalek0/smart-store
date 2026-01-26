import 'package:flutter/material.dart';
import 'package:smart_store_linux/core/models/rtsp_stream.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';

class CameraSidebar extends StatefulWidget {
  final List<RTSPStream> streams;
  final String? selectedStreamId;
  final Function(String) onStreamSelected;
  final bool isOpen;
  final StreamProcessManager? processManager;

  const CameraSidebar({
    super.key,
    required this.streams,
    required this.selectedStreamId,
    required this.onStreamSelected,
    this.isOpen = true,
    this.processManager,
  });

  @override
  State<CameraSidebar> createState() => _CameraSidebarState();
}

class _CameraSidebarState extends State<CameraSidebar> {
  // Mock groups for now since RTSPStream doesn't have group info
  final Map<String, bool> _groupExpansionState = {'Available Cameras': true};

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) {
      return const SizedBox(width: 0);
    }

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF111722), // Deep dark blue background
        border: Border(
          right: BorderSide(
            color: Color(0xFF1E293B), // Slate-800 border
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text(
              "CAMERA GROUPS",
              style: TextStyle(
                color: Color(0xFF64748B), // Slate-500
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildCameraGroup(
                  "Available Cameras",
                  widget.streams, // Put all actual streams here for now
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraGroup(
    String title,
    List<RTSPStream> groupStreams, {
    String? subtitle,
  }) {
    final isExpanded = _groupExpansionState[title] ?? false;
    // Calculate ratio text e.g. "6/6"
    final ratioText =
        subtitle ??
        "${groupStreams.length}/${groupStreams.length}"; // Mock logic

    return Column(
      children: [
        // Group Header
        InkWell(
          onTap: () {
            setState(() {
              _groupExpansionState[title] = !isExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  // Simple icon mapping for mock groups
                  title.contains("Store")
                      ? Icons.storefront
                      : title.contains("Storage")
                      ? Icons.inventory_2_outlined
                      : Icons.local_parking,
                  color: const Color(0xFF94A3B8),
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1), // Slate-300
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  ratioText,
                  style: const TextStyle(
                    color: Color(0xFF475569), // Slate-600
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Group Items (Collapsible)
        if (isExpanded)
          Column(
            children: groupStreams.asMap().entries.map((entry) {
              // Use index to fake some UI details if needed
              // final index = entry.key;
              final stream = entry.value;
              return _buildCameraItem(stream);
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildCameraItem(RTSPStream stream) {
    final isSelected = widget.selectedStreamId == stream.id;
    final isRunning = widget.processManager?.getProcessor(stream.id) != null;

    // Status dot color
    final statusColor = isRunning
        ? const Color(0xFF3B82F6) // Blue (Active)
        : const Color(0xFF475569); // Slate (Inactive)

    return InkWell(
      onTap: () => widget.onStreamSelected(stream.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3B82F6)
              : Colors.transparent, // Active Blue or Transparent
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // Status Dot
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : statusColor,
                shape: BoxShape.circle,
                boxShadow: isRunning && !isSelected
                    ? [
                        BoxShadow(
                          color: statusColor.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Text(
                stream.name,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF94A3B8), // Slate-400
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Settings Icon (Hover only in real web app, always here for design?)
            // Reference shows gear icon.
            if (!isSelected)
              Icon(
                Icons.settings,
                size: 14,
                color: const Color(0xFF475569), // Slate-600
              ),
          ],
        ),
      ),
    );
  }
}
