import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';

import 'package:smart_store_linux/ui/view/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/ui/viewModels/streams_viewmodel.dart';
import 'package:smart_store_linux/ui/view/widgets/dialogs/stream_dialogs.dart';

class StreamsScreen extends StatelessWidget {
  const StreamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StreamsViewModel(AppService.instance),
      child: const _StreamsContent(),
    );
  }
}

class _StreamsContent extends StatelessWidget {
  const _StreamsContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<StreamsViewModel>(
      builder: (context, vm, _) {
        return Column(
          children: [
            ModernHeader(
              title: "Streams",
              subtitle: "Manage RTSP streams",
              actions: [
                ModernButton(
                  label: "Add Stream",
                  icon: Icons.add,
                  onPressed: () => showAddStreamDialog(context, vm),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: vm.streams.isEmpty
                  ? _buildEmptyState(context, vm)
                  : ListView.builder(
                      itemCount: vm.streams.length,
                      itemBuilder: (context, index) {
                        final stream = vm.streams[index];
                        return _buildCameraCard(context, stream, vm);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCameraCard(
    BuildContext context,
    StreamConfig stream,
    StreamsViewModel vm,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827), // Dark slate/black card bg
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 80,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              image: const DecorationImage(
                image: NetworkImage(
                  "https://placeholder.com/150",
                ), // Placeholder
                fit: BoxFit.cover,
                opacity: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stream.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stream.url,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
                onPressed: () {},
                tooltip: "Settings",
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFEF4444),
                ),
                onPressed: () => vm.removeStream(stream.id),
                tooltip: "Remove Camera",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, StreamsViewModel vm) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_off_outlined,
            size: 64,
            color: AppTheme.text.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          ModernLabel(
            "No cameras connected",
            color: AppTheme.text.withValues(alpha: 0.5),
            fontSize: 16,
          ),
          const SizedBox(height: 24),
          ModernButton(
            label: "Add your first stream",
            icon: Icons.add,
            onPressed: () => showAddStreamDialog(context, vm),
          ),
        ],
      ),
    );
  }
}
