import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/application/blocs/playback/playback_bloc.dart';
import 'package:smart_store_linux/application/blocs/playback/playback_state.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';

class CameraSidebar extends StatefulWidget {
  final List<StreamConfig> streams;
  final String? selectedStreamId;
  final Function(String) onStreamSelected;
  final bool isOpen;

  const CameraSidebar({
    super.key,
    required this.streams,
    required this.selectedStreamId,
    required this.onStreamSelected,
    this.isOpen = true,
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
            child: BlocBuilder<PlaybackBloc, PlaybackState>(
              buildWhen: (prev, curr) =>
                  prev.activePipelineIds != curr.activePipelineIds,
              builder: (context, state) {
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildCameraGroup(
                      "Available Cameras",
                      widget.streams,
                      state,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraGroup(
    String title,
    List<StreamConfig> groupStreams,
    PlaybackState state, {
    String? subtitle,
  }) {
    final isExpanded = _groupExpansionState[title] ?? false;
    final ratioText =
        subtitle ?? "${groupStreams.length}/${groupStreams.length}";

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
            children: groupStreams
                .map((s) => _buildCameraItem(s, state))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildCameraItem(StreamConfig stream, PlaybackState state) {
    final isSelected = widget.selectedStreamId == stream.id;
    final isRunning = state.isPipelineActive(stream.id);

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
              : Colors.transparent,
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
                          color: statusColor.withValues(alpha: 0.5),
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

            if (!isSelected)
              const Icon(
                Icons.settings,
                size: 14,
                color: Color(0xFF475569), // Slate-600
              ),
          ],
        ),
      ),
    );
  }
}
